import "std.io" as io

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

import "./lint" as lint

fn params() -> s.ModelSchema {
  { title: "WriteArgs", description: "Arguments for writing a file", fields: [s.required_str("path", []), s.required_str("content", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "content") {
      None => Err(e.single("", "missing_field", "content is required")),
      Some(content) => match io.write(path, content) {
        Err(msg) => Err(e.single("", "io_error", msg)),
        Ok(_) => lint.finalize(path, content, "wrote"),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("write", "Write content to a file, creating or overwriting it entirely. For .lex files, auto-formats and runs lex check automatically — if it fails, the error includes a specific fix hint. Keep calling write until it returns ok. On success the actual on-disk content is echoed back when formatting changed the file, so the next edit matches reality.", params(), execute)
}

