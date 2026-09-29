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
fn copy_dir_for(issue_id :: Str) -> Str {
  str.join(["/tmp/lex-code-parallel-", issue_id], "")
}

fn log_path_for(issue_id :: Str) -> Str {
  str.join(["/tmp/lex-code-parallel-", issue_id, ".log"], "")
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
fn spawn_issue_child(copy_dir :: Str, issue_id :: Str, guidance :: Option[Str], provider_flag :: Str) -> [proc, env] Result[ProcessHandle, Str] {
  match env.get("LEX_CODE_BIN") {
    None => Err("LEX_CODE_BIN is not set — run this through bin/lex-code, not `lex run` directly"),
    Some(bin) => {
      let log := log_path_for(issue_id)
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
fn wait_issue_child(issue_id :: Str, copy_dir :: Str, handle :: ProcessHandle) -> [proc] ChildResult {
  let st := proc.wait(handle)
  { issue_id: issue_id, copy_dir: copy_dir, log: log_path_for(issue_id), exit_code: st.code }
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
            Ok(merged) => {
              let check_path := str.join([".lex/plans/", project, ".merge-check.lex"], "")
              let __d := proc.run("mkdir", ["-p", ".lex/plans"])
              let __w := io.write(check_path, merged)
              match proc.run("lex", ["check", check_path]) {
                Err(e) => Err(e),
                Ok(out) => if out.exit_code != 0 {
                  Err(str.join(["merged ", scaffold_path, " for issue ", r.issue_id, " doesn't type-check — canonical scaffold left untouched:\n", str.trim(str.concat(out.stdout, out.stderr))], ""))
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

# The whole point: copy + spawn every id in the batch first — nothing in
# this phase blocks — THEN wait for each (blocking only on that one
# child; the others keep running), THEN merge one at a time, in-process,
# no lock needed since nothing else is writing the canonical scaffold
# while this runs. Real overlap comes entirely from spawning before any
# waiting starts; get that ordering wrong and this degrades silently
# back to sequential.
fn dispatch_and_merge(project :: Str, ids :: List[Str], guidance :: Str, provider_flag :: Str) -> [proc, env, io] List[BatchOutcome] {
  let spawned := list.map(ids, fn (id :: Str) -> [proc, env] (Str, Str, Result[ProcessHandle, Str]) {
    let copy := copy_dir_for(id)
    let __mk := make_isolated_copy(copy)
    (id, copy, spawn_issue_child(copy, id, Some(guidance), provider_flag))
  })
  let waited := list.map(spawned, fn (t :: (Str, Str, Result[ProcessHandle, Str])) -> [proc] (Str, Result[ChildResult, Str]) {
    match t {
      (id, copy, Err(e)) => (id, Err(str.join(["spawning issue ", id, " failed: ", e], ""))),
      (id, copy, Ok(h)) => (id, Ok(wait_issue_child(id, copy, h))),
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

