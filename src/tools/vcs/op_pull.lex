import "std.proc" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsOpPullArgs", description: "Pull ops from a remote lex-vcs server.", fields: [s.required_str("remote_url", []), s.optional(s.required_str("branch", [])), s.optional(s.required_str("limit", [])), s.optional(s.required_str("dry_run", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "remote_url") {
    None => Err(e.single("", "missing_field", "remote_url is required")),
    Some(url) => {
      let base := ["op", "pull", url, "--output", "json"]
      let branch_args := match util.field_str(args, "branch") {
        None => [],
        Some(b) => ["--branch", b],
      }
      let limit_args := match util.field_str(args, "limit") {
        None => [],
        Some(n) => ["--limit", n],
      }
      let dry_args := match util.field_bool(args, "dry_run") {
        Some(true) => ["--dry-run"],
        _ => [],
      }
      let cmd := list.concat(base, list.concat(branch_args, list.concat(limit_args, dry_args)))
      match proc.spawn("lex", cmd) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_op_pull", "Pull lex-vcs operations from a remote server onto the local branch.", params(), execute)
}

