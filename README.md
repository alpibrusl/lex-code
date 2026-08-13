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
lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/tui/main.lex main -- --opencode "implement list.zip"

# override the default model (kimi-k2.7-code)
OPENCODE_MODEL=qwen3.7-max \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/tui/main.lex main -- --opencode "implement list.zip"

# via the LiteLLM proxy instead (shares one proxy + model list with lex-loom — see below)
LITELLM_MODEL=deepseek-v4-flash \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
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
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/tui/main.lex main

# one-shot via the --litellm flag
LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/tui/main.lex main -- --litellm "implement list.zip"

# OpenCode Go through the proxy instead of native --opencode
LITELLM_MODEL=kimi-k2.7-code \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/tui/main.lex main -- --litellm "implement list.zip"

# override the proxy URL (default: http://localhost:4000)
LITELLM_BASE_URL=http://gpu-box:4000 \
LITELLM_MODEL=qwen3-coder:30b \
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
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
  lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time \
  src/bootstrap/fizzbuzz_lex.lex main
# [fizzbuzz_lex] starting build via litellm
# [fizzbuzz_lex] done — steps: 71
```

```sh
$ lex check fizzbuzz.lex && lex run fizzbuzz.lex run_all
ok
0
```

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
- [x] v0.6 — OpenCode Go provider (native + via the bundled LiteLLM proxy, shared config with lex-loom)

---

## License

EUPL-1.2 — matches the rest of the lex ecosystem.

---

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).
