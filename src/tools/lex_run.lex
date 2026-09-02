# lex_run — run a Lex function
#
# A program that exits non-zero is an answer, not a failure: the run
# happened and it went badly, which is exactly what the caller wanted to
# know. So this keeps returning the output — but a CLI that *refused the
# invocation* never ran anything, and returning its complaint as program
# output would be the #83 failure in miniature.

import "std.process" as proc

import "std.str" as str

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexRunArgs", description: "Run a Lex function", fields: [s.required_str("path", []), s.required_str("fn_name", []), s.optional(s.required_str("fn_args", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "fn_name") {
      None => Err(e.single("", "missing_field", "fn_name is required")),
      Some(fn_name) => {
        let cmd_args := match util.field_str(args, "fn_args") {
          None => ["run", path, fn_name],
          Some(fn_args) => ["run", path, fn_name, fn_args],
        }
        match proc.run("lex", cmd_args) {
          Err(msg) => Err(e.single("", "proc_error", msg)),
          Ok(out) => outcome(out),
        }
      },
    },
  }
}

# The exit code is reported rather than dropped, because "it printed
# nothing" and "it printed nothing and exited 1" are different runs.
fn outcome(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Result[jv.Json, e.Errors] {
  if util.is_usage_error(util.combined(out)) {
    Err(e.single("", "run_refused", util.unavailable("lex run", util.combined(out))))
  } else {
    Ok(JStr(str.join(["exit ", int.to_str(out.exit_code), "\n", util.combined(out)], "")))
  }
}

fn tool() -> t.Tool {
  t.define("lex_run", "Run a Lex function with `lex run path fn_name`. Returns stdout and stderr.", params(), execute)
}

