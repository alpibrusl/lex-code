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
      },
    d.StepToolExec(name, _) =>
      io.print(str.concat("[running: ", str.concat(name, "]"))),
    d.StepToolResult(_, ok) =>
      if ok { io.print("[ok]") } else { io.print("[error]") },
    d.StepDone(_) =>
      io.print(""),
  }
}

fn repl(session :: sess.Session, provider_tag :: Str) -> [io, net, llm, proc, sql, time] Nil {
  io.print("\n> ")
  match io.readline() {
    None       => io.print("\nbye"),
    Some(line) => {
      let input := str.trim(line)
      if str.is_empty(input) { repl(session, provider_tag) }
      else {
        let result := sess.run_turn_with_provider(session, input, provider_tag)
        let _ := list.map(result.steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        repl(result.session, provider_tag)
      }
    },
  }
}

fn run_once(task :: Str, mode :: sess.AgentMode, provider_tag :: Str)
  -> [io, net, llm, proc, sql, time] Nil {
  match sess.new_session_with_provider("cli", mode, provider_tag) {
    Err(e)      => io.println(str.concat("error: ", e)),
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, task, provider_tag)
      let _ := list.map(result.steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
      io.println("")
    },
  }
}

fn multi_repl(provider_tag :: Str) -> [io, net, llm, proc, sql, time] Nil {
  io.print("\n[multi] task> ")
  match io.readline() {
    None       => io.print("\nbye"),
    Some(line) => {
      let task := str.trim(line)
      if str.is_empty(task) { multi_repl(provider_tag) }
      else {
        io.print("[impl agent running...]")
        let result := multi.run_impl_then_test(task, provider_tag)
        io.print("[impl agent done — test agent running...]")
        let _ := list.map(result.impl_steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        io.print("\n[test agent output:]")
        let _ := list.map(result.test_steps, fn (s :: d.Step) -> [io] Nil { print_step(s) })
        multi_repl(provider_tag)
      }
    },
  }
}

fn has_flag(argv :: List[Str], flag :: Str) -> Bool {
  match list.find(argv, fn (a :: Str) -> Bool { str.eq(a, flag) }) {
    Some(_) => true,
    None    => false,
  }
}

# First non-flag argument is the task (one-shot CLI mode).
fn find_task(argv :: List[Str]) -> Option[Str] {
  list.find(argv, fn (a :: Str) -> Bool {
    if str.is_empty(a) { false }
    else { match list.head(str.chars(a)) {
      None    => false,
      Some(c) => str.neq(str.from_char(c), "-"),
    } }
  })
}

fn select_mode(argv :: List[Str]) -> sess.AgentMode {
  if has_flag(argv, "--plan") { sess.Plan }
  else { if has_flag(argv, "--explore") { sess.Explore }
  else { if has_flag(argv, "--refactor") { sess.Refactor }
  else { if has_flag(argv, "--spec") { sess.Spec }
  else { if has_flag(argv, "--test") { sess.Test }
  else { if has_flag(argv, "--review") { sess.Review }
  else { sess.Build } } } } } }
}

fn select_provider_tag(argv :: List[Str]) -> Str {
  if has_flag(argv, "--mistral") { "mistral" }
  else { if has_flag(argv, "--openai") { "openai" }
  else { if has_flag(argv, "--google") { "google" }
  else { if has_flag(argv, "--ollama") { "ollama" }
  else { if has_flag(argv, "--vllm") { "vllm" }
  else { "anthropic" } } } } }
}

fn main() -> [io, net, llm, proc, sql, time] Nil {
  let argv         := io.argv()
  let provider_tag := select_provider_tag(argv)
  let mode         := select_mode(argv)
  match find_task(argv) {
    Some(task) =>
      run_once(task, mode, provider_tag),
    None => {
      io.println("lex-code — Lex-specialized coding assistant")
      io.println("modes:     --plan | --explore | --refactor | --spec | --test | --review | --multi")
      io.println("providers: --mistral | --openai | --google | --ollama | --vllm  (default: anthropic)")
      io.println("one-shot:  lex run src/tui/main.lex -- [flags] \"your task\"")
      io.println("Ctrl-D to exit")
      if has_flag(argv, "--multi") { multi_repl(provider_tag) }
      else {
        match sess.new_session_with_provider("tui", mode, provider_tag) {
          Err(e)      => io.println(str.concat("startup error: ", e)),
          Ok(session) => repl(session, provider_tag),
        }
      }
    },
  }
}
