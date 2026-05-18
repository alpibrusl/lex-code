# lex-code

A Lex-specialized coding assistant. Equivalent to Claude Code / Cursor / Aider for Lex codebases, built on top of `lex-llm` + `lex-agent` + `lex-trail` + `lex-spec`.

## Why Lex-specific?

| Generic assistant | lex-code |
|---|---|
| grep + LSP for search | SigId lookup — content-addressed identity |
| Guesses purity from comments | Effect-row aware — knows `[net]` vs `[pure]` from types |
| Run-then-recover | Pre-flight `lex check` before committing edits |
| File-level diff | AST-level structural merge via `lex-store` |
| Session log = chat transcript | `lex-trail` — content-hashed, replayable, attestable |

## Quickstart

```sh
export ANTHROPIC_API_KEY=sk-ant-...
# or MISTRAL_API_KEY / OPENAI_API_KEY / GOOGLE_API_KEY

lex run src/tui/main.lex main          # build mode (default)
lex run src/tui/main.lex main --plan   # plan mode
lex run src/tui/main.lex main --explore  # explore mode
```

## Agent modes

| Flag | Agent | Tools | Purpose |
|---|---|---|---|
| _(none)_ | `build` | all | Default developer agent |
| `--plan` | `plan` | read-only + todowrite | Writes plan to `.lex/plans/` |
| `--explore` | `explore` | read-only | Codebase navigation and Q&A |

## Tools

### Standard

| Tool | Description |
|---|---|
| `read` | Read file contents |
| `write` | Create or overwrite a file |
| `edit` | Exact string replacement (unique match enforced) |
| `grep` | `grep -rn` pattern search |
| `glob` | `find` by filename pattern |
| `bash` | Run a shell command |
| `todowrite` | Track remaining steps in `.lex/todos.md` |

### Lex-specific

| Tool | Wraps | Purpose |
|---|---|---|
| `lex_check` | `lex check` | Type-check files or whole project |
| `lex_audit` | `lex audit` | Semantic queries (`--calls`, `--effects`, `--impure`) |
| `lex_run` | `lex run` | Execute a Lex function |
| `lex_test` | `lex run tests/... run_all` | Run test suite |

## Providers

Set one environment variable; the matching provider is used automatically.

| Env var | Provider | Recommended model |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic | `claude-sonnet-4-6` (default) |
| `MISTRAL_API_KEY` | Mistral AI | `codestral-latest` for code tasks |
| `OPENAI_API_KEY` | OpenAI | `gpt-4o` |
| `GOOGLE_API_KEY` | Google | `gemini-2.5-pro` |
| _(none)_ | Ollama | any local model |

To switch model/provider, edit the agent definition in `src/agents/build.lex`.

## Architecture

```
lex-code
├── src/tui/main.lex        # REPL entry point
├── src/server/
│   ├── session.lex         # Session state + run_turn
│   ├── persist.lex         # lex-trail event logging
│   └── api.lex             # A2A server surface (lex-agent)
├── src/agents/             # AgentDef values (build/plan/explore)
├── src/tools/              # Tool implementations
└── src/prompts/            # System prompts per agent
```

## Dependencies

- [`lex-llm`](https://github.com/alpibrusl/lex-llm) — provider abstraction + agent loop
- [`lex-agent`](https://github.com/alpibrusl/lex-agent) — A2A protocol server/client
- [`lex-trail`](https://github.com/alpibrusl/lex-trail) — content-addressed event log
- [`lex-spec`](https://github.com/alpibrusl/lex-spec) — permission predicates (v0.2)

## Roadmap

- **v0.1** ✅ — `build` / `plan` / `explore` agents, standard + Lex tools, TUI, lex-trail persistence
- **v0.2** — `refactor` / `spec` / `test` / `review` agents; `lex_store_*` tools; per-agent lex-spec permission gating; two-agent parallel A2A run
- **v0.3** — VSCode extension; web frontend; bootstrap milestone (lex-code writes Lex stdlib end-to-end)
