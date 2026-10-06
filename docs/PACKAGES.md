# Building whole packages

[README](../README.md) · [All docs](../README.md#documentation)

Plan a package as a graph of typed issues, build it, prove it works, and leave a report. The staged commands, the acceptance gate, repair, the dashboard and the overnight supervisor.

## Building a whole package

One issue is one function. A package is a **project** of typed issues with
`--dep` edges between them, and three commands take it from a sentence to a
verified module. Requires `lex issue next` and `lex issue verify --project`
(lex-lang 0.11.75+).

```sh
lex init && lex-code --package "a small text-utilities package: slugify, word_count, wrap, ..." --name=textkit
#   an agent draws the issue graph into .lex/plans/textkit.json — nothing is filed yet
lex-code --package-apply=textkit               # after you have read the plan: file it
lex-code --project=textkit --ollama            # drive it to done
```

**You can stop after any stage and pick up later.** Each one is its own command,
and everything between them is a file you can read and edit:

| Stage | Command | What it does | Ends with |
|---|---|---|---|
| 1. Plan | `lex-code --package "<brief>" --name=P --ollama` | An agent drafts `.lex/plans/P.json` (and, for a server, `P.acceptance.json`), checks it, and repairs it up to `--plan-tries=N` times (default 3). **Files nothing.** | `[PLAN] valid` or `invalid` |
| 2. Check | `lex-code --package-check=P` | Re-validates the plan file — after you or an agent edited it. No model. | `[PLAN_CHECK] ok` or `invalid` |
| 3. File | `lex-code --package-apply=P` | Files the reviewed plan as issues and writes the scaffold. No model. | the issue ids |
| 4. Build | `lex-code --project=P --ollama` | Drives the issues to done, then re-verifies, hardens and runs acceptance. Resumable: verified units are kept. | `[PROJECT_VERDICT]` |
| one unit | `lex-code --issue=<id>` | One attempt on one issue. | `[ISSUE_VERDICT]` |
| by hand | `lex-code --project=P --patch=FILE --patch-issue=ID` | You (or your assistant) write a unit; lex-code verifies it like any other. | the unit's verdict |
| gate only | `lex-code --acceptance-check=P` | Starts the built package and replays its scenarios. | `[ACCEPTANCE] pass\|fail\|none` |
| everything | `lex-code --package "<brief>" --name=P --auto` | Stages 1–4 with no human step. | `[PROJECT_VERDICT]` |
| watch | `lex-code --dashboard=P [--log=F] [--port=N]` | A read-only live view of a running build (default log `P.log`, port 7800). See [Watching a build](#watching-a-build-the-dashboard). | — |

There is no way yet to save a half-finished plan and resume it, or to build only some
of a project's units from `--project` (use `--issue` for one at a time).

The plan is JSON — units, each with signatures, examples and `deps` — and it
is checked before it can be filed (every example must call a declared
function, an example is a bare call — `f(x).field => ..` can never verify —
an invariant can fail — `... or true` and `f(x) == f(x)` check nothing —
no function is named like one a dependency exports (`open`, `insert`, ... — such a
unit can never verify) —
no cycles, a pure function needs an example, a function is declared
by exactly one unit). Filing is deterministic on purpose: an LLM does not get
to decide, unreviewed, what "done" means.

The driver loops: `lex issue next` → run one issue → verify → **re-verify
everything that had verified**. That last step is the point: an agent turn that
rewrites a file can silently drop another issue's function, and nothing else
would notice. A regressed issue simply comes back on the board.

| flag | meaning |
|---|---|
| `--max-attempts=N` | attempts per issue before it is given up on (default 4; applies to `--parallel` too) |
| `--hint=TEXT` / `--hint-file=PATH` | extra guidance appended to every issue's task on this run — use it when resuming a stuck build (`--project=NAME`; verified issues are kept) |
| `--patch=FILE[,FILE]` / `--patch-issue=ID` | finish a stuck unit yourself (or have your assistant do it): FILE defines the unit's function(s), lex-code splices it in and runs its own check, publish and `issue verify` on it — the patch is never taken on trust, and the hardening and package gates still run after. Rejected patches change nothing. The issue is inferred from the function names unless `--patch-issue` is given |
| `--fallback=TAG` `--switch-after=N` | after N failures on an issue, hand it to another provider, e.g. `--ollama --fallback=opencode` (default 2) |
| `--max-turns=N` | budget for the whole run (default 40) |
| `--plan-tries=N` | repair rounds the planner gets when its plan fails validation (default 3) |
| `--repair-rounds=N` | how many times the assembled package may be handed back to the model as one integration task when it fails to type-check or fails acceptance (default 2, `0` = off). The model may edit any function; a round that leaves the file not type-checking is rolled back |
| `--harden-rounds=N` / `--harden-turns=N` | how many rounds, and how many agent turns per round, hardening may spend fixing invariant violations (defaults 3 and 10) |
| `--no-harden` | skip the closing turn that writes property tests |
| `--no-acceptance` | skip the closing acceptance run (below) |
| `--acceptance-check=P` | run only that closing step on an already-built package: start it, replay its scenarios, print `[ACCEPTANCE] pass\|fail\|none` |

**Acceptance: does the assembled program actually run?** Units verify one at a
time, and that does not show the whole thing works: every unit can verify and the
package still never start. A plan with a
network handler therefore carries `.lex/plans/<project>.acceptance.json`:
black-box scenarios (a request, and the status — and optionally a substring or an
absent secret — that must come back) taken from the brief's own requirements and
written *before* the units. After the build and hardening, lex-code starts the real
package on a free loopback port with a fresh temp dir, replays the scenarios in
order against that one server, stops it, and fails the gate if the program does not
come up or a scenario does not hold. Plans without a `net` unit (libraries) need no
file. Env names/values, headers and paths in the file are restricted character
sets (raw spaces, quotes and the like in a path are percent-encoded for you, so a
"SQL injection in the filter" scenario can be written naturally), and the runner only
ever connects to `127.0.0.1`.

Two coverage rules are checked when the plan is checked, because a passing gate
only means the scenarios passed. A route called with a query string
(`GET /jobs?state=done`) must also be called with none and expect a 2xx; one build
passed 18 of 18 scenarios and answered 500 to a plain `GET /jobs`. And when the
file uses two or more tokens, every scenario that succeeds on a numbered resource
(`/jobs/1`, `/jobs/1/claim`) needs a *twin*: the same method and path with the other
token, expecting 404, so a handler that forgets the ownership check cannot pass.

Hardening treats a **plan contradiction** as a plan defect, not a failure of the
run: an invariant that fails on *every* probed input is the plan disagreeing with
itself (its examples are fixed once filed), not a code bug, and no attempt could close
an issue for it. It is reported as `[PLAN] contradiction`, skipped — it is **not
enforced** — and the run goes on to the acceptance gate and repair. Such a run can
end `done` only if the real program passed acceptance; fix the plan to enforce the
invariant.

It ends with machine-readable lines: `[PROJECT_VERDICT]  done|built|gate_failed|stuck|budget|error|provider_error|no_plan`
and `[PACKAGE_GATE]  pass|fail|unavailable|none|skipped` (`lex test` over `tests/`).
`done` means every unit verified **and** the assembled file type-checks **and** the
gate ran and passed. `built` = every unit verified but the gate could not run;
`gate_failed` = it ran and failed. Neither is finished. Verified is
necessary, not sufficient — an issue's examples are a finite list and code can
satisfy them without being right — which is why the run ends by asking for
round-trip and property tests and running them.

**A package is one module.** The store's head tracks a single module: publish
a second `.lex` file and the first file's functions drop out of it, and their
issues read "absent at head". So every issue is told to put its code in
`src/<project>.lex`. Units split the work, not the files.

**Integration repair.** Units verify one at a time, so a failure that only exists
once they share a file has no unit to blame: every unit can verify and the
assembled file still fail to type-check. After the build, a
failing type-check — and later a failing acceptance scenario — is handed back to
a model as one task: here is what the whole program does wrong, edit any function
to fix it. It gets `--repair-rounds` tries (default 2). Each round is snapshotted,
and one that leaves the file not type-checking is rolled back — a round that
merely passes fewer scenarios is not. It helps and it is not
a cure. For a failing scenario the prompt includes how to reproduce it — the
server command with the gate's own env and a `curl` for the first failing request —
and says to debug in a copy, because a 500 body is usually generic and the cause
(a swallowed database error) is invisible without running it. On the invoices
build, repair without that moved acceptance from 10/16 to 11/16 and the run ended
`gate_failed`; with it, a repair-only rerun on that same package went 11/16 → 16/16
and `done` (the cause was one query not naming its table). On a second, from-scratch
build with different bugs (create dropped the customer, a SQL parameter of the wrong
type) it went 11/16 → 14/16 → 16/16 and `done`, and left no debugging code behind.
Two packages, one local model, thinking on: read it as "the gap was visibility", not
as a success rate.

**A failed attempt is only retried if the code was what failed.** After an attempt
that does not verify, lex-code asks the store why (no model involved). If the store
rejected the unit's own examples — an example is immutable once filed, so no edit can
fix it — or the verify command itself broke, it prints `not retrying issue … plan
defect` (or `tooling failure`) with the store's message, uses up that unit's budget,
and carries on with every unit that does not depend on it; the run ends `stuck`,
naming the cause. Everything else is retried as before. It is deliberately
conservative: it never guesses from how a failure *looks* (a padding bug and a
miscounted example print the same expected-versus-got), only from what the store
says. `--parallel` does not use this yet.

A provider that returns nothing (a rate limit, a rejected key) stops the run
with the provider named instead of burning attempts; verified issues are kept.

## Watching a build: the dashboard

A package build runs for a long time, so there is a live view of it. It is
**read-only**: it never drives, retries or edits anything, and it writes
nothing but a start timestamp (`.lex/dashboard-P.start.ts`, used to show elapsed
time).

```sh
lex-code --project=invoices --ollama > invoices.log 2>&1 &   # or --auto; any run's stdout
lex-code --dashboard=invoices                                 # → http://127.0.0.1:7800
```

It reads three things you already have: the plan (`.lex/plans/P.json`), the issue
store, and the **log file the run's stdout was redirected to** — `lex-code`
prints its progress to stdout and keeps no log of its own, so a run you start
without redirecting has nothing to watch. Use `--log=FILE` if the log is not
`P.log` in the current directory and `--port=N` if 7800 is taken. **It has no
authentication, so it listens on the loopback interface only** (`127.0.0.1`) —
other machines on your network cannot reach it. To watch a build running on
another machine, forward the port (`ssh -L 7800:127.0.0.1:7800 host`) rather than
exposing it.
The page polls every two seconds; closing it does not affect the build.

What it shows:

- **Flow stepper** — plan → file → build → regression → gate, with the current
  stage highlighted and a failed stage in red (the gate step reads `gate: pass|fail`
  once the run ends).
- **Table, kanban and graph views** of the units. Status is `ready`, `running`,
  `failed` or `verified`, with the attempt number; the graph lays units out by
  dependency level and colours them the same way.
- **Unit panel** — click any unit for its spec, signatures, examples,
  invariants and dependencies, as the plan has them.
- **Recent activity**, the elapsed time, the run's aggregate line, and a
  `stuck — gave up on: …` banner naming the units that ran out of attempts —
  which is your cue to resume with `--hint` or `--patch`.

- **Token usage per task** — prompt and completion tokens for each unit (summed
  over every attempt, so a retried unit shows what *all* its tries cost), for the
  planner, and for the whole run. It is read from the `[USAGE]` lines the run
  prints, so it only counts what the provider reports: Ollama and Gemini do. A turn
  whose provider reported nothing shows "not reported" rather than zero, and a unit
  with no attempt yet shows `-`.

What it does not show (yet): the model's output or the diff of an attempt. Those
are in the session trail (`.lex/sessions/`) and the stage's own output.

## Running it overnight

A whole package on a local model takes hours, and `--auto` stops at the first thing
that needs a person: a unit that is stuck, a step budget that ran out, a gate that
failed, a provider that blinked. If the tokens are free and the time is not, a
supervisor can make the routine decisions for you:

```sh
lex-code-overnight --name=invoices --brief-file=brief.txt --ollama
lex-code-overnight --name=invoices --ollama      # a plan exists: resume it
cat .lex/overnight/REPORT.md                      # in the morning
```

It plans if there is no plan (and files it), then runs build rounds, resuming after
`stuck`, `gate_failed`, `budget` or a kill **while a round makes progress** — more
units verified or more acceptance scenarios holding. A round with none switches a
local model's thinking on (it verified a hard unit 4/4 where thinking-off managed
2/4 — four trials each, one model); a second round in a row without progress stops
the run. A provider that stops answering is waited for with backoff, not counted as
a failure. A round that hangs is killed at its own ceiling, the machine is kept awake
(`caffeinate`), and a shared file left unparseable by a kill mid-edit is put back
from the newest copy that parsed (copied every two minutes while a round runs, so the
restore costs minutes, not the round; the broken file is kept next to it). Anything else on the command line goes to `lex-code`
(`--ollama`, `--lex-os`, ...).

| option | |
|---|---|
| `--max-hours=N` / `--round-hours=N` | the whole run's limit (10) and one round's ceiling (3) |
| `--stall-rounds=N` | rounds without progress before stopping (2) |
| `--steps=N` | agent steps per task for a local model (80; lex-code's own default is 60) |
| `--outage-minutes=N` | how long to wait for a provider that is down (90) |
| `--on-finish=CMD` | run when it ends; env `LEX_OVERNIGHT_PROJECT`, `_REASON`, `_REPORT` |
| `--no-escalate`, `--no-caffeinate` | never switch thinking on; do not keep the machine awake |

`--steps` is not higher on purpose. Past about a hundred steps a local model's context
is long enough that a single step outran a five-minute provider timeout and ended a
repair round with nothing applied; shorter rounds, each starting from a fresh context,
did better, so `--repair-rounds` defaults to 6 here (give your own to override) and
`LLM_TIMEOUT_MS` to 15 minutes. `LEX_MAX_STEPS` sets the same budget for a plain
`lex-code` run.

`lex-code --report=P [--log=F] [--rounds=F]` is the report on its own: one Markdown
page with the verdict, every unit's attempts and tokens (read from the issue store, so
a resumed build is counted correctly), the last acceptance result, what was set aside
(skipped invariants, plan defects) and what each round did, so it also shows
where the time and the tokens went.

`lex-code --lessons=P [--min-sessions=N]` reads the project's session trails
(`.lex/sessions/*.db`, run from the project directory) and groups the failed tool calls
by what they say. A failure that recurs in at least N sessions (default 3) is a
**candidate lesson**: it is printed, and written to `.lex/lessons-candidates.jsonl`.
Grouping is by normalised text (names, quoted text and numbers taken out), not by a
model's reading of it, and nothing is fed back to a prompt: a wrong lesson shown to every
later run is worse than none, so a person decides which become notes. On the stalled
`cronexpr` build it put the real cause first (one unit's failing examples blocking every
other unit's edit: 125 failures in 13 of 15 sessions), which had taken reading SQLite by
hand to find.

Limits, honestly. It will sometimes end the night `stuck`; the report then says where.
Switching thinking on and the repair-round count are guesses backed by small runs, not
measured defaults. It runs shell commands unattended: the permission gate applies, but
run it in a dedicated project directory (or `--lex-os`), not in a checkout you care
about. Exit status: 0 done, 1 stopped without finishing, 2 usage, 3 no plan, 4 provider
stayed down. `scripts/test-overnight.sh` tests its decisions with a stand-in for
`lex-code`, in seconds.
