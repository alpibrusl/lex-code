# lex-code — manifesto demo: the concurrency effect is enforced, not advisory
#
# The DISHONEST twin of manifesto_parallel.lex. `run_parallel` spawns
# and asks actors — both `[concurrent]` operations — but the signature
# omits `[concurrent]`. The checker REJECTS it: you cannot orchestrate
# parallel actors under a signature that claims to be effect-free.
#
#   lex check examples/manifesto_parallel_bad.lex   # → FAILS (by design)
#
# This is the enforcement behind §VI's "the type system verifies the
# result": the composed effect row is a checked obligation.

import "std.conc" as conc

type Task = { kind :: Str, payload :: Str }

type StepResult = { worker :: Str, steps :: Int, summary :: Str }

type WorkerState = { name :: Str, steps :: Int }

fn worker_handler(state :: WorkerState, task :: Task) -> (WorkerState, StepResult) {
  let next := { name: state.name, steps: state.steps + 1 }
  (next, { worker: state.name, steps: next.steps, summary: task.kind })
}

# Missing `[concurrent]` — spawn/ask are concurrent effects, so this
# is rejected.
fn run_parallel(build_task :: Task) -> StepResult {
  let build_actor := conc.spawn({ name: "build", steps: 0 }, worker_handler)
  conc.ask(build_actor, build_task)
}

