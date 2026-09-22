import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.time" as time

import "std.crypto" as crypto

import "std.int" as int

import "lex-llm/delta" as d

import "lex-llm/agent" as ag

import "lex-llm/streaming" as streaming

import "std.iter" as iter

import "lex-llm/message" as msg

import "lex-schema/json_value" as jv

import "std.process" as proc

import "../issue_contract" as ic

import "../server/session" as sess

import "../server/multi_agent" as multi

import "../server/graph" as graph

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
      UsageDelta(_) => (),
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

# A unique id per invocation, not the fixed "cli" new_session_with_provider
# used to key on. `new_session_from_log` (session.lex) always starts a
# session's in-memory cache at `messages: []`, regardless of what a log
# under that id already holds — the right behavior for a graph pipeline
# node, whose id is reused deliberately across runs of the SAME pipeline,
# but wrong for a one-shot CLI task: a second `bin/lex-code "task"` in the
# same project would find "cli"'s log already holding the first run's
# events, immediately fail the fresh session's event_count check, and
# refuse before ever reaching the model. A fresh id per invocation gives
# each run its own file with no such collision.
fn cli_session_id() -> [time, crypto, random] Str {
  str.join(["cli-", int.to_str(time.now_ms()), "-", crypto.random_str_hex(4)], "")
}

# One-shot sessions persist their trail (session.new_session_persistent_with_provider,
# `.lex/sessions/<id>.db`) rather than the ephemeral in-memory log the REPL
# uses. A REPL user watches every step live; a one-shot run that stops
# without producing anything — hits its step budget, say — otherwise
# leaves no record of what it actually did once the process exits, which
# is exactly the case that needs a post-mortem the most.
fn run_once(task :: Str, mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let session_id := cli_session_id()
  match sess.new_session_persistent_with_provider(session_id, mode, provider_tag) {
    Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
    Ok(session) => {
      let __printed := sess.run_turn_streaming_with_provider(session, task, provider_tag, print_step)
      io.print(str.join(["\n(trail: .lex/sessions/", session_id, ".db)\n"], ""))
    },
  }
}

# `--issue=<id> ["extra guidance"]` (#173, lex-lang #949): implement a
# typed issue from its declared acceptance, then let the gate say whether
# it is done.
#
# The issue's acceptance becomes the task (issue_contract.contract_prompt)
# — the contract to satisfy, not a paraphrase of it. `.lex/intent/issue`
# ties this session to the issue, so every clean .lex write publishes with
# `--intent-issue` and its ops link back (issue ↔ intent ↔ ops). The run
# ends with `lex issue verify` whatever the model claimed, and prints the
# verdict on a machine-readable last line:
#
#   [ISSUE_VERDICT]\t<verified|failed|inconclusive|unavailable>\t<issue_id>
fn fetch_issue(issue_id :: Str) -> [proc] Result[jv.Json, Str] {
  match proc.run("lex", ["--output", "json", "issue", "show", issue_id]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code != 0 {
      Err(str.join(["cannot read issue ", issue_id, ": ", str.trim(str.concat(out.stdout, out.stderr))], ""))
    } else {
      match jv.parse(str.trim(out.stdout)) {
        Err(_) => Err(str.concat("unreadable issue ", issue_id)),
        Ok(issue) => Ok(issue),
      }
    },
  }
}

# `--refine=<id> ["guidance"]` (#956): the agent reads the code and proposes
# a typed acceptance for a free-form issue with `issue_propose`; the run
# ends by listing the issue's proposals and the command that approves one.
# Approving stays with the human — lex-code has no tool for it. The
# session is NOT bound to the issue: refining produces no code to link.
fn run_refine(issue_id :: Str, guidance :: Option[Str], provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  match fetch_issue(issue_id) {
    Err(e) => io.print(str.join(["error: ", e, "\n"], "")),
    Ok(issue) => if ic.shape_of(issue) != "free_form" {
      io.print(str.join(["issue ", issue_id, " is already ", ic.shape_of(issue), " — nothing to refine; implement it with --issue=", issue_id, "\n"], ""))
    } else {
      let prompt := match guidance {
        None => ic.refine_prompt(issue),
        Some(g) => str.join([ic.refine_prompt(issue), "\nAdditional guidance from the user:\n", g, "\n"], ""),
      }
      let session_id := cli_session_id()
      match sess.new_session_persistent_with_provider(session_id, Build, provider_tag) {
        Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
        Ok(session) => {
          let __printed := sess.run_turn_streaming_with_provider(session, prompt, provider_tag, print_step)
          let listed := match proc.run("lex", ["issue", "proposals", issue_id]) {
            Err(e) => e,
            Ok(o) => str.trim(str.concat(o.stdout, o.stderr)),
          }
          io.print(str.join(["\n(trail: .lex/sessions/", session_id, ".db)\nproposals for ", issue_id, ":\n", listed, "\n\nreview, then:  lex issue approve <proposal> --by <you>   (or: lex issue reject <proposal> --by <you> --notes ...)\n"], ""))
        },
      }
    },
  }
}

fn run_issue(issue_id :: Str, guidance :: Option[Str], mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  match fetch_issue(issue_id) {
    Err(e) => io.print(str.join(["error: ", e, "\n"], "")),
    Ok(issue) => {
      let contract := ic.contract_prompt(issue)
      let task := match guidance {
        None => contract,
        Some(g) => str.join([contract, "\nAdditional guidance from the user:\n", g, "\n"], ""),
      }
      let session_id := cli_session_id()
      match sess.new_session_persistent_with_provider(session_id, mode, provider_tag) {
        Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
        Ok(session) => {
          let __d := proc.run("mkdir", ["-p", ".lex/intent"])
          let __w := io.write(".lex/intent/issue", str.join([session_id, "\t", issue_id], ""))
          let __printed := sess.run_turn_streaming_with_provider(session, task, provider_tag, print_step)
          let verdict := match proc.run("lex", ["--output", "json", "issue", "verify", issue_id]) {
            Err(_) => "unavailable",
            Ok(v) => match ic.verdict_of(v.stdout) {
              None => "unavailable",
              Some(word) => word,
            },
          }
          io.print(str.join(["\n(trail: .lex/sessions/", session_id, ".db)\n[ISSUE_VERDICT]\t", verdict, "\t", issue_id, "\n"], ""))
        },
      }
    },
  }
}

# `--once --multi --pipeline=NAME "task"` — a graph pipeline run non-
# interactively, exactly once, the multi-agent counterpart to `run_once`.
# Before this, `--multi`/`--pipeline=` were silently ignored whenever a
# task was given on the command line: `main`'s dispatch only ever
# consulted them in the no-task branch that launches `multi_repl`, so
# there was no way to drive a graph pipeline (including a fix loop) from
# a single non-interactive invocation — only from a live REPL session.
# Uses the persistent runner, same as `run_once`, so every node's trail —
# `impl`, `test`, and any `impl_retryN` a fix loop actually ran — survives
# the process for post-mortem debugging.
fn run_once_multi(task :: Str, pipeline :: graph.Node, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random, concurrent] Nil {
  io.print(str.join(["[running ", int.to_str(graph.node_count(pipeline)), " agents: ", graph.render_shape(pipeline), "]\n"], ""))
  let result := graph.run_graph_persistent(pipeline, task, provider_tag)
  let __printed := list.map(result.results, fn (r :: graph.NodeResult) -> [io] Nil {
    print_node(r)
  })
  io.print(str.join(["\n(trails: ", str.join(list.map(result.results, fn (r :: graph.NodeResult) -> Str {
    str.join([".lex/sessions/", r.name, ".db"], "")
  }), ", "), ")\n"], ""))
}

fn multi_repl(provider_tag :: Str, pipeline :: graph.Node) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random, concurrent] Nil {
  io.print(str.join(["\n[multi ", graph.render_shape(pipeline), "] task> "], ""))
  match io.read("-") {
    Err(_) => io.print("\nbye"),
    Ok(line) => {
      let task := str.trim(line)
      if str.is_empty(task) {
        multi_repl(provider_tag, pipeline)
      } else {
        io.print(str.join(["[running ", int.to_str(graph.node_count(pipeline)), " agents...]"], ""))
        let result := graph.run_graph(pipeline, task, provider_tag)
        let __printed := list.map(result.results, fn (r :: graph.NodeResult) -> [io] Nil {
          print_node(r)
        })
        multi_repl(provider_tag, pipeline)
      }
    },
  }
}

fn print_node(r :: graph.NodeResult) -> [io] Nil {
  io.print(str.join(["\n[", r.name, " agent output:]"], ""))
  let __printed := list.map(r.steps, fn (s :: d.Step) -> [io] Nil {
    print_step(s)
  })
  ()
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

# `--pipeline=NAME`, one token rather than two.
#
# Two tokens would break `find_task`, which takes the first argv entry not
# starting with "-" — so `--pipeline impl_then_test` would silently run
# "impl_then_test" as the task. Gluing the value to the flag keeps the
# whole thing invisible to that scan.
fn find_pipeline(argv :: List[Str]) -> Option[Str]
  examples {
    find_pipeline(["--pipeline=impl_then_test"]) => Some("impl_then_test"),
    find_pipeline(["--multi", "--pipeline=x", "a task"]) => Some("x"),
    find_pipeline(["--pipeline="]) => None,
    find_pipeline(["--multi"]) => None,
    find_pipeline([]) => None
  }
{
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    str.starts_with(a, "--pipeline=")
  })) {
    None => None,
    Some(tok) => match str.strip_prefix(tok, "--pipeline=") {
      None => None,
      Some(name) => if str.is_empty(name) {
        None
      } else {
        Some(name)
      },
    },
  }
}

# `--issue=<id>` (#173): implement a typed issue from its declared
# acceptance. One token for the same reason as `--pipeline=`.
fn find_issue(argv :: List[Str]) -> Option[Str]
  examples {
    find_issue(["--issue=9fd3cc"]) => Some("9fd3cc"),
    find_issue(["--ollama", "--issue=abc", "keep it small"]) => Some("abc"),
    find_issue(["--issue="]) => None,
    find_issue(["--issue", "abc"]) => None,
    find_issue([]) => None
  }
{
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    str.starts_with(a, "--issue=")
  })) {
    None => None,
    Some(tok) => match str.strip_prefix(tok, "--issue=") {
      None => None,
      Some(id) => if str.is_empty(id) {
        None
      } else {
        Some(id)
      },
    },
  }
}

# `--refine=<id>` (#956): propose a typed acceptance for a free-form issue.
fn find_refine(argv :: List[Str]) -> Option[Str]
  examples {
    find_refine(["--refine=abc"]) => Some("abc"),
    find_refine(["--refine="]) => None,
    find_refine(["--issue=abc"]) => None
  }
{
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    str.starts_with(a, "--refine=")
  })) {
    None => None,
    Some(tok) => match str.strip_prefix(tok, "--refine=") {
      None => None,
      Some(id) => if str.is_empty(id) {
        None
      } else {
        Some(id)
      },
    },
  }
}

# A `--pipeline=` value that names nothing must not quietly become the
# default pipeline: the user asked for a specific arrangement of agents,
# and running a different one is a wrong answer dressed as a working run.
#
# A preset name wins over the spec grammar, so `impl_then_test` is not
# read as a single agent called "impl_then_test" and rejected. Anything
# that is not a preset is parsed as a spec, which is what makes
# `--pipeline=build,spec,test` work without a second flag.
fn resolve_pipeline(name :: Option[Str]) -> Result[graph.Node, Str] {
  match name {
    None => Ok(graph.impl_then_test()),
    Some(n) => match graph.preset(n) {
      Some(node) => Ok(node),
      None => match graph.from_spec(n) {
        Ok(node) => Ok(node),
        Err(m) => Err(str.join([m, "\npresets: ", str.join(graph.preset_names(), ", ")], "")),
      },
    },
  }
}

# Precedence is first-match down the chain below, not command-line order:
# `--bar --plan` and `--plan --bar` both select Plan. Nothing documented
# that until these examples did.
fn select_mode(argv :: List[Str]) -> sess.AgentMode
  examples {
    select_mode([]) => Build,
    select_mode(["--bar"]) => Bar,
    select_mode(["--review"]) => Review,
    select_mode(["--verify"]) => Verify,
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
              if has_flag(argv, "--verify") {
                Verify
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
}

# Same first-match precedence as select_mode: `--ollama --mistral` is
# mistral, whichever order they appear in.
fn select_provider_tag(argv :: List[Str]) -> Str
  examples {
    select_provider_tag([]) => "litellm",
    select_provider_tag(["--ollama"]) => "ollama",
    select_provider_tag(["--litellm"]) => "litellm",
    select_provider_tag(["--ollama", "--mistral"]) => "mistral",
    select_provider_tag(["--bar"]) => "litellm"
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
                  "litellm"
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
fn run_headless(task :: Str, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, crypto, random] Nil {
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
            UsageDelta(_) => "",
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

# ---- `--regenerate`: the replay-as-verification runner (lex-lang #836) ----
#
# `lex op replay <op> --regenerate-cmd 'lex-code --ollama --regenerate'`
# pipes a ReplayRequest JSON to this on stdin; lex-code regenerates the
# target function from its recorded intent + parent program and writes
# ONLY the Lex source of that function to stdout, which lex op replay
# then compares (content-addressed) against what the op recorded. This
# closes the loop: lex-code both *produces* ops (with intent) and can
# *regenerate* them for verification.
#
# It is a single no-tools completion, deliberately: regeneration must
# return text, never touch the filesystem — and lex-code's write/edit
# tools now publish into the op-log, which would be exactly wrong here.
# stdout is the artifact; on any failure it stays empty, so lex op
# replay records an honest "not reproduced" rather than crashing.
fn jstr(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    None => "",
    Some(v) => match jv.as_str(v) {
      None => "",
      Some(s) => s,
    },
  }
}

fn regen_system() -> Str {
  str.join(["You regenerate exactly one Lex function and output ONLY its Lex source.", "No prose, no explanation, no markdown fences — just the function.", "Lex is expression-bodied: the last expression is the return value, with no `return` and no trailing semicolons.", "Type annotations use `::` (e.g. `x :: Int`). Local bindings are `let name := value`. Matching is `match e { Pat => expr, ... }`.", "Lex has NO match guards: `Pat if cond => ...` is a PARSE ERROR — use plain patterns, or a nested `if` in the arm body / instead of `match`.", "Lex has NO unary minus: write `0 - x`, never `-x`.", "Conditionals are expressions: `if cond { a } else { b }`; chain as `if c1 { .. } else { if c2 { .. } else { .. } }`.", "Example: fn add(a :: Int, b :: Int) -> Int { a + b }"], "\n")
}

fn regen_user_prompt(sig :: Str, prompt :: Str, parent :: Str) -> Str {
  let ctx := if str.is_empty(str.trim(parent)) {
    ""
  } else {
    str.join(["Existing program (context — do NOT repeat it in your output):\n", parent, "\n\n"], "")
  }
  let intent := if str.is_empty(str.trim(prompt)) {
    "Intent: (none recorded — reproduce the function faithfully)\n\n"
  } else {
    str.join(["Intent (what was asked):\n", prompt, "\n\n"], "")
  }
  let want := if str.is_empty(str.trim(sig)) {
    ""
  } else {
    str.join(["Regenerate exactly this function, with this signature:\n", sig, "\n"], "")
  }
  str.join([ctx, intent, want], "")
}

# Strip a leading/trailing markdown fence if the model wrapped its
# output in one, keeping the inner source verbatim.
fn strip_fences(s :: Str) -> Str {
  let t := str.trim(s)
  if str.starts_with(t, "```") {
    let lines := str.split(t, "\n")
    let no_open := list.tail(lines)
    let rev := list.reverse(no_open)
    let no_close := match list.head(rev) {
      Some(last) => if str.starts_with(str.trim(last), "```") {
        list.tail(rev)
      } else {
        rev
      },
      None => rev,
    }
    str.trim(str.join(list.reverse(no_close), "\n"))
  } else {
    t
  }
}

# The agent used for regeneration: the provider/model the flags select,
# but with tools stripped and a one-completion budget so it returns text
# and never touches the filesystem (lex-code's write/edit tools publish
# into the op-log, which would be exactly wrong inside a replay).
fn regen_agent(provider_tag :: Str) -> [env] ag.AgentLoop {
  let base := sess.pick_agent(Build, provider_tag)
  { name: "regenerate", goal: regen_system(), model: base.model, provider: base.provider, tools: [], options: { temperature: None, top_p: None, max_steps: Some(1), max_tokens: None }, permission_spec: None }
}

# The regenerated source text for one request. Uses the provider's
# streaming half when it has one — ollama's non-streaming `chat` returns
# nothing, and every working lex-code run streams — folding TextChunks
# into the answer. Providers with no streaming half fall back to the
# non-streaming path.
fn regen_text(agent :: ag.AgentLoop, user :: Str) -> [net, llm, stream] Str {
  let messages := [msg.system(agent.goal), msg.user(user)]
  let deltas := match agent.provider.stream {
    Some(sc) => streaming.collect(sc, agent.model, messages, []),
    None => iter.to_list(agent.provider.chat(agent.model, messages, [])),
  }
  list.fold(deltas, "", fn (acc :: Str, dl :: d.Delta) -> Str {
    match dl {
      TextChunk(t) => str.concat(acc, t),
      _ => acc,
    }
  })
}

# Read all of stdin, one line at a time, until EOF. `io.read("-")` does
# NOT read stdin (it opens a file literally named "-", which fails on a
# pipe); `io.readline()` is the real stdin reader, and the ReplayRequest
# JSON that `lex op replay --regenerate-cmd` pipes in is pretty-printed
# across many lines, so a single read would only ever see the opening `{`.
fn drain_stdin(acc :: List[Str]) -> [io] List[Str] {
  match io.readline() {
    None => list.reverse(acc),
    Some(l) => drain_stdin(list.cons(l, acc)),
  }
}

fn regenerate(provider_tag :: Str) -> [env, io, net, llm, stream] Nil {
  let raw := str.join(drain_stdin([]), "\n")
  match jv.parse(raw) {
    Err(_) => (),
    Ok(req) => {
      let user := regen_user_prompt(jstr(req, "target_signature"), jstr(req, "prompt"), jstr(req, "parent_program"))
      io.print(strip_fences(regen_text(regen_agent(provider_tag), user)))
    },
  }
}

type Invocation = { mode :: sess.AgentMode, provider :: Str, task :: Option[Str], multi :: Bool, pipeline :: Option[Str], regenerate :: Bool, issue :: Option[Str], refine :: Option[Str] }

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
    plan_invocation([]) => { mode: Build, provider: "litellm", task: None, multi: false, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--bar", "walk this repo"]) => { mode: Bar, provider: "litellm", task: Some("walk this repo"), multi: false, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--ollama", "--plan"]) => { mode: Plan, provider: "ollama", task: None, multi: false, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--multi"]) => { mode: Build, provider: "litellm", task: None, multi: true, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--litellm", "--review", "check the diff"]) => { mode: Review, provider: "litellm", task: Some("check the diff"), multi: false, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--litellm", "--verify", "check src/abi.lex against the ABI spec"]) => { mode: Verify, provider: "litellm", task: Some("check src/abi.lex against the ABI spec"), multi: false, pipeline: None, regenerate: false, issue: None, refine: None },
    plan_invocation(["--multi", "--pipeline=impl_then_spec_then_test"]) => { mode: Build, provider: "litellm", task: None, multi: true, pipeline: Some("impl_then_spec_then_test"), regenerate: false, issue: None, refine: None },
    plan_invocation(["--ollama", "--regenerate"]) => { mode: Build, provider: "ollama", task: None, multi: false, pipeline: None, regenerate: true, issue: None, refine: None },
    plan_invocation(["--opencode", "--issue=9fd3cc"]) => { mode: Build, provider: "opencode", task: None, multi: false, pipeline: None, regenerate: false, issue: Some("9fd3cc"), refine: None },
    plan_invocation(["--ollama", "--refine=ab12"]) => { mode: Build, provider: "ollama", task: None, multi: false, pipeline: None, regenerate: false, issue: None, refine: Some("ab12") }
  }
{
  { mode: select_mode(argv), provider: select_provider_tag(argv), task: find_task(argv), multi: has_flag(argv, "--multi"), pipeline: find_pipeline(argv), regenerate: has_flag(argv, "--regenerate"), issue: find_issue(argv), refine: find_refine(argv) }
}

fn main() -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random, concurrent] Nil {
  let inv := plan_invocation(io.argv())
  let provider_tag := inv.provider
  let mode := inv.mode
  if inv.regenerate {
    regenerate(provider_tag)
  } else {
    match inv.refine {
      Some(issue_id) => run_refine(issue_id, inv.task, provider_tag),
      None => match inv.issue {
        Some(issue_id) => run_issue(issue_id, inv.task, mode, provider_tag),
        None => dispatch(inv, mode, provider_tag),
      },
    }
  }
}

fn dispatch(inv :: Invocation, mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random, concurrent] Nil {
  match inv.task {
    Some(task) => if inv.multi {
      match resolve_pipeline(inv.pipeline) {
        Err(msg) => io.print(str.concat(msg, "\n")),
        Ok(pipeline) => run_once_multi(task, pipeline, provider_tag),
      }
    } else {
      run_once(task, mode, provider_tag)
    },
    None => {
      io.print(str.concat("lex-code — Lex-specialized coding assistant", "\n"))
      io.print(str.concat("modes:     --plan | --explore | --refactor | --spec | --test | --review | --verify | --bar | --multi", "\n"))
      io.print(str.join(["pipelines: --pipeline=", str.join(graph.preset_names(), " | --pipeline="), "\n           --pipeline=build,spec,test|review   (\",\" in order, \"|\" at once)", "\n"], ""))
      io.print(str.concat("providers: --mistral | --openai | --google | --vertex | --litellm | --ollama | --vllm | --opencode  (default: anthropic)", "\n"))
      io.print(str.concat("one-shot:  lex run src/tui/main.lex -- [flags] \"your task\"", "\n"))
      io.print(str.concat("issue:     --issue=<id> [\"extra guidance\"]   implement a typed issue from its acceptance, then verify it", "\n"))
      io.print(str.concat("refine:    --refine=<id>                      propose a typed acceptance for a free_form issue (you approve it)", "\n"))
      io.print(str.concat("Ctrl-D to exit", "\n"))
      if inv.multi {
        match resolve_pipeline(inv.pipeline) {
          Err(msg) => io.print(str.concat(msg, "\n")),
          Ok(pipeline) => multi_repl(provider_tag, pipeline),
        }
      } else {
        match sess.new_session_with_provider("tui", mode, provider_tag) {
          Err(e) => io.print(str.concat(str.concat("startup error: ", e), "\n")),
          Ok(session) => repl(session, provider_tag),
        }
      }
    },
  }
}

