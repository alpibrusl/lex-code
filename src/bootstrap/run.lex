import "../server/session" as sess

import "std.str" as str

import "std.io" as io

import "std.int" as int

import "std.list" as list

type Phase = { name :: Str, task :: Str, mode :: sess.AgentMode }

fn run_phase(phase :: Phase, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_write, time, approval] Nil {
  io.print(str.concat("[bootstrap] starting phase: ", phase.name))
  match sess.new_session_with_provider(phase.name, phase.mode, provider_tag) {
    Err(e) => io.print(str.concat("[bootstrap] session error: ", e)),
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, phase.task, provider_tag)
      let n := list.len(result.steps)
      io.print(str.concat("[bootstrap] phase ", str.concat(phase.name, str.concat(" done — ", str.concat(int.to_str(n), " steps")))))
    },
  }
}

fn main() -> [env, io, net, llm, proc, sql, fs_write, time, approval] Nil {
  let provider_tag := "anthropic"
  let task := "Add fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] to src/list.lex"
  let phases := [{ name: "impl", task: task, mode: Build }, { name: "spec", task: str.concat("Write lex-spec Spec for list.zip: ", task), mode: Spec }, { name: "test", task: str.concat("Write unit tests for list.zip: ", task), mode: Test }, { name: "review", task: str.concat("Review the list.zip implementation and tests: ", task), mode: Review }]
  let __lex_discard_1 := list.map(phases, fn (phase :: Phase) -> [env, io, net, llm, proc, sql, fs_write, time, approval] Nil {
    run_phase(phase, provider_tag)
  })
  ()
}

