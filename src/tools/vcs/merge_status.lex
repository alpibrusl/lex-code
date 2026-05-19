import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeStatusArgs",
    description: "Check the status of an in-flight lex-vcs merge session.",
    fields: [
      s.required_str("merge_id", []),
    ] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "merge_id") {
    None => Err(e.single("", "missing_field", "merge_id is required")),
    Some(id) =>
      match proc.spawn("lex", ["merge", "status", id, "--output", "json"]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out)  => Ok(jv.JStr(str.concat(out.stdout, out.stderr))),
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_merge_status",
    "Check remaining conflicts and status of an in-flight lex-vcs merge session.",
    params(),
    execute)
}
