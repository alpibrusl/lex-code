# lex-code

A Lex-native coding assistant — think Claude Code or Cursor, built entirely in the Lex ecosystem.

## Manifesto demo

Effect-typed parallel orchestration (§VI) + tamper-evident audit (§VIII) — verified live by the type checker:

[![Demo — effect-typed orchestration + hash chain](https://asciinema.org/a/yFiI8KVZf9HLTWie.svg)](https://asciinema.org/a/yFiI8KVZf9HLTWie)

```sh
# run it yourself
bash examples/manifesto_full_chain/demo.sh
```

## Quickstart

```sh
# set provider key
export ANTHROPIC_API_KEY=sk-...

# build mode (default), interactive REPL
lex run src/tui/main.lex

# one-shot CLI mode (exits after the task)
lex run src/tui/main.lex "implement list.zip"

# plan mode
lex run src/tui/main.lex -- --plan

# mistral provider
lex run src/tui/main.lex -- --mistral

# bootstrap demo: impl → spec → test → review
lex run src/bootstrap/run.lex

# A2A server (JSON-RPC 2.0)
lex run src/server/api.lex

# ACP server (BeeAI Agent Communication Protocol)
lex run src/server/acp.lex
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
| `--multi` | Multi | Run Build + Test in parallel via `std.conc` |

## Providers

| Flag | Provider | Model | Key required |
|------|----------|-------|--------------|
| *(default)* | Anthropic | claude-sonnet-4-6 | `ANTHROPIC_API_KEY` |
| `--openai` | OpenAI | gpt-4o | `OPENAI_API_KEY` |
| `--google` | Google | gemini-2.0-flash | `GOOGLE_API_KEY` |
| `--mistral` | Mistral | mistral-large-latest | `MISTRAL_API_KEY` |
| `--ollama` | Ollama (local) | codellama | none |
| `--vllm` | vLLM (local/remote) | `$VLLM_MODEL` | none |

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

## Server Protocols

### A2A (Agent-to-Agent, JSON-RPC 2.0)

```sh
lex run src/server/api.lex
```

Exposes the standard Google A2A protocol: `tasks/send`, `tasks/get`, `tasks/cancel`,
`tasks/sendSubscribe` (SSE). Agent card at `/.well-known/agent.json`.

### ACP (Agent Communication Protocol, BeeAI)

```sh
lex run src/server/acp.lex
```

Exposes a REST API compatible with the BeeAI ACP standard:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Agent info JSON |
| `POST` | `/runs` | Synchronous run — returns completed JSON |
| `POST` | `/runs/stream` | Streaming run — SSE events |

Example:
```sh
curl -X POST http://localhost:8080/runs \
  -H 'Content-Type: application/json' \
  -d '{"input":[{"role":"user","content":[{"type":"text","text":"write list.zip"}]}]}'
```

Streaming example:
```sh
curl -X POST http://localhost:8080/runs/stream \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -d '{"input":[{"role":"user","content":[{"type":"text","text":"write list.zip"}]}]}'
# event: run.started
# data: {"run_id":"...","status":"running"}
#
# event: run.completed
# data: {"run_id":"...","agent_id":"lex-code","status":"completed","output":[...]}
```

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
│   ├── agents/          # AgentDef values (build, plan, explore, refactor, spec, test, review)
│   ├── prompts/         # System prompts per mode
│   ├── tools/           # Tool implementations
│   │   ├── standard/    # read, write, edit, grep, glob, bash, todowrite
│   │   ├── lex_*.lex    # check, audit, run, test, spec_check, spec_smt
│   │   ├── lex_store_*  # sigid, attestations, effects, diff, apply, merge
│   │   └── vcs/         # 17 lex-vcs tools (ast_diff, op_*, branch_*, merge_*)
│   ├── permissions/     # lex-spec Spec values per agent mode
│   ├── server/
│   │   ├── session.lex      # Session type, run_turn, AgentMode
│   │   ├── multi_agent.lex  # std.conc parallel dispatch
│   │   ├── persist.lex      # lex-trail log helpers
│   │   ├── api.lex          # A2A server (JSON-RPC 2.0)
│   │   └── acp.lex          # ACP server (BeeAI REST protocol)
│   ├── tui/main.lex     # CLI REPL + one-shot mode
│   ├── vscode/          # VSCode extension (TypeScript)
│   ├── web/             # Web frontend (vanilla JS)
│   └── bootstrap/run.lex  # Demo 4-phase pipeline
├── bin/lex-code      # Shell wrapper (used by make install)
├── Makefile          # install / uninstall targets
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
filters the tool list using the spec, so agents can only call the tools they’re
authorised to use.

## Roadmap

- [x] v0.1 — agents, tools, TUI REPL, A2A server, lex-trail persistence
- [x] v0.2 — refactor/spec/test/review agents, store tools, lex-spec permissions, Mistral provider
- [x] v0.3 — parallel multi-agent (`std.conc`), VSCode extension, web frontend, bootstrap script
- [x] v0.4 — lex-vcs tools (17), CLI one-shot mode, Ollama + vLLM providers, install target
- [x] v0.5 — ACP server (`src/server/acp.lex`), ACP helpers in lex-agent

---

Built under the principles of [Trust Without Comprehension](https://alpibru.com/manifesto).
