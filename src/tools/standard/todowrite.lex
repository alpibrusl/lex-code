import "std.io" as io

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "TodoWriteArgs", description: "Update the session TODO list", fields: [s.required_str("todos", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "todos") {
    None => Err(e.single("", "missing_field", "todos is required")),
    Some(todos) => match io.write(".lex/todos.md", todos) {
      Ok(_) => Ok(jv.JStr("todos updated")),
      Err(msg) => Err(e.single("", "io_error", msg)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("todowrite", "Write a markdown TODO list to .lex/todos.md to track remaining steps.", params(), execute)
}

