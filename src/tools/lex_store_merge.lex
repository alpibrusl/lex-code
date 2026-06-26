import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStoreMergeArgs", description: "3-way structural merge of three SigIds", fields: [s.required_str("base", []), s.required_str("left", []), s.required_str("right", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "base") {
    None => Err(e.single("", "missing_field", "base is required")),
    Some(base) => match util.field_str(args, "left") {
      None => Err(e.single("", "missing_field", "left is required")),
      Some(left) => match util.field_str(args, "right") {
        None => Err(e.single("", "missing_field", "right is required")),
        Some(right) => match proc.run("lex", ["store", "merge", base, left, right]) {
          Err(msg) => Err(e.single("", "proc_error", msg)),
          Ok(out) => if out.exit_code == 0 {
            Ok(JStr(str.concat("merged\n", out.stdout)))
          } else {
            Err(e.single("", "merge_conflict", str.concat(out.stdout, out.stderr)))
          },
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_store_merge", "3-way structural merge: base, left, right SigIds. Returns merged SigId or conflict details.", params(), execute)
}

