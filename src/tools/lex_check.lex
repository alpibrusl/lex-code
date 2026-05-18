import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexCheckArgs",
    description: "Arguments for lex type-check",
    fields: [
      s.optional_str("path", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  let target := util.field_str_or(args, "path", ".")
  match proc.spawn("lex", ["check", target]) {
    Err(msg) => Err(e.single("proc_error", msg)),
    Ok(out)  =>
      let output :=
        if out.ok then
          if str.is_empty(out.stdout) then "type check passed" else out.stdout
        else
          str.concat(out.stdout, out.stderr)
      Ok(jv.JsonStr(output)),
  }
}

fn tool() -> t.Tool {
  t.define(
    "lex_check",
    "Run `lex check` to type-check files or the whole project. Always run after edits.",
    params(),
    execute)
}
