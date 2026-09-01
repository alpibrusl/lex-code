import "std.io" as io

import "std.str" as str

import "std.list" as list

import "lex-llm/delta" as d

import "lex-llm/message" as msg

import "lex-schema/json_value" as jv

import "../server/session" as sess

import "../server/multi_agent" as multi

# The live sink. run_turn_streaming_with_provider hands each Step to this the
# moment it happens, so a TextChunk here is a token the model has just
# produced rather than one recovered from a finished transcript.
#
# Callers must not also walk the returned steps with this — the turn would
# print twice. That is why repl and run_once discard the result's steps.
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

fn repl(session :: sess.Session, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream] Nil {
  io.print("\n> ")
  match io.read("-") {
    Err(_) => io.print("\nbye"),
    Ok(line) => {
      let input := str.trim(line)
      if str.is_empty(input) {
        repl(session, provider_tag)
      } else {
        let result := sess.run_turn_streaming_with_provider(session, input, provider_tag, print_step)
        repl(result.session, provider_tag)
      }
    },
  }
}

fn run_once(task :: Str, mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream] Nil {
  match sess.new_session_with_provider("cli", mode, provider_tag) {
    Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
    Ok(session) => {
      let __printed := sess.run_turn_streaming_with_provider(session, task, provider_tag, print_step)
      io.print(str.concat("", "\n"))
    },
  }
}

fn multi_repl(provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval] Nil {
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

fn has_flag(argv :: List[Str], flag :: Str) -> Bool
  examples {
    has_flag(["--plan"], "--plan") => true,
    has_flag([], "--plan") => false,
    has_flag(["--plans"], "--plan") => false,
    has_flag(["task", "--plan"], "--plan") => true
  }
{
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    a == flag
  })) {
    Some(_) => true,
    None => false,
  }
}

# First non-flag argument is the task (one-shot CLI mode).
fn find_task(argv :: List[Str]) -> Option[Str]
  examples {
    find_task(["--plan", "implement list.zip"]) => Some("implement list.zip"),
    find_task(["--plan"]) => None,
    find_task([]) => None,
    find_task(["first", "second"]) => Some("first")
  }
{
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

# Precedence is first-match down the chain below, not command-line order:
# `--bar --plan` and `--plan --bar` both select Plan. Nothing documented
# that until these examples did.
fn select_mode(argv :: List[Str]) -> sess.AgentMode
  examples {
    select_mode([]) => Build,
    select_mode(["--bar"]) => Bar,
    select_mode(["--review"]) => Review,
    select_mode(["--bar", "--plan"]) => Plan,
    select_mode(["a task"]) => Build
  }
{
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
              if has_flag(argv, "--bar") {
                Bar
              } else {
                Build
              }
            }
          }
        }
      }
    }
  }
}

# Same first-match precedence as select_mode: `--ollama --mistral` is
# mistral, whichever order they appear in.
fn select_provider_tag(argv :: List[Str]) -> Str
  examples {
    select_provider_tag([]) => "anthropic",
    select_provider_tag(["--ollama"]) => "ollama",
    select_provider_tag(["--litellm"]) => "litellm",
    select_provider_tag(["--ollama", "--mistral"]) => "mistral",
    select_provider_tag(["--bar"]) => "anthropic"
  }
{
  if has_flag(argv, "--mistral") {
    "mistral"
  } else {
    if has_flag(argv, "--openai") {
      "openai"
    } else {
      if has_flag(argv, "--google") {
        "google"
      } else {
        if has_flag(argv, "--vertex") {
          "vertex"
        } else {
          if has_flag(argv, "--litellm") {
            "litellm"
          } else {
            if has_flag(argv, "--ollama") {
              "ollama"
            } else {
              if has_flag(argv, "--vllm") {
                "vllm"
              } else {
                if has_flag(argv, "--opencode") {
                  "opencode"
                } else {
                  "anthropic"
                }
              }
            }
          }
        }
      }
    }
  }
}

# Headless entry point for agentcmp and CI.
#
# Usage (from the lex-code source directory):
#   lex run src/tui/main.lex run_headless '"<task>"' '"ollama"' \
#       --allow-effects env,io,net,llm,proc,sql,fs_write,time,concurrent,approval
#
# Emits streaming progress to stdout (tool names + text chunks), then on
# the last line emits a machine-readable sentinel the adapter can parse:
#
#   [AGENTCMP_RESULT]	{"ok":true,"final":"<escaped>"}
#
fn run_headless(task :: Str, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval] Nil {
  match sess.new_session_with_provider("headless", Build, provider_tag) {
    Err(e) => io.print(str.join(["[AGENTCMP_RESULT]\t{\"ok\":false,\"final\":\"", e, "\"}\n"], "")),
    Ok(session) => {
      let result := sess.run_turn_with_provider(session, task, provider_tag)
      let nsteps := list.len(result.steps)
      let __lex_discard_1 := io.print(str.join(["[dbg:steps=", int.to_str(nsteps), "]\n"], ""))
      let __lex_discard_2 := list.map(result.steps, fn (s :: d.Step) -> [io] Nil {
        let __lex_discard_3 := io.print(match s {
          StepDelta(delta) => match delta {
            TextChunk(t) => str.join(["[dbg:text:", t, "]\n"], ""),
            ToolCallBegin(_, n) => str.join(["[dbg:toolbegin:", n, "]\n"], ""),
            ToolArgChunk(_, _) => "",
            FinishDelta(r) => str.join(["[dbg:finish:", r, "]\n"], ""),
          },
          StepToolExec(n, _) => str.join(["[dbg:exec:", n, "]\n"], ""),
          StepToolResult(_, ok) => if ok {
            "[dbg:result:ok]\n"
          } else {
            "[dbg:result:err]\n"
          },
          StepDone(_) => "[dbg:done]\n",
        })
        print_step(s)
      })
      let final_text := collect_final_text(result.steps)
      io.print(str.join(["\n[AGENTCMP_RESULT]\t{\"ok\":true,\"final\":", jv.stringify(JStr(final_text)), "}\n"], ""))
    },
  }
}

# Extract the final assistant message text from the steps.
# Prefers the StepDone message (full assembled text) over accumulating
# TextChunk deltas, which are absent for models that use XML tool calls.
fn collect_final_text(steps :: List[d.Step]) -> Str {
  match sess.find_done_msg(steps) {
    Some(m) => match m {
      AssistantMsg(text, _) => text,
      _ => "",
    },
    None => list.fold(steps, "", fn (acc :: Str, s :: d.Step) -> Str {
      match s {
        StepDelta(delta) => match delta {
          TextChunk(t) => str.concat(acc, t),
          _ => acc,
        },
        _ => acc,
      }
    }),
  }
}

type Invocation = { mode :: sess.AgentMode, provider :: Str, task :: Option[Str], multi :: Bool }

# The whole command line, resolved in one pure function.
#
# This exists because of the bug it would have caught. `main` used to read
# `let argv := []` — a workaround for lex 0.9.5 having no `io.argv()` that
# outlived the toolchain needing it — so every flag and the task argument
# were dropped, for releases, unnoticed. The parsers below were correct the
# entire time; nothing tested the wiring between them and `main`, because
# `main` is effectful and interactive and examples cannot reach it.
#
# Resolving the invocation here leaves `main` with one job it cannot get
# subtly wrong: hand `io.argv()` to this and act on the result. The examples
# then cover the whole parse path rather than its pieces.
fn plan_invocation(argv :: List[Str]) -> Invocation
  examples {
    plan_invocation([]) => { mode: Build, provider: "anthropic", task: None, multi: false },
    plan_invocation(["--bar", "walk this repo"]) => { mode: Bar, provider: "anthropic", task: Some("walk this repo"), multi: false },
    plan_invocation(["--ollama", "--plan"]) => { mode: Plan, provider: "ollama", task: None, multi: false },
    plan_invocation(["--multi"]) => { mode: Build, provider: "anthropic", task: None, multi: true },
    plan_invocation(["--litellm", "--review", "check the diff"]) => { mode: Review, provider: "litellm", task: Some("check the diff"), multi: false }
  }
{
  { mode: select_mode(argv), provider: select_provider_tag(argv), task: find_task(argv), multi: has_flag(argv, "--multi") }
}

fn main() -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream] Nil {
  let inv := plan_invocation(io.argv())
  let provider_tag := inv.provider
  let mode := inv.mode
  match inv.task {
    Some(task) => run_once(task, mode, provider_tag),
    None => {
      io.print(str.concat("lex-code — Lex-specialized coding assistant", "\n"))
      io.print(str.concat("modes:     --plan | --explore | --refactor | --spec | --test | --review | --bar | --multi", "\n"))
      io.print(str.concat("providers: --mistral | --openai | --google | --vertex | --litellm | --ollama | --vllm | --opencode  (default: anthropic)", "\n"))
      io.print(str.concat("one-shot:  lex run src/tui/main.lex -- [flags] \"your task\"", "\n"))
      io.print(str.concat("Ctrl-D to exit", "\n"))
      if inv.multi {
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

