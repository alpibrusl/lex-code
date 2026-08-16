# lex-code — Agent Guidelines

A Lex-native coding assistant — agents, tools, TUI, and A2A/ACP
servers, all written in Lex. Read `lex agent-guidelines` in full
before writing code. The four highest-leverage discipline rules:

1. **Narrow effects, always.** `fn foo() -> [fs_write("/tmp/x")] T`,
   not `[fs_write]`. If the type checker rejects, narrow the body.
2. **Repair, don't regenerate.** `lex check --output json` →
   `lex repair --apply`. Only regenerate after two failed repairs.
3. **`examples {}` blocks on every pure fn.** They fold into the
   SigId and run at `lex check` time.
4. **Use the stdlib.** `std.crypto` for hashing, `std.regex` over
   hand-rolled scanners.

## The loop

```sh
lex pkg install                 # resolves lex-llm, lex-agent, lex-trail, lex-spec, lex-schema, ...
lex check <each src/*.lex file> # this repo has no tests/ dir — see below
lex fmt --check src/
```

There is no `tests/` directory. CI type-checks every file in `src/`
individually, then gates on the manifesto demo examples:

```sh
lex check examples/manifesto_parallel.lex          # must pass
lex check examples/manifesto_parallel_bad.lex      # must FAIL (missing [concurrent])
bash examples/manifesto_semantic_diff/run.sh        # semantic diff must surface the effect-row change
```

Treat those three as the regression suite until a real `tests/`
directory exists.

## Project-specific overrides — lex-code

- **Two call sites per agent mode, times seven files.** Each
  `src/agents/*.lex` (build, explore, plan, refactor, review,
  spec_agent, test_agent) defines one `AgentLoop`-builder per
  provider: `agent()` (Anthropic), `openai_agent()`, `mistral_agent()`,
  `google_agent()`, `vertex_agent()`, `ollama_agent()`,
  `vllm_agent()`, `litellm_agent()`, `opencode_agent()`. Adding a
  provider means adding the function to **all seven** files *and* a
  matching branch in `src/server/session.lex`'s `pick_agent` — a
  missing branch is a silent fallthrough, not a type error.
- **`select_provider_tag` (TUI) and `pick_agent` (session) must move
  together.** A new `--flag` in `src/tui/main.lex` with no matching
  `"tag" => ...` arm in `session.lex`'s `pick_agent` silently no-ops
  rather than failing to compile — always change both in the same
  commit.
- **Local-model tool budgets are curated, not accidental.**
  `ollama_agent`/`litellm_agent` use `tools.minimal_tools()` (build)
  or `[]` (every other mode) instead of `all_tools()` — 38 tool
  schemas overwhelm small local models (see the local-model
  compatibility table in `README.md`). Don't widen this without
  re-testing against a real local model.
- **Permission specs gate tool *visibility*, not just execution.**
  `ag.with_permission_gate(base, rules.<mode>_permission())` (from
  `src/permissions/rules.lex`) filters the tool list at construction
  time. Every provider variant for a given mode must be wrapped with
  the *same* permission spec — don't special-case one provider's tool
  list without updating its spec.
- **`src/server/session.lex` is the single turn-handling path.** The
  TUI, the A2A server (`src/server/api.lex`), the BeeAI ACP server
  (`src/server/acp.lex`), and the Zed Agent Client Protocol server
  (`src/server/client_protocol.lex`) are four transports over the same
  `Session`/`run_turn_with_provider` (`run_turn_streaming_with_provider`
  for the one transport — ACP — that needs a per-step callback). Extend
  `session.lex`, don't duplicate turn logic into a transport file.
- **Two different protocols are both called "ACP" in this repo.**
  `src/server/acp.lex` is BeeAI's REST-based Agent Communication
  Protocol. `src/server/client_protocol.lex` is Zed's JSON-RPC-over-
  stdio Agent Client Protocol — an unrelated standard that happens to
  share the acronym. Don't rename either file to disambiguate further;
  the doc comments at the top of each already do, and the README's
  "Server Protocols" section labels them accordingly.
- **LiteLLM config lives in `litellm/`.** `config.yaml` +
  `docker-compose.yml` are the reference proxy setup (Ollama local
  models, vLLM, ChatGPT/Claude subscription passthrough, OpenCode Go)
  — kept in sync with `lex-loom`'s own `litellm/` directory since both
  repos are meant to work against the same proxy. Don't fork the model
  list; add new entries to both repos together.
