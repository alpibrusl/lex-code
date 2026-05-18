import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "GlobArgs",
    description: "Find files matching a pattern",
    fields: [
      s.required_str("pattern", []),
      s.optional_str("directory", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "pattern") {
    None => Err(e.single("missing_field", "pattern is required")),
    Some(pattern) =>
      let dir := util.field_str_or(args, "directory", ".")
      match proc.spawn("find", [dir, "-name", pattern, "-type", "f"]) {
        Err(msg) => Err(e.single("proc_error", msg)),
        Ok(out)  =>
          let result := if str.is_empty(out.stdout) then "no files found" else out.stdout
          Ok(jv.JsonStr(result)),
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "glob",
    "Find files matching a pattern. Returns newline-separated file paths.",
    params(),
    execute)
}
