# Examples

Every script here is a runnable check for a specific claim in the main
[README](../README.md) — not a tutorial, a regression test you can run by
hand. Each one prints what it's verifying and ends with a clear PASS/FAIL
signal.

| Script | Verifies |
|---|---|
| `providers/ollama.sh` | [Providers → Ollama](../README.md#ollama) |
| `providers/opencode_go.sh` | [Providers → OpenCode Go plan](../README.md#opencode-go-plan) |
| `delegate_via_typed_issue.sh` | [Delegating to it from another agent](../README.md#delegating-to-it-from-another-agent-claude-code-etc) — the `[ISSUE_VERDICT]` line a calling agent branches on |
| `lex_os/run_mediated.sh` | [Running under lex-os](../README.md#running-under-lex-os) |
| `agent_modes/multi.sh` | [Parallel Multi-Agent](../README.md#parallel-multi-agent-stdconc) |
| `agent_modes/verify.sh` | [Independent verification mode](../README.md#independent-verification-mode) |
| `minimum_bar_probes.sh` | [Minimum bar mode](../README.md#minimum-bar-mode)'s no-model probes command |
| `mcp_server_smoke.sh` | [Server Protocols → MCP](../README.md#mcp-model-context-protocol) |
| `acp_server_smoke.py` | [Server Protocols → ACP](../README.md#agent-client-protocol-acp-zed--phase-1) |
| `semantic_search/build_and_query.sh` | [Semantic search](../README.md#semantic-search) — builds a real index, queries it, checks the top hit is actually relevant |
| `observability_stdout.sh` | [Observability](../README.md#observability-opentelemetry) |
| `eval_harness_quick.sh` | [Eval harness](../README.md#eval-harness) |
| `bootstrap_custom_task.sh` | [Bootstrap Script](../README.md#bootstrap-script)'s env-var overrides |
| `web_frontend_smoke.sh` | [Web Frontend](../README.md#web-frontend) |
| `manifesto_full_chain/`, `manifesto_semantic_diff/`, `manifesto_parallel*.lex` | [Trust Without Comprehension — live demo](../README.md#trust-without-comprehension--live-demo) |
| `tasks/*.task` | [Bootstrap Script → Task specs](../README.md#bootstrap-script) — consumed by `eval_harness_quick.sh` / `make eval` |

## Prerequisites

Most scripts need Ollama running locally (`ollama serve`, default model
`qwen3.8:27b-mlx` pulled) — free, no key. A few need more:

- `providers/opencode_go.sh` — `OPENCODE_API_KEY`
- `lex_os/run_mediated.sh` — `lex-os`/`lex-os-guest` built and on `PATH`
- `semantic_search/build_and_query.sh` — Docker, and `ollama pull nomic-embed-text`

## What this caught

Building `semantic_search/build_and_query.sh` — actually running the
README's documented commands rather than trusting them — found three real
bugs in the bundled `litellm/` setup that made "Semantic search" silently
non-functional:

1. `litellm/config.yaml`'s `chatgpt/*` entries resolve their OAuth device-code
   flow at **proxy boot**, not lazily "on first request" as the config's own
   comment claimed — blocking the whole proxy (every model, not just those
   entries) until someone completes it interactively. Commented out by
   default.
2. Newer `litellm:main-latest` refuses to boot with no master key configured
   at all. `docker-compose.yml` never set one.
3. `src/embed.lex`'s `embed_one` never sent an `Authorization` header at
   all, so every embedding call 401'd once (2) was fixed. Fixed in
   `src/embed.lex`/`src/index_build.lex`/`src/tools/semantic_search.lex` —
   see those files' comments for why the key is threaded as a plain
   parameter rather than folded into the persisted index header.
