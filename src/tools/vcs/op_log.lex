import "std.proc" as proc
import "std.str"  as str
import "std.list" as list

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsOpLogArgs",
    description: "Walk the operation log for a branch.",
    fields: [
      s.optional_str("branch", []),
      s.optional_str("limit", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  let base := ["op", "log", "--output", "json"]
  let branch_args := match util.field_str(args, "branch") {
    None    => [],
    Some(b) => ["--branch", b]
  }
  let limit_args := match util.field_str(args, "limit") {
    None    => [],
    Some(n) => ["--limit", n]
  }
  let cmd := list.concat(base, list.concat(branch_args, limit_args))
  match proc.spawn("lex", cmd) {
    Err(msg) => Err(e.single("proc_error", msg)),
    Ok(out)  => Ok(jv.JsonStr(str.concat(out.stdout, out.stderr))),
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_op_log",
    "Walk the lex-vcs operation log for a branch (newest first). Optionally filter by branch name or cap with limit.",
    params(),
    execute)
}
