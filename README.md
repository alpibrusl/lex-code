# lex-code

A Lex-native coding assistant — think Claude Code or Cursor, built entirely in the Lex ecosystem.

## Quickstart

```sh
# set provider key
export ANTHROPIC_API_KEY=sk-...

# build mode (default)
lex run src/tui/main.lex

# plan mode
lex run src/tui/main.lex -- --plan

# mistral provider
lex run src/tui/main.lex -- --mistral

# bootstrap demo: impl → spec → test → review
lex run src/bootstrap/run.lex

# A2A server
lex run src/server/api.lex
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
| `--multi` | Multi | Run Build + Test in parallel via `std.conc` |

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

## Providers

| Flag | Provider | Model |
|------|----------|-------|
| *(default)* | Anthropic | claude-3-7-sonnet |
| `--openai` | OpenAI | gpt-4o |
| `--google` | Google | gemini-2.0-flash |
| `--mistral` | Mistral | mistral-large-latest |
| `--ollama` | Ollama (local) | llama3 |

## Architecture

```
lex-code
├── src/
│   ├── agents/          # AgentDef values (build, plan, explore, refactor, spec, test, review)
│   ├── prompts/         # System prompts per mode
│   ├── tools/           # Tool implementations
│   │   ├── standard/    # read, write, edit, grep, glob, bash, todowrite
│   │   ├── lex_*.lex    # check, audit, run, test, spec_check, spec_smt
│   │   └── lex_store_*  # sigid, attestations, effects, diff, apply, merge
│   ├── permissions/     # lex-spec Spec values per agent mode
│   ├── server/
│   │   ├── session.lex  # Session type, run_turn, AgentMode
│   │   ├── multi_agent.lex  # std.conc parallel dispatch
│   │   ├── persist.lex  # lex-trail log helpers
│   │   └── api.lex      # A2A (JSON-RPC 2.0) server
│   ├── tui/main.lex     # CLI REPL
│   ├── vscode/          # VSCode extension (TypeScript)
│   ├── web/             # Web frontend (vanilla JS)
│   └── bootstrap/run.lex  # Demo 4-phase pipeline
└── lex.toml
```

## VSCode Extension

```sh
cd src/vscode
npm install
npm run build
# then install .vsix or press F5 in VSCode to debug
```

Open the panel: **Cmd+Shift+L** (Mac) / **Ctrl+Shift+L** (Linux/Windows).

Commands available via the Command Palette:
- `Lex Code: Open Chat`
- `Lex Code: Build mode`
- `Lex Code: Plan mode`
- `Lex Code: Refactor mode`
- `Lex Code: Spec mode`
- `Lex Code: Test mode`
- `Lex Code: Review mode`

Configure server URL, default mode, and provider via **Settings → Lex Code**.

## Web Frontend

```sh
# start the A2A server
lex run src/server/api.lex

# open in browser
open src/web/index.html
# or serve with any static server:
npx serve src/web
```

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

`src/bootstrap/run.lex` demonstrates a full 4-phase pipeline:

1. **impl** — Build agent writes the function
2. **spec** — Spec agent generates a lex-spec `Spec`
3. **test** — Test agent writes unit tests
4. **review** — Review agent checks the whole thing

## Permissions

Each agent mode has a `lex-spec` `Spec` value (in `src/permissions/rules.lex`) that
allowlists its tool set. At construction time, `with_permission_gate` (from `lex-llm`)
filters the tool list using the spec, so agents can only call the tools they're
authorised to use.

## Roadmap

- [x] v0.1 — agents, tools, TUI REPL, A2A server, lex-trail persistence
- [x] v0.2 — refactor/spec/test/review agents, store tools, lex-spec permissions, Mistral provider
- [x] v0.3 — parallel multi-agent (`std.conc`), VSCode extension, web frontend, bootstrap script
