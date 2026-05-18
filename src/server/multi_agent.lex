# lex-code — multi-agent dispatch
#
# v0.2: sequential impl+test. The impl agent writes code, then the
# test agent writes tests against the same codebase state.
#
# v0.3 target: true parallel via std.conc actors + lex-store merge
# to reconcile the two agents' Operation logs without text conflicts.

import "lex-llm/delta"   as d
import "lex-llm/message" as msg

import "std.list" as list
import "std.str"  as str

import "./session" as sess

type MultiResult = {
  impl_steps :: List[d.Step],
  test_steps :: List[d.Step],
}

# Run impl agent then test agent sequentially.
# Both agents share the same filesystem state; the test agent sees
# the files written by the impl agent.
fn run_impl_then_test(
  task         :: Str,
  provider_tag :: Str
) -> [net, llm, io, proc, sql, time] MultiResult {
  match sess.new_session_with_provider("impl", sess.Build, provider_tag) {
    Err(_) => { impl_steps: [], test_steps: [] },
    Ok(impl_session) =>
      let impl_result := sess.run_turn_with_provider(impl_session, task, provider_tag)
      let test_prompt :=
        str.concat("Write a comprehensive Lex test suite for: ", task)
      match sess.new_session_with_provider("test", sess.Test, provider_tag) {
        Err(_) => { impl_steps: impl_result.steps, test_steps: [] },
        Ok(test_session) =>
          let test_result := sess.run_turn_with_provider(test_session, test_prompt, provider_tag)
          { impl_steps: impl_result.steps, test_steps: test_result.steps },
      }
  }
}

fn print_multi_result(result :: MultiResult) -> Str {
  let impl_done := count_done(result.impl_steps)
  let test_done := count_done(result.test_steps)
  str.concat("=== impl agent: ",
    str.concat(int_str(impl_done), str.concat(" steps\n",
      str.concat("=== test agent: ", str.concat(int_str(test_done), " steps")))))
}

fn count_done(steps :: List[d.Step]) -> Int {
  list.len(list.filter(steps, fn (s :: d.Step) -> Bool {
    match s { d.StepDone(_) => true, _ => false }
  }))
}

fn int_str(n :: Int) -> Str {
  match n {
    0 => "0", 1 => "1", 2 => "2", 3 => "3", 4 => "4",
    5 => "5", 6 => "6", 7 => "7", 8 => "8", 9 => "9",
    _ => "many",
  }
}
