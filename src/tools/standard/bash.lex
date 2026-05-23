import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "BashArgs", description: "Run a bash command in the project directory", fields: [s.required_str("command", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "command") {
    None => Err(e.single("", "missing_field", "command is required")),
    Some(cmd) => match proc.spawn("bash", ["-c", cmd]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => {
        let combined := str.concat(out.stdout, out.stderr)
        Ok(jv.JStr(combined))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("bash", "Run a bash command and return combined stdout and stderr.", params(), execute)
}

