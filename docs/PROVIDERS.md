# Providers

[README](../README.md) · [All docs](../README.md#documentation)

Every model provider lex-code supports, how to select one, and what each needs.

## Providers

lex-code can talk to ten provider backends (see `--help` for the full
flag list — Anthropic, OpenAI, Google, Mistral, LiteLLM, lex-gpu and Vertex
are implemented in code alongside the three below), but only these three have
actually been run end-to-end against this repo:

| Flag | Provider | Model | Key required |
|------|----------|-------|--------------|
| `--ollama` | Ollama (local, native API) | `$OLLAMA_MODEL` (default `qwen3.8:27b-mlx`) | none |
| `--opencode` | OpenCode Go plan (cloud, direct) | `$OPENCODE_MODEL` | `OPENCODE_API_KEY` |
| `--vllm` | Any OpenAI-compatible server (vLLM, a local inference engine) | `$VLLM_MODEL` | none; `$VLLM_BASE_URL` = the full `.../v1/chat/completions` URL |

Every env-var-driven provider's model can also be set on the command line
instead of a separate `export` — `bin/lex-code` turns the flag into the
matching export before invoking the agent: `--opencode-model=X`,
`--ollama-model=X`, `--litellm-model=X`, `--vllm-model=X`,
`--lex-gpu-model=X`. A generic `--opencode --model=X` resolves against
whichever provider flag is present (same precedence `select_provider_tag`
uses to pick the provider itself). Anthropic/OpenAI/Mistral/Google/Vertex
build their model from a fixed constructor rather than an env var, so
`--model` with one of those is a hard error for now, not a silent no-op.

### lex-gpu

`--lex-gpu` points at [lex-gpu](https://github.com/alpibrusl/lex-gpu)'s
server, which answers OpenAI chat completions from its own compiled Metal
and CUDA kernels rather than llama.cpp or MLX. No key; `$LEX_GPU_BASE_URL`
overrides the default `http://127.0.0.1:8080`.

```sh
cargo run --release -p lex-rt --example serve -- --model qwen3.8:27b-mlx
lex-code --lex-gpu --explore "what does src/agents/build.lex do?"
```

**Chat only, for now.** lex-gpu accepts a `tools` list and drops it, so the
model is never told the tools exist and its replies carry no `tool_calls` —
the agent loop gets an answer and never dispatches a tool, which for a
coding agent means it will describe work rather than do it. The wiring is
here so that it starts working the moment lex-gpu renders `tools` into its
prompt and splits `<think>` out of `content`; neither needs a change on
this side.

### Ollama

_Runnable: `examples/providers/ollama.sh`_

Fully local, no key. Verified with the default model (`qwen3.8:27b-mlx`),
including a full `--issue=<id>` run through to an `[ISSUE_VERDICT]\tverified`
close (see [Delegating to it from another agent](DELEGATION.md#delegating-to-it-from-another-agent-claude-code-etc)).

```sh
ollama pull qwen3.8:27b-mlx   # or set OLLAMA_MODEL to whatever you have
lex-code --ollama "implement list.zip"
```

### OpenCode Go plan

_Runnable: `examples/providers/opencode_go.sh`_

[OpenCode Go](https://opencode.ai/docs/zen) bundles cloud access to several
open-weight coding models behind one subscription key.

```sh
export OPENCODE_API_KEY=...
lex-code --opencode "implement list.zip"
```

```sh
$ lex check fizzbuzz.lex && lex run fizzbuzz.lex run_all
ok
0
```
