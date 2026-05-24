import "std.io" as io

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

import "../linter" as linter

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
        Ok(_) => {
          let lint := linter.run(path)
          let header := str.concat("wrote ", path)
          if lint.failed {
            Err(e.single("", "lint_failed", str.concat(header, str.concat("\n", str.concat(lint.summary, "\nFix the errors above and rewrite.")))))
          } else {
            if str.is_empty(lint.summary) {
              Ok(JStr(header))
            } else {
              Ok(JStr(str.concat(header, str.concat("\n", lint.summary))))
            }
          }
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("write", "Write content to a file, creating or overwriting it entirely. For .lex files, auto-formats and runs lex check — lint results are always returned so you know if formatting was auto-applied or if errors must be fixed.", params(), execute)
}

