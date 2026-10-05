# Security model

[README](../README.md) · [All docs](../README.md#documentation)

What an agent can and cannot do: effect grants enforced by the VM, permissions, and the outer lex-os sandbox.

## Permissions

Each agent mode has a `lex-spec` `Spec` value (in `src/permissions/rules.lex`) that
allowlists its tool set. At construction time, `with_permission_gate` (from `lex-llm`)
filters the tool list using the spec, so agents can only call the tools they’re
authorised to use.

## Running under lex-os

_Runnable: `examples/lex_os/run_mediated.sh`_

The permission gate above and `--allow-effects` are both *inside* the Lex
VM — real, but one process trusting itself. [lex-os](https://github.com/alpibrusl/lex-os)
is a separate, host-level sandbox: a supervisor *outside* the process
mediates a grant (filesystem/network/exec, each independently levelled)
and, on a KVM host, actually runs the mediated command inside a real
Firecracker microVM. The two boundaries stack — lex-os doesn't know or
care what `--allow-effects` list lex-code passed itself internally.

```sh
lex-code --lex-os --ollama "implement list.zip"
```

This re-execs the same `lex-code` invocation as `lex-os exec --manifest
lex-os/manifest.json -- lex-code ...` instead of running directly —
`lex-os/manifest.json` (shipped in this repo, installed alongside the
binary by `make install`) grants `filesystem: ReadWrite`, `network: Full`,
`exec: Sandboxed`, matching what Build/Refactor/Test modes actually need.
Override it with `LEX_OS_MANIFEST=/path/to/other.json`.

**Prerequisite:** `lex-os` isn't installed by lex-code's own installer —
it's a separate Rust project you build yourself:

```sh
git clone https://github.com/alpibrusl/lex-os
cd lex-os && cargo build --release -p lex-os -p lex-os-guest
# put target/release/{lex-os,lex-os-guest} on your PATH
```

Off a KVM host (most laptops), add `LEX_OS_SIMULATED=1` — lex-os's own
in-process perimeter, which it's explicit about **not** being a security
boundary, only the same grant-mediation logic running anywhere:

```sh
LEX_OS_SIMULATED=1 lex-code --lex-os --ollama "implement list.zip"
```

Verified end-to-end (simulated perimeter): a real `lex-code --ollama`
session, mediated through `lex-os exec`, actually wrote a file and passed
`lex check` — the audit chain recorded the mediated command, `exit_code:
0`, and the file was genuinely on disk afterward, not just claimed in
the transcript.

## Effect-typed orchestration + tamper-evident audit

A narrower, earlier demo of two specific manifesto guarantees (§VI, §VIII):

[![Demo — effect-typed orchestration + hash chain](https://asciinema.org/a/pdL5GnjFtakQi6bC.svg)](https://asciinema.org/a/pdL5GnjFtakQi6bC)

```sh
# run it yourself
bash examples/manifesto_full_chain/demo.sh
```
