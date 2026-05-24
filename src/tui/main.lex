import "std.io" as io

import "std.str" as str

import "std.list" as list

import "lex-llm/delta" as d

import "../server/session" as sess

import "../server/multi_agent" as multi

fn print_step(step :: d.Step) -> [io] Nil {
  match step {
    StepDelta(delta) => match delta {
      TextChunk(text) => io.print(text),
      ToolCallBegin(_, name) => io.print(str.concat("\n[tool: ", str.concat(name, "]"))),
      ToolArgChunk(_, _) => (),
      FinishDelta(_) => (),
    },
    StepToolExec(name, _) => io.print(str.concat("[running: ", str.concat(name, "]"))),
    StepToolResult(_, ok) => if ok {
      io.print("[ok]")
    } else {
      io.print("[error]")
    },
    StepDone(_) => io.print(""),
  }
}

fn repl(session :: sess.Session, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_write, time] Nil {
  io.print("\n> ")
  match io.read("-") {
    Err(_) => io.print("\nbye"),
    Ok(line) => {
      let input := str.trim(line)
      if str.is_empty(input) {
        repl(session, provider_tag)
      } else {
        let result := sess.run_turn_with_provider(session, input, provider_tag)
        let __lex_discard_1 := list.map(result.steps, fn (s :: d.Step) -> [io] Nil {
          print_step(s)
        })
        repl(result.session, provider_tag)
      }
    },
  }
}

fn run_once(task :: Str, mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_write, time] Nil {
  match sess.new_session_with_provider("cli", mode, provider_tag) {
    Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, task, provider_tag)
      let __lex_discard_2 := list.map(result.steps, fn (s :: d.Step) -> [io] Nil {
        print_step(s)
      })
      io.print(str.concat("", "\n"))
    },
  }
}

fn multi_repl(provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_write, time] Nil {
  io.print("\n[multi] task> ")
  match io.read("-") {
    Err(_) => io.print("\nbye"),
    Ok(line) => {
      let task := str.trim(line)
      if str.is_empty(task) {
        multi_repl(provider_tag)
      } else {
        io.print("[impl agent running...]")
        let result := multi.run_impl_then_test(task, provider_tag)
        io.print("[impl agent done — test agent running...]")
        let __lex_discard_3 := list.map(result.impl_steps, fn (s :: d.Step) -> [io] Nil {
          print_step(s)
        })
        io.print("\n[test agent output:]")
        let __lex_discard_4 := list.map(result.test_steps, fn (s :: d.Step) -> [io] Nil {
          print_step(s)
        })
        multi_repl(provider_tag)
      }
    },
  }
}

fn has_flag(argv :: List[Str], flag :: Str) -> Bool {
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    a == flag
  })) {
    Some(_) => true,
    None => false,
  }
}

# First non-flag argument is the task (one-shot CLI mode).
fn find_task(argv :: List[Str]) -> Option[Str] {
  list.head(list.filter(argv, fn (a :: Str) -> Bool {
    if str.is_empty(a) {
      false
    } else {
      match list.head(str.split(a, "")) {
        None => false,
        Some(c) => c != "-",
      }
    }
  }))
}

fn select_mode(argv :: List[Str]) -> sess.AgentMode {
  if has_flag(argv, "--plan") {
    Plan
  } else {
    if has_flag(argv, "--explore") {
      Explore
    } else {
      if has_flag(argv, "--refactor") {
        Refactor
      } else {
        if has_flag(argv, "--spec") {
          Spec
        } else {
          if has_flag(argv, "--test") {
            Test
          } else {
            if has_flag(argv, "--review") {
              Review
            } else {
              Build
            }
          }
        }
      }
    }
  }
}

fn select_provider_tag(argv :: List[Str]) -> Str {
  if has_flag(argv, "--mistral") {
    "mistral"
  } else {
    if has_flag(argv, "--openai") {
      "openai"
    } else {
      if has_flag(argv, "--google") {
        "google"
      } else {
        if has_flag(argv, "--ollama") {
          "ollama"
        } else {
          if has_flag(argv, "--vllm") {
            "vllm"
          } else {
            "anthropic"
          }
        }
      }
    }
  }
}

fn main() -> [env, io, net, llm, proc, sql, fs_write, time] Nil {
  let argv := []
  let provider_tag := select_provider_tag(argv)
  let mode := select_mode(argv)
  match find_task(argv) {
    Some(task) => run_once(task, mode, provider_tag),
    None => {
      io.print(str.concat("lex-code — Lex-specialized coding assistant", "\n"))
      io.print(str.concat("modes:     --plan | --explore | --refactor | --spec | --test | --review | --multi", "\n"))
      io.print(str.concat("providers: --mistral | --openai | --google | --ollama | --vllm  (default: anthropic)", "\n"))
      io.print(str.concat("one-shot:  lex run src/tui/main.lex -- [flags] \"your task\"", "\n"))
      io.print(str.concat("Ctrl-D to exit", "\n"))
      if has_flag(argv, "--multi") {
        multi_repl(provider_tag)
      } else {
        match sess.new_session_with_provider("tui", mode, provider_tag) {
          Err(e) => io.print(str.concat(str.concat("startup error: ", e), "\n")),
          Ok(session) => repl(session, provider_tag),
        }
      }
    },
  }
}

