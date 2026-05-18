import "std.io"   as io
import "std.str"  as str
import "std.list" as list
import "std.env"  as env

import "lex-llm/delta"   as d
import "lex-llm/message" as msg

import "../server/session"     as sess
import "../server/multi_agent" as multi

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

fn repl(session :: sess.Session, provider_tag :: Str) -> [io, net, llm, proc, sql, time] Nil {
  io.print("\n> ")
  match io.readline() {
    None       => io.print("\nbye"),
    Some(line) =>
      let input := str.trim(line)
      if str.is_empty(input) then
        repl(session, provider_tag)
      else
        let result := sess.run_turn_with_provider(session, input, provider_tag)
        let _ := list.map(result.steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        repl(result.session, provider_tag),
  }
}

fn multi_repl(provider_tag :: Str) -> [io, net, llm, proc, sql, time] Nil {
  io.print("\n[multi] task> ")
  match io.readline() {
    None       => io.print("\nbye"),
    Some(line) =>
      let task := str.trim(line)
      if str.is_empty(task) then
        multi_repl(provider_tag)
      else
        io.print("[impl agent running...]")
        let result := multi.run_impl_then_test(task, provider_tag)
        io.print("[impl agent done — test agent running...]")
        let _ := list.map(result.impl_steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        io.print("\n[test agent output:]")
        let _ := list.map(result.test_steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        multi_repl(provider_tag),
  }
}

fn has_flag(argv :: List[Str], flag :: Str) -> Bool {
  match list.find(argv, fn (a :: Str) -> Bool { str.eq(a, flag) }) {
    Some(_) => true,
    None    => false,
  }
}

fn select_mode(argv :: List[Str]) -> sess.AgentMode {
  if has_flag(argv, "--plan")     then sess.Plan
  else if has_flag(argv, "--explore")  then sess.Explore
  else if has_flag(argv, "--refactor") then sess.Refactor
  else if has_flag(argv, "--spec")     then sess.Spec
  else if has_flag(argv, "--test")     then sess.Test
  else if has_flag(argv, "--review")   then sess.Review
  else sess.Build
}

fn select_provider_tag(argv :: List[Str]) -> Str {
  if has_flag(argv, "--mistral") then "mistral"
  else if has_flag(argv, "--openai")  then "openai"
  else if has_flag(argv, "--google")  then "google"
  else if has_flag(argv, "--ollama")  then "ollama"
  else "anthropic"
}

fn main() -> [io, net, llm, proc, sql, time] Nil {
  io.print("lex-code v0.2 — Lex-specialized coding assistant")
  io.print("modes:     --plan | --explore | --refactor | --spec | --test | --review | --multi")
  io.print("providers: --mistral | --openai | --google | --ollama  (default: anthropic)")
  io.print("Ctrl-D to exit")
  let argv         := io.argv()
  let provider_tag := select_provider_tag(argv)
  if has_flag(argv, "--multi") then
    multi_repl(provider_tag)
  else
    let mode := select_mode(argv)
    match sess.new_session_with_provider("tui", mode, provider_tag) {
      Err(e)      => io.print(str.concat("startup error: ", e)),
      Ok(session) => repl(session, provider_tag),
    }
}
