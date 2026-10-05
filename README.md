# lex-code

[![CI](https://github.com/alpibrusl/lex-code/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-code/actions/workflows/ci.yml)
[![License: EUPL-1.2](https://img.shields.io/badge/license-EUPL--1.2-blue.svg)](LICENSE)

**A coding assistant for [Lex](https://lexlang.org) that proves its work.**

Most coding assistants hand you a transcript and ask you to read the diff.
lex-code hands you a verdict: every task ends in a machine-readable result
produced by the type checker and by examples written *before* the code, not by
what the model says about itself. It can plan and build a whole package from a
brief, run unattended on a local model, and leave a report of what happened.
It is written in Lex, so it runs under the same effect-typed sandbox it enforces.

```sh
lex-code --ollama "implement list.zip"          # one task, fully local, no key
lex-code --issue=<id> --ollama                  # implement a typed issue, then verify it
lex-code-overnight --name=invoices --brief-file=brief.txt --ollama   # a whole package, unattended
```

## Contents

- [What it does](#what-it-does)
- [Install](#install)
- [Quick start](#quick-start)
- [How a result gets checked](#how-a-result-gets-checked)
- [Modes](#modes)
- [Providers](#providers)
- [Safety model](#safety-model)
- [Documentation](#documentation)
- [Status and limits](#status-and-limits)
- [Development](#development)
- [License](#license)

## What it does

- **Verifies, doesn't narrate.** A *typed issue* is a contract: exact
  signatures plus the examples that decide whether it holds. `--issue=<id>`
  iterates against the type checker and those examples and ends with one
  `[ISSUE_VERDICT]` line, whatever the model claims.
- **Builds whole packages.** Give it a brief. It drafts a graph of typed issues,
  checks the plan before spending a token on code, builds the units in
  dependency order, hardens them with generated invariants, starts the real
  program and replays black-box scenarios against it, and repairs what fails.
- **Runs while you sleep.** `lex-code-overnight` resumes a build across rounds,
  waits out a provider that goes away, restores the shared source file after a
  kill, and writes a report: verdict, per-unit attempts and tokens, what is
  still wrong.
- **Is sandboxed by the language.** Every session runs under an explicit
  capability grant enforced by the Lex VM: the agent cannot use `net`,
  `fs_write` and the like unless it was granted them. `--lex-os` adds an outer,
  host-level perimeter.
- **Works with any provider, including none.** `--ollama` runs entirely on your
  machine. Cloud and OpenAI-compatible providers use the same flags.
- **Leaves a trail.** Each session is a database of events, each issue is in a
  content-addressed store, and a running build has a read-only live dashboard.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alpibrusl/lex-code/main/install.sh | bash
```

This installs the pinned Lex toolchain if `lex` is not already on your `PATH`,
resolves lex-code's own dependencies, and installs `lex-code` and
`lex-code-overnight`. It is safe to re-run. macOS and Linux; on Windows use WSL.
Set `LEX_CODE_PREFIX=~/.local` to install somewhere other than `/usr/local`.

From a checkout instead: `make install` (or `make install PREFIX=~/.local`),
and `make uninstall` to remove it. See [docs/INSTALL.md](docs/INSTALL.md).

## Quick start

Run with a local model, no key:

```sh
lex-code --ollama                         # interactive session in the current directory
lex-code --ollama "implement list.zip"    # one task, then exit
lex-code --plan --ollama                  # plan only; nothing is written
```

Use a cloud provider by selecting its flag and setting its key
(see [Providers](#providers)):

```sh
export OPENCODE_API_KEY=...
lex-code --opencode "implement list.zip"
```

A whole package, in stages you can stop at (each stage's last line is
machine-readable, and every file in between is one you can read and edit):

```sh
lex-code --package "a small invoice REST API ..." --name=invoices --ollama   # 1. plan; files nothing
lex-code --package-check=invoices                                             # 2. re-validate after you edit it
lex-code --package-apply=invoices                                             # 3. file the reviewed plan as issues
lex-code --project=invoices --ollama > invoices.log 2>&1 &                    # 4. build, harden, accept, repair
lex-code --dashboard=invoices                                                 #    watch it live (127.0.0.1:7800)
```

Or do all of it unattended, with a report at the end (`.lex/overnight/REPORT.md`):

```sh
lex-code-overnight --name=invoices --brief-file=brief.txt --ollama
```

[docs/TUTORIAL.md](docs/TUTORIAL.md) is a walkthrough of installing, a first run,
picking a mode and the typed-issue workflow.

## How a result gets checked

| Check | What it catches | Where |
|---|---|---|
| **Typed issue verification** | code that does not match its declared signatures or fails its own examples | [Modes](docs/MODES.md) |
| **Plan check** | a plan that cannot be built: unbuildable examples, cycles, a function named like one a dependency exports, invariants that can never fail | [Packages](docs/PACKAGES.md) |
| **Regression pass** | a unit that was verified and was broken by a later one | [Packages](docs/PACKAGES.md) |
| **Hardening** | violations of invariants the plan itself declared, checked on generated inputs | [Packages](docs/PACKAGES.md) |
| **Acceptance gate** | a package whose units all verify but which does not run: the real program is started and the brief's requirements are replayed as requests | [Packages](docs/PACKAGES.md) |
| **Integration repair** | failures that only exist once the units share a file; handed back to a model as one task | [Packages](docs/PACKAGES.md) |
| **Independent verification** | an implementation that satisfies its own tests but not the task: expected output is re-derived from the spec | [Quality](docs/QUALITY.md) |
| **Minimum bar** | a project that is missing the basics, checked read-only | [Quality](docs/QUALITY.md) |

"Verified" is necessary, not sufficient: a unit's examples are a finite list.
That is why a package build ends by *running* the program, and why you should
attack the result yourself (see [Status and limits](#status-and-limits)).

## Modes

| Flag | Mode | Role |
|------|------|------|
| *(default)* | Build | Write and edit Lex source files |
| `--plan` | Plan | Produce implementation plans, no writes |
| `--explore` | Explore | Read and search the codebase |
| `--refactor` | Refactor | Restructure code, rename, inline |
| `--spec` | Spec | Generate lex-spec `Spec` values |
| `--test` | Test | Write unit and property tests |
| `--review` | Review | Review correctness, style and effects |
| `--verify` | Verify | Re-derive expected output from the spec and check the implementation |
| `--bar` | Bar | Walk a project against the minimum bar, read-only |
| `--multi` | Multi | Build and test in parallel |
| `--issue=<id>` | Build | Implement a typed issue from its declared acceptance, then verify it |
| `--refine=<id>` | Build | Propose a typed acceptance for a free-form issue; a human approves it |

Modes can be chained into pipelines (`--pipeline=impl_then_test`). Details in
[docs/MODES.md](docs/MODES.md) and [docs/PIPELINES.md](docs/PIPELINES.md).

## Providers

| Flag | Provider | Needs |
|------|----------|-------|
| `--ollama` | Ollama, local | nothing; model from `$OLLAMA_MODEL` (default `qwen3.8:27b-mlx`) |
| `--opencode` | OpenCode Go, cloud | `OPENCODE_API_KEY`; model from `$OPENCODE_MODEL` |
| `--vllm` | Any OpenAI-compatible server | `VLLM_BASE_URL`, `VLLM_MODEL` |

Also implemented, with less mileage: `--litellm`, `--lex-gpu`, `--openai`,
`--mistral`, `--google`, `--vertex`, and Anthropic (the default when no flag is
given). Only the three above have been run end to end in this repository. Pick a
model on the command line with `--ollama-model=X`, `--opencode-model=X` and the
like. See [docs/PROVIDERS.md](docs/PROVIDERS.md).

## Safety model

- **Capability grants, enforced by the VM.** A session runs under
  `--allow-effects` and cannot perform an effect it was not granted, whatever
  its prompt says.
- **A permission gate** sits in front of the tools that change things.
- **An outer sandbox on request.** `--lex-os` runs the whole session inside
  lex-os's host-level perimeter.
- **Unattended runs execute shell commands.** Run `lex-code-overnight` in a
  dedicated project directory (or with `--lex-os`), not in a checkout you care about.
- **The dashboard listens on `127.0.0.1` only** and is read-only.

See [docs/SECURITY.md](docs/SECURITY.md).

## Documentation

| | |
|---|---|
| [Tutorial](docs/TUTORIAL.md) | Install, first run, modes, the typed-issue workflow |
| [Install and run](docs/INSTALL.md) | Installing, from a checkout, running |
| [Modes](docs/MODES.md) | Agent modes, typed issues, parallel agents |
| [Building whole packages](docs/PACKAGES.md) | Plan, build, accept, repair, dashboard, overnight, report |
| [Pipelines](docs/PIPELINES.md) | Chaining modes, task specs, the fix loop |
| [Providers](docs/PROVIDERS.md) | Selecting and configuring a model provider |
| [Delegating from another agent](docs/DELEGATION.md) | Using lex-code from Claude Code, Cursor, Codex |
| [Servers and the web UI](docs/SERVER.md) | Web UI, HTTP API, MCP and ACP servers, sessions |
| [Tools](docs/TOOLS.md) | Built-in tools and external tools over MCP |
| [Memory, search and observability](docs/MEMORY.md) | Project memory, semantic search, OpenTelemetry |
| [Quality gates](docs/QUALITY.md) | Minimum bar, independent verification, the eval harness |
| [Security model](docs/SECURITY.md) | Effect grants, permissions, lex-os |
| [Architecture](docs/ARCHITECTURE.md) | How it is put together |
| [Examples](examples/README.md) | Runnable checks for the major claims |

## Status and limits

lex-code is young and has mostly been run with one local model. What that does
and does not support:

- **Builds work end to end, but not every time.** Whole-package builds have gone
  from a brief to a passing acceptance gate, and have also stalled; the causes
  found so far were defects in the plan, in a tool, or in a library trap, and
  each now has a check. A different brief or library can still find a new one.
- **A passing gate is not a security review.** The acceptance scenarios come from
  the brief's own requirements. An independent attack on a finished build found a
  case the scenarios had not covered, so treat `done` as "meets the brief as
  tested", and test the result yourself before exposing it.
- **Local models are slow.** A whole package takes hours on a laptop-class local
  model; the overnight supervisor exists for that.
- **Thinking mode and the repair-round count are tuned from small runs**, not
  from a benchmark.

## Development

lex-code is written in Lex and checks itself with the same tools it asks of
others. CI runs, from the repository root:

```sh
lex pkg install
lex check <each src/*.lex and tests/*.lex>    # type-check every file
lex fmt --check src/ tests/                    # formatting
lex doc-sync --check                           # generated docs are current
lex test --allow-effects crypto,fs_read,fs_write,io,proc,random,sql,time tests
bash scripts/test-overnight.sh                 # the overnight supervisor, against a stand-in
```

[AGENTS.md](AGENTS.md) is the contract for any agent working on this repository
(it is generated from `lex agent-guidelines`; `lex doc-sync` keeps it current).
`make hooks` installs the pre-commit hook.

## License

[EUPL-1.2](LICENSE), matching the rest of the Lex ecosystem.

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).
