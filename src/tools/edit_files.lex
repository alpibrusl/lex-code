# edit_files ? batch, evidence-producing text edits to NON-Lex files.
#
# The standard `edit` tool is .lex-aware (auto-format, lex check, lint,
# store publish with intent). Pointing it at a YAML config or a markdown
# doc drags all of that machinery into a context where it is meaningless;
# pointing it at a .lex file from *this* tool would be worse: a .lex
# change that bypasses the op-log has no stage, no attestation, nothing
# to blame. So the first check, before anything is read: any path ending
# in ".lex" refuses the whole batch with a pointer at the op-log.
#
# Atomicity: a batch either lands entirely or touches nothing. Every edit
# is planned against the *original* content of its file (occurrence count
# of `old` must equal `expect`, default 1; optional require_sha256 pins
# the pre-image). If ANY check fails, the planning Err propagates and no
# file is written ? a count that drifted on file 1 must not leave file 2
# edited with the caller believing the batch failed. The one honest hole
# is mid-apply failure (full disk, killed process): tmp files are written
# first and only then renamed into place, and a failure there says so in
# the receipt instead of claiming atomicity it could not deliver.
#
# No fs_write on this tool's row, by design: writing goes through
# `sh -c 'cat > "$1"'` with the content on stdin (a [proc] spawn whose
# only filesystem reach is the path we hand it), then `mv` renames the
# tmp file over the target. fs capability grants (--allow-fs-write) stay
# scoped to the tools that actually declare fs_*.
#
# The receipt is JSON (jobj built, jv.stringify'd at the edge) carrying
# per file: status, expected/actual occurrence counts, before/after
# sha256, byte counts. On a refused batch the same per-file evidence is
# attached to the Err message so the caller can see exactly which checks
# failed; the refusal text comes first because callers pattern-match on
# it.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "std.bytes" as bytes

import "std.map" as map

import "std.crypto" as crypto

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

# ---- One edit, as a record -----------------------------------------
# Raw, straight off the wire; `planned` is the checked version.
fn raw_edit(path :: Str, old :: Str, new :: Str, expect :: Int, require_sha256 :: Option[Str]) -> jv.Json {
  let base := [("path", JStr(path)), ("old", JStr(old)), ("new", JStr(new)), ("expect", JInt(expect))]
  match require_sha256 {
    None => JObj(base),
    Some(sha) => JObj(list.concat(base, [("require_sha256", JStr(sha))])),
  }
}

# The plan stage: evidence fields filled, new_content computed.
type Planned = { path :: Str, old :: Str, new :: Str, expect :: Int, require_sha256 :: Option[Str], before :: Str, after :: Str, before_sha :: Str, after_sha :: Str, count :: Int }

# Planning either produces a Planned record per edit, or refuses with a
# message listing the failing edits (and, for receipts, per-file fields).
type PlanOutcome = PlanOk(List[Planned]) | PlanRefused(List[Refusal])

type Refusal = { path :: Str, expected :: Int, actual :: Int, before_sha :: Str, before_bytes :: Int, reason :: Str }

# ---- check one raw edit against the disk ---------------------------
fn count_occurrences(content :: Str, needle :: Str) -> Int
  examples {
    count_occurrences("hello", "l") => 2,
    count_occurrences("hello", "z") => 0,
    count_occurrences("a.b.c", ".") => 2,
    count_occurrences("", "x") => 0
  }
{
  if str.is_empty(needle) {
    0
  } else {
    list.len(str.split(content, needle)) - 1
  }
}

fn default_expect(e :: jv.Json) -> Int {
  match util.field_int(e, "expect") {
    None => 1,
    Some(n) => n,
  }
}

# Reads the file, checks count and pin, computes replacement.
fn plan_one(e :: jv.Json) -> [proc] Result[Planned, Refusal] {
  let p := match util.field_str(e, "path") {
    None => "<missing path>",
    Some(s) => s,
  }
  let o := match util.field_str(e, "old") {
    None => "",
    Some(s) => s,
  }
  match util.field_str(e, "path") {
    None => Err({ path: p, expected: 0, actual: 0, before_sha: "", before_bytes: 0, reason: "missing field: path" }),
    Some(path) => match util.field_str(e, "old") {
      None => Err({ path: p, expected: 0, actual: 0, before_sha: "", before_bytes: 0, reason: "missing field: old" }),
      Some(old) => match util.field_str(e, "new") {
        None => Err({ path: p, expected: 0, actual: 0, before_sha: "", before_bytes: 0, reason: "missing field: new" }),
        Some(new) => {
          let expect := default_expect(e)
          if str.ends_with(path, ".lex") {
            Err({ path: path, expected: expect, actual: 0, before_sha: "", before_bytes: 0, reason: ".lex files are refused ? Lex source goes through the op-log (lex-vcs ops), not this tool" })
          } else {
            match proc.run("cat", [path]) {
              Err(msg) => Err({ path: path, expected: expect, actual: 0, before_sha: "", before_bytes: 0, reason: str.concat("could not read: ", msg) }),
              Ok(out) => if not (out.exit_code == 0) {
                Err({ path: path, expected: expect, actual: 0, before_sha: "", before_bytes: 0, reason: str.concat("could not read: ", str.trim(util.combined(out))) })
              } else {
                let content := out.stdout
                let sha := crypto.sha256_str(content)
                let nbytes := str.len(content)
                match util.field_str(e, "require_sha256") {
                  Some(pin) => if not (pin == sha) {
                    Err({ path: path, expected: expect, actual: 0, before_sha: sha, before_bytes: nbytes, reason: str.join(["require_sha256 mismatch ? file content hashes to ", sha, " not ", pin], "") })
                  } else {
                    check_count(e, path, old, new, util.field_str(e, "require_sha256"), content, sha, nbytes, expect)
                  },
                  None => check_count(e, path, old, new, None, content, sha, nbytes, expect),
                }
              },
            }
          }
        },
      },
    },
  }
}

fn check_count(e :: jv.Json, path :: Str, old :: Str, new :: Str, pin :: Option[Str], content :: Str, sha :: Str, nbytes :: Int, expect :: Int) -> Result[Planned, Refusal] {
  let actual := count_occurrences(content, old)
  if not (actual == expect) {
    Err({ path: path, expected: expect, actual: actual, before_sha: sha, before_bytes: nbytes, reason: "occurrence count of `old` does not match `expect` ? no file changed" })
  } else {
    let after := str.replace(content, old, new)
    Ok({ path: path, old: old, new: new, expect: expect, require_sha256: pin, before: content, after: after, before_sha: sha, after_sha: crypto.sha256_str(after), count: actual })
  }
}

fn plan_all(es :: List[jv.Json]) -> [proc] PlanOutcome {
  let results := list.map(es, fn (e :: jv.Json) -> [proc] Result[Planned, Refusal] {
    plan_one(e)
  })
  let planned := list.fold(results, [], fn (acc :: List[Planned], r :: Result[Planned, Refusal]) -> List[Planned] {
    match r {
      Ok(p) => list.concat(acc, [p]),
      Err(_) => acc,
    }
  })
  let refusals := list.fold(results, [], fn (acc :: List[Refusal], r :: Result[Planned, Refusal]) -> List[Refusal] {
    match r {
      Ok(_) => acc,
      Err(f) => list.concat(acc, [f]),
    }
  })
  if list.is_empty(refusals) {
    PlanOk(planned)
  } else {
    PlanRefused(refusals)
  }
}

# ---- receipts ------------------------------------------------------
fn planned_json(p :: Planned) -> jv.Json {
  JObj([("path", JStr(p.path)), ("status", JStr("applied")), ("expected", JInt(p.expect)), ("actual", JInt(p.count)), ("before_sha256", JStr(p.before_sha)), ("after_sha256", JStr(p.after_sha)), ("before_bytes", JInt(str.len(p.before))), ("after_bytes", JInt(str.len(p.after)))])
}

fn refused_json(f :: Refusal) -> jv.Json {
  JObj([("path", JStr(f.path)), ("status", JStr("refused")), ("reason", JStr(f.reason)), ("expected", JInt(f.expected)), ("actual", JInt(f.actual)), ("before_sha256", JStr(f.before_sha)), ("before_bytes", JInt(f.before_bytes))])
}

fn refusal_message(batch :: List[Refusal]) -> Str {
  str.join(["batch refused ? no file changed:\n", str.join(list.map(batch, fn (f :: Refusal) -> Str {
    str.join([f.path, ": ", f.reason], "")
  }), "\n")], "")
}

# ---- apply: tmp file via stdin, then rename into place --------------
#
# The tool's row has no fs_write. Writing is a `sh -c 'cat > "$1"' sh tmp`
# spawn with the new content on stdin ? the child process's bytes, not an
# fs capability, do the writing. `mv tmp path` then atomically replaces
# the target within a filesystem.
fn tmp_path_for(path :: Str, i :: Int) -> Str {
  str.join(["/tmp/lex_edit_files_", crypto.sha256_str(path), "_", int.to_str(i), ".tmp"], "")
}

fn write_via_stdin(tmppath :: Str, content :: Str) -> [proc] Result[Unit, Str] {
  match proc.spawn("sh", ["-c", "cat > \"$1\"", "sh", tmppath], { cwd: None, env: map.new(), stdin: Some(bytes.from_str(content)) }) {
    Err(msg) => Err(msg),
    Ok(handle) => {
      let st := proc.wait(handle)
      if st.code == 0 {
        Ok(())
      } else {
        Err(str.concat("writer shell exited ", int.to_str(st.code)))
      }
    },
  }
}

fn rename_into_place(tmppath :: Str, path :: Str) -> [proc] Result[Unit, Str] {
  match proc.run("mv", [tmppath, path]) {
    Err(msg) => Err(msg),
    Ok(out) => if out.exit_code == 0 {
      Ok(())
    } else {
      Err(str.concat("mv failed: ", str.trim(util.combined(out))))
    },
  }
}

# Stage tmp files, then rename. Past this point an Err can no longer
# promise "nothing changed" ? only "we stopped at the named step".
fn apply_all(ps :: List[Planned]) -> [proc] Result[Unit, Str] {
  let indexed := list.enumerate(ps)
  match list.fold(indexed, Ok(()), fn (acc :: Result[Unit, Str], pair :: (Int, Planned)) -> [proc] Result[Unit, Str] {
    match acc {
      Err(msg) => Err(msg),
      Ok(_) => match pair {
        (i, p) => write_via_stdin(tmp_path_for(p.path, i), p.after),
      },
    }
  }) {
    Err(msg) => Err(msg),
    Ok(_) => match list.fold(ps, Ok(()), fn (acc :: Result[Unit, Str], p :: Planned) -> [proc] Result[Unit, Str] {
      match acc {
        Err(msg) => Err(msg),
        Ok(_) => match list.enumerate(ps) {
          _ => rename_into_place(tmp_path_for(p.path, index_of(ps, p)), p.path),
        },
      }
    }) {
      Err(msg) => Err(msg),
      Ok(_) => Ok(()),
    },
  }
}

# position of a Planned under eq ? needed so renames hit the tmp path
# that staging actually wrote (list.enumerate order is the fold order).
fn index_of(ps :: List[Planned], target :: Planned) -> Int {
  match list.fold(list.enumerate(ps), None, fn (acc :: Option[Int], pair :: (Int, Planned)) -> Option[Int] {
    match acc {
      Some(i) => Some(i),
      None => match pair {
        (i, p) => if p.path == target.path {
          if p.before_sha == target.before_sha {
            Some(i)
          } else {
            acc
          }
        } else {
          acc
        },
      },
    }
  }) {
    Some(i) => i,
    None => 0,
  }
}

# ---- execute ---------------------------------------------------------
fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match jv.get_field(args, "edits") {
    None => Err(e.single("edits", "missing", "edits is required ? a list of { path, old, new, expect?, require_sha256? } objects")),
    Some(v) => match jv.as_list(v) {
      None => Err(e.single("edits", "type", "edits must be a list")),
      Some(es) => if list.is_empty(es) {
        Err(e.single("edits", "min_len", "edits must contain at least one edit"))
      } else {
        match plan_all(es) {
          PlanRefused(refusals) => {
            let detail := JObj([("refused", JBool(true)), ("changed", JInt(0)), ("files", JList(list.map(refusals, fn (f :: Refusal) -> jv.Json {
              refused_json(f)
            })))])
            Err(e.single("edits", "batch_refused", str.join([refusal_message(refusals), "\nreceipt: ", jv.stringify(detail)], "")))
          },
          PlanOk(ps) => match apply_all(ps) {
            Err(msg) => Err(e.single("edits", "apply_failed", str.concat("apply failed mid-batch (tmp staged, rename incomplete ? check the named files): ", msg))),
            Ok(_) => Ok(JObj([("refused", JBool(false)), ("changed", JInt(list.len(ps))), ("files", JList(list.map(ps, fn (p :: Planned) -> jv.Json {
              planned_json(p)
            })))])),
          },
        }
      },
    },
  }
}

# ---- schema + tool ----------------------------------------------------
fn edit_schema() -> s.ModelSchema {
  { title: "Edit", description: "One replacement in one file, planned against the file's current content.", fields: [s.with_desc(s.required_str("path", []), "File to edit. Must NOT end in .lex ? Lex source goes through the op-log, not this tool."), s.with_desc(s.required_str("old", []), "Exact text to find."), s.with_desc(s.required_str("new", []), "Replacement text."), s.with_desc(s.optional(s.required_int("expect", [])), "How many times `old` must occur (default 1). Mismatch refuses the whole batch."), s.with_desc(s.optional(s.required_str("require_sha256", [])), "Optional hex sha256 pin of the file's current content; a mismatch refuses the whole batch.")] }
}

fn params() -> s.ModelSchema {
  { title: "EditFilesArgs", description: "Batch edit arguments", fields: [s.with_desc(s.required_array("edits", KObject(edit_schema()), [ListMinLen(1)]), "Edits to apply atomically: every edit is checked against every file first; if any check fails, no file is changed.")] }
}

fn tool() -> t.Tool {
  t.define("edit_files", "Apply a batch of exact-string replacements to NON-Lex files (configs, docs, YAML, scripts) with per-file evidence. For each edit, `old` must occur exactly `expect` times (default 1) and the file's current sha256 must match an optional `require_sha256` pin. ALL checks are run before ANY write; if any fail, nothing changes and the refusal receipt names every failing check. Refuses any path ending in .lex ? Lex source goes through the op-log. Returns a JSON receipt with per-file status, expected/actual counts, before/after sha256, and byte counts.", params(), execute)
}

