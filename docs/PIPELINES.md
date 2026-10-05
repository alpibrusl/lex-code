# Pipelines, task specs and the fix loop

[README](../README.md) · [All docs](../README.md#documentation)

Chaining modes (impl, spec, test, review), specifying what "done" means, and the fix loops.

## Bootstrap Script

_Runnable: `examples/bootstrap_custom_task.sh`_

`src/bootstrap/run.lex` runs a multi-phase pipeline against a real task. It
used to hardcode one — implement `list.zip`, in four fixed phases, with its
own sequential runner — and now drives the same agent graph the TUI does.

This entry point needs the same `--max-steps` override the Quickstart's
`bin/lex-code` wrapper supplies for the TUI, and for the same reason: it's
trusted, long-running orchestration code, not the untrusted-sandboxed-snippet
case the VM's 10,000,000-step default guards against. There's no wrapper
script for this entry point, so it has to be typed by hand every time —
omit the flag and a long run panics with `step limit exceeded`, and because
`bootstrap/run.lex` only prints step-by-step after the graph run returns, the
whole run's output is lost, not just the final result.

```sh
# the original demo, unchanged
lex run --max-steps 20000000000 --allow-effects … src/bootstrap/run.lex main

# a real task, phases of your choosing
LEX_TASK="add a retry wrapper to src/http.lex" \
LEX_PIPELINE=build,test \
LEX_PROVIDER=litellm \
  lex run --max-steps 20000000000 --allow-effects … src/bootstrap/run.lex main
```

| Variable | Default | Meaning |
|---|---|---|
| `LEX_TASK` | the `list.zip` demo | what to build |
| `LEX_PIPELINE` | `impl_then_spec_then_test` | preset name, or a spec |
| `LEX_PROVIDER` | `anthropic` | provider tag |

### Task specs — checking that it got done

A task is a string, and whether it got done is whatever the agent says at the
end. That is the one claim in this system with nothing behind it. A task spec
pairs the goal with criteria a machine evaluates afterwards.

`examples/tasks/zip.task`:

```toml
goal = "Add fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] to src/list.lex"

check       = ["src/list.lex"]        # lex check must pass
spec_check  = []                      # lex spec check
test        = []                      # lex run <path> run_all
verified    = ["verified.type_check"] # a pass of this kind, anywhere
verified_on = []                      # "<path>:<kind>" — a pass on that path
```

```sh
LEX_TASK_SPEC=examples/tasks/zip.task \
  lex run --max-steps 20000000000 --allow-effects … src/bootstrap/run.lex main
```

The spec's `goal` becomes the task the agents are told, so the words they act
on and the criteria they are judged against come from one file and cannot
disagree. When the pipeline finishes:

```
task "the task_spec module itself type-checks": SATISFIED
  ok    lex check src/task_spec.lex
  ok    lex check src/embed.lex
```

Every criterion runs — no stopping at the first failure, so one round of work
can address all of them. **A criterion that could not be evaluated counts as
unmet**: treating an unrunnable check as satisfied would turn a broken
toolchain into a passing task. And **a spec with no criteria reports
UNVERIFIED**, not satisfied — "all of nothing succeeded" is vacuously true and
exactly the wrong answer.

Two fields from the original design are deliberately absent. `allowed_effects`
would be a third mechanism constraining effects after `os_check` and
`permissions/rules.lex`, and a declaration nothing enforces still reads as a
guarantee. `inputs` would be a type hint no code consumes. Both are additive
later; neither is load-bearing for `is_satisfied`.

`verified` asserts a pass of that kind happened somewhere in the project;
`verified_on` narrows it to a path:

```toml
verified    = ["verified.type_check"]
verified_on = ["src/list.lex:verified.type_check"]
```

A malformed `verified_on` entry becomes a criterion that can never be met,
rather than being dropped — a typo should fail the task loudly, not silently
shrink what it checks.

The path is as far as this goes. Since [lex-llm#48](https://github.com/alpibrusl/lex-llm/pull/48)
a `verified.*` record names the argument the tool was given (`lex check
src/list.lex`), and a file is not a function, so neither criterion can say
`zip` in particular was checked. Function-level evidence needs the store's
attestation graph, which is what `lex blame --with-evidence` reads and what
`attestation_query` calls the stronger signal.

`verified.type_check`/`.spec_check`/`.test` are written by lex-llm's own
dispatcher whenever `lex_check`/`lex_spec_check`/`lex_test` reports a pass —
mechanical evidence the tool actually ran and actually passed, not the
model's word for it. `verified.independent_check` is the fourth kind, and
it is lex-code's own: a bare `lex_run` pass proves nothing on its own (an
ordinary build-mode run passing is not evidence of anything beyond "the
function didn't crash"), so it is written directly by
`impl_test_fix_loop_verified`'s fix-loop gate (`graph.lex`'s
`attest_verify_pass_if_clean`) only when a `verify`-mode agent's own
`lex_run` came back clean — the strongest evidence in the system, since
verify re-derives the expected output instead of trusting anything on
disk. A task spec can require it the same way as the others:
`verified = ["verified.independent_check"]`.

### Pipeline specs

A spec is two characters of grammar: `,` runs stages in order, `|` runs them
at once. Agents are `build` (alias `impl`), `spec`, `test`, `review`, `verify`.

```
build,test              impl → test
build|test              impl ∥ test
build,spec,test|review  impl → spec → (test ∥ review)
build,test,verify       impl → test → verify
```

The last two are exactly the `impl_then_spec_then_test` and
`impl_then_test_then_verify` presets — an `examples {}` case asserts each
pair stays equal, so the grammar and the named presets cannot drift apart.

The same values work on the TUI's `--pipeline=` flag, which takes a preset
name or a spec. An unrecognised agent is refused with the list of valid ones
rather than skipped: a pipeline quietly missing a stage is a run that looks
successful and did less than it was asked to.

### The fix loop — `impl_test_fix_loop`

Every preset above runs each stage exactly once, win or lose: if `test`'s
tests fail, that failure is just the pipeline's final state — nothing
reruns `build` with it. `impl_test_fix_loop` (`--pipeline=impl_test_fix_loop`,
or `LEX_PIPELINE=impl_test_fix_loop` for the bootstrap script) does: `impl →
test`, then a real subprocess (`lex test tests`, the same command
`lex_test`'s tool wraps) decides pass or fail by exit code — never by asking
the fixing agent whether it thinks it's done, the same "mechanical, not
LLM-judged" rule `examples/tasks/*.task`'s criteria already apply to one task,
extended across attempts. On a nonzero exit it re-runs `impl` (up to twice)
with that command's actual output appended to the task, so the model is
fixing a named failure, not guessing at one. Each retry gets its own session
id (`impl_retry1`, `impl_retry2`) so the persistent trail keeps every
attempt separately, `.lex/sessions/impl_retry1.db` included, rather than a
later round colliding with an earlier one on disk. It is preset-only — the
`,`/`|` spec grammar composes fixed agent names, and a retry loop isn't one.

### The fix loop, verified — `impl_test_fix_loop_verified`

`lex test tests` exiting 0 is evidence the test file's own assertions held,
not evidence they asserted the right thing (a mistyped expected value in an
implementation's own tests passes its own tests). `impl_test_fix_loop_verified`
(`--pipeline=impl_test_fix_loop_verified`) is `impl_test_fix_loop` with one
more gate: once `lex test tests` passes, a `verify` agent runs and
independently re-derives whether the implementation is actually correct
instead of trusting anything already on disk (see [Independent
verification mode](QUALITY.md#independent-verification-mode) — `verify` never edits
the implementation or its tests). A FAIL it reports goes to the same `fix`
agent, from the same shared retry budget as a mechanical failure — not a
second one — and the next round re-checks `lex test` before trusting
`verify` again, since a fix aimed at `verify`'s finding could in principle
break a test that was passing before.
