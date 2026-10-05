# Servers, sessions and the web UI

[README](../README.md) · [All docs](../README.md#documentation)

The web UI and HTTP API, MCP and ACP servers, persistent sessions and streaming.

## Web sessions

The browser client sends `session_id` and the server honours it. A session is
whatever its trail derives — `resume_session` reads
`.lex/sessions/<id>.db` and rebuilds the conversation per request, so it
survives a page reload *and* a server restart.

This is not the registry pattern the ACP path uses, and could not be:
`net.serve_fn` hands the handler a `Request` and nothing else, so there is no
value to thread between requests and nowhere to keep an in-memory map. That
constraint points at #54's contract rather than away from it — the
conversation is a projection of the trail, so deriving it per request is the
design, not a substitute for a cache.

A client-supplied id becomes a file path, so it is checked: lowercase hex,
4–64 characters, anything else replaced with a fresh id. An id the server has
never seen is a working empty session rather than an error, because a log with
no events derives the empty conversation.

Session logs are swept at server start — older than
`persist.max_session_age_days()` (30) by mtime, which moves on every turn.
Age rather than count, so an eviction cannot take a conversation someone is
still in.

## Streaming

Turns arrive as they happen. Text appears token by token, tool calls announce
themselves as they are dispatched, and the reply lands when the model is done —
rather than the whole turn appearing at once when it finishes.

This reaches every surface that shows steps: the TUI (`repl` and one-shot),
the ACP server's `session/update` notifications, and the web backend.

It depends on the provider offering a streaming half. `anthropic`, `ollama`, and
everything routed through the OpenAI adapter (LiteLLM, vLLM, lex-moe, MLX,
opencode-go, Mistral) do. `google` and `vertex` do not — Gemini answers with a
JSON array rather than SSE — so a turn on those still arrives in one burst.
Nothing else changes: the same steps reach the same renderer either way, so
there is no separate code path to fall out of date.

The pull loop lives in lex-llm's `run_steps_streamed`; `run_turn_streaming_with_provider`
in `src/server/session.lex` is the seam. Consuming a live socket carries the
`[stream]` effect, so every entry point's `--allow-effects` list includes it.

**Step count explained:** `steps` counts all `d.Step` records emitted by the agent loop — `StepDelta` (per LLM token event), `StepToolExec`, `StepToolResult`, and `StepDone`. One LLM round + one tool call ≈ 5 step records. 71 steps ≈ 14 LLM rounds (`max_steps: 20` counts rounds, not records).

**Avoiding the 0-delta stall:** If Ollama receives many large-context requests in rapid succession it can enter a state where it returns `{"done": false, "response": ""}`. The agent loop sees 0 deltas, emits a silent empty `StepDone`, and the run appears to complete in 1 step with no output. Fix: restart Ollama (`pkill -f "ollama serve" && open -a Ollama`) and avoid batching many large-context calls without pauses.

#### Thinking models (gemma4, deepseek-r1)

Models with a chain-of-thought "thinking" phase need two things to work through LiteLLM:

1. **`max_tokens ≥ 2000`** — thinking tokens count against the budget before any visible output is produced. With `max_tokens: 256` the model exhausts its budget mid-thought and returns empty content.
2. **`merge_reasoning_content_in_choices: true`** in `litellm_config.yaml` — without this, LiteLLM drops the `content` field when `thinking` is present in the Ollama response.

```yaml
# litellm_config.yaml
- model_name: gemma4:26b
  litellm_params:
    model: ollama/gemma4:26b
    api_base: http://localhost:11434
    merge_reasoning_content_in_choices: true
```

Even with these fixes, thinking models tend to emit tool calls as embedded JSON in `content` (rather than in the `tool_calls` field) when given 10+ function schemas. The `openai.lex` adapter has a `content_tool_call` fallback parser, but the generated code quality degrades significantly under large context. Use `qwen3-coder:30b` for coding tasks.

## Server Protocols

### MCP (Model Context Protocol)

_Runnable: `examples/mcp_server_smoke.sh`_

`src/server/mcp_main.lex` exposes lex-code as a single `code` tool over
MCP, so any MCP-speaking host — Claude Code, Cursor, Zed — can hand it
a task. `mode` selects the agent strategy; the provider is a
server-launch choice, not a per-call argument.

```sh
LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
lex run --max-steps 20000000000 --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/mcp_main.lex main &

curl -s http://localhost:7778/.well-known/agent.json
curl -s -X POST http://localhost:7778/mcp \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
curl -s -X POST http://localhost:7778/mcp \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code",
       "arguments":{"task":"add retries to fetch()","mode":"refactor"}}}'
```

The same port serves the A2A agent card at
`/.well-known/agent.json`. All eight modes are reachable through the
`mode` argument (`build|plan|explore|refactor|spec|test|review|bar`).

### Agent Client Protocol (ACP, Zed) — Phase 1

_Runnable: `python3 examples/acp_server_smoke.py`_

[Zed's Agent Client Protocol](https://zed.dev/acp) — a JSON-RPC-over-stdio standard for launching a
coding agent as a subprocess (Zed, JetBrains, Neovim, and Emacs all speak it; opencode is one of the
other agents already on the [ACP Registry](https://zed.dev/blog/acp-registry)). Note the name collides
with BeeAI's Agent *Communication* Protocol, which is a different, unrelated thing; lex-code no longer
carries a server for it.

```sh
LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
  lex run --max-steps 20000000000 --allow-effects approval,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/client_protocol.lex main
```

Phase 1 covers `initialize`, `session/new`, `session/prompt` (`session/update`
notifications per step, emitted as each step happens rather than replayed after the
turn — see Streaming), and `session/close` — enough to work from an ACP-aware editor. Not yet
implemented: `session/request_permission`, `$/cancel_request`, client-mediated `fs/*`/`terminal/*`,
and `auth/login` — see the header comment in `src/server/client_protocol.lex` for why each is
deferred rather than silently missing. The exact `session/update` field shapes are a best-effort
reconstruction of the protocol's v2 schema; validate against a real client before relying on this
for production interop.

## Web Frontend

_Runnable: `examples/web_frontend_smoke.sh`_

`src/server/web.lex` is the backend: it serves the static files in
`src/web/` **and** the `POST /a2a` endpoint the page calls, so one
process is the whole thing — no separate static server needed.

```sh
lex run --max-steps 20000000000 --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/web.lex serve_web

# then open http://localhost:7700
```

`PORT` (default 7700) and `WEB_DIR` (default `src/web`) override the
defaults. The effect list is what `lex check src/server/web.lex`
reports as required.

Each `POST /a2a` currently starts a **fresh session**: the request
carries a `session_id` and the page stores the one it gets back, but
the handler mints a new one per call, so the page has no conversation
memory across turns. Fine for the demo it is; not yet a client to work
in.
