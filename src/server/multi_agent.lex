import "lex-llm/delta" as d

import "std.list" as list

import "std.str" as str

import "./session" as sess

type MultiResult = { impl_steps :: List[d.Step], test_steps :: List[d.Step] }

fn run_task(task :: Str, mode :: sess.AgentMode, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] List[d.Step] {
  match sess.new_session_with_provider("worker", mode, provider_tag) {
    Err(_) => [],
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, task, provider_tag)
      result.steps
    },
  }
}

fn run_parallel(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] MultiResult {
  let pairs := [(task, Build), (str.concat("Write unit tests for: ", task), Test)]
  let results := list.par_map(pairs, fn (pair :: (Str, sess.AgentMode)) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] List[d.Step] {
    match pair {
      (t, mode) => run_task(t, mode, provider_tag),
    }
  })
  let impl_steps := match list.head(results) {
    Some(s) => s,
    None => [],
  }
  let test_steps := match list.head(list.tail(results)) {
    Some(s) => s,
    None => [],
  }
  { impl_steps: impl_steps, test_steps: test_steps }
}

fn run_impl_then_test(task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] MultiResult {
  let impl_steps := run_task(task, Build, provider_tag)
  let test_steps := run_task(str.concat("Write unit tests for: ", task), Test, provider_tag)
  { impl_steps: impl_steps, test_steps: test_steps }
}

fn run_impl_then_spec_then_test(task :: Str, provider_tag :: Str) -> [env, concurrent, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] List[d.Step] {
  let impl_steps := run_task(task, Build, provider_tag)
  let spec_steps := run_task(str.concat("Write lex-spec Spec for: ", task), Spec, provider_tag)
  let parallel_tasks := [(str.concat("Write unit tests for: ", task), Test), (str.concat("Review implementation: ", task), Review)]
  let parallel_results := list.par_map(parallel_tasks, fn (pair :: (Str, sess.AgentMode)) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval] List[d.Step] {
    match pair {
      (t, mode) => run_task(t, mode, provider_tag),
    }
  })
  let test_steps := match list.head(parallel_results) {
    Some(s) => s,
    None => [],
  }
  let rev_steps := match list.head(list.tail(parallel_results)) {
    Some(s) => s,
    None => [],
  }
  list.concat(impl_steps, list.concat(spec_steps, list.concat(test_steps, rev_steps)))
}

