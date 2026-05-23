import "lex-llm/delta" as d

import "std.conc" as conc

import "std.list" as list

import "std.str" as str

import "./session" as sess

type WorkerMsg = Execute(Str)

type WorkerState = { mode :: sess.AgentMode, provider_tag :: Str }

type MultiResult = { impl_steps :: List[d.Step], test_steps :: List[d.Step] }

fn worker_handler(state :: WorkerState, msg :: WorkerMsg) -> [env, net, llm, io, proc, sql, fs_write, time] (WorkerState, List[d.Step]) {
  match msg {
    Execute(task) => match sess.new_session_with_provider("worker", state.mode, state.provider_tag) {
      Err(_) => (state, []),
      Ok(session) => {
        let result := sess.run_turn_with_provider(session, task, state.provider_tag)
        (state, result.steps)
      },
    },
  }
}

fn run_parallel(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_write, time] MultiResult {
  let impl_state := { mode: sess.Build, provider_tag: provider_tag }
  let test_state := { mode: sess.Test, provider_tag: provider_tag }
  let impl_actor := conc.spawn(impl_state, worker_handler)
  let test_actor := conc.spawn(test_state, worker_handler)
  let impl_steps := conc.ask(impl_actor, Execute(task))
  let test_steps := conc.ask(test_actor, Execute(str.concat("Write unit tests for: ", task)))
  { impl_steps: impl_steps, test_steps: test_steps }
}

fn run_impl_then_test(task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_write, time] MultiResult {
  match sess.new_session_with_provider("impl", sess.Build, provider_tag) {
    Err(_) => { impl_steps: [], test_steps: [] },
    Ok(impl_sess) => {
      let impl_result := sess.run_turn_with_provider(impl_sess, task, provider_tag)
      let test_task := str.concat("Write unit tests for: ", task)
      match sess.new_session_with_provider("test", sess.Test, provider_tag) {
        Err(_) => { impl_steps: impl_result.steps, test_steps: [] },
        Ok(test_sess) => {
          let test_result := sess.run_turn_with_provider(test_sess, test_task, provider_tag)
          { impl_steps: impl_result.steps, test_steps: test_result.steps }
        },
      }
    },
  }
}

fn run_impl_then_spec_then_test(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_write, time] List[d.Step] {
  match sess.new_session_with_provider("impl", sess.Build, provider_tag) {
    Err(_) => [],
    Ok(impl_sess) => {
      let impl_result := sess.run_turn_with_provider(impl_sess, task, provider_tag)
      let spec_task := str.concat("Write lex-spec Spec for: ", task)
      match sess.new_session_with_provider("spec", sess.Spec, provider_tag) {
        Err(_) => impl_result.steps,
        Ok(spec_sess) => {
          let spec_result := sess.run_turn_with_provider(spec_sess, spec_task, provider_tag)
          let test_task := str.concat("Write unit tests for: ", task)
          let rev_task := str.concat("Review implementation: ", task)
          let test_actor := conc.spawn({ mode: sess.Test, provider_tag: provider_tag }, worker_handler)
          let rev_actor := conc.spawn({ mode: sess.Review, provider_tag: provider_tag }, worker_handler)
          let test_steps := conc.ask(test_actor, Execute(test_task))
          let rev_steps := conc.ask(rev_actor, Execute(rev_task))
          list.concat(impl_result.steps, list.concat(spec_result.steps, list.concat(test_steps, rev_steps)))
        },
      }
    },
  }
}

