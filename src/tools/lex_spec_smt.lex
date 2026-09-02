# lex_spec_smt — export a lex-spec Spec to SMT-LIB
#
# The tool offered an `out` argument and passed it as `--out <path>`.
# `lex spec smt` has no such flag: the CLI read `--out` itself as the
# spec path and failed with `reading --out: No such file` (#83).
#
# The command writes SMT-LIB to stdout, which is where it stays. A tool
# that wrote the file would need `fs_write`, and `Tool.execute` is fixed
# at `[net, io, proc]` — but more to the point, the model asked for the
# encoding, and handing back a path it then has to read is a round trip
# for nothing.

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexSpecSmtArgs", description: "Export a lex-spec Spec to SMT-LIB", fields: [s.required_str("spec", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "spec") {
    None => Err(e.single("", "missing_field", "spec is required — the path to a .spec file")),
    Some(spec_file) => match proc.run("lex", ["spec", "smt", spec_file]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match util.cli_result(out) {
        Err(detail) => Err(e.single("", "smt_export_failed", detail)),
        Ok(body) => Ok(JStr(body)),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_spec_smt", "Export a lex-spec Spec to SMT-LIB with `lex spec smt <spec>`, for optional Z3 verification. Returns the encoding itself; write it to a file with the write tool if you need one.", params(), execute)
}

