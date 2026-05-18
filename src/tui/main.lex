import "std.io"   as io
import "std.str"  as str
import "std.list" as list
import "std.env"  as env

import "lex-llm/delta"   as d
import "lex-llm/message" as msg

import "../server/session" as sess
import "../agents/build"   as build_agent
import "../agents/plan"    as plan_agent
import "../agents/explore" as explore_agent

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

fn has_flag(argv :: List[Str], flag :: Str) -> Bool {
  match list.find(argv, fn (a :: Str) -> Bool { str.eq(a, flag) }) {
    Some(_) => true,
    None    => false,
  }
}

fn select_mode(argv :: List[Str]) -> sess.AgentMode {
  if has_flag(argv, "--plan") then sess.Plan
  else if has_flag(argv, "--explore") then sess.Explore
  else sess.Build
}

fn select_provider_tag(argv :: List[Str]) -> Str {
  if has_flag(argv, "--mistral")  then "mistral"
  else if has_flag(argv, "--openai")   then "openai"
  else if has_flag(argv, "--google")   then "google"
  else if has_flag(argv, "--ollama")   then "ollama"
  else "anthropic"
}

fn main() -> [io, net, llm, proc, sql, time] Nil {
  io.print("lex-code v0.1 — Lex-specialized coding assistant")
  io.print("modes: --plan | --explore  (default: build)")
  io.print("providers: --mistral | --openai | --google | --ollama  (default: anthropic)")
  io.print("Ctrl-D to exit")
  let argv     := io.argv()
  let mode     := select_mode(argv)
  let provider := select_provider_tag(argv)
  match sess.new_session_with_provider("tui", mode, provider) {
    Err(e)      => io.print(str.concat("startup error: ", e)),
    Ok(session) => repl(session),
  }
}
