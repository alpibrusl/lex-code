import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexSpecSmtArgs", description: "Export a Spec to SMT-LIB for Z3 verification", fields: [s.required_str("path", []), s.optional(s.required_str("out", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => {
      let out_args := match util.field_str(args, "out") {
        None => ["spec", "smt", path],
        Some(out_path) => ["spec", "smt", "--out", out_path, path],
      }
      match proc.spawn("lex", out_args) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_spec_smt", "Export a lex-spec Spec to SMT-LIB format for optional Z3 verification.", params(), execute)
}

