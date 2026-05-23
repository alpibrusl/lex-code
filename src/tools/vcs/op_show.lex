import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsOpShowArgs", description: "Show a single operation record from the op log.", fields: [s.required_str("op_id", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "op_id") {
    None => Err(e.single("", "missing_field", "op_id is required")),
    Some(id) => match proc.spawn("lex", ["op", "show", id, "--output", "json"]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => Ok(jv.JStr(str.concat(out.stdout, out.stderr))),
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_op_show", "Show the full record for a single lex-vcs operation by op_id.", params(), execute)
}

