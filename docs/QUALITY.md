# Quality gates

[README](../README.md) · [All docs](../README.md#documentation)

The minimum bar, independent verification, and the evaluation harness.

## Minimum bar mode

_Runnable: `examples/minimum_bar_probes.sh`_

`--bar` walks a project against a checklist and reports where it stands.
It never edits: the output is a work queue, in the order the gaps will
hurt.

The checklist is not invented here. It is the two "short version" cards
from [*Prompt to
Production*](https://github.com/alpibrusl/prompt-to-production) ch. 16
and [*Prompt to
Evidence*](https://github.com/alpibrusl/prompt-to-evidence) ch. 15 —
each book's five items with the worst consequence-to-effort ratio in it
— plus four items from the production checklist that a repository can
settle about itself. Fourteen in total, in `src/bar/ledger.lex`.

The interesting part is the tier on each item, because it is an
admission:

| Tier | Count | What lex-code does |
|------|-------|--------------------|
| `repo` | 6 | Runs a probe and reports the verdict **and its bound** |
| `attested` | 4 | Cannot verify. Asks, records who said it and when, and reports NOT DONE if nobody answers |
| `judgement` | 4 | Cannot verify. Asks for the reasoning, not a verdict |

Six of fourteen. "The database is backed up and a restore has actually
been performed" is a claim about the world, and no coding agent can
settle it — so BAR mode is forbidden from ticking it, and marking such
an item not-applicable requires a stated reason. A bare N/A is how a
checklist becomes a rubber stamp.

The six probes, all read-only:

| Probe | Item | What it cannot see |
|-------|------|--------------------|
| `secret_scan` | No secrets in the repository, checked through the history | Credentials in an unrecognised format; commits outside the range it reports |
| `git_remote` | A remote copy that is not your laptop | Whether the remote is reachable or current |
| `tests_present` | Tests exist for the paths that must not break | Which paths those are |
| `ci_on_pr` | Tests run on every PR and block the merge | Branch protection — it lives in the forge, so this probe never returns better than `partial` |
| `toolchain_pin` | What is pinned is pinned consistently | The `lex-*` packages, unpinned on purpose while they move fast; only the lex-lang toolchain is compared — `lex.toml` against every version named in `.github/workflows`, not a pin written in a Dockerfile or a README |
| `examples_coverage` | Tested against a case with a known answer | Which fns are pure; an `examples {}` block **is** the known-answer test, so this is a floor, not coverage |

```sh
lex run src/tui/main.lex -- --bar "walk this project"

# the probes alone, no model:
lex run --allow-effects io,proc src/bar/checks.lex gate '"."' '"src"'
```

That last command is also a CI step: lex-code is held to the bar it
walks other projects against. It fails the build on a `fail` verdict
only — `partial` is the honest state for an item a probe can half
answer, and failing on it would push the next author to weaken the
probe rather than answer the question.

It caught two real ones on the way in. First: `lex.toml` pinned
toolchain 0.10.10 while CI installed 0.10.11. Then, once that was
fixed, the probe itself turned out to be reading only the first
`LEX_VERSION` assignment it found — so `publish.yml`, which writes the
version inline in a download URL with no variable at all, had sat two
patch versions behind unnoticed. It now reads every lex-lang version
named in any workflow and names the file that disagrees.

## Independent verification mode

_Runnable: `examples/agent_modes/verify.sh`_

`--review` audits structure and trust — effects, attestations, SigIds,
"is this well-scoped". `--verify` answers a different question: "does
the implementation actually do what it claims", and it does not take
the implementation's own test file as evidence for that.

This came out of two real failures, on two different from-scratch
packages, that a build → test pipeline alone did not catch: a test
file with a broken relative import that made `lex test` refuse to even
load it, and two hand-typed 500+ character hex strings in a test file
that were each a few characters short — an error invisible by
inspection, and one that makes `lex test` fail for the wrong reason
(the test's own expected value was wrong, not the implementation). A
real algorithmic bug (a fold accumulator that overwrote its
accumulated list each step instead of appending) sat underneath both,
indistinguishable from "the test is wrong" until someone re-derived
the expected values independently.

So `--verify` is built around one rule: **an implementation's existing
test file is not independent evidence.** It:

- Re-derives expected output from the task's own cited spec (a
  worked example, a canonical test vector, an algorithm described
  step by step) — by hand, from first principles — rather than
  trusting a constant already sitting in the code or its test file.
- Says so explicitly when a cited spec's exact text isn't available to
  confirm against, rather than silently trusting whatever the
  implementation already assumes. lex-code has no web-access tool
  today, so an external standard cited by name (an RFC, a vendor spec)
  is exactly this case.
- Writes its own new verification file — never edits the
  implementation or its existing tests — and never reuses the
  implementation's own expected-value constants.
- Never hand-types one long literal as a single comparison: a
  multi-word hex string or long JSON blob gets built from smaller,
  individually-labeled pieces and joined, so a wrong piece is visible
  by inspection instead of buried in one long string.
- Reports every case checked, not just failures — "all N checked, all
  pass" is itself the finding when nothing is wrong.

It never edits anything (`verify_permission`: `read`, `write` — for its
own new file only — `grep`, `glob`, `lex_check`, `lex_run`, `lex_test`;
no `edit`, no `bash`) — a verifier that can shell out or patch the
implementation directly can quietly fix around what it finds instead of
reporting it.

```sh
lex run src/tui/main.lex -- --verify "check src/bar/checks.lex's verdict_label function against its own examples{} block"

# as a pipeline stage, after build and test:
lex run src/tui/main.lex -- --multi --pipeline=impl_then_test_then_verify
```

## Eval harness

_Runnable: `examples/eval_harness_quick.sh`_

Nothing else in this repo measures whether lex-code writes good Lex — CI
checks types, formatting, doc-sync, unit tests, and that tools invoke real
commands, all upstream of that question. `make eval` runs a small, fixed set
of task specs against a fixed set of providers and reports a pass/fail table.

```sh
make eval
EVAL_PROVIDERS="litellm anthropic" EVAL_TASKS="examples/tasks/zip.task" scripts/eval.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `EVAL_TASKS` | the 4 tasks below | space-separated task-spec paths |
| `EVAL_PROVIDERS` | `litellm` | space-separated provider tags |
| `EVAL_PIPELINE` | `build` | pipeline preset or spec (see "Pipeline specs" above) |
| `EVAL_STRICT` | unset | `1` to hard-fail on an unconfigured provider instead of skipping it |
| `EVAL_RESULTS_DIR` | `.lex/eval-runs/<timestamp>` | per-run logs + preserved `.lex/` trail |

Scoring is exactly what `src/task_spec.lex`'s `is_satisfied` already computes
per task — `lex check` on the touched files, the task spec's `examples {}`
blocks, and its `verified`/`verified_on` criteria. No LLM judge: a criterion
that could not be run counts as unmet, the same reasoning `task_spec.lex`'s
own header already uses to keep it honest. `scripts/eval.sh` doesn't
reimplement any of that — it runs `bootstrap/run.lex` once per (task,
provider) pair and greps the verdict and step-count lines it already prints.

Four of the five task shapes from
[#86](https://github.com/alpibrusl/lex-code/issues/86) are covered:

| task | what it tests |
|---|---|
| `examples/tasks/zip.task` | pure fn, generics, `examples {}` |
| `examples/tasks/effect_narrow.task` | effect discipline — a narrow `[env]` row |
| `examples/tasks/repair_examples.task` | reading a `lex check` error and repairing it |
| `examples/tasks/widen_effect.task` | `propagate_effect` — widen a leaf's row, propagate to 2 callers |

The fifth ("answer a question without editing") is **not** built here:
`SuccessCriterion` has no way to express "no files changed," and adding a new
criterion kind is out of scope for a first version whose point is to ship the
case that's already fully supported. Additive later.

Each (task, provider) pair runs in its own `git worktree` checked out from
`HEAD`, torn down after. This is why: `.lex/verified.jsonl` is append-only and
project-scoped with no content hash binding a record to what it was a pass of
([#91](https://github.com/alpibrusl/lex-code/issues/91)) — a stale record from
an earlier run can satisfy a later, unrelated run's criteria in the same
working tree. A worktree sidesteps this rather than working around it:
`.lex/` is gitignored, so a fresh worktree has no `.lex/verified.jsonl` to
inherit from at all. One consequence: `make eval` only ever evaluates the
last **committed** state — uncommitted edits to a task spec or fixture are
invisible to it until committed.

Not run in CI: it needs a provider — a key, or a local `litellm`/`ollama`/
`vllm` daemon — and a full matrix against a local model can take many
minutes. A CI job gated on a secret can come later.
