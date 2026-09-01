# lex-code — inspect the conflicts in an in-flight merge
#
# `vcs_merge_resolve` takes a path to a JSON array of resolutions, which
# the agent has to author before it has seen a single conflict. This tool
# is the missing half: what is actually in dispute, so the decision can be
# made from evidence rather than from a guess about what the merge found.
#
# ---- why two commands -------------------------------------------------
#
# `lex merge status` knows which conflicts are still open, and which
# branches are being merged. It does not carry the competing stage ids.
# `lex store-merge <src> <dst> --json` carries those — base, src and dst
# per sig — but knows nothing about the merge session or what has already
# been resolved. Neither alone answers "what am I deciding". So this reads
# the session for the open set and the store report for the detail, and
# joins them on sig id.
#
# ---- what it deliberately does not claim ------------------------------
#
# #23 asked for a file path, a function name and a readable diff of the
# competing bodies. The toolchain does not expose them: a stage id is not
# resolvable to a body through `lex store get` or `lex stage`, and the
# merge report carries no path. Rather than invent a diff, this reports
# the three stage ids and says plainly where to go next — `lex blame
# <file>` maps a fn to its current stage, which is what ties a conflict
# back to a name. An honest gap beats a fabricated diff; a merge decision
# made on invented evidence is the one failure this tool exists to avoid.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeShowConflictsArgs", description: "Inspect the open conflicts in a merge session", fields: [s.required_str("merge_id", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "merge_id") {
    None => Err(e.single("", "missing_field", "merge_id is required")),
    Some(id) => match proc.run("lex", ["merge", "status", id]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => if out.exit_code == 0 {
        Ok(JStr(report(out.stdout, detail_for(out.stdout))))
      } else {
        Err(e.single("", "merge_status_failed", str.trim(str.concat(out.stdout, out.stderr))))
      },
    },
  }
}

# The store report for the branches this session is merging, or an empty
# string when the branch line could not be read. A missing report degrades
# the output to ids and kinds rather than failing the call: knowing which
# conflicts are open is still worth having.
#
# The exit code is deliberately ignored. `lex store-merge` exits 2 when it
# finds conflicts, and writes the full JSON report to stdout anyway — so
# gating on exit 0 throws away the report in exactly the case this tool
# exists to serve. It did, at first: every conflict came back "competing
# stages: UNAVAILABLE" while a complete report sat unread in stdout. That
# is the #32 shape again, a broken read presenting as an honest absence,
# which is why the parse is what decides here, not the exit status.
fn detail_for(status_out :: Str) -> [proc] Str {
  match branches_of(status_out) {
    None => "",
    Some(pair) => match pair {
      (src, dst) => match proc.run("lex", ["store-merge", src, dst, "--json"]) {
        Err(_) => "",
        Ok(out) => out.stdout,
      },
    },
  }
}

# "merging:  feature → main" -> ("feature", "main")
fn branches_of(status_out :: Str) -> Option[(Str, Str)] {
  match list.head(list.filter(str.split(status_out, "\n"), fn (l :: Str) -> Bool {
    str.starts_with(str.trim(l), "merging:")
  })) {
    None => None,
    Some(line) => split_arrow(strip_or(str.trim(line), "merging:")),
  }
}

fn split_arrow(s :: Str) -> Option[(Str, Str)]
  examples {
    split_arrow("  feature → main") => Some(("feature", "main")),
    split_arrow("a→b") => Some(("a", "b")),
    split_arrow("no arrow here") => None,
    split_arrow("") => None
  }
{
  let parts := str.split(s, "→")
  if list.len(parts) == 2 {
    match (list.head(parts), list.head(list.tail(parts))) {
      (Some(l), Some(r)) => Some((str.trim(l), str.trim(r))),
      _ => None,
    }
  } else {
    None
  }
}

fn strip_or(s :: Str, prefix :: Str) -> Str
  examples {
    strip_or("merging: a", "merging:") => " a",
    strip_or("other", "merging:") => "other"
  }
{
  match str.strip_prefix(s, prefix) {
    None => s,
    Some(rest) => rest,
  }
}

# A conflict line from `lex merge status` is indented and looks like
#   "  3949a70f… (ModifyModify)"
# The header lines (merge_id:, merging:, remaining:) are not indented, so
# indentation alone separates them.
fn conflict_ids(status_out :: Str) -> List[Str] {
  list.fold(str.split(status_out, "\n"), [], fn (acc :: List[Str], line :: Str) -> List[Str] {
    if is_conflict_line(line) {
      list.concat(acc, [first_word(str.trim(line))])
    } else {
      acc
    }
  })
}

fn is_conflict_line(line :: Str) -> Bool
  examples {
    is_conflict_line("  3949a7 (ModifyModify)") => true,
    is_conflict_line("merge_id: merge_1") => false,
    is_conflict_line("remaining: 1") => false,
    is_conflict_line("  ") => false,
    is_conflict_line("") => false
  }
{
  if str.starts_with(line, " ") {
    let t := str.trim(line)
    if str.is_empty(t) {
      false
    } else {
      str.contains(t, "(")
    }
  } else {
    false
  }
}

fn first_word(s :: Str) -> Str
  examples {
    first_word("3949a7 (ModifyModify)") => "3949a7",
    first_word("alone") => "alone",
    first_word("") => ""
  }
{
  match list.head(str.split(s, " ")) {
    None => s,
    Some(w) => w,
  }
}

# Pull base/src/dst stage ids for one sig out of the store-merge report.
fn stages_of(report_json :: Str, sig_id :: Str) -> Option[(Str, Str, Str)] {
  match jv.parse_into_errors(report_json) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "conflicts") {
      Some(JList(items)) => match list.head(list.filter(items, fn (it :: jv.Json) -> Bool {
        field_of(it, "sig_id") == sig_id
      })) {
        None => None,
        Some(hit) => Some((field_of(hit, "base"), field_of(hit, "src"), field_of(hit, "dst"))),
      },
      _ => None,
    },
  }
}

fn field_of(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(v)) => v,
    _ => "",
  }
}

# An add-add conflict has no common ancestor: the report carries a JSON
# null, which reads back as "". Printing that as a blank field looks like
# a value this tool failed to fetch, when in fact there is none to fetch —
# and the difference decides whether the agent goes looking for a base.
fn base_or_none(base :: Str) -> Str
  examples {
    base_or_none("abc123") => "abc123",
    base_or_none("") => "(none — added on both sides, no common ancestor)"
  }
{
  if str.is_empty(base) {
    "(none — added on both sides, no common ancestor)"
  } else {
    base
  }
}

fn report(status_out :: Str, detail :: Str) -> Str {
  let ids := conflict_ids(status_out)
  if list.is_empty(ids) {
    str.concat(str.trim(status_out), "\n\nNo open conflicts. `vcs_merge_commit` will land this merge.")
  } else {
    str.join([str.trim(status_out), "\n\n", str.join(list.map(ids, fn (id :: Str) -> Str {
      one(id, detail)
    }), "\n\n"), "\n\n", footer(detail)], "")
  }
}

fn one(sig_id :: Str, detail :: Str) -> Str {
  match stages_of(detail, sig_id) {
    None => str.join(["conflict ", sig_id, "\n  competing stages: UNAVAILABLE (no store-merge report for this session)"], ""),
    Some(triple) => match triple {
      (base, src, dst) => str.join(["conflict ", sig_id, "\n  base (common ancestor): ", base_or_none(base), "\n  src  (take_theirs):     ", src, "\n  dst  (take_ours):       ", dst], ""),
    },
  }
}

fn footer(detail :: Str) -> Str {
  let head := "Resolve one at a time with `vcs_merge_resolve_one(merge_id, conflict_id, resolution)`, where resolution is take_ours (keep dst), take_theirs (keep src) or defer."
  if str.is_empty(detail) {
    str.concat(head, "\n\nStage ids were unavailable: `lex store-merge` did not report on these branches. The conflict ids above are still authoritative.")
  } else {
    str.concat(head, "\n\nA stage id is not resolvable to a function body, so there is no diff here. To tie a conflict to a name, run `lex blame <file>` — it prints each fn with its current stage id, which matches the dst stage above.")
  }
}

fn tool() -> t.Tool {
  t.define("vcs_merge_show_conflicts", "Inspect the open conflicts in an in-flight lex-vcs merge: conflict ids, and the competing base/src/dst stage ids for each. Call this before vcs_merge_resolve_one so a resolution is chosen from evidence rather than guessed.", params(), execute)
}

