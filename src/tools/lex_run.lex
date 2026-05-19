import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexRunArgs",
    description: "Run a Lex function",
    fields: [
      s.required_str("path", []),
      s.required_str("fn_name", []),
      s.optional_str("fn_args", []),
    ] }
}

fn execute(args :: jv.Json) -> [proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("missing_field", "path is required")),
    Some(path) =>
      match util.field_str(args, "fn_name") {
        None => Err(e.single("missing_field", "fn_name is required")),
        Some(fn_name) => {
          let cmd_args :=
            match util.field_str(args, "fn_args") {
              None          => ["run", path, fn_name],
              Some(fn_args) => ["run", path, fn_name, fn_args],
            }
          match proc.spawn("lex", cmd_args) {
            Err(msg) => Err(e.single("proc_error", msg)),
            Ok(out)  => Ok(jv.JsonStr(str.concat(out.stdout, out.stderr))),
          }
        }
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "lex_run",
    "Run a Lex function with `lex run path fn_name`. Returns stdout and stderr.",
    params(),
    execute)
}
