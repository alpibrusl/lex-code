# `lex test <dir>`, not `lex run <dir> run_all`: `lex run` opens whatever
# path it's given as a single file, so the default `path: "tests"` — a
# directory — always failed with a raw OS "Is a directory" error, never
# actually running anything. Found live when a `graph.lex` fix-loop test
# used this same broken invocation as its mechanical verify step and
# never got past that opaque error to see the real bug underneath.
# `lex test` is the real native subcommand for "run every
# tests/test_*.lex file, calling run_all in each".

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexTestArgs", description: "Run Lex tests", fields: [s.optional(s.with_desc(s.required_str("path", []), "Test DIRECTORY to scan for test_*.lex files (default: tests). Not a single file path — use lex_run for that."))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let target := util.field_str_or(args, "path", "tests")
  match proc.run("lex", ["test", target]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => {
      let output := if out.exit_code == 0 {
        str.concat("tests passed\n", out.stdout)
      } else {
        str.concat("tests failed\n", str.concat(out.stdout, out.stderr))
      }
      Ok(JStr(output))
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_test", "Run every tests/test_*.lex file with `lex test`, calling run_all in each. Returns pass/fail output per file.", params(), execute)
}

