# lex-code, for humans

This is a walkthrough, not a reference — it gets you from "never used this"
to "comfortable using it daily." For the full command/flag/tool reference,
see the main [README](../README.md); this doc links back to it where it
matters.

## What it is

`lex-code` is a coding assistant, like Claude Code or Cursor, but built
entirely in the [Lex](https://lexlang.org) language and specialized for
writing Lex. It runs as a terminal program: you type a task, it reads your
code, writes and edits files, runs the type checker and tests, and reports
back — the same loop as any AI coding agent, with two things that are less
common:

- **It talks to whichever model you point it at** — Anthropic, OpenAI,
  Google, Mistral, a local Ollama model, vLLM, or an OpenCode-compatible
  proxy — with the same flags either way.
- **It can work from a typed contract instead of a paragraph of prose.**
  You can hand it an exact function signature and a set of examples, and
  it iterates until a type checker and those examples actually pass — not
  until it *says* it's done. This is the `--issue` workflow, covered below,
  and it's the part worth learning even if you skip everything else here.

## Before you start

You need the `lex` toolchain on your `PATH` (`lex --version` should print
something). If you don't have it, grab the release for your platform from
[github.com/alpibrusl/lex-lang/releases](https://github.com/alpibrusl/lex-lang/releases)
and put the binary on your `PATH`.

You also need a model to talk to. Pick one:

- **Cloud, zero setup beyond a key:** export `ANTHROPIC_API_KEY` (the
  default provider), or use `--openai`/`--google`/`--mistral` with their
  matching key env var.
- **Local, free, private:** install [Ollama](https://ollama.com), `ollama
  pull qwen2.5-coder` (or any coding model), and pass `--ollama` to every
  command below. Local models are noticeably weaker on anything but small,
  well-specified functions — see [Choosing a provider](#choosing-a-provider).

## Getting it

Fastest path — installs the Lex toolchain too, if you don't already have it:

```sh
curl -fsSL https://raw.githubusercontent.com/alpibrusl/lex-code/main/install.sh | bash
```

Or, from a clone (also what the one-liner does under the hood):

```sh
git clone https://github.com/alpibrusl/lex-code
cd lex-code
lex pkg install
```

That's enough to run it from the source tree with `./bin/lex-code`. If
you'd rather have a `lex-code` command on your `PATH`:

```sh
make install            # installs to /usr/local/bin + /usr/local/lib
# make install PREFIX=~/.local   # or a custom prefix
```

Everything below assumes `lex-code` on your `PATH`; if you're running from
the source tree, use `./bin/lex-code` instead. **Always use this wrapper,
not `lex run` directly** — it supplies the capability grant and step budget
a real session needs; see the README's [Quickstart](../README.md#quickstart)
if you're curious why.

## Your first conversation

From inside any Lex project (a directory with a `lex.toml`):

```sh
lex-code
```

You'll land in a prompt (`>`). Type a task in plain English and press Enter:

```
> add a function that reverses the words in a sentence
```

You'll see it stream its reasoning, open files, write code, and run the
type checker, then hand control back to the `>` prompt. Keep talking — it's
a conversation, not a one-shot command; ask it to fix something, add a
test, or explain what it just did. `Ctrl-D` exits.

If you'd rather script it or run it once from a shell:

```sh
lex-code "implement list.zip"
```

This runs one task and exits — the mode you want in CI or a script.

## Picking a mode

By default `lex-code` writes code (**Build** mode). A handful of flags
switch what it's for:

| You want it to... | Flag |
|---|---|
| Write or edit code (the default) | *(nothing)* |
| Sketch an approach first, no writes | `--plan` |
| Understand a codebase before touching it | `--explore` |
| Restructure existing code without changing behavior | `--refactor` |
| Review a diff for bugs, style, effect mistakes | `--review` |
| Write tests | `--test` |
| Check an implementation against its own spec, independently | `--verify` |

Flags combine with a task the same way: `lex-code --review "check the
changes in src/checkout.lex"`. The full mode list (including `--spec`,
`--bar`, and `--multi` for running two agents in parallel) is in the
README's [Agent Modes](../README.md#agent-modes) table.

## Choosing a provider

The default is Anthropic. Switch with a flag:

```sh
lex-code --mistral "..."
lex-code --ollama "..."          # local, needs `ollama pull <model>` first
lex-code --openai --plan "..."   # flags combine
```

A rule of thumb from actually running both: **cloud models handle
multi-step, ambiguous, or whole-package tasks well; local models are
reliable on small, precisely specified functions and unreliable on
anything bigger** — they'll either loop without converging or produce
code that looks right but overfits the examples you gave it (more on
that in the next section). If you're doing serious work and don't have a
cloud key, `--ollama` still works, but keep tasks small and check the
output.

## The good part: working from a typed contract

Prose tasks work, but they leave "done" up to the model's judgment. There's
a sharper way: tell it the *exact* signature and the examples that decide
whether it's right, and let a type checker be the judge.

```sh
lex issue create --title "digit_sum" --shape typed_delta \
  --api 'digit_sum:(n :: Int) -> Int:added' \
  --example 'digit_sum(1234) => 10' --example 'digit_sum(-56) => 11'
```

This prints an issue id. Now hand it to `lex-code`:

```sh
lex-code --issue=<id>
```

It reads the contract, implements it, and — this is the part that
matters — **it doesn't get to decide it's done**. The run always ends by
running `lex issue verify` against what it actually wrote, and the last
line tells you the real answer:

```
[ISSUE_VERDICT]	verified	<id>
```

If the examples don't pass, or the signature doesn't match, you get
`failed` and the exact reason (the wrong output, or the wrong type), not
a model's self-assessment. Every file it wrote also gets published with
this issue attached, so later you can ask "what was ever done for this
issue?" and get a real, provenance-backed answer.

**A caution worth internalizing, learned the hard way while building
this:** a passing verdict proves the examples hold, not that the
implementation is *correct*. A model under pressure can satisfy a handful
of examples by special-casing them — a lookup table dressed up as a
function — and the gate has no way to catch that from the contract alone.
If a function matters, write one or two more test cases yourself that
weren't in the original examples (a value it never saw, a boundary case)
and check the code, not just the verdict. Treat "verified" as "the stated
contract holds," not "this is definitely right."

### When you don't have a signature yet

If you only have a rough idea — "we need to clamp values into a range" —
you don't have to invent the exact signature yourself:

```sh
lex issue create --title "clamp values into a range" --shape free_form
lex-code --refine=<id>
```

In this mode it reads your code and *proposes* a typed contract — signatures
plus examples — instead of writing anything. It cannot approve its own
proposal; the run ends by printing the exact commands to review and decide:

```sh
lex issue proposals <id>
lex issue approve <proposal-id> --by you      # or: reject --notes "..."
lex-code --issue=<id>                          # now implement it
```

This is the same asymmetry as code review: the agent does the labor of
turning a vague idea into something checkable, and a human — you — is the
one who signs off on what "done" means before any code gets written to
satisfy it.

## Watching it work in a browser

If you'd rather watch a session as a chat feed instead of raw terminal
output — useful for a long-running task, or to show someone else what's
happening — start the web UI:

```sh
lex run --max-steps 20000000000 \
  --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/web.lex serve_web
```

and open `http://localhost:7700`. Every turn is visible live — tool calls
as they happen, not after the fact — and a session can be shared read-only
with `?watch=<session-id>`. Details in the README's
[Web sessions](../README.md#web-sessions) section.

## When something goes wrong

- **`command not found: lex-code`** — it's not on your `PATH`. Run it as
  `./bin/lex-code` from the repo, or `make install` first.
- **It refuses immediately with a provider error** — you're missing the
  matching API key env var for the provider you selected (see the
  [Providers](../README.md#providers) table).
- **A long task dies partway with a step-limit error** — you called `lex
  run` directly instead of the `lex-code` wrapper, which raises the
  default step budget. Use the wrapper.
- **It says something is missing an "effect"** — that's the model hitting
  Lex's type system, not a bug you need to fix; it's the model's job to
  add the right effect to its own function signature, and it usually does
  on the next turn. If it doesn't, tell it what it's missing.
- **A local model spins for a long time and writes nothing** — this is a
  known failure mode of small local models on open-ended tasks (see
  [Choosing a provider](#choosing-a-provider)); narrow the task or switch
  to a cloud provider.

## Where to go deeper

The [README](../README.md) is the full reference: every mode and tool,
project memory (so it remembers your codebase's conventions across
sessions), semantic search over your own code, running two agents in
parallel, the minimum-bar and independent-verification review modes, and
how the whole thing is built. This tutorial only covers enough to be
productive day to day.
