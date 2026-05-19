import "lex-llm/agent" as ag
import "lex-llm/providers" as providers
import "std.conc" as conc
import "std/list" as list
import "std/str" as str
import "lex-trail/log" as log
import "lex-trail/event" as ev
import "src/server/session" as sess
import "src/server/persist" as persist
import "lex-llm/dialogue" as d

type WorkerMsg = Execute(Str)

type WorkerState = {
  mode        :: sess.AgentMode,
  provider_tag :: Str,
  log         :: log.Log
}

type MultiResult = {
  impl_steps   :: List[d.Step],
  test_steps   :: List[d.Step]
}

fn worker_handler(state :: WorkerState, msg :: WorkerMsg)
  -> [net, llm, io, proc, sql, time] (WorkerState, List[d.Step]) {
  match msg {
    Execute(task) => {
      let session := sess.new_session_with_provider(state.mode, state.provider_tag, state.log)
      let steps   := sess.run_turn(session, task)
      (state, steps)
    }
  }
}

fn run_parallel(task :: Str, provider_tag :: Str)
  -> [concurrent, net, llm, io, proc, sql, time] MultiResult {
  let impl_log := persist.open_ephemeral()
  let test_log := persist.open_ephemeral()

  let impl_state := { mode: sess.Build,  provider_tag: provider_tag, log: impl_log }
  let test_state := { mode: sess.Test,   provider_tag: provider_tag, log: test_log }

  let impl_actor := conc.spawn(worker_handler, impl_state)
  let test_actor := conc.spawn(worker_handler, test_state)

  let impl_steps := conc.ask(impl_actor, Execute(task))
  let test_steps := conc.ask(test_actor, Execute(str.concat("Write unit tests for: ", task)))

  { impl_steps: impl_steps, test_steps: test_steps }
}

fn run_impl_then_spec_then_test(task :: Str, provider_tag :: Str)
  -> [concurrent, net, llm, io, proc, sql, time] List[d.Step] {
  let impl_log := persist.open_ephemeral()
  let spec_log := persist.open_ephemeral()
  let test_log := persist.open_ephemeral()
  let rev_log  := persist.open_ephemeral()

  let impl_sess := sess.new_session_with_provider(sess.Build,   provider_tag, impl_log)
  let impl_out  := sess.run_turn(impl_sess, task)

  let spec_task  := str.concat("Write lex-spec Spec for: ", task)
  let spec_sess  := sess.new_session_with_provider(sess.Spec,   provider_tag, spec_log)
  let spec_out   := sess.run_turn(spec_sess, spec_task)

  let test_task  := str.concat("Write unit tests for: ", task)
  let test_actor := conc.spawn(worker_handler, { mode: sess.Test,   provider_tag: provider_tag, log: test_log })
  let rev_actor  := conc.spawn(worker_handler, { mode: sess.Review, provider_tag: provider_tag, log: rev_log  })

  let test_steps := conc.ask(test_actor, Execute(test_task))
  let rev_steps  := conc.ask(rev_actor,  Execute(str.concat("Review implementation: ", task)))

  list.concat([impl_out, spec_out, test_steps, rev_steps])
}
