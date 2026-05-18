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

lex run src/tui/main.lex main                    # build mode (default)
lex run src/tui/main.lex main --plan             # plan mode
lex run src/tui/main.lex main --explore          # explore mode
lex run src/tui/main.lex main --refactor         # refactor mode
lex run src/tui/main.lex main --spec             # spec mode
lex run src/tui/main.lex main --test             # test mode
lex run src/tui/main.lex main --review           # review mode
lex run src/tui/main.lex main --multi            # impl + test agents in sequence
lex run src/tui/main.lex main --multi --mistral  # same, via Mistral
```

## Agent modes

| Flag | Agent | Tools | Purpose |
|---|---|---|---|
| _(none)_ | `build` | all | Default developer agent |
| `--plan` | `plan` | read-only + todowrite | Writes plan to `.lex/plans/` |
| `--explore` | `explore` | read-only + lex_audit | Codebase navigation and Q&A |
| `--refactor` | `refactor` | read/write/edit + lex_store_* + sigid/effects | SigId-aware rename, signature changes, effect-row migration |
| `--spec` | `spec` | read/write/edit + lex_spec_check + lex_spec_smt | Property spec author + random-check loop |
| `--test` | `test` | read/write/edit + lex_test + lex_run | Test suite author |
| `--review` | `review` | read-only + attestation_query + effects_of | Attestation-aware code review |
| `--multi` | impl + test | all | Impl agent then test agent on the same task |

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
| `lex_audit` | `lex audit` | Semantic queries (`--calls`, `--effects`, `--impure`, `--unattested`) |
| `lex_run` | `lex run` | Execute a Lex function |
| `lex_test` | `lex run tests/... run_all` | Run test suite |
| `lex_spec_check` | `lex spec check` | Random property-test a Spec |
| `lex_spec_smt` | `lex spec smt` | Export Spec to SMT-LIB for Z3 |
| `sigid_lookup` | `lex store lookup` | Find a function by content hash |
| `attestation_query` | `lex store attestations` | List attestation chain on a function |
| `effects_of` | `lex check --json --effects` | Get the effect row of a function |
| `lex_store_diff` | `lex store diff` | Content-addressed structural diff |
| `lex_store_apply` | `lex store apply` | Apply an AST-level Operation |
| `lex_store_merge` | `lex store merge` | 3-way structural merge |

## Providers

Set one environment variable; the matching provider is used automatically.

| Env var | Provider | Recommended model |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic | `claude-sonnet-4-6` (default) |
| `MISTRAL_API_KEY` | Mistral AI | `codestral-latest` for code tasks |
| `OPENAI_API_KEY` | OpenAI | `gpt-4o` |
| `GOOGLE_API_KEY` | Google | `gemini-2.5-pro` |
| _(none)_ | Ollama | any local model |

Pass `--mistral`, `--openai`, `--google`, or `--ollama` to override the active provider.

## Architecture

```
lex-code
├── src/tui/main.lex           # REPL entry point (all mode + provider flags)
├── src/server/
│   ├── session.lex            # Session state + run_turn_with_provider
│   ├── multi_agent.lex        # impl + test sequential dispatch
│   ├── persist.lex            # lex-trail event logging
│   └── api.lex                # A2A server surface (lex-agent)
├── src/agents/                # AgentDef values per mode
├── src/tools/                 # Tool implementations
├── src/prompts/               # System prompts per agent
└── src/permissions/rules.lex  # lex-spec Spec predicates per agent
```

## Dependencies

- [`lex-llm`](https://github.com/alpibrusl/lex-llm) — provider abstraction + agent loop
- [`lex-agent`](https://github.com/alpibrusl/lex-agent) — A2A protocol server/client
- [`lex-trail`](https://github.com/alpibrusl/lex-trail) — content-addressed event log
- [`lex-spec`](https://github.com/alpibrusl/lex-spec) — permission predicates

## Roadmap

- **v0.1** ✅ — `build` / `plan` / `explore` agents, standard + Lex tools, TUI, lex-trail persistence
- **v0.2** ✅ — `refactor` / `spec` / `test` / `review` agents; `lex_store_*` tools; `sigid_lookup` / `attestation_query` / `effects_of`; lex-spec permission rules; `--multi` sequential two-agent run
- **v0.3** — parallel multi-agent via `std.conc`; `AgentDef.permission` runtime gating in `lex-llm`; VSCode extension; web frontend; bootstrap milestone (lex-code writes Lex stdlib end-to-end)
