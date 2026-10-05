# Agent modes

[README](../README.md) · [All docs](../README.md#documentation)

The modes lex-code runs in, typed issues, and running several agents at once.

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
| `--verify` | Verify | Independently re-derive expected output from the task's own spec and check the implementation against it — never trusts the implementation's existing test file ([below](QUALITY.md#independent-verification-mode)) |
| `--bar` | Bar | Walk a project against the minimum bar, read-only ([below](QUALITY.md#minimum-bar-mode)) |
| `--multi` | Multi | Run Build + Test in parallel via `std.conc` |
| `--issue=<id>` | Build | Implement a typed issue from its declared acceptance, then verify it ([below](#implementing-a-typed-issue)) |
| `--refine=<id>` | Build | Propose a typed acceptance for a free-form issue; a human approves it ([below](#refining-a-free-form-issue)) |

### Implementing a typed issue

A [typed issue](https://github.com/alpibrusl/lex-lang/issues/949) is a
contract, not a description: exact signatures to add, change, or remove,
plus the examples that decide whether it holds (or, for a bug, the one
example that fails at head). `--issue=<id>` works from that contract:

```sh
lex issue create --title "digit_sum" --shape typed_delta \
  --api 'digit_sum:(n :: Int) -> Int:added' \
  --example 'digit_sum(1234) => 10' --example 'digit_sum(-56) => 11'
lex-code --issue=<id> ["optional extra guidance"]
```

1. `lex issue show` renders the acceptance as the task.
2. The session is bound to the issue, so every clean `.lex` write is
   published with `--intent-issue` and its ops link back to it
   (issue → intent → ops → attestation).
3. The agent iterates against the oracle with the `issue_verify` tool.
4. Whatever the model claims, the run ends with `lex issue verify` and a
   machine-readable last line:
   `[ISSUE_VERDICT]\t<verified|failed|inconclusive|unavailable>\t<id>`.

`typed_delta` and `failing_example` issues close by proof. `free_form`,
`metric_invariant` and `evidence` verify as `inconclusive` for now.

### Refining a free-form issue

Not every issue starts with a contract. `--refine=<id>` has the agent read
the code and **propose** one — exact signatures plus the examples that pin
them, or the one failing example for a bug — with the `issue_propose`
tool ([lex-lang #956](https://github.com/alpibrusl/lex-lang/issues/956)).
It stops there: lex-code has no tool that approves, and the run ends by
listing the proposals and the command that decides them.

```sh
lex-code --refine=<id>                         # agent proposes
lex issue proposals <id>                       # review
lex issue approve <proposal> --by <you>        # or: reject --notes "..."
lex-code --issue=<id>                          # implement against the approved contract
```

Approving never rewrites the issue — its id, intents and verdicts stay
put; the gate judges it against the latest approved proposal
(`effective_acceptance` in `lex issue show`). `--refine` runs in Build
mode with a prompt that forbids implementing; there is no dedicated
read-only toolset yet (#88).

## Parallel Multi-Agent (`std.conc`)

_Runnable: `examples/agent_modes/multi.sh`_

The `--multi` TUI flag (and `run_parallel` in `src/server/multi_agent.lex`) spawns two
actors via `std.conc.spawn` and runs Build + Test concurrently:

```lex
let impl_actor := conc.spawn(worker_handler, impl_state)
let test_actor := conc.spawn(worker_handler, test_state)
let impl_steps := conc.ask(impl_actor, Execute(task))
let test_steps := conc.ask(test_actor, Execute(test_task))
```
