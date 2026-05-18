import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsBranchShowArgs",
    description: "Show the head stage map for a lex-vcs branch.",
    fields: [
      s.required_str("branch", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "branch") {
    None => Err(e.single("missing_field", "branch is required")),
    Some(name) =>
      match proc.spawn("lex", ["branch", "show", name, "--output", "json"]) {
        Err(msg) => Err(e.single("proc_error", msg)),
        Ok(out)  => Ok(jv.JsonStr(str.concat(out.stdout, out.stderr))),
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_branch_show",
    "Show the head SigId→StageId map for a lex-vcs branch.",
    params(),
    execute)
}
