import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "SigidLookupArgs", description: "Find a function by its content-addressed SigId", fields: [s.required_str("sigid", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "sigid") {
    None => Err(e.single("", "missing_field", "sigid is required")),
    Some(sigid) => match proc.run("lex", ["store", "lookup", sigid]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => if out.exit_code == 0 {
        Ok(JStr(out.stdout))
      } else {
        Err(e.single("", "not_found", str.concat("sigid not found: ", sigid)))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("sigid_lookup", "Look up a function definition by its content-addressed SigId hash. Exact identity, not name-based.", params(), execute)
}

