import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexTestArgs", description: "Run Lex tests", fields: [s.optional(s.required_str("path", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let target := util.field_str_or(args, "path", "tests")
  match proc.run("lex", ["run", target, "run_all"]) {
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
  t.define("lex_test", "Run Lex tests with `lex run tests/... run_all`. Returns pass/fail output.", params(), execute)
}

