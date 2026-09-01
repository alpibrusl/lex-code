# lex-code — resolve a single merge conflict
#
# `vcs_merge_resolve` takes a path to a JSON array, so deciding one
# conflict means authoring a file, and deciding five means authoring the
# whole batch before seeing whether the first was right. This resolves
# one, so the loop is show → reason → resolve → check → repeat.
#
# The file is still how `lex merge resolve` is fed — that is the CLI's
# only interface — but writing it is this tool's job rather than the
# model's. That closes a real failure mode: a hand-authored resolutions
# file with a mistyped kind is rejected wholesale by the parser, and the
# model sees a serde error about an "internally tagged enum" rather than
# the fact that it named a resolution that does not exist.
#
# `custom` is deliberately not supported here. It requires an `op` field
# carrying an AST Operation, which is not something to assemble from a
# few string arguments; `vcs_merge_resolve` with a written file remains
# the route for that.

import "std.process" as proc

import "std.str" as str

import "std.io" as io

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeResolveOneArgs", description: "Resolve a single conflict in a merge session", fields: [s.required_str("merge_id", []), s.required_str("conflict_id", []), s.required_str("resolution", [])] }
}

# The vocabulary `lex merge resolve` accepts for a resolution kind.
# `custom` is real but needs an `op` payload, so it is not offered here.
fn kinds() -> List[Str]
  examples {
    kinds() => ["take_ours", "take_theirs", "defer"]
  }
{
  ["take_ours", "take_theirs", "defer"]
}

fn is_kind(k :: Str) -> Bool
  examples {
    is_kind("take_ours") => true,
    is_kind("take_theirs") => true,
    is_kind("defer") => true,
    is_kind("custom") => false,
    is_kind("take ours") => false,
    is_kind("") => false
  }
{
  list.fold(kinds(), false, fn (acc :: Bool, cand :: Str) -> Bool {
    if acc {
      true
    } else {
      cand == k
    }
  })
}

fn scratch_path() -> Str
  examples {
    scratch_path() => ".lex/merge-resolution.json"
  }
{
  ".lex/merge-resolution.json"
}

fn resolution_json(conflict_id :: Str, kind :: Str) -> Str
  examples {
    resolution_json("abc", "take_ours") => "[{\"conflict_id\":\"abc\",\"resolution\":{\"kind\":\"take_ours\"}}]"
  }
{
  jv.stringify(JList([JObj([("conflict_id", JStr(conflict_id)), ("resolution", JObj([("kind", JStr(kind))]))])]))
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "merge_id") {
    None => Err(e.single("", "missing_field", "merge_id is required")),
    Some(id) => match util.field_str(args, "conflict_id") {
      None => Err(e.single("", "missing_field", "conflict_id is required")),
      Some(cid) => match util.field_str(args, "resolution") {
        None => Err(e.single("", "missing_field", "resolution is required")),
        Some(kind) => if is_kind(kind) {
          run_resolve(id, cid, kind)
        } else {
          Err(e.single("", "bad_resolution", str.join(["resolution must be one of ", str.join(kinds(), ", "), " — got \"", kind, "\". For a custom merged body, write a resolutions file and use vcs_merge_resolve."], "")))
        },
      },
    },
  }
}

fn run_resolve(merge_id :: Str, conflict_id :: Str, kind :: Str) -> [io, proc] Result[jv.Json, e.Errors] {
  match io.write(scratch_path(), resolution_json(conflict_id, kind)) {
    Err(msg) => Err(e.single("", "io_error", str.concat("could not write the resolution file: ", msg))),
    Ok(_) => match proc.run("lex", ["merge", "resolve", merge_id, "--file", scratch_path()]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => if out.exit_code == 0 {
        Ok(JStr(str.join([str.trim(str.concat(out.stdout, out.stderr)), "\n\n", outcome_note(conflict_id, kind)], "")))
      } else {
        Err(e.single("", "resolve_failed", str.trim(str.concat(out.stdout, out.stderr))))
      },
    },
  }
}

# A deferred conflict is still counted in `remaining`, and still listed by
# vcs_merge_show_conflicts — `lex merge status` does not mark it. Left
# unsaid, that reads as a no-op, and the obvious next move is to defer it
# again; the loop never terminates. So say it here, where the agent is
# looking, rather than letting it be inferred from a count that did not
# move.
fn outcome_note(conflict_id :: Str, kind :: Str) -> Str
  examples {
    outcome_note("c1", "take_ours") => "Resolved c1 as take_ours. Call vcs_merge_show_conflicts for what is left, or vcs_merge_commit once remaining is 0.",
    outcome_note("c1", "defer") => "Deferred c1. It still counts toward `remaining` and will keep appearing in vcs_merge_show_conflicts — that is expected, not a failed write. Deferring again will not clear it: the merge cannot be committed until it is decided with take_ours or take_theirs."
  }
{
  if kind == "defer" {
    str.join(["Deferred ", conflict_id, ". It still counts toward `remaining` and will keep appearing in vcs_merge_show_conflicts — that is expected, not a failed write. Deferring again will not clear it: the merge cannot be committed until it is decided with take_ours or take_theirs."], "")
  } else {
    str.join(["Resolved ", conflict_id, " as ", kind, ". Call vcs_merge_show_conflicts for what is left, or vcs_merge_commit once remaining is 0."], "")
  }
}

fn tool() -> t.Tool {
  t.define("vcs_merge_resolve_one", "Resolve one conflict in an in-flight lex-vcs merge. resolution is take_ours (keep the dst/current branch's version), take_theirs (keep the src branch's version) or defer. Use vcs_merge_show_conflicts first to see what is in dispute.", params(), execute)
}

