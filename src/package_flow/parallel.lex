# lex-code — drive more than one ready issue at once, as separate OS
# processes (see docs/design/project-to-issue-graph.md #7: "issues with
# no edge between them are independently implementable in parallel").
#
# Lex has no primitive for concurrent *effectful* work today: `std.conc`
# actors run their handler synchronously on the caller's own thread
# (mutex-guarded, not dispatched — filed as lex-lang#1085), and
# `list.par_map`'s worker threads are `DenyAllEffects`, so neither can
# run an `io`/`proc`/`net`/`llm` Build session in parallel. This module
# gets real OS-level parallelism the other way: `proc.spawn` a separate
# `bin/lex-code --issue=<id>` child per ready issue, genuinely
# concurrent because they're different processes, not different
# closures in the same VM.
#
# Each child works in its OWN temp copy of the whole project — copy,
# not a shared checkout — so two concurrent children never read or
# write the same file at the same moment; there is nothing to lock.
# Once a batch's children have all exited, the driver (single-threaded,
# in-process, one issue at a time) splices each issue's own function
# body out of its copy and into the ONE canonical `src/<project>.lex`
# via `merge.lex`, then re-verifies for real against the canonical
# store. The concurrency buys the slow part (the LLM turns); the fast
# part (merge + verify) stays exactly as sequential as it already was.
#
# A child's own stdout/stderr are redirected straight to a log FILE by
# the shell wrapper, not left on `spawn`'s own pipe: nothing is ever
# written to that pipe, so there is no risk of a long Build session
# filling an unread pipe buffer and deadlocking against a `wait` this
# module never drains concurrently with. The trade-off is that a
# child's output isn't visible until it exits — acceptable for a batch
# whose whole point is running unattended.

import "std.str" as str

import "std.list" as list

import "std.process" as proc

import "std.io" as io

import "std.map" as map

import "std.env" as env

import "lex-schema/json_value" as jv

import "./merge" as merge

import "../issue_contract" as ic

import "./board" as pb

# A private, unique directory to run one issue's Build session in
# complete isolation from the canonical project and from every other
# issue's own copy.
#
# Reproduced live: this used to be keyed by `issue_id` alone — one flat
# `/tmp/lex-code-parallel-<id>` namespace shared by every project on the
# machine, no matter how many were running at once. A Build session's own
# bash/grep/glob tools have no reason to look outside their own copy_dir,
# but nothing stopped them: two unrelated projects (`billsplit`,
# `checkout`) run concurrently each had their model narrate specifics
# about the OTHER project's files by name, because a plain `ls /tmp`
# turned up the sibling's entire isolated copy sitting right next to its
# own. Never corrupted an actual merge (that still only ever reads the
# canonical file plus the copy `merge_issue` was explicitly handed), but
# wasted turns and, once, sent a session down a real rabbit hole
# ("the store is shared with parallel sessions" — it was right).
# Prefixing every path with the project name doesn't require any new
# state (every caller already has `project` in scope) and turns a
# same-machine cross-project collision into a same-project collision —
# the one case an issue's own content-addressed id already prevents.
fn copy_dir_for(project :: Str, issue_id :: Str) -> Str {
  str.join(["/tmp/lex-code-parallel-", project, "-", issue_id], "")
}

fn log_path_for(project :: Str, issue_id :: Str) -> Str {
  str.join(["/tmp/lex-code-parallel-", project, "-", issue_id, ".log"], "")
}

# `cp -R . dest` (not `cp -R * dest`, which shell-globs and drops
# dotfiles): copies the CURRENT directory's own contents, `.lex/`
# included, into `dest`. Wipes any stale copy from an earlier attempt
# at the same issue first.
fn make_isolated_copy(copy_dir :: Str) -> [proc] Result[Unit, Str] {
  let __rm := proc.run("rm", ["-rf", copy_dir])
  let __mk := proc.run("mkdir", ["-p", copy_dir])
  match proc.run("bash", ["-c", "cp -R . \"$1\"", "bash", copy_dir]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code == 0 {
      Ok(())
    } else {
      Err(str.join(["copying into ", copy_dir, " failed: ", str.trim(str.concat(out.stdout, out.stderr))], ""))
    },
  }
}

# Spawn `bin/lex-code <provider_flag> --issue=<issue_id> [guidance]` with
# its cwd set to `copy_dir` — the REAL `bin/lex-code`, at its own fixed
# location (`LEX_CODE_BIN`, exported by that same script so a child
# never needs to guess where it lives), not a copy of it: the isolated
# copy is of the PROJECT being built, which never contains this tool's
# own `bin/`. Its `$0`-relative resolution of `src/tui/main.lex` still
# comes from the real installation; only the working directory — where
# `.lex/plans/`, `src/`, `lex.toml` resolve — is the copy. `proc.spawn`
# inherits the caller's whole environment by default (`std::process`
# only ever adds to it, never clears it), so `LEX_CODE_BIN` and the
# provider's own credentials (`OPENCODE_API_KEY`, …) reach the child
# without being named here. Output goes straight to a log file (see
# module header); `proc.spawn` returns immediately, so the caller can
# start several of these before waiting on any of them.
fn spawn_issue_child(project :: Str, copy_dir :: Str, issue_id :: Str, guidance :: Option[Str], provider_flag :: Str) -> [proc, env] Result[ProcessHandle, Str] {
  match env.get("LEX_CODE_BIN") {
    None => Err("LEX_CODE_BIN is not set — run this through bin/lex-code, not `lex run` directly"),
    Some(bin) => {
      let log := log_path_for(project, issue_id)
      let g := match guidance {
        None => "",
        Some(text) => text,
      }
      let script := "cd \"$1\" && if [ -n \"$6\" ]; then exec \"$2\" \"$3\" \"--issue=$4\" \"$6\" > \"$5\" 2>&1; else exec \"$2\" \"$3\" \"--issue=$4\" > \"$5\" 2>&1; fi"
      proc.spawn("bash", ["-c", script, "bash", copy_dir, bin, provider_flag, issue_id, log, g], { cwd: None, env: map.new(), stdin: None })
    },
  }
}

type ChildResult = { issue_id :: Str, copy_dir :: Str, log :: Str, exit_code :: Int }

# Block until this one child exits (its own OS process — not the LLM
# turns of any other concurrently-running child, which keep going on
# their own). Real concurrency comes from calling this once per
# already-`spawn`ed handle, all spawned before any of them is waited on.
fn wait_issue_child(project :: Str, issue_id :: Str, copy_dir :: Str, handle :: ProcessHandle) -> [proc] ChildResult {
  let st := proc.wait(handle)
  { issue_id: issue_id, copy_dir: copy_dir, log: log_path_for(project, issue_id), exit_code: st.code }
}

# `[ISSUE_VERDICT]\t<verdict>\t<id>` is `run_issue`'s own last line
# (`tui/main.lex`) — the same parseable marker the sequential driver
# already depends on, read back out of the child's log file instead of
# its (never-drained) own stdout pipe.
fn verdict_from_log(text :: Str) -> Str {
  let lines := list.filter(str.split(text, "\n"), fn (l :: Str) -> Bool {
    str.starts_with(l, "[ISSUE_VERDICT]\t")
  })
  match list.head(list.reverse(lines)) {
    None => "unavailable",
    Some(line) => match list.head(list.tail(str.split(line, "\t"))) {
      None => "unavailable",
      Some(v) => v,
    },
  }
}

# The function names this issue's `typed_delta` acceptance declares —
# the only ones a merge for this issue is allowed to touch. Fetched
# fresh (not carried from plan-time), so this works no matter how long
# after `--package-apply` the project is later driven with `--parallel`.
fn api_names(issue_id :: Str) -> [proc] Result[List[Str], Str] {
  match proc.run("lex", ["--output", "json", "issue", "show", issue_id]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code != 0 {
      Err(str.join(["cannot read issue ", issue_id, ": ", str.trim(str.concat(out.stdout, out.stderr))], ""))
    } else {
      match jv.parse(str.trim(out.stdout)) {
        Err(_) => Err(str.concat("unreadable issue ", issue_id)),
        Ok(issue) => Ok(list.map(ic.field_list(ic.acceptance_of(issue), "api"), fn (e :: jv.Json) -> Str {
          ic.field_text(e, "name")
        })),
      }
    },
  }
}

# Splice every function this issue declares out of its own isolated
# copy's scaffold and into the canonical one, then re-verify for real
# against the canonical store (the child's own verify ran only against
# its throwaway copy's store, which the canonical project never sees).
# `Err` leaves the canonical scaffold untouched — never a partial merge.
fn merge_issue(project :: Str, r :: ChildResult) -> [proc, io] Result[Str, Str] {
  let scaffold_path := str.join(["src/", project, ".lex"], "")
  let copy_scaffold := str.join([r.copy_dir, "/", scaffold_path], "")
  match api_names(r.issue_id) {
    Err(e) => Err(e),
    Ok(names) => if list.is_empty(names) {
      Err(str.concat("issue ", str.concat(r.issue_id, " declares no api entries — nothing to merge")))
    } else {
      match io.read(copy_scaffold) {
        Err(e) => Err(str.join(["reading ", copy_scaffold, ": ", e], "")),
        Ok(child_source) => match io.read(scaffold_path) {
          Err(e) => Err(str.join(["reading ", scaffold_path, ": ", e], "")),
          Ok(canonical_source) => match list.fold(names, Ok(canonical_source), fn (acc :: Result[Str, Str], name :: Str) -> Result[Str, Str] {
            match acc {
              Err(e) => Err(e),
              Ok(src) => merge.replace_fn_block(src, name, child_source),
            }
          }) {
            Err(e) => Err(str.join(["merging issue ", r.issue_id, ": ", e], "")),
            Ok(merged_declared) => {
              let merged := merge.append_extra_imports(merge.append_extra_fns(merged_declared, child_source, names), child_source)
              let check_path := str.join([".lex/plans/", project, ".merge-check.lex"], "")
              let __d := proc.run("mkdir", ["-p", ".lex/plans"])
              let __w := io.write(check_path, merged)
              match proc.run("lex", ["check", check_path]) {
                Err(e) => Err(e),
                Ok(out) => if out.exit_code != 0 {
                  Err(str.join(["merged ", scaffold_path, " for issue ", r.issue_id, " doesn't type-check — canonical scaffold left untouched:\n", str.trim(str.concat(out.stdout, out.stderr)), locate_error(merged, str.concat(out.stdout, out.stderr))], ""))
                } else {
                  let __w2 := io.write(scaffold_path, merged)
                  match proc.run("lex", ["publish", scaffold_path, "--activate"]) {
                    Err(e) => Err(e),
                    Ok(pub) => if pub.exit_code != 0 {
                      Err(str.join(["publishing ", scaffold_path, " for issue ", r.issue_id, " failed: ", str.trim(str.concat(pub.stdout, pub.stderr))], ""))
                    } else {
                      match proc.run("lex", ["--output", "json", "issue", "verify", r.issue_id]) {
                        Err(e) => Err(e),
                        Ok(v) => Ok(match ic.verdict_of(v.stdout) {
                          None => "unavailable",
                          Some(word) => word,
                        }),
                      }
                    },
                  }
                },
              }
            },
          },
        },
      }
    },
  }
}

fn cleanup(copy_dir :: Str) -> [proc] Unit {
  let __rm := proc.run("rm", ["-rf", copy_dir])
  ()
}

fn take_ready(xs :: List[pb.Ready], n :: Int) -> List[pb.Ready] {
  if n <= 0 {
    []
  } else {
    match list.head(xs) {
      None => [],
      Some(h) => list.cons(h, take_ready(list.tail(xs), n - 1)),
    }
  }
}

type BatchOutcome = { issue_id :: Str, verdict :: Str }

# Reproduced live (2026-09-30): the SAME issue, redispatched after a
# `merge_error`, gets the exact same task text every time —
# `contract_prompt` is built purely from the issue's own static fields
# (id, title, body, acceptance); nothing about a previous attempt's
# failure, for this issue or any other, is ever recorded or read back.
# Two separate --parallel runs each spent 7+ retries stuck on their own
# rounding function, in both cases repeating variations on the same
# wrong guess with no way to have done otherwise: a fresh session every
# time, with nothing to learn from because nothing told it what it got
# wrong last time. Not a memory or session bug (each retry's session_id
# is genuinely fresh, cli_session_id(), no persisted history) — the
# opposite one: there is no feedback channel for this at all.
#
# `last_errors` closes it: one (issue_id, last verdict) pair per issue
# still outstanding, carried across `project_loop_parallel`'s recursion
# and folded into that one issue's own task text on its next dispatch —
# every OTHER issue in the same batch is unaffected. A verdict clears
# its own entry (from `update_errors`) once it's no longer a failure, so
# this never accretes stale history past the attempt that produced it.
fn error_for(last_errors :: List[(Str, Str)], id :: Str) -> Option[Str] {
  list.fold(last_errors, None, fn (acc :: Option[Str], e :: (Str, Str)) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => match e {
        (eid, msg) => if eid == id {
          Some(msg)
        } else {
          None
        },
      },
    }
  })
}

fn guidance_for(base_guidance :: Str, last_errors :: List[(Str, Str)], id :: Str) -> Str {
  match error_for(last_errors, id) {
    None => base_guidance,
    Some(err) => str.join([base_guidance, "\n\nYour own previous attempt at this exact issue failed with this error. Read it carefully and fix the SPECIFIC problem it names — do not just retry the same body again:\n", err], ""),
  }
}

# Drop an id's entry once its own verdict is no longer a merge/spawn
# failure (it may still be `failed`/`inconclusive` from `issue_verify`,
# which is a different, already-surfaced signal — not a reason to keep
# repeating a merge error that no longer applies); otherwise replace it
# with the new one, never accumulate more than one per id.
fn update_errors(last_errors :: List[(Str, Str)], outcomes :: List[BatchOutcome]) -> List[(Str, Str)] {
  list.fold(outcomes, last_errors, fn (acc :: List[(Str, Str)], o :: BatchOutcome) -> List[(Str, Str)] {
    let cleared := list.filter(acc, fn (e :: (Str, Str)) -> Bool {
      match e {
        (eid, _) => eid != o.issue_id,
      }
    })
    if str.starts_with(o.verdict, "merge_error: ") or str.starts_with(o.verdict, "spawn_error: ") {
      list.cons((o.issue_id, o.verdict), cleared)
    } else {
      cleared
    }
  })
}

# A merge_error points at a line of `.lex/plans/<project>.merge-check.lex`,
# a file that only exists in the canonical project: the model retrying in
# its own isolated copy cannot open it, so "line 265" meant nothing to it
# and the same mistake came back attempt after attempt. Quote the line
# itself (for a whole-function error that is the `fn` header).
fn check_error_line(out :: Str) -> Int {
  list.fold(str.split(out, "\n"), 0, fn (acc :: Int, l :: Str) -> Int {
    if acc > 0 or not str.starts_with(str.trim(l), "{") {
      acc
    } else {
      match jv.parse(str.trim(l)) {
        Err(_) => acc,
        Ok(j) => match jv.get_field(j, "position") {
          None => acc,
          Some(pos) => match jv.get_field(pos, "line") {
            None => acc,
            Some(n) => match jv.as_int(n) {
              None => acc,
              Some(i) => i,
            },
          },
        },
      }
    }
  })
}

fn line_at(text :: Str, n :: Int) -> Str
  examples {
    line_at("a\nb\nc", 2) => "b",
    line_at("a\nb\nc", 9) => ""
  }
{
  list.fold(list.enumerate(str.split(text, "\n")), "", fn (acc :: Str, p :: (Int, Str)) -> Str {
    match p {
      (i, l) => if i + 1 == n {
        l
      } else {
        acc
      },
    }
  })
}

fn locate_error(merged :: Str, out :: Str) -> Str {
  let n := check_error_line(out)
  let src := str.trim(line_at(merged, n))
  if n <= 0 or str.is_empty(src) {
    ""
  } else {
    str.join(["\nThat position is in the merged file, which you do not have; the offending code is at or inside: `", src, "` — find it in your own file and fix it there."], "")
  }
}

# The whole point: copy + spawn every id in the batch first — nothing in
# this phase blocks — THEN wait for each (blocking only on that one
# child; the others keep running), THEN merge one at a time, in-process,
# no lock needed since nothing else is writing the canonical scaffold
# while this runs. Real overlap comes entirely from spawning before any
# waiting starts; get that ordering wrong and this degrades silently
# back to sequential.
fn dispatch_and_merge(project :: Str, ids :: List[Str], guidance :: Str, provider_flag :: Str, last_errors :: List[(Str, Str)]) -> [proc, env, io] List[BatchOutcome] {
  let spawned := list.map(ids, fn (id :: Str) -> [proc, env] (Str, Str, Result[ProcessHandle, Str]) {
    let copy := copy_dir_for(project, id)
    let __mk := make_isolated_copy(copy)
    let g := guidance_for(guidance, last_errors, id)
    (id, copy, spawn_issue_child(project, copy, id, Some(g), provider_flag))
  })
  let waited := list.map(spawned, fn (t :: (Str, Str, Result[ProcessHandle, Str])) -> [proc] (Str, Result[ChildResult, Str]) {
    match t {
      (id, copy, Err(e)) => (id, Err(str.join(["spawning issue ", id, " failed: ", e], ""))),
      (id, copy, Ok(h)) => (id, Ok(wait_issue_child(project, id, copy, h))),
    }
  })
  list.map(waited, fn (w :: (Str, Result[ChildResult, Str])) -> [proc, io] BatchOutcome {
    match w {
      (id, Err(e)) => { issue_id: id, verdict: str.concat("spawn_error: ", e) },
      (id, Ok(r)) => {
        let verdict := match merge_issue(project, r) {
          Ok(v) => v,
          Err(e) => str.concat("merge_error: ", e),
        }
        let __cl := cleanup(r.copy_dir)
        { issue_id: id, verdict: verdict }
      },
    }
  })
}

