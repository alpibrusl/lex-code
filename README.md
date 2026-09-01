# lex-code

[![CI](https://github.com/alpibrusl/lex-code/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-code/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project** — Agents · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

A Lex-native coding assistant — think Claude Code or Cursor, built entirely in the Lex ecosystem.

## [Trust Without Comprehension](https://lexlang.org/manifesto) — live demo

Effect-typed parallel orchestration (§VI) + tamper-evident audit (§VIII) — verified live by the type checker:

[![Demo — effect-typed orchestration + hash chain](https://asciinema.org/a/pdL5GnjFtakQi6bC.svg)](https://asciinema.org/a/pdL5GnjFtakQi6bC)

```sh
# run it yourself
bash examples/manifesto_full_chain/demo.sh
```

## Quickstart

Use `bin/lex-code` rather than calling `lex run` by hand: it supplies
the capability grant every session needs and the `main --` separator
that stops your first flag being read as a function name.

```sh
# set provider key
export ANTHROPIC_API_KEY=sk-...

# build mode (default), interactive REPL
./bin/lex-code

# one-shot CLI mode (exits after the task)
./bin/lex-code "implement list.zip"

# plan mode
./bin/lex-code --plan

# mistral provider
./bin/lex-code --mistral

# bootstrap demo: impl → spec → test → review
lex run src/bootstrap/run.lex

# web UI + HTTP API on :7700 (see Web Frontend)
lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/web.lex serve_web
```

## Install as a binary

```sh
# installs to /usr/local/bin/lex-code and /usr/local/lib/lex-code/
make install

# custom prefix
make install PREFIX=~/.local

# uninstall
make uninstall
```

After install, `lex` must still be on your PATH (it’s the interpreter).

```sh
lex-code "implement list.zip"
lex-code --plan --ollama "how should we structure the session module?"
```

## Agent Modes

| Flag | Mode | Role |
|------|------|------|
| *(default)* | Build | Write and edit Lex source files |
| `--plan` | Plan | Produce implementation plans, no writes |
| `--explore` | Explore | Read + grep, understand the codebase |
| `--refactor` | Refactor | Restructure code, rename, inline |
| `--spec` | Spec | Generate lex-spec `Spec` values |
| `--test` | Test | Write unit and property tests |
| `--review` | Review | Code-review: correctness, style, effects |
| `--bar` | Bar | Walk a project against the minimum bar, read-only ([below](#minimum-bar-mode)) |
| `--multi` | Multi | Run Build + Test in parallel via `std.conc` |

## Providers

| Flag | Provider | Model | Key required |
|------|----------|-------|--------------|
| *(default)* | Anthropic | claude-sonnet-4-6 | `ANTHROPIC_API_KEY` |
| `--openai` | OpenAI | gpt-5.5 | `OPENAI_API_KEY` |
| `--google` | Google | gemini-3.5-flash | `GOOGLE_API_KEY` |
| `--mistral` | Mistral | mistral-large-latest | `MISTRAL_API_KEY` |
| `--litellm` | LiteLLM proxy | `$LITELLM_MODEL` | none (proxy handles keys) |
| `--ollama` | Ollama (local, native API) | `$OLLAMA_MODEL` | none |
| `--vllm` | vLLM (local/remote) | `$VLLM_MODEL` | none |
| `--opencode` | OpenCode Go plan (cloud, direct) | `$OPENCODE_MODEL` | `OPENCODE_API_KEY` |

### Ollama

```sh
ollama pull codellama   # or llama3, deepseek-coder, qwen2.5-coder, …
lex run src/tui/main.lex --ollama
```

### vLLM

```sh
# start vLLM server
python -m vllm.entrypoints.openai.api_server \
  --model mistralai/Mistral-7B-Instruct-v0.3

# run lex-code against it
VLLM_MODEL=mistralai/Mistral-7B-Instruct-v0.3 \
  lex run src/tui/main.lex --vllm "implement list.zip"

# remote GPU box
VLLM_BASE_URL=http://gpu-box:8000/v1/chat/completions \
VLLM_MODEL=deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct \
  lex run src/tui/main.lex --vllm
```

`VLLM_MODEL` defaults to `mistralai/Mistral-7B-Instruct-v0.3`.
`VLLM_BASE_URL` defaults to `http://localhost:8000/v1/chat/completions`.

### OpenCode Go plan

[OpenCode Go](https://opencode.ai/docs/zen) bundles cloud access to several open-weight coding models (DeepSeek, Qwen3, Kimi, GLM, MiniMax, MiMo) behind one subscription key. Two ways to reach it — same key either way:

```sh
# native (direct to the Go endpoint, no proxy)
export OPENCODE_API_KEY=$(cat ~/.credentials/opencode/key | tr -d '\n')
lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --opencode "implement list.zip"

# override the default model (kimi-k2.7-code)
OPENCODE_MODEL=qwen3.7-max \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --opencode "implement list.zip"

# via the LiteLLM proxy instead (shares one proxy + model list with lex-loom — see below)
LITELLM_MODEL=deepseek-v4-flash \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --litellm "implement list.zip"
```

`OPENCODE_MODEL` accepts any Go-plan model id (see `litellm/config.yaml`'s "OpenCode Go plan" section for the full list). `OPENCODE_BASE_URL` overrides the endpoint if you're routing through a local reasoning proxy instead of hitting `opencode.ai` directly.

### LiteLLM (local models + OpenCode Go via proxy)

[LiteLLM](https://github.com/BerriAI/litellm) is the recommended path for running local models, and the only path that gives OpenCode Go's thinking-mode models correct `merge_reasoning_content_in_choices` handling. It provides an OpenAI-compatible endpoint over any backend (Ollama, vLLM, OpenCode Go, MLX, …), which gives cleaner tool calling than the native Ollama wire format.

This repo ships a ready-to-run proxy config at `litellm/config.yaml` + `litellm/docker-compose.yml` — kept in sync with [lex-loom](https://github.com/alpibrusl/lex-loom)'s own `litellm/` directory (same model list, same OpenCode Go entries) so both repos can point at one shared proxy instance.

```sh
# start the bundled proxy
cd litellm
ANTHROPIC_API_KEY=... OPENAI_API_KEY=... OPENCODE_API_KEY=... docker compose up -d
cd ..

# run lex-code against qwen3-coder:30b (recommended local model)
LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main

# one-shot via the --litellm flag
LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --litellm "implement list.zip"

# OpenCode Go through the proxy instead of native --opencode
LITELLM_MODEL=kimi-k2.7-code \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --litellm "implement list.zip"

# override the proxy URL (default: http://localhost:4000)
LITELLM_BASE_URL=http://gpu-box:4000 \
LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/tui/main.lex main -- --litellm
```

`LITELLM_MODEL` is the model name as it appears in `litellm/config.yaml`'s `model_name` field.
`LITELLM_BASE_URL` defaults to `http://localhost:4000`.

Running against a standalone LiteLLM install instead of the bundled compose file works the same way — point `litellm --config <your-config.yaml> --port 4000` at any config with the model names you use.

#### Local model compatibility

Tested on [lex-code fizzbuzz bootstrap](src/bootstrap/fizzbuzz_lex.lex) — task: write `fizzbuzz.lex` with `fn fizzbuzz(n :: Int) -> List[Str]` + 4 unit tests, `lex check` clean, `run_all` returns 0.

| Model | VRAM | Steps | Result | Notes |
|-------|------|-------|--------|-------|
| `qwen3-coder:30b` (Q4_K_M) | 45 GB | ~14 LLM rounds | ✅ passes | Best local choice. Correct tool use, proper Lex idioms after linter feedback. |
| `gemma4:26b` (Q4) | 19 GB | — | ❌ fails | Thinking model: consumes 500–700 tokens on chain-of-thought before any output. Tool calls appear as embedded JSON in `content` instead of `tool_calls`. Generates Python instead of Lex under large context. |
| `gemma4:latest` (9 B) | 10 GB | — | not tested | Lighter variant; same thinking-model caveats apply. |

**Reliable patterns with `qwen3-coder:30b`:**

```sh
# Warm the model before a run (first call loads weights, subsequent calls are faster)
curl -s http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-coder:30b","messages":[{"role":"user","content":"hi"}],"max_tokens":10,"stream":false}' \
  > /dev/null

LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time,approval \
  src/bootstrap/fizzbuzz_lex.lex main
# [fizzbuzz_lex] starting build via litellm
# [fizzbuzz_lex] done — steps: 71
```

```sh
$ lex check fizzbuzz.lex && lex run fizzbuzz.lex run_all
ok
0
```

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

## Project memory

Facts that outlive a session — a convention, a version pin, a gotcha. Three
stages, and the boundary between them is enforced by the effect system rather
than by policy.

**The agent proposes.** `remember(kind, content, key?, why?)` appends a
candidate. It cannot do more than that: lex-llm fixes the tool row at
`[net, io, proc]`, with no `sql` and no `time`, and record-field rows unify by
equality — so no tool can widen it to what a durable write needs. An agent
*cannot* install a belief.

**Consolidation disposes.** At session start, `src/memory/consolidate.lex`
reconciles each candidate against what the project already knows:

| | |
|---|---|
| unknown kind, empty content | rejected |
| nothing known yet | accepted |
| identical to what is known | skipped |
| contradicts what is known | superseded — the trail keeps the previous value |
| `recent_change` | accepted; it accumulates by design |

Rules are mechanical, not model-judged: a model adjudicating between two
contradictory beliefs is the failure this mechanism exists to contain.

**The trail records why.** Every outcome, including a rejection, becomes a
`memory.recorded` event with a chained `memory.reconciled` attestation in
`.lex/memory_trail.db` — deliberately not the session log, which is in-memory
and gone at exit. So `attest.chain` answers "why does it believe this" with
something better than "it said so once".

**A session opens with a summary, not the store.** At most five entries per
kind, newest first, and the header says how many were left out — a model that
can see its excerpt is partial can ask for the rest; one shown a silently
truncated list cannot.

Everything the prompt sees was attested by consolidation. A candidate that
was refused never leaves `.lex/memory-candidates.jsonl`.

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

## Semantic search

`grep` and `glob` match names. `semantic_search` matches intent — "validate an
A2A envelope", "retry a failed HTTP call" — by ranking every function's
signature, effects and examples against the query.

It needs an index, and the index needs an embeddings endpoint. LiteLLM is the
one lex-code speaks to, which is how Ollama is reached: the proxy presents
OpenAI's `/v1/embeddings` over `ollama/nomic-embed-text`, so lex-code never
learns Ollama's native embeddings shape. `litellm/config.yaml` ships the entry.

```sh
ollama pull nomic-embed-text        # 768-dim, ~270MB, CPU is fine
cd litellm && docker compose up -d && cd ..

lex run --max-steps 20000000000 --allow-effects env,io,net,proc \
  src/index_build.lex main
```

| Variable | Default | Meaning |
|---|---|---|
| `LITELLM_BASE_URL` | `http://localhost:4000` | proxy (shared with the chat path) |
| `LEX_EMBED_MODEL` | `nomic-embed-text` | must be in the proxy's model list |
| `LEX_EMBED_DIMS` | `128` | components kept per vector — see below |
| `LEX_INDEX_PATH` | `src/` | what to index |

**`--max-steps` is not optional.** The default VM budget is 10M opcode
dispatches and a whole-repo build blows straight through it.

### Why the index stores a prefix

Reading `.lex/index.jsonl` dominates query latency, and the reason is upstream:
`jv.parse_into_errors` is **quadratic in document size**, because
`json_value.char_at` walks the input with `str.slice(src, p, p + 1)` and slicing
is O(p). Doubling a JSON document roughly quadruples parse time — 16K/0.2s,
33K/0.9s, 66K/3.2s, 132K/13.7s, 264K/55.7s. So the index has to stay small, and
on this repo's 674 functions it measures:

| dims | index | read |
|---|---|---|
| 512 | 932K | 34s |
| 128 | ~500K | ~6s |
| 64 | 336K | 3s |

A 34-second search tool is not a search tool, so only the first
`LEX_EMBED_DIMS` components are kept. The same parser cost bounds indexing:
`lex docs` output for the whole tree is 310K and takes ~55s to parse before a
single embedding is requested, which is why `LEX_INDEX_PATH` defaults to a
subtree-sized scope rather than the repo. That is sound rather than merely cheap
for a Matryoshka-trained model like `nomic-embed-text`, which is trained so a
leading slice of the vector is itself a usable embedding; the prefix is
renormalised, since truncating changes the norm. Raise it for better ranking on
a small tree, lower it on a large one.

### Rebuilds are incremental

The reuse key is `sig_id`, not mtime: it hashes the function's own content, so
it answers "did this function change" rather than "was this file touched",
which is true after a comment edit and false after a `git checkout` that
rewinds content. Changing the model, endpoint or dims invalidates the whole
index — vectors are only comparable within one model, and mixing two vector
spaces in one ranking produces plausible nonsense rather than an error.

`semantic_search` is available to the explore, plan and review agents. It never
builds the index itself: a build makes one HTTP call per function, and
`Tool.execute`'s `[net, io, proc]` row cannot read the env it would need.

## Observability (OpenTelemetry)

Off by default. Point it at a collector and every turn arrives as a trace:

```sh
LEX_OTLP_ENDPOINT=http://localhost:4318 lex-code
```

| Variable | Effect |
|---|---|
| `LEX_OTLP_ENDPOINT` | POST OTLP/JSON to `/v1/traces` and `/v1/metrics` |
| `LEX_OTEL_STDOUT=1` | print the same envelopes to stdout instead |

An endpoint wins over the stdout flag, and with neither set nothing is
emitted — `io.print` is the TUI's own output stream, so a default-on stdout
exporter would dump OTel envelopes into your session on every turn.

**The trace is projected from the trail, not instrumented separately.**
lex-llm already writes `cap.invoked` before every tool call and
`cap.completed` / `cap.failed` after it, parented to the invoke, and every
trail event carries `ts_ms`. A start, an end, a parent link and a name is a
span — the trail was already a trace, just never spoken in OTel's wire
format. `src/observability.lex` reads the turn's slice of the log and
translates. Running a second span stream inside the same dispatch loop would
put two recorders on one set of facts, which is precisely how the
attestation chain broke (#32): the loop wrote one place, the reader read
another.

You get an `agent.turn` root span per turn, one `tool.<name>` child per
completed tool call, a `tool.calls` counter tagged by tool and success, and a
`turn.duration_ms` histogram. An invoke with no outcome — a turn cut short
mid-tool — is dropped rather than exported with a fabricated end time.

**Span ids are derived, not drawn.** Trail event ids are sha256 hashes of the
event's own content, so a span id taken from one is stable: re-exporting a
session reproduces the same trace instead of forging a rival. That also keeps
`random` out of the turn's effect row entirely. An unreachable collector
costs telemetry, never the turn.

## Server Protocols

### MCP (Model Context Protocol)

`src/server/mcp_main.lex` exposes lex-code as a single `code` tool over
MCP, so any MCP-speaking host — Claude Code, Cursor, Zed — can hand it
a task. `mode` selects the agent strategy; the provider is a
server-launch choice, not a per-call argument.

```sh
LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
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

[Zed's Agent Client Protocol](https://zed.dev/acp) — a JSON-RPC-over-stdio standard for launching a
coding agent as a subprocess (Zed, JetBrains, Neovim, and Emacs all speak it; opencode is one of the
other agents already on the [ACP Registry](https://zed.dev/blog/acp-registry)). Note the name collides
with BeeAI's Agent *Communication* Protocol, which is a different, unrelated thing; lex-code no longer
carries a server for it.

```sh
LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
  lex run --allow-effects approval,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
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

## Tools

### Standard tools (all modes)

| Tool | Description |
|------|-------------|
| `read_file` | Read file contents |
| `write_file` | Write / create a file |
| `edit_file` | Targeted string replacement |
| `grep` | Search file contents by regex |
| `glob` | List files matching a glob |
| `bash` | Run a shell command |
| `todo_write` | Write structured TODO list |

### Lex tools

| Tool | Description |
|------|-------------|
| `lex_check` | Type-check a Lex file |
| `lex_audit` | Effect audit |
| `lex_run` | Run a Lex expression |
| `lex_test` | Run tests |

### Spec tools

| Tool | Description |
|------|-------------|
| `lex_spec_check` | Evaluate a Spec against bindings |
| `lex_spec_smt` | SMT-backed spec verification |

### Store tools

| Tool | Description |
|------|-------------|
| `sigid_lookup` | Resolve a SigId to a function |
| `attestation_query` | List attestations for a function |
| `effects_of` | Query effect row of a function |
| `lex_store_diff` | Diff two store snapshots |
| `lex_store_apply` | Apply a store patch |
| `lex_store_merge` | Merge two store snapshots |

### VCS tools (lex-vcs / AST-level)

The agent can read and drive lex-vcs directly via these tools.

| Tool | CLI command | Description |
|------|-------------|-------------|
| `ast_diff` | `lex diff <a> <b>` | AST-level diff between two files |
| `op_show` | `lex op show <id>` | Inspect a content-addressed operation |
| `op_log` | `lex op log` | Show the operation log |
| `op_push` | `lex op push` | Push ops to remote |
| `op_pull` | `lex op pull` | Pull ops from remote |
| `branch_list` | `lex branch list` | List branches |
| `branch_current` | `lex branch current` | Show active branch |
| `branch_show` | `lex branch show <name>` | Inspect a branch |
| `branch_create` | `lex branch create <name>` | Create a branch |
| `branch_use` | `lex branch use <name>` | Switch branch |
| `branch_peek` | `lex branch peek <name>` | Read-only view of another branch |
| `branch_overlay` | `lex branch overlay <name>` | Overlay a branch without switching |
| `merge_start` | `lex merge start <branch>` | Begin a merge session |
| `merge_status` | `lex merge status` | Show pending conflicts |
| `merge_resolve` | `lex merge resolve <id>` | Resolve a conflict |
| `merge_defer` | `lex merge defer <id>` | Defer a conflict for later |
| `merge_commit` | `lex merge commit` | Commit a completed merge |

## Architecture

```
lex-code
├── src/
│   ├── agents/          # AgentDef values (build, plan, explore, refactor, spec, test, review, bar)
│   ├── bar/             # Minimum-bar ledger, probe ids, repository probes
│   ├── prompts/         # System prompts per mode
│   ├── tools/           # Tool implementations
│   │   ├── standard/    # read, write, edit, grep, glob, bash, todowrite
│   │   ├── lex_*.lex    # check, audit, run, test, spec_check, spec_smt
│   │   ├── lex_store_*  # sigid, attestations, effects, diff, apply, merge
│   │   └── vcs/         # 17 lex-vcs tools (ast_diff, op_*, branch_*, merge_*)
│   ├── permissions/     # lex-spec Spec values per agent mode
│   ├── server/
│   │   ├── session.lex        # Session type, run_turn, AgentMode
│   │   ├── session_events.lex # Durable conversation record (the trail)
│   │   ├── multi_agent.lex    # std.conc parallel dispatch
│   │   ├── persist.lex        # lex-trail log helpers
│   │   ├── web.lex            # HTTP: static src/web + POST /a2a  (runnable)
│   │   ├── mcp_main.lex       # MCP + A2A agent card on :7778     (runnable)
│   │   └── client_protocol.lex # Zed ACP over stdio, Phase 1      (runnable)
│   ├── tui/main.lex     # CLI REPL + one-shot mode
│   ├── web/             # Web frontend (vanilla JS)
│   └── bootstrap/run.lex  # Demo 4-phase pipeline
├── bin/lex-code      # Shell wrapper (used by make install)
├── Makefile          # install / uninstall targets
└── lex.toml
```

## Web Frontend

`src/server/web.lex` is the backend: it serves the static files in
`src/web/` **and** the `POST /a2a` endpoint the page calls, so one
process is the whole thing — no separate static server needed.

```sh
lex run --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
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

## Parallel Multi-Agent (`std.conc`)

The `--multi` TUI flag (and `run_parallel` in `src/server/multi_agent.lex`) spawns two
actors via `std.conc.spawn` and runs Build + Test concurrently:

```lex
let impl_actor := conc.spawn(worker_handler, impl_state)
let test_actor := conc.spawn(worker_handler, test_state)
let impl_steps := conc.ask(impl_actor, Execute(task))
let test_steps := conc.ask(test_actor, Execute(test_task))
```

## Bootstrap Script

`src/bootstrap/run.lex` runs a multi-phase pipeline against a real task. It
used to hardcode one — implement `list.zip`, in four fixed phases, with its
own sequential runner — and now drives the same agent graph the TUI does.

```sh
# the original demo, unchanged
lex run --allow-effects … src/bootstrap/run.lex main

# a real task, phases of your choosing
LEX_TASK="add a retry wrapper to src/http.lex" \
LEX_PIPELINE=build,test \
LEX_PROVIDER=litellm \
  lex run --allow-effects … src/bootstrap/run.lex main
```

| Variable | Default | Meaning |
|---|---|---|
| `LEX_TASK` | the `list.zip` demo | what to build |
| `LEX_PIPELINE` | `impl_then_spec_then_test` | preset name, or a spec |
| `LEX_PROVIDER` | `anthropic` | provider tag |

### Pipeline specs

A spec is two characters of grammar: `,` runs stages in order, `|` runs them
at once. Agents are `build` (alias `impl`), `spec`, `test`, `review`.

```
build,test              impl → test
build|test              impl ∥ test
build,spec,test|review  impl → spec → (test ∥ review)
```

That last one is exactly the `impl_then_spec_then_test` preset — an
`examples {}` case asserts the two stay equal, so the grammar and the named
presets cannot drift apart.

The same values work on the TUI's `--pipeline=` flag, which takes a preset
name or a spec. An unrecognised agent is refused with the list of valid ones
rather than skipped: a pipeline quietly missing a stage is a run that looks
successful and did less than it was asked to.

## Minimum bar mode

`--bar` walks a project against a checklist and reports where it stands.
It never edits: the output is a work queue, in the order the gaps will
hurt.

The checklist is not invented here. It is the two "short version" cards
from [*Prompt to
Production*](https://github.com/alpibrusl/prompt-to-production) ch. 16
and [*Prompt to
Evidence*](https://github.com/alpibrusl/prompt-to-evidence) ch. 15 —
each book's five items with the worst consequence-to-effort ratio in it
— plus four items from the production checklist that a repository can
settle about itself. Fourteen in total, in `src/bar/ledger.lex`.

The interesting part is the tier on each item, because it is an
admission:

| Tier | Count | What lex-code does |
|------|-------|--------------------|
| `repo` | 6 | Runs a probe and reports the verdict **and its bound** |
| `attested` | 4 | Cannot verify. Asks, records who said it and when, and reports NOT DONE if nobody answers |
| `judgement` | 4 | Cannot verify. Asks for the reasoning, not a verdict |

Six of fourteen. "The database is backed up and a restore has actually
been performed" is a claim about the world, and no coding agent can
settle it — so BAR mode is forbidden from ticking it, and marking such
an item not-applicable requires a stated reason. A bare N/A is how a
checklist becomes a rubber stamp.

The six probes, all read-only:

| Probe | Item | What it cannot see |
|-------|------|--------------------|
| `secret_scan` | No secrets in the repository, checked through the history | Credentials in an unrecognised format; commits outside the range it reports |
| `git_remote` | A remote copy that is not your laptop | Whether the remote is reachable or current |
| `tests_present` | Tests exist for the paths that must not break | Which paths those are |
| `ci_on_pr` | Tests run on every PR and block the merge | Branch protection — it lives in the forge, so this probe never returns better than `partial` |
| `toolchain_pin` | What is pinned is pinned consistently | The `lex-*` packages, unpinned on purpose while they move fast; only the lex-lang toolchain is compared — `lex.toml` against every version named in `.github/workflows`, not a pin written in a Dockerfile or a README |
| `examples_coverage` | Tested against a case with a known answer | Which fns are pure; an `examples {}` block **is** the known-answer test, so this is a floor, not coverage |

```sh
lex run src/tui/main.lex -- --bar "walk this project"

# the probes alone, no model:
lex run --allow-effects io,proc src/bar/checks.lex gate '"."' '"src"'
```

That last command is also a CI step: lex-code is held to the bar it
walks other projects against. It fails the build on a `fail` verdict
only — `partial` is the honest state for an item a probe can half
answer, and failing on it would push the next author to weaken the
probe rather than answer the question.

It caught two real ones on the way in. First: `lex.toml` pinned
toolchain 0.10.10 while CI installed 0.10.11. Then, once that was
fixed, the probe itself turned out to be reading only the first
`LEX_VERSION` assignment it found — so `publish.yml`, which writes the
version inline in a download URL with no variable at all, had sat two
patch versions behind unnoticed. It now reads every lex-lang version
named in any workflow and names the file that disagrees.

## Permissions

Each agent mode has a `lex-spec` `Spec` value (in `src/permissions/rules.lex`) that
allowlists its tool set. At construction time, `with_permission_gate` (from `lex-llm`)
filters the tool list using the spec, so agents can only call the tools they’re
authorised to use.

## Roadmap

- [x] v0.1 — agents, tools, TUI REPL, A2A server, lex-trail persistence (that server since removed — see below)
- [x] v0.2 — refactor/spec/test/review agents, store tools, lex-spec permissions, Mistral provider
- [x] v0.3 — parallel multi-agent (`std.conc`), VSCode extension (since removed, superseded by v0.7's Zed ACP server), web frontend, bootstrap script
- [x] v0.4 — lex-vcs tools (17), CLI one-shot mode, Ollama + vLLM providers, install target
- [x] v0.5 — BeeAI ACP server (`src/server/acp.lex`), ACP helpers in lex-agent (server since removed — it never had a listener, and `lex-agent/acp_server` supplies only pure JSON/SSE builders, so finishing it meant writing a second HTTP server for a job `web.lex` and the MCP server already cover; the helpers remain upstream)
- [x] v0.6 — OpenCode Go provider (native + via the bundled LiteLLM proxy, shared config with lex-loom)
- [x] v0.7 — Agent Client Protocol (Zed) server, Phase 1: `initialize`/`session/new`/`session/prompt`/`session/close`

`src/server/api.lex` went the same way as the BeeAI ACP server, and for a
sharper reason. It had no entry point, and its handler could not have run
a turn even with one: lex-agent fixes `Skill.handle`'s effect row without
`llm`, so an A2A handler is structurally incapable of calling a model
until that type changes upstream. The agent card it was meant to publish
is served today by the MCP server, on the same `/.well-known/agent.json`
path.

The VSCode extension was dropped once that server existed: one ACP
implementation reaches Zed, JetBrains, Neovim and Emacs, where the
extension reached one editor and was the only TypeScript in the repo —
so the only code `lex check`, `lex fmt` and CI could not see.

---

## License

EUPL-1.2 — matches the rest of the lex ecosystem.

---

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).
