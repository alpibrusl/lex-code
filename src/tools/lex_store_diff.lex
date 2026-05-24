import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStoreDiffArgs", description: "Content-addressed structural diff between two SigIds", fields: [s.required_str("sigid_a", []), s.required_str("sigid_b", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "sigid_a") {
    None => Err(e.single("", "missing_field", "sigid_a is required")),
    Some(a) => match util.field_str(args, "sigid_b") {
      None => Err(e.single("", "missing_field", "sigid_b is required")),
      Some(b) => match proc.spawn("lex", ["store", "diff", a, b]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_store_diff", "Compute a content-addressed structural diff between two function SigIds.", params(), execute)
}

