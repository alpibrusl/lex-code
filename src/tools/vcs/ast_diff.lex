# vcs_ast_diff — structural diff between two Lex source files
#
# The tool ran `lex diff a b --json`. `lex diff` reports the first NodeId
# where two *execution traces* diverge and takes two run ids; handed two
# source paths it failed with `io error: No such file or directory`. The
# command this tool has always meant is `lex ast-diff` (#83).

import "std.process" as proc

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
      Some(b) => match proc.run("lex", ["ast-diff", "--json", a, b]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => match util.cli_result(out) {
          Err(detail) => Err(e.single("", "ast_diff_failed", detail)),
          Ok(body) => Ok(JStr(body)),
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_ast_diff", "Structural AST diff between two Lex source files. Reports added, removed, renamed, and modified functions with effect changes highlighted.", params(), execute)
}

