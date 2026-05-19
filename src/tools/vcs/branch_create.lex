import "std.proc" as proc
import "std.str"  as str
import "std.list" as list

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsBranchCreateArgs",
    description: "Create a new lex-vcs branch.",
    fields: [
      s.required_str("name", []),
      s.optional_str("from_branch", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "name") {
    None => Err(e.single("missing_field", "name is required")),
    Some(name) => {
      let base := ["branch", "create", name, "--output", "json"]
      let from_args := match util.field_str(args, "from_branch") {
        None    => [],
        Some(f) => ["--from", f]
      }
      let cmd := list.concat(base, from_args)
      match proc.spawn("lex", cmd) {
        Err(msg) => Err(e.single("proc_error", msg)),
        Ok(out)  => Ok(jv.JsonStr(str.concat(out.stdout, out.stderr))),
      }
    }
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_branch_create",
    "Create a new lex-vcs branch, optionally forking from a specific source branch.",
    params(),
    execute)
}
