# lex_store_merge — three-way structural merge between two branches
#
# The tool took `base`, `left` and `right` SigIds and ran
# `lex store merge`. There is no such subcommand — `lex store` accepts
# `list` and `get` — so it had never run (#83), and the signature it
# advertised describes an API the store does not expose: the base of a
# merge is *derived* from the two branches, not supplied.
#
# `lex store-merge <src> <dst>` is the real command, and it is not a
# duplicate of what already exists: `vcs_branch_overlay` previews and
# `vcs_merge_start` opens an interactive session, while this is the
# one-shot that can also commit a clean result.
#
# Exit 2 means *conflicts were found*, and the full report is on stdout —
# the trap #23 hit in `merge_show_conflicts`, where gating on exit 0 threw
# away the answer.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStoreMergeArgs", description: "Three-way structural merge between two store branches", fields: [s.required_str("src", []), s.required_str("dst", []), s.optional(s.required_bool("commit"))] }
}

# execute reads `commit` with field_bool, so the schema must declare it a
# boolean or the flag is silently dropped and a merge the caller asked to
# preview would commit — or, here, the reverse. See util.declares_bool (#28).
fn commit_is_bool() -> Bool
  examples {
    commit_is_bool() => true
  }
{
  util.declares_bool(params(), "commit")
}

fn cmd_for(src :: Str, dst :: Str, commit :: Bool) -> List[Str]
  examples {
    cmd_for("feature", "main", false) => ["store-merge", "feature", "main", "--json"],
    cmd_for("feature", "main", true) => ["store-merge", "feature", "main", "--json", "--commit"]
  }
{
  let base := ["store-merge", src, dst, "--json"]
  if commit {
    list.concat(base, ["--commit"])
  } else {
    base
  }
}

# Exit 2 is a finding, not a failure: the merge ran and found conflicts,
# and the report describing them is on stdout. Anything else non-zero is
# the command refusing to run.
fn outcome(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Result[Str, Str]
  examples {
    outcome({ stdout: "{\"summary\":{}}", stderr: "", exit_code: 0 }) => Ok("{\"summary\":{}}"),
    outcome({ stdout: "{\"conflicts\":1}", stderr: "", exit_code: 2 }) => Ok("{\"conflicts\":1}"),
    outcome({ stdout: "", stderr: "error: unknown branch", exit_code: 1 }) => Err("error: unknown branch")
  }
{
  if out.exit_code == 0 {
    Ok(util.combined(out))
  } else {
    if out.exit_code == 2 {
      Ok(util.combined(out))
    } else {
      Err(util.combined(out))
    }
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "src") {
    None => Err(e.single("", "missing_field", "src is required — the branch to merge from")),
    Some(src) => match util.field_str(args, "dst") {
      None => Err(e.single("", "missing_field", "dst is required — the branch to merge into")),
      Some(dst) => run(src, dst, match util.field_bool(args, "commit") {
        Some(true) => true,
        _ => false,
      }),
    },
  }
}

fn run(src :: Str, dst :: Str, commit :: Bool) -> [io, proc] Result[jv.Json, e.Errors] {
  match proc.run("lex", cmd_for(src, dst, commit)) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => match outcome(out) {
      Err(detail) => Err(e.single("", "merge_failed", detail)),
      Ok(body) => Ok(JStr(body)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_store_merge", "Three-way structural merge of store branches with `lex store-merge <src> <dst> --json`. Previews by default; set commit=true to apply a clean merge to dst (refused if there are conflicts). Conflicts are reported in the JSON, not as an error.", params(), execute)
}

