import "std.proc" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsAstDiffArgs", description: "Structural AST diff between two Lex source files.", fields: [s.required_str("file_a", []), s.required_str("file_b", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "file_a") {
    None => Err(e.single("", "missing_field", "file_a is required")),
    Some(a) => match util.field_str(args, "file_b") {
      None => Err(e.single("", "missing_field", "file_b is required")),
      Some(b) => match proc.spawn("lex", ["diff", a, b, "--json"]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_ast_diff", "Structural AST diff between two Lex source files. Reports added, removed, renamed, and modified functions with effect changes highlighted.", params(), execute)
}

