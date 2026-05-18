import "std.io"   as io
import "std.str"  as str
import "std.list" as list

import "lex-llm/delta"   as d
import "lex-llm/message" as msg

import "../server/session" as sess

fn print_step(step :: d.Step) -> [io] Nil {
  match step {
    d.StepDelta(delta) =>
      match delta {
        d.TextChunk(text)         => io.print(text),
        d.ToolCallBegin(_, name)  => io.print(str.concat("\n[tool: ", str.concat(name, "]"))),
        d.ToolArgChunk(_, _)      => Nil,
        d.FinishDelta(_)          => Nil,
      }
    d.StepToolExec(name, _) =>
      io.print(str.concat("[running: ", str.concat(name, "]"))),
    d.StepToolResult(_, ok) =>
      if ok then io.print("[ok]") else io.print("[error]"),
    d.StepDone(_) =>
      io.print(""),
  }
}

fn repl(session :: sess.Session) -> [io, net, llm, proc, sql, time] Nil {
  io.print("\n> ")
  match io.readline() {
    None       => io.print("\nbye"),
    Some(line) =>
      let input := str.trim(line)
      if str.is_empty(input) then
        repl(session)
      else
        let result := sess.run_turn(session, input)
        let _ := list.map(result.steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        repl(result.session),
  }
}

fn parse_mode(argv :: List[Str]) -> sess.AgentMode {
  match list.find(argv, fn (a :: Str) -> Bool { str.eq(a, "--plan") }) {
    Some(_) => sess.Plan,
    None =>
      match list.find(argv, fn (a :: Str) -> Bool { str.eq(a, "--explore") }) {
        Some(_) => sess.Explore,
        None    => sess.Build,
      }
  }
}

fn main() -> [io, net, llm, proc, sql, time] Nil {
  io.print("lex-code v0.1 — Lex-specialized coding assistant")
  io.print("flags: --plan | --explore  (default: build mode)")
  io.print("Ctrl-D to exit")
  let mode := parse_mode(io.argv())
  match sess.new_session("tui", mode) {
    Err(e)      => io.print(str.concat("startup error: ", e)),
    Ok(session) => repl(session),
  }
}
