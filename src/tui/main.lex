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

import "../package_flow/plan" as pplan

import "../package_flow/board" as pb

import "../package_flow/apply" as papply

import "../package_flow/parallel" as par

import "../package_flow/merge" as merge

import "../tools/session_health" as health

import "../server/session" as sess

import "../server/multi_agent" as multi

import "../server/graph" as graph

# The live sink. run_turn_streaming_with_provider hands each Step to this the
# moment it happens, so a TextChunk here is a token the model has just
# produced rather than one recovered from a finished transcript.
#
# Callers must not also walk the returned steps with this — the turn would
# print twice. That is why repl and run_once discard the result's steps.
#
# A provider streams TextChunk deltas one small fragment at a time — often
# a sub-word piece, never aligned to a sentence — and io.print always
# appends a newline (std.io has no raw, newline-free write), so printing
# each fragment as it arrives put one on almost every line: prose came out
# as a vertical staircase instead of flowing, wrapped text. line_buf_path
# is a scratch file (not the trail, not anything committed) that holds
# whatever fragment hasn't reached a real "\n" yet; each new fragment is
# appended there and only the complete line(s) it completes are printed,
# so a paragraph reaches the terminal as the same lines the model actually
# wrote, not one per fragment. A single fixed path is fine — only one
# streaming turn is ever live in a process at a time.
fn line_buf_path() -> Str {
  "/tmp/lex-code-linebuf"
}

fn read_buf() -> [io] Str {
  match io.read(line_buf_path()) {
    Ok(s) => s,
    Err(_) => "",
  }
}

fn write_buf(text :: Str) -> [io] Nil {
  match io.write(line_buf_path(), text) {
    _ => (),
  }
}

# Splits on "\n", prints every complete line, and returns the trailing
# fragment (the part after the last "\n", possibly empty) to keep buffering.
fn flush_complete_lines(text :: Str) -> [io] Str {
  let parts := str.split(text, "\n")
  if list.len(parts) <= 1 {
    text
  } else {
    let rev := list.reverse(parts)
    let complete := list.reverse(list.tail(rev))
    let __printed := list.fold(complete, (), fn (acc :: Unit, line :: Str) -> [io] Unit {
      io.print(line)
    })
    match list.head(rev) {
      Some(r) => r,
      None => "",
    }
  }
}

fn append_chunk(text :: Str) -> [io] Nil {
  write_buf(flush_complete_lines(str.concat(read_buf(), text)))
}

# Prints whatever's pending even without a trailing "\n" — called right
# before a tool marker or StepDone, each already its own line, so nothing
# waits behind a paragraph that never happened to end in a newline.
fn flush_remaining() -> [io] Nil {
  let pending := read_buf()
  if str.is_empty(pending) {
    ()
  } else {
    let __printed := io.print(pending)
    write_buf("")
  }
}

# Did the model do anything at all — say something, or call a tool? A turn
# that produced neither means the provider returned nothing (a rejected key, an
# exhausted quota, a dropped connection): retrying it instantly cannot help.
fn produced_output(steps :: List[d.Step]) -> Bool
  examples {
    produced_output([]) => false,
    produced_output([StepToolExec("read", "{}")]) => true,
    produced_output([StepDelta(TextChunk("  "))]) => false,
    produced_output([StepDelta(TextChunk("done"))]) => true,
    produced_output([StepDelta(TextChunk("[provider error: HTTP 429: Go usage limit exceeded]"))]) => false
  }
{
  list.fold(steps, false, fn (acc :: Bool, s :: d.Step) -> Bool {
    acc or match s {
      StepToolExec(_, _) => true,
      StepDelta(delta) => match delta {
        TextChunk(t) => not str.is_empty(str.trim(t)) and not str.starts_with(str.trim(t), "[provider error:"),
        _ => false,
      },
      _ => false,
    }
  })
}

# A streamed turn's last line has no trailing newline, so it sits in the line
# buffer until another step flushes it — and after the final step there is no
# other step. A provider error ("[provider error: HTTP 429: ...]") is exactly
# such a last line, so a rate-limited run printed nothing and looked hung.
fn run_turn_flushed(session :: sess.Session, task :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, approval, stream] sess.TurnResult {
  let turn := sess.run_turn_streaming_with_provider(session, task, provider_tag, print_step)
  let __flushed := flush_remaining()
  turn
}

# Prompt and completion tokens a turn used, summed over its provider calls.
fn turn_usage(steps :: List[d.Step]) -> (Int, Int)
  examples {
    turn_usage([]) => (0, 0),
    turn_usage([StepDelta(UsageDelta(10, 2, 12)), StepDelta(TextChunk("x")), StepDelta(UsageDelta(30, 5, 35))]) => (40, 7)
  }
{
  list.fold(steps, (0, 0), fn (acc :: (Int, Int), s :: d.Step) -> (Int, Int) {
    match s {
      StepDelta(delta) => match delta {
        UsageDelta(p, c, _) => match acc {
          (ap, ac) => (ap + p, ac + c),
        },
        _ => acc,
      },
      _ => acc,
    }
  })
}

fn print_step(step :: d.Step) -> [io] Nil {
  match step {
    StepDelta(delta) => match delta {
      TextChunk(text) => append_chunk(text),
      ToolCallBegin(_, name) => {
        let __flushed := flush_remaining()
        io.print(str.concat("\n[tool: ", str.concat(name, "]")))
      },
      ToolArgChunk(_, _) => (),
      FinishDelta(_) => (),
      UsageDelta(_) => (),
    },
    StepToolExec(name, _) => {
      let __flushed := flush_remaining()
      io.print(str.concat("[running: ", str.concat(name, "]")))
    },
    StepToolResult(_, ok) => {
      let __flushed := flush_remaining()
      if ok {
        io.print("[ok]")
      } else {
        io.print("[error]")
      }
    },
    StepDone(_) => {
      let __flushed := flush_remaining()
      io.print("")
    },
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
        let __reset := write_buf("")
        let result := run_turn_flushed(session, input, provider_tag)
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
      let __reset := write_buf("")
      let __printed := run_turn_flushed(session, task, provider_tag)
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
          let __reset := write_buf("")
          let __printed := run_turn_flushed(session, prompt, provider_tag)
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

type IssueOutcome = { verdict :: Str, session_id :: Str }

fn run_issue_verdict_full(issue_id :: Str, guidance :: Option[Str], mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] IssueOutcome {
  match fetch_issue(issue_id) {
    Err(e) => {
      let __err := io.print(str.join(["error: ", e, "\n"], ""))
      { verdict: "unavailable", session_id: "" }
    },
    Ok(issue) => {
      let contract := ic.contract_prompt(issue)
      let task := match guidance {
        None => contract,
        Some(g) => str.join([contract, "\nAdditional guidance from the user:\n", g, "\n"], ""),
      }
      let session_id := cli_session_id()
      match sess.new_session_persistent_with_provider(session_id, mode, provider_tag) {
        Err(e) => {
          let __err := io.print(str.concat(str.concat("error: ", e), "\n"))
          { verdict: "unavailable", session_id: session_id }
        },
        Ok(session) => {
          let __d := proc.run("mkdir", ["-p", ".lex/intent"])
          let __w := io.write(".lex/intent/issue", str.join([session_id, "\t", issue_id], ""))
          let __reset := write_buf("")
          let turn := run_turn_flushed(session, task, provider_tag)
          let verdict := if produced_output(turn.steps) {
            match proc.run("lex", ["--output", "json", "issue", "verify", issue_id]) {
              Err(_) => "unavailable",
              Ok(v) => match ic.verdict_of(v.stdout) {
                None => "unavailable",
                Some(word) => word,
              },
            }
          } else {
            "no_response"
          }
          let __usage := match turn_usage(turn.steps) {
            (p, c) => io.print(str.join(["[USAGE]\t", int.to_str(p), "\t", int.to_str(c), "\t", issue_id], "")),
          }
          let __trail := io.print(str.join(["\n(trail: .lex/sessions/", session_id, ".db)"], ""))
          { verdict: verdict, session_id: session_id }
        },
      }
    },
  }
}

fn run_issue_verdict(issue_id :: Str, guidance :: Option[Str], mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Str {
  run_issue_verdict_full(issue_id, guidance, mode, provider_tag).verdict
}

# The live counterpart to `--session-health`: check THIS issue attempt's
# own session, right after it happens, instead of only on demand after
# the fact. A ceiling cluster is the one signal precise enough to call
# "this is a lex-code bug" rather than "the model got this wrong" or
# "the task is hard" — confirmed three times in one afternoon, each one
# a real tooling bug that no amount of retrying the model could have
# fixed, discovered only by manual archaeology hours later. `None` on
# any lookup failure (no session, unreadable db): silence here just
# means "couldn't check", never "checked and it's fine".
fn tool_bug_check(session_id :: Str) -> [sql, fs_write] Option[Str] {
  if str.is_empty(session_id) {
    None
  } else {
    match health.load_calls(str.join([".lex/sessions/", session_id, ".db"], "")) {
      Err(_) => None,
      Ok(calls) => {
        let flags := health.systemic_ceiling_flags(calls)
        if list.is_empty(flags) {
          None
        } else {
          Some(str.join(flags, "; "))
        }
      },
    }
  }
}

# A stable, fixed title across every firing — not one baked from the
# per-incident counts (`reason`), which differ every time and would
# defeat the dedup check below. `known_ceilings_ms` names one ceiling
# today; if a second is ever added, this can grow into one title per
# label, but a single fixed title covers the one case that exists.
fn tool_bug_issue_title() -> Str {
  "[auto] lex-code: tool-call latency cluster suggests a timeout bug"
}

# Checked with `gh issue list`, not tracked locally: the source of
# truth for "does an open report already exist" is the repo itself, and
# a run in a fresh checkout has no local state to check against anyway.
fn tool_bug_issue_open_already(title :: Str) -> [proc] Result[Bool, Str] {
  match proc.run("gh", ["issue", "list", "--repo", "alpibrusl/lex-code", "--search", title, "--state", "open", "--json", "number"]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code != 0 {
      Err(str.trim(str.concat(out.stdout, out.stderr)))
    } else {
      match jv.parse(str.trim(out.stdout)) {
        Err(_) => Err("could not parse `gh issue list`'s own output"),
        Ok(j) => match jv.as_list(j) {
          None => Err("`gh issue list --json number` did not return an array"),
          Some(items) => Ok(not list.is_empty(items)),
        },
      }
    },
  }
}

# Filed against lex-code itself: `tool_bug_check`'s whole premise is
# that this specific pattern (a known, hardcoded timeout, clustered) is
# a bug in the TOOL, not the model or the task — every real instance
# found this session was fixed at the tool, never by retrying. Checks
# for an existing open report first so a recurring bug doesn't spam
# duplicates; silently skips filing (with a clear reason printed) on
# any step that fails, rather than risk a malformed or duplicate issue.
fn file_tool_bug_issue(project :: Str, issue_id :: Str, reason :: Str, session_path :: Str) -> [proc, io] Nil {
  let title := tool_bug_issue_title()
  match tool_bug_issue_open_already(title) {
    Err(e) => io.print(str.join(["[PROJECT] could not check for an existing tool-bug report (", e, ") — not filing, to avoid risking a duplicate"], "")),
    Ok(true) => io.print(str.join(["[PROJECT] an open tool-bug report already exists (\"", title, "\") — not filing a duplicate. See: gh issue list --repo alpibrusl/lex-code --search \"", title, "\""], "")),
    Ok(false) => {
      let body := str.join(["Automatically filed by lex-code's own live tool-bug detector (`project_loop`'s `tool_bug_check`) — not a person.\n\n", "**Project:** ", project, "\n", "**Issue that triggered this:** ", issue_id, "\n", "**Detected pattern:** ", reason, "\n", "**Session to inspect:** `lex-code --session-health=", session_path, "`\n\n", "Fires only when at least 3 tool calls AND at least 20% of one issue attempt's own calls land within 10% of a hardcoded timeout ceiling (`known_ceilings_ms` in `src/tools/session_health.lex`) — deliberately stricter than the advisory `--session-health` check, precisely so a single legitimately slow call never triggers this. Every real instance of this pattern found so far was a genuine tool bug (not the model, not the task) fixed in the tool itself, never by retrying.\n"], "")
      match proc.run("gh", ["issue", "create", "--repo", "alpibrusl/lex-code", "--title", title, "--body", body]) {
        Err(e) => io.print(str.concat("[PROJECT] failed to file the tool-bug report: ", e)),
        Ok(out) => if out.exit_code == 0 {
          io.print(str.concat("[PROJECT] filed: ", str.trim(out.stdout)))
        } else {
          io.print(str.concat("[PROJECT] `gh issue create` failed: ", str.trim(str.concat(out.stdout, out.stderr))))
        },
      }
    },
  }
}

fn run_issue(issue_id :: Str, guidance :: Option[Str], mode :: sess.AgentMode, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let verdict := run_issue_verdict(issue_id, guidance, mode, provider_tag)
  io.print(str.join(["[ISSUE_VERDICT]\t", verdict, "\t", issue_id, "\n"], ""))
}

# ---- Whole packages: plan a graph of typed issues, file it, drive it -------------
#
#   lex-code --package "<brief>" --name=P   an agent draws the issue graph into
#                                           .lex/plans/P.json; nothing is filed
#   lex-code --package-apply=P              file that reviewed plan as issues
#   lex-code --project=P                    drive the project to done
#
# A package is a project of typed issues with dependency edges. The plan is
# reviewed by a human before anything is filed, and filing is deterministic —
# an LLM does not get to decide unreviewed what "done" means.
fn plan_path(name :: Str) -> Str {
  str.join([".lex/plans/", name, ".json"], "")
}

# One free-standing agent turn (a Build session, no issue bound to it).
fn run_task_turn(task :: Str, provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  run_mode_turn(task, provider_tag, Build)
}

fn run_mode_turn(task :: Str, provider_tag :: Str, mode :: sess.AgentMode) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let session_id := cli_session_id()
  match sess.new_session_persistent_with_provider(session_id, mode, provider_tag) {
    Err(e) => io.print(str.concat(str.concat("error: ", e), "\n")),
    Ok(session) => {
      let __reset := write_buf("")
      let __printed := run_turn_flushed(session, task, provider_tag)
      io.print(str.join(["\n(trail: .lex/sessions/", session_id, ".db)"], ""))
    },
  }
}

# Ask the planner for a plan, check it, and while the check rejects it send the
# problems back — up to `tries` rounds. Ok = a plan that passed every check.
fn errs_repeated(errs :: List[Str], prev :: Option[List[Str]]) -> Bool
  examples {
    errs_repeated(["a"], None) => false,
    errs_repeated(["a", "b"], Some(["a", "b"])) => true,
    errs_repeated(["a", "b"], Some(["b", "a"])) => false,
    errs_repeated(["a"], Some(["a", "b"])) => false
  }
{
  match prev {
    None => false,
    Some(p) => p == errs,
  }
}

# `prev_errs` is the previous attempt's own rejection, if any — carried
# so a repeat can be told apart from a first offense. Reproduced live: a
# repair-loop attempt can reject on the exact same problems as the one
# before it, turn after turn — the planner isn't acting on the repair
# prompt's own errors, and nothing said so until every try was spent.
# The check is exact list equality on purpose: `full_check`'s errors are
# deterministic given the same plan text, so a genuine fix changes the
# list, not just its wording.
fn plan_loop(name :: Str, provider_tag :: Str, tries :: Int, prompt :: Str, original :: Str, prev_errs :: Option[List[Str]]) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Result[pplan.Plan, List[Str]] {
  let path := plan_path(name)
  let __turn := run_mode_turn(prompt, provider_tag, Planner)
  let checked := match io.read(path) {
    Err(_) => Err(["no plan was written to the plan file"]),
    Ok(text) => papply.full_check(text),
  }
  match checked {
    Ok(plan) => Ok(plan),
    Err(errs) => if tries <= 1 {
      Err(errs)
    } else {
      let repeated := errs_repeated(errs, prev_errs)
      let note := if repeated {
        " — SAME problems as the last attempt (the planner isn't acting on the repair prompt)"
      } else {
        ""
      }
      let __again := io.print(str.join(["\n[PLAN] rejected by validation (", int.to_str(list.len(errs)), " problems)", note, " — sending them back to the planner, ", int.to_str(tries - 1), " tries left"], ""))
      plan_loop(name, provider_tag, tries - 1, pplan.retry_prompt(original, errs, path), original, Some(errs))
    },
  }
}

fn fresh_plan_prompt(brief :: Str, name :: Str) -> [proc] Str {
  let path := plan_path(name)
  let __d := proc.run("mkdir", ["-p", ".lex/plans"])
  let __rm := proc.run("rm", ["-f", path])
  pplan.plan_prompt(brief, name, path)
}

fn run_package_plan(brief :: Str, name :: Str, provider_tag :: Str, tries :: Int) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let path := plan_path(name)
  let first := fresh_plan_prompt(brief, name)
  match plan_loop(name, provider_tag, tries, first, first, None) {
    Err(errs) => io.print(str.join(["\nthe plan does not pass validation — fix ", path, " (or re-run) and check it with --package-check=", name, ":\n  - ", str.join(errs, "\n  - "), "\n[PLAN]\tinvalid\t", name], "")),
    Ok(plan) => io.print(str.join(["\nplan for `", name, "` — ", int.to_str(list.len(plan.units)), " units, in dependency order, all checks pass:\n", pplan.render_plan(plan), "\n\nfile it:  lex-code --package-apply=", name, "\n[PLAN]\tvalid\t", name], "")),
  }
}

# `--auto`: brief in, verified package out, nobody in between. Plan (repaired
# until it passes validation), scaffold and file it, then drive it to done.
fn run_package_auto(brief :: Str, name :: Str, argv :: List[Str], provider_tag :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let tries := pb.flag_int(argv, "--plan-tries=", 3)
  let first := fresh_plan_prompt(brief, name)
  match plan_loop(name, provider_tag, tries, first, first, None) {
    Err(errs) => io.print(str.join(["\n[AUTO] stopped at planning — no plan passed validation:\n  - ", str.join(errs, "\n  - "), "\n[PROJECT_VERDICT]\tno_plan\t", name], "")),
    Ok(plan) => match apply_checked_plan(plan) {
      Err(e) => io.print(str.join(["\n[AUTO] stopped at filing: ", e, "\n[PROJECT_VERDICT]\tno_scaffold\t", name], "")),
      Ok(report) => {
        let __r := io.print(str.join(["\n[AUTO] plan passed every check; ", report], ""))
        run_project(name, argv, provider_tag)
      },
    },
  }
}

# `--package-check=P`: everything a plan must pass before it is filed, with
# no model involved. Exit-style last line for scripts: [PLAN_CHECK] ok|invalid.
fn run_package_check(name :: Str) -> [proc, io] Nil {
  let path := plan_path(name)
  match io.read(path) {
    Err(_) => io.print(str.join(["error: no plan at ", path, "\n[PLAN_CHECK]\tmissing\t", name], "")),
    Ok(text) => match papply.full_check(text) {
      Err(errs) => io.print(str.join(["the plan does not pass:\n  - ", str.join(errs, "\n  - "), "\n[PLAN_CHECK]\tinvalid\t", name], "")),
      Ok(plan) => io.print(str.join(["plan `", name, "`: ", int.to_str(list.len(plan.units)), " units — structure, consistency rules and the type checker all pass\n[PLAN_CHECK]\tok\t", name], "")),
    },
  }
}

fn filed_report(name :: Str, note :: Str, made :: List[(Str, Str)]) -> Str {
  let rows := str.join(list.map(made, fn (p :: (Str, Str)) -> Str {
    match p {
      (k, id) => str.join(["  ", id, "  ", k], ""),
    }
  }), "\n")
  str.join([note, "\nfiled ", int.to_str(list.len(made)), " issues under project `", name, "`:\n", rows, "\n\ndrive it:  lex-code --project=", name, " --ollama   (add --fallback=opencode to hand a stuck issue to a stronger model)\n"], "")
}

# File a plan that passes every check: the tool writes the scaffold (lex.toml,
# shared types, the stubbed module) and files the issues. Ok carries the report.
fn apply_checked_plan(plan :: pplan.Plan) -> [proc, io] Result[Str, Str] {
  match papply.write_scaffold(plan) {
    Err(e) => Err(str.concat("scaffold: ", e)),
    Ok(note) => match papply.apply_plan(plan) {
      Err(e) => Err(e),
      Ok(made) => Ok(filed_report(plan.project, note, made)),
    },
  }
}

fn run_package_apply(name :: Str) -> [proc, io, fs_read] Nil {
  let path := plan_path(name)
  match io.read(path) {
    Err(_) => io.print(str.join(["error: no plan at ", path, " — create one with: lex-code --package \"<brief>\" --name=", name, "\n"], "")),
    Ok(text) => match papply.full_check(text) {
      Err(errs) => io.print(str.join(["error: the plan is not fit to file:\n  - ", str.join(errs, "\n  - "), "\n"], "")),
      Ok(plan) => match apply_checked_plan(plan) {
        Err(e) => io.print(str.join(["error: ", e, "\n"], "")),
        Ok(report) => io.print(report),
      },
    },
  }
}

fn fetch_board(project :: Str) -> [proc] Result[pb.Board, Str] {
  match proc.run("lex", ["--output", "json", "issue", "next", "--project", project]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code != 0 {
      Err(str.trim(str.concat(out.stdout, out.stderr)))
    } else {
      pb.parse_board(out.stdout)
    },
  }
}

# `lex issue verify --verified-only` has a known hang (lex-lang#1089): a
# compile_program hot loop, observed burning 100% CPU for 40+ minutes with
# zero progress on a project with only 6 verified issues, on top of every
# OTHER step in this file that already respects a budget (turns, steps,
# LLM_TIMEOUT_MS). `process.run`/`process.wait` have no timeout of their
# own — confirmed against the Rust handler, both are a fully blocking
# `Command::output()`/`child.wait()` — so the only way to bound this from
# Lex is a POSIX self-timeout: run the real command in the background,
# race it against a `sleep` watcher that SIGKILLs it, propagate whichever
# finishes first. `project` and the timeout travel as `sh -c script sh
# "$@"` positional params, never interpolated into the script text, so a
# project name can never reach the shell as anything but an inert argv
# string.
fn regression_timeout_secs() -> Int {
  180
}

# Re-verify every issue of the project. Closing one issue can quietly break
# an earlier one (an agent turn that rewrites a file whole can drop another
# issue's verified function); nothing else re-checks them. The board then
# offers any regressed issue again.
fn regression_pass(project :: Str) -> [proc, io] Nil {
  let script := "lex issue verify --project \"$1\" --verified-only & pid=$!; ( sleep \"$2\"; kill -9 \"$pid\" 2>/dev/null ) & watcher=$!; wait \"$pid\" 2>/dev/null; status=$?; kill \"$watcher\" 2>/dev/null; exit $status"
  match proc.run("sh", ["-c", script, "sh", project, int.to_str(regression_timeout_secs())]) {
    Err(e) => io.print(str.concat("regression pass unavailable: ", e)),
    Ok(out) => if out.exit_code == 137 {
      io.print(str.join(["[REGRESSION] timed out after ", int.to_str(regression_timeout_secs()), "s (lex-lang#1089) — not re-verified this pass, continuing\n", str.trim(str.concat(out.stdout, out.stderr))], ""))
    } else {
      io.print(str.join(["[REGRESSION]\n", str.trim(str.concat(out.stdout, out.stderr))], ""))
    },
  }
}

fn scaffold_file(project :: Str) -> Str {
  str.join(["src/", project, ".lex"], "")
}

# A failed in-place attempt can leave the scaffold unparsable (the model ran
# out of steps mid-edit). Put back what was there before the attempt, so the
# next attempt, a patch, or a human starts from a file that checks.
fn restore_if_broken(project :: Str, before :: Str) -> [proc, io] Nil {
  let path := scaffold_file(project)
  match proc.run("lex", ["check", path]) {
    Err(_) => (),
    Ok(o) => if o.exit_code == 0 {
      ()
    } else {
      let __w := io.write(path, before)
      io.print(str.join(["[PROJECT] the failed attempt left ", path, " not type-checking — restored it to what it was before the attempt"], ""))
    },
  }
}

# Issues on the board whose every declared function the patch defines.
fn matching_issues(ready :: List[pb.Ready], defined :: List[Str]) -> [proc] List[Str] {
  let named := list.map(ready, fn (r :: pb.Ready) -> [proc] (Str, List[Str]) {
    match par.api_names(r.id) {
      Err(_) => (r.id, []),
      Ok(ns) => (r.id, ns),
    }
  })
  list.map(list.filter(named, fn (p :: (Str, List[Str])) -> Bool {
    match p {
      (_, ns) => if list.is_empty(ns) {
        false
      } else {
        list.fold(ns, true, fn (acc :: Bool, n :: Str) -> Bool {
          if acc {
            merge.list_has(defined, n)
          } else {
            false
          }
        })
      },
    }
  }), fn (p :: (Str, List[Str])) -> Str {
    match p {
      (id, _) => id,
    }
  })
}

# `--patch=FILE`: the human, or the assistant driving lex-code, finishes a
# unit themselves. The file defines the unit's function(s) (helpers are fine).
# lex-code does not take the patch on trust: it goes through the same merge,
# type-check, publish and `lex issue verify` a model's work does, and the
# hardening and package gates still run after. Ok(verdict) or Err(why).
fn apply_patch(project :: Str, path :: Str, forced :: Option[Str]) -> [proc, io] Result[(Str, Str), Str] {
  match io.read(path) {
    Err(e) => Err(str.join(["cannot read ", path, ": ", e], "")),
    Ok(source) => {
      let defined := merge.all_fn_names(source)
      let target := match forced {
        Some(id) => Ok(id),
        None => match fetch_board(project) {
          Err(e) => Err(e),
          Ok(board) => {
            let hits := matching_issues(board.ready, defined)
            if list.len(hits) == 1 {
              match list.head(hits) {
                None => Err("no matching issue"),
                Some(id) => Ok(id),
              }
            } else {
              if list.is_empty(hits) {
                Err(str.join([path, " defines ", str.join(defined, ", "), " but no open issue declares exactly those functions — pass --patch-issue=ID"], ""))
              } else {
                Err(str.join([path, " matches several open issues (", str.join(hits, ", "), ") — pass --patch-issue=ID"], ""))
              }
            }
          },
        },
      }
      match target {
        Err(e) => Err(e),
        Ok(id) => match par.merge_source(project, id, source) {
          Err(e) => Err(e),
          Ok(verdict) => Ok((id, verdict)),
        },
      }
    },
  }
}

fn apply_patches(project :: Str, argv :: List[Str]) -> [proc, io] Bool {
  match pb.flag_value(argv, "--patch=") {
    None => true,
    Some(paths) => list.fold(str.split(paths, ","), true, fn (ok :: Bool, path :: Str) -> [proc, io] Bool {
      if not ok {
        false
      } else {
        match apply_patch(project, str.trim(path), pb.flag_value(argv, "--patch-issue=")) {
          Err(e) => {
            let __e := io.print(str.join(["[PROJECT] patch ", path, " rejected — nothing was changed:\n", e], ""))
            false
          },
          Ok(r) => match r {
            (id, verdict) => {
              let __v := io.print(str.join(["[PROJECT] patch ", path, " applied to issue ", id, " → ", verdict], ""))
              verdict == "verified"
            },
          },
        }
      }
    }),
  }
}

fn project_loop(project :: Str, primary :: Str, fallback :: Option[Str], switch_after :: Int, max_attempts :: Int, attempts :: List[(Str, Int)], fuel :: Int, guidance :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Str {
  if fuel <= 0 {
    "budget"
  } else {
    match fetch_board(project) {
      Err(e) => {
        let __err := io.print(str.concat("error: ", e))
        "error"
      },
      Ok(board) => {
        let __progress := io.print(str.join(["\n[PROJECT] ", project, "  ", int.to_str(board.verified), "/", int.to_str(board.total), " verified, ", int.to_str(list.len(board.ready)), " ready"], ""))
        match pb.decide(board, attempts, primary, fallback, switch_after, max_attempts) {
          PkgDone => "done",
          PkgStuck(why) => {
            let __why := io.print(str.concat("[PROJECT] stuck: ", why))
            "stuck"
          },
          PkgRun(id, tag) => {
            let tried := pb.attempts_of(attempts, id)
            let __start := io.print(str.join(["[PROJECT] issue ", id, " — attempt ", int.to_str(tried + 1), " on ", tag], ""))
            let before := match io.read(scaffold_file(project)) {
              Err(_) => "",
              Ok(t) => t,
            }
            let outcome := run_issue_verdict_full(id, Some(guidance), Build, tag)
            let verdict := outcome.verdict
            let __rb := if verdict != "verified" and not str.is_empty(before) {
              restore_if_broken(project, before)
            } else {
              ()
            }
            let __v := io.print(str.join(["[PROJECT] issue ", id, " → ", verdict], ""))
            match tool_bug_check(outcome.session_id) {
              Some(reason) => {
                let session_path := str.join([".lex/sessions/", outcome.session_id, ".db"], "")
                let __why := io.print(str.join(["[PROJECT] ⚠ STOPPING — this looks like a lex-code tooling bug, not a model or task problem: ", reason, ". Retrying won't fix it; check `--session-health=", session_path, "` before running again. Verified issues are kept."], ""))
                let __file := file_tool_bug_issue(project, id, reason, session_path)
                "tool_bug_suspected"
              },
              None => if verdict == "no_response" {
                let __why := io.print(str.join(["[PROJECT] the provider (", tag, ") returned nothing — stopping instead of burning attempts. Check the key, the quota and the network, then run again: verified issues are kept."], ""))
                "provider_error"
              } else {
                let __reg := if verdict == "verified" {
                  regression_pass(project)
                } else {
                  io.print("")
                }
                project_loop(project, primary, fallback, switch_after, max_attempts, pb.bump_attempts(attempts, id), fuel - 1, guidance)
              },
            }
          },
        }
      },
    }
  }
}

# `--parallel=N`: drive up to N currently-ready issues at once, as
# separate OS processes (`package_flow/parallel.lex`) — real
# concurrency, since Lex itself has none for effectful work today
# (lex-lang#1085). Every issue in a batch is spawned before any of them
# is waited on; `dispatch_and_merge` merges the whole batch back into
# the canonical scaffold sequentially, one issue at a time, before the
# next batch's board fetch — so this never reads a board that a
# still-running batch could still change out from under it. No fallback
# escalation here (a stuck issue's contract doesn't change by trying a
# different model N-at-a-time instead of one-at-a-time); `--fallback=`
# only has meaning for `project_loop`'s sequential path.
fn project_loop_parallel(project :: Str, primary :: Str, guidance :: Str, concurrency :: Int, fuel :: Int, max_attempts :: Int, attempts :: List[(Str, Int)], last_errors :: List[(Str, Str)]) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Str {
  if fuel <= 0 {
    "budget"
  } else {
    match fetch_board(project) {
      Err(e) => {
        let __err := io.print(str.concat("error: ", e))
        "error"
      },
      Ok(board) => if board.done {
        "done"
      } else {
        let open := pb.under_cap(board.ready, attempts, max_attempts)
        let batch := par.take_ready(open, concurrency)
        if list.is_empty(batch) {
          let __s := if list.is_empty(board.ready) {
            io.print(str.join(["[PROJECT] stuck: nothing ready (", int.to_str(board.verified), "/", int.to_str(board.total), " verified)"], ""))
          } else {
            io.print(str.join(["[PROJECT] stuck: gave up after ", int.to_str(max_attempts), " attempts on: ", pb.titles(board.ready), " (", int.to_str(board.verified), "/", int.to_str(board.total), " verified; verified work is kept — rerun to try again, or raise --max-attempts=)\n", str.join(list.map(last_errors, fn (e :: (Str, Str)) -> Str {
              match e {
                (eid, msg) => str.join(["  last error for ", eid, ": ", msg], ""),
              }
            }), "\n")], ""))
          }
          "stuck"
        } else {
          let ids := list.map(batch, fn (r :: pb.Ready) -> Str {
            r.id
          })
          let __start := io.print(str.join(["\n[PROJECT] ", project, "  ", int.to_str(board.verified), "/", int.to_str(board.total), " verified — dispatching ", int.to_str(list.len(ids)), " in parallel: ", str.join(ids, ", ")], ""))
          let outcomes := par.dispatch_and_merge(project, ids, guidance, str.concat("--", primary), last_errors)
          let lines := list.map(outcomes, fn (o :: par.BatchOutcome) -> Str {
            str.join(["[PROJECT] issue ", o.issue_id, " → ", o.verdict], "")
          })
          let __report := io.print(str.join(lines, "\n"))
          let __reg := regression_pass(project)
          project_loop_parallel(project, primary, guidance, concurrency, fuel - list.len(ids), max_attempts, list.fold(ids, attempts, fn (acc :: List[(Str, Int)], id :: Str) -> List[(Str, Int)] {
            pb.bump_attempts(acc, id)
          }), par.update_errors(last_errors, outcomes))
        }
      },
    }
  }
}

# The whole-package gate: verified issues are necessary, not sufficient — a
# codec whose `integer_to_hex` was a lookup table of its own examples passed
# every issue. `lex test` (property/round-trip tests in tests/) is the check
# a table cannot pass.
fn package_gate() -> [proc, io] Str {
  let has_tests := match proc.run("sh", ["-c", "ls tests/test_*.lex >/dev/null 2>&1 && echo yes || echo no"]) {
    Err(_) => "no",
    Ok(o) => str.trim(o.stdout),
  }
  if has_tests == "yes" {
    match proc.run("lex", ["test", "--allow-effects", "crypto,fs_read,fs_write,io,random,sql,time", "tests"]) {
      Err(_) => "unavailable",
      Ok(o) => if o.exit_code == 0 {
        "pass"
      } else {
        let __out := io.print(str.trim(str.concat(o.stdout, o.stderr)))
        "fail"
      },
    }
  } else {
    "none"
  }
}

# Hardening, deterministic: verified issues are necessary, not sufficient — a
# codec whose `integer_to_hex` was a lookup table of its own examples passed
# every issue, and a function whose examples all happen to avoid a run of
# separators can still double a hyphen. Nobody writes the check by hand and
# nobody is asked to: it comes straight from the plan's own invariants
# (papply.harden), each one already validated the same way a signature is.
# A violation becomes a `failing_example` issue in the same project — fixed
# is exactly what the ordinary build loop already means — never a human
# reading a report.
fn file_invariant_issue(project :: Str, call :: Str) -> [proc] Result[Str, Str] {
  match proc.run("lex", ["issue", "create", "--title", str.concat("invariant: ", call), "--shape", "failing_example", "--example", str.concat(call, " => true"), "--project", project]) {
    Err(e) => Err(e),
    Ok(o) => if o.exit_code == 0 {
      Ok(str.trim(o.stdout))
    } else {
      Err(str.trim(str.concat(o.stdout, o.stderr)))
    },
  }
}

fn file_invariant_issues(project :: Str, failing :: List[Str]) -> [proc, io] Int {
  list.len(list.filter(list.map(failing, fn (call :: Str) -> [proc, io] Bool {
    match file_invariant_issue(project, call) {
      Err(e) => {
        let __w := io.print(str.join(["  could not file `", call, "`: ", e], ""))
        false
      },
      Ok(_) => true,
    }
  }), fn (ok :: Bool) -> Bool {
    ok
  }))
}

# Check the plan's invariants; if any fail, file them and give the ordinary
# build loop `harden_fuel` more turns to fix them, then check again.
# `rounds_left` bounds that to a fixed number of round trips.
fn harden_round(project :: Str, plan :: pplan.Plan, primary :: Str, fallback :: Option[Str], switch_after :: Int, max_attempts :: Int, guidance :: Str, rounds_left :: Int, harden_fuel :: Int) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Str {
  match papply.harden(plan) {
    Err(e) => {
      let __err := io.print(str.concat("hardening unavailable: ", e))
      "unavailable"
    },
    Ok(r) => if list.is_empty(r.failing) {
      if r.calls_checked == 0 {
        "none"
      } else {
        let __ok := io.print(str.join(["[PROJECT] hardening: ", int.to_str(r.calls_checked), " invariant checks, all hold"], ""))
        "pass"
      }
    } else {
      if rounds_left <= 0 {
        let __gv := io.print(str.join(["[PROJECT] hardening: gave up after the round budget, still failing:\n  ", str.join(r.failing, "\n  ")], ""))
        "fail"
      } else {
        let __rep := io.print(str.join(["\n[PROJECT] hardening found ", int.to_str(list.len(r.failing)), " violation(s) out of ", int.to_str(r.calls_checked), " checks — filing them as issues:"], ""))
        let filed := file_invariant_issues(project, r.failing)
        let status2 := project_loop(project, primary, fallback, switch_after, max_attempts, [], harden_fuel, guidance)
        let __reg := regression_pass(project)
        if status2 == "done" {
          harden_round(project, plan, primary, fallback, switch_after, max_attempts, guidance, rounds_left - 1, harden_fuel)
        } else {
          let __st := io.print(str.join(["[PROJECT] hardening: fixing the violations did not finish (", status2, ")"], ""))
          "fail"
        }
      }
    },
  }
}

fn harden(project :: Str, primary :: Str, fallback :: Option[Str], switch_after :: Int, max_attempts :: Int, guidance :: Str, argv :: List[Str]) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Str {
  match io.read(plan_path(project)) {
    Err(_) => package_gate(),
    Ok(text) => match pplan.parse_plan(text) {
      Err(_) => package_gate(),
      Ok(plan) => harden_round(project, plan, primary, fallback, switch_after, max_attempts, guidance, pb.flag_int(argv, "--harden-rounds=", 3), pb.flag_int(argv, "--harden-turns=", 10)),
    },
  }
}

# Reproduced live (2026-09-30): a `--parallel` run reported "6/6
# verified" and `[PROJECT_VERDICT] done` for a package where four of
# six functions — including one whose own merge attempt had *just*
# failed with `Panic("todo() reached")` — were still bare `todo()`
# stubs in the published file. Per-issue "verified" comes from the VCS
# store (`lex issue verify`), a separate process this loop doesn't
# control; trusting it alone means a store-level problem (a shared,
# unscoped global store across concurrent unrelated projects, in the
# case that was caught) can make a broken package look finished. This
# reads the one thing that can't be wrong for someone else's reasons:
# the actual text of the file about to be called done.
fn run_project(project :: Str, argv :: List[Str], primary :: Str) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random] Nil {
  let fallback := pb.flag_value(argv, "--fallback=")
  let switch_after := pb.flag_int(argv, "--switch-after=", 2)
  let max_attempts := pb.flag_int(argv, "--max-attempts=", 4)
  let fuel := pb.flag_int(argv, "--max-turns=", 40)
  let scaffolded := match proc.run("sh", ["-c", str.join(["test -f .lex/plans/", project, ".scaffold && echo yes || echo no"], "")]) {
    Err(_) => false,
    Ok(o) => str.trim(o.stdout) == "yes",
  }
  let base_guidance := if scaffolded {
    pb.scaffold_guidance(project)
  } else {
    pb.module_guidance(project)
  }
  let hint := match pb.flag_value(argv, "--hint=") {
    Some(h) => h,
    None => match pb.flag_value(argv, "--hint-file=") {
      None => "",
      Some(path) => match io.read(path) {
        Err(_) => "",
        Ok(t) => str.trim(t),
      },
    },
  }
  let guidance := if str.is_empty(hint) {
    base_guidance
  } else {
    str.join([base_guidance, "\n\nHint from the human running this build — take it seriously, it comes from reading your earlier failed attempts:\n", hint], "")
  }
  let concurrency := pb.flag_int(argv, "--parallel=", 1)
  let patches_ok := apply_patches(project, argv)
  let status := if not patches_ok {
    "stuck"
  } else {
    if concurrency > 1 {
      project_loop_parallel(project, primary, guidance, concurrency, fuel, max_attempts, [], [])
    } else {
      project_loop(project, primary, fallback, switch_after, max_attempts, [], fuel, guidance)
    }
  }
  let __final := regression_pass(project)
  let scaffold_path := str.join(["src/", project, ".lex"], "")
  let stubs := match io.read(scaffold_path) {
    Err(_) => [],
    Ok(source) => merge.stub_fn_names(source),
  }
  let gate := if not list.is_empty(stubs) {
    let __w := io.print(str.join(["[PROJECT] ⚠ still stubbed (todo()) despite the board reporting done: ", str.join(stubs, ", "), " — not safe to call this package finished. If nothing else is running against the same store, run `lex pkg init` here (or pass --store) to give this project its own, then try again."], ""))
    "fail"
  } else {
    if status == "done" {
      if has_flag(argv, "--no-harden") {
        package_gate()
      } else {
        harden(project, primary, fallback, switch_after, max_attempts, guidance, argv)
      }
    } else {
      "skipped"
    }
  }
  io.print(str.join(["[PROJECT_VERDICT]\t", status, "\t", project, "\n[PACKAGE_GATE]\t", gate, "\t", project, "\n"], ""))
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
                if has_flag(argv, "--lex-gpu") {
                  "lex-gpu"
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
  let argv := io.argv()
  let inv := plan_invocation(argv)
  let provider_tag := inv.provider
  let mode := inv.mode
  match pb.flag_value(argv, "--package-check=") {
    Some(name) => run_package_check(name),
    None => match pb.flag_value(argv, "--package-apply=") {
      Some(name) => run_package_apply(name),
      None => match pb.flag_value(argv, "--session-health=") {
        Some(path) => health.run_session_health(path),
        None => run_main_rest(argv, inv, provider_tag, mode),
      },
    },
  }
}

fn run_main_rest(argv :: List[Str], inv :: Invocation, provider_tag :: Str, mode :: sess.AgentMode) -> [env, io, net, llm, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream, crypto, random, concurrent] Nil {
  match pb.flag_value(argv, "--project=") {
    Some(project) => run_project(project, argv, provider_tag),
    None => if has_flag(argv, "--package") {
      match inv.task {
        None => io.print("usage: lex-code --package \"<what the package should do>\" --name=<project>"),
        Some(brief) => match pb.flag_value(argv, "--name=") {
          None => io.print("usage: lex-code --package \"<what the package should do>\" --name=<project>"),
          Some(name) => if has_flag(argv, "--auto") {
            run_package_auto(brief, name, argv, provider_tag)
          } else {
            run_package_plan(brief, name, provider_tag, pb.flag_int(argv, "--plan-tries=", 3))
          },
        },
      }
    } else {
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
    },
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
      io.print(str.concat("providers: --mistral | --openai | --google | --vertex | --litellm | --ollama | --vllm | --lex-gpu | --opencode  (default: anthropic)", "\n"))
      io.print(str.concat("one-shot:  lex run src/tui/main.lex -- [flags] \"your task\"", "\n"))
      io.print(str.concat("issue:     --issue=<id> [\"extra guidance\"]   implement a typed issue from its acceptance, then verify it", "\n"))
      io.print(str.concat("refine:    --refine=<id>                      propose a typed acceptance for a free_form issue (you approve it)", "\n"))
      io.print(str.concat("package:   --package \"<brief>\" --name=P   draw a graph of typed issues into .lex/plans/P.json (nothing filed)", "\n"))
      io.print(str.concat("           --package \"<brief>\" --name=P --auto   plan, check, scaffold, file and drive — no human step", "\n"))
      io.print(str.concat("           --package-check=P                  validate a plan: structure, consistency, real type check", "\n"))
      io.print(str.concat("  hardening: --no-harden | --harden-rounds=N | --harden-turns=N   invariants are checked and violations fixed automatically by default", "\n"))
      io.print(str.concat("           --package-apply=P                  file that reviewed plan as issues", "\n"))
      io.print(str.concat("           --project=P [--fallback=TAG]       drive the project to done, escalating a stuck issue to TAG", "\n"))
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

