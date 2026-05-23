import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStoreApplyArgs", description: "Apply an AST-level Operation to the lex-store", fields: [s.required_str("operation", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "operation") {
    None => Err(e.single("", "missing_field", "operation is required")),
    Some(op_json) => match proc.spawn("lex", ["store", "apply", op_json]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => if out.exit_code == 0 {
        Ok(jv.JStr(str.concat("applied\n", out.stdout)))
      } else {
        Err(e.single("", "apply_error", str.concat(out.stdout, out.stderr)))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_store_apply", "Apply an AST-level Operation (JSON) to the lex-store. Preferred over text-edit for structural changes.", params(), execute)
}

