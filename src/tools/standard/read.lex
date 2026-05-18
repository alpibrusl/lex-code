import "std.io"  as io
import "std.str" as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "ReadArgs",
    description: "Arguments for reading a file",
    fields: [
      s.required_str("path", []),
      s.optional_int("offset", []),
      s.optional_int("limit", []),
    ] }
}

fn execute(args :: jv.Json) -> [io] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None =>
      Err(e.single("missing_field", "path is required")),
    Some(path) =>
      match io.read(path) {
        Err(msg) => Err(e.single("io_error", msg)),
        Ok(content) => Ok(jv.JsonStr(content)),
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "read",
    "Read the full contents of a file at the given path.",
    params(),
    execute)
}
