import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexAuditArgs", description: "Semantic audit queries on the codebase", fields: [s.required_str("query", []), s.optional(s.required_str("path", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "query") {
    None => Err(e.single("", "missing_field", "query is required")),
    Some(query) => {
      let target := util.field_str_or(args, "path", ".")
      match proc.spawn("lex", ["audit", query, target]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(jv.JStr(str.concat(out.stdout, out.stderr))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_audit", "Run `lex audit` semantic queries. query is a flag like '--calls', '--effects', '--impure', '--unattested'.", params(), execute)
}

