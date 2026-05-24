import "std.io" as io

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "EditArgs", description: "Edit a file by exact string replacement. old_str must appear exactly once.", fields: [s.required_str("path", []), s.required_str("old_str", []), s.required_str("new_str", [])] }
}

fn replace_once(content :: Str, old_str :: Str, new_str :: Str) -> Result[Str, Str] {
  let parts := str.split(content, old_str)
  let n := list.len(parts)
  match n {
    1 => Err("old_str not found in file"),
    2 => match list.head(parts) {
      None => Err("internal error"),
      Some(head) => match list.head(list.tail(parts)) {
        None => Err("internal error"),
        Some(tail) => Ok(str.concat(str.concat(head, new_str), tail)),
      },
    },
    _ => Err("old_str is not unique — found multiple occurrences"),
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "old_str") {
      None => Err(e.single("", "missing_field", "old_str is required")),
      Some(old_str) => match util.field_str(args, "new_str") {
        None => Err(e.single("", "missing_field", "new_str is required")),
        Some(new_str) => match io.read(path) {
          Err(msg) => Err(e.single("", "io_error", msg)),
          Ok(content) => match replace_once(content, old_str, new_str) {
            Err(reason) => Err(e.single("", "edit_error", reason)),
            Ok(updated) => match io.write(path, updated) {
              Ok(_) => Ok(JStr("edit applied")),
              Err(msg) => Err(e.single("", "io_error", msg)),
            },
          },
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("edit", "Edit a file by replacing old_str with new_str. old_str must be unique in the file.", params(), execute)
}

