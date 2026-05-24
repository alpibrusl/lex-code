import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "AttestationQueryArgs", description: "List attestations on a function", fields: [s.required_str("fn_name", []), s.optional(s.required_str("path", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "fn_name") {
    None => Err(e.single("", "missing_field", "fn_name is required")),
    Some(fn_name) => {
      let cmd_args := match util.field_str(args, "path") {
        None => ["store", "attestations", fn_name],
        Some(path) => ["store", "attestations", "--path", path, fn_name],
      }
      match proc.spawn("lex", cmd_args) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => {
          let result := if str.is_empty(out.stdout) {
            str.concat(fn_name, " has no attestations")
          } else {
            out.stdout
          }
          Ok(JStr(result))
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("attestation_query", "List attestations on a function from lex-trail. Shows who attested, when, and the attestation chain.", params(), execute)
}

