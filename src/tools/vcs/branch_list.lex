import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

fn params() -> s.ModelSchema {
  { title: "VcsBranchListArgs",
    description: "List all lex-vcs branches.",
    fields: [] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  match proc.spawn("lex", ["branch", "list", "--output", "json"]) {
    Err(msg) => Err(e.single("proc_error", msg)),
    Ok(out)  => Ok(jv.JsonStr(str.concat(out.stdout, out.stderr))),
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_branch_list",
    "List all lex-vcs branches, indicating which is current.",
    params(),
    execute)
}
