import "std.io"  as io
import "std.str" as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "WriteArgs",
    description: "Arguments for writing a file",
    fields: [
      s.required_str("path", []),
      s.required_str("content", []),
    ] }
}

fn execute(args :: jv.Json) -> [io] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("missing_field", "path is required")),
    Some(path) =>
      match util.field_str(args, "content") {
        None => Err(e.single("missing_field", "content is required")),
        Some(content) =>
          match io.write(path, content) {
            Ok(_)    => Ok(jv.JsonStr(str.concat("wrote ", path))),
            Err(msg) => Err(e.single("io_error", msg)),
          }
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "write",
    "Write content to a file, creating or overwriting it entirely.",
    params(),
    execute)
}
