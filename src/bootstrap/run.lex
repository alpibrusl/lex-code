import "src/server/session" as sess
import "src/server/persist" as persist
import "std/str" as str
import "std/io" as io
import "lex-llm/dialogue" as d
import "std/list" as list

type Phase = {
  name    :: Str,
  task    :: Str,
  mode    :: sess.AgentMode
}

fn run_phase(phase :: Phase, provider_tag :: Str) -> [io, net, llm, proc, sql, time] Nil {
  io.println(str.concat("[bootstrap] starting phase: ", phase.name))
  let trail := persist.open_ephemeral()
  let session := sess.new_session_with_provider(phase.mode, provider_tag, trail)
  let steps   := sess.run_turn(session, phase.task)
  let n       := list.length(steps)
  io.println(str.concat("[bootstrap] phase ", str.concat(phase.name, str.concat(" done — ", str.concat(str.from_int(n), " steps")))))
}

fn main() -> [io, net, llm, proc, sql, time] Nil {
  let provider_tag := "anthropic"

  let task := "Add fn zip[A, B](xs :: List[A], ys :: List[B]) -> List[(A, B)] to src/list.lex"

  let phases := [
    { name: "impl",   task: task,                                                              mode: sess.Build  },
    { name: "spec",   task: str.concat("Write lex-spec Spec for list.zip: ", task),            mode: sess.Spec   },
    { name: "test",   task: str.concat("Write unit tests for list.zip: ", task),               mode: sess.Test   },
    { name: "review", task: str.concat("Review the list.zip implementation and tests: ", task), mode: sess.Review }
  ]

  list.for_each(phases, fn (phase :: Phase) -> [io, net, llm, proc, sql, time] Nil {
    run_phase(phase, provider_tag)
  })
}
