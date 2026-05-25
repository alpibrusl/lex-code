# lex-code — manifesto demo: effect-typed parallel orchestration (§VI)
#
# Manifesto §VI:
#   "The orchestrator manages parallel multi-agent execution with
#    effect-typed concurrency ... It composed the effect rows correctly
#    across parallel sub-agents ... the substrate carries the
#    constraints; the model fills the bodies; the type system verifies
#    the result."
#
# A miniature `run_parallel`: spawn two std.conc actors (a build worker
# and a test worker), drive them concurrently, and compose their
# results. The `[concurrent]` effect is REQUIRED by conc.spawn/ask, and
# the type checker verifies the composed row of `run_parallel` and
# `main`. The bodies here are pure compute, so the row is exactly
# `[concurrent]` (plus `[io]` where we print) — no network, no API key,
# fully deterministic and offline.
#
#   lex check examples/manifesto_parallel.lex                 # row verified
#   lex run --allow-effects concurrent,io examples/manifesto_parallel.lex main
#
# The negative twin manifesto_parallel_bad.lex drops `[concurrent]` from
# the signature and is REJECTED — the row is enforced, not advisory.

import "std.conc" as conc

import "std.str" as str

import "std.io" as io

type Task = { kind :: Str, payload :: Str }

type StepResult = { worker :: Str, steps :: Int, summary :: Str }

type WorkerState = { name :: Str, steps :: Int }

type MultiResult = { build :: StepResult, test :: StepResult }

# A pure actor handler: (state, message) -> (next_state, reply). One
# task advances the worker by one step and reports what it did.
fn worker_handler(state :: WorkerState, task :: Task) -> (WorkerState, StepResult) {
  let next := { name: state.name, steps: state.steps + 1 }
  let summary := str.concat(state.name, str.concat(" handled ", task.kind))
  (next, { worker: state.name, steps: next.steps, summary: summary })
}

# Spawn build + test workers and ask each to run its task. The
# composed effect row is `[concurrent]` and the type checker proves it.
fn run_parallel(build_task :: Task, test_task :: Task) -> [concurrent] MultiResult {
  let build_actor := conc.spawn({ name: "build", steps: 0 }, worker_handler)
  let test_actor := conc.spawn({ name: "test", steps: 0 }, worker_handler)
  let build_res := conc.ask(build_actor, build_task)
  let test_res := conc.ask(test_actor, test_task)
  { build: build_res, test: test_res }
}

fn main() -> [concurrent, io] Unit {
  let r := run_parallel({ kind: "implement", payload: "list.zip" }, { kind: "property-test", payload: "list.zip" })
  let __b := io.print(str.concat("build worker: ", r.build.summary))
  let __t := io.print(str.concat("test worker:  ", r.test.summary))
  io.print("composed effect row [concurrent] verified at lex check time")
}

