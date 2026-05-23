import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "GrepArgs", description: "Search for a pattern in files", fields: [s.required_str("pattern", []), s.required_str("path", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "pattern") {
    None => Err(e.single("", "missing_field", "pattern is required")),
    Some(pattern) => match util.field_str(args, "path") {
      None => Err(e.single("", "missing_field", "path is required")),
      Some(path) => match proc.spawn("grep", ["-r", "-n", pattern, path]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => {
          let result := if str.is_empty(out.stdout) {
            "no matches found"
          } else {
            out.stdout
          }
          Ok(jv.JStr(result))
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("grep", "Search for a pattern in files using grep -rn. Returns matching lines with line numbers.", params(), execute)
}

