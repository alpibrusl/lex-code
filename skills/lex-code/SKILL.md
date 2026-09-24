---
name: lex-code
description: Delegate a Lex-specific coding task (writing, fixing, or extending .lex source, or anything touching the Lex language/toolchain) to lex-code, a specialized Lex-native coding agent — with a result you can trust without reading the diff yourself, not just a transcript claiming success. Use this whenever the user's task involves Lex code, or when they explicitly ask to "use lex-code" / "integrate lex-code".
---

# lex-code

`lex-code` is a coding agent purpose-built for the [Lex](https://lexlang.org)
language — it knows Lex's effect-row type system, its stdlib, and its
idioms better than a general-purpose model prompted on the fly. When a task
touches `.lex` files or the Lex toolchain, delegate to it instead of writing
Lex yourself from general knowledge.

Full reference: <https://github.com/alpibrusl/lex-code#readme>. This file is
the short version — enough to decide when to use it and how to call it
without reading that whole document first.

## 1. Check it's installed

```bash
command -v lex-code >/dev/null 2>&1 || \
  curl -fsSL https://raw.githubusercontent.com/alpibrusl/lex-code/main/install.sh | bash
```

The installer also installs the Lex toolchain itself if it isn't already on
`PATH` (checking what `lex --version` actually prints, not just whether some
binary named `lex` resolves — `/usr/bin/lex` is `flex` on most systems).
Safe to re-run.

## 2. Pick a provider

No key needed — fully local:

```bash
lex-code --ollama "..."
```

Requires `ollama serve` running locally with a model pulled (default
`qwen3.8:27b-mlx`; `OLLAMA_MODEL` overrides it). If the user has a cloud
key already configured for this session (`ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, etc.), the matching flag (`--anthropic` is the default
with no flag, `--openai`, `--google`, `--mistral`) works the same way —
see the README's [Providers](https://github.com/alpibrusl/lex-code#providers)
table for the full list. Default to `--ollama` when unsure; it needs
nothing from the user.

## 3. Delegate — two patterns

**Quick, one-shot** — for a task you (the calling agent) will read the
result of and use your own judgment on:

```bash
lex-code --ollama "implement fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] in src/list.lex"
```

Exits after the task; the transcript is on stdout.

**Trustworthy, machine-verifiable** — when the calling agent needs a result
it can act on WITHOUT reading the diff itself (e.g. reporting back to a
human, or feeding a pipeline): hand lex-code a typed issue instead of a
prose task. It iterates against the type checker and the issue's own
acceptance examples, and the run ends with one line regardless of what the
model claims:

```bash
ISSUE_ID=$(lex issue create --title "add zip" --shape typed_delta \
  --api 'zip:(xs :: List[A], ys :: List[B]) -> List[(A, B)]' \
  --example 'zip([1,2],["a","b"]) => [(1,"a"),(2,"b")]')

lex-code "--issue=$ISSUE_ID" --ollama > /tmp/lex-code.log 2>&1

grep '^\[ISSUE_VERDICT\]' /tmp/lex-code.log
# [ISSUE_VERDICT]	verified	<issue_id>
```

Branch on that line — `verified` means the type checker and the issue's
examples actually passed, not that the model said so. `failed` /
`inconclusive` / `unavailable` are the other possible values.

## 4. Optional: an outer sandbox

If the calling agent's own environment doesn't already sandbox what it
runs, add `--lex-os` to run the whole lex-code session inside
[lex-os](https://github.com/alpibrusl/lex-os)'s host-level mediated
perimeter (real microVM isolation on a KVM host; needs `lex-os` built
separately — see the README's
[Running under lex-os](https://github.com/alpibrusl/lex-code#running-under-lex-os)
section). Not needed for a normal trusted CI/dev environment.

## Notes for the calling agent

- lex-code's own effect-row grant (what files/network/processes a session
  may touch) is separate from and stacks with whatever sandbox the calling
  agent already runs under — no extra wiring needed.
- Every invocation writes a durable trail to `.lex/sessions/<id>.db`; you
  don't need to parse the transcript for an audit record.
- If the task isn't actually about Lex, don't reach for lex-code — it's
  scoped to the Lex ecosystem, not a general coding agent.
