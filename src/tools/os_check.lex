import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./os_grant" as grant

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "OsCheckArgs", description: "Check a Lex file's declared effects against the mode's trust grant", fields: [s.required_str("path", [])] }
}

# `mode` is bound when the tool is constructed, not read from `args`.
# It used to be a caller-supplied field defaulting to "build", the one
# mode that forbids nothing — so a model could clear any grant simply by
# omitting the argument. The grant now comes from the harness, the same
# way the tool list does.
fn execute_for_mode(mode :: Str, args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let path := util.field_str_or(args, "path", ".")
  match proc.run("lex", ["--output", "json", "check", path]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => if out.exit_code != 0 {
      Err(e.single("", "lex_check_failed", str.concat(out.stdout, out.stderr)))
    } else {
      match jv.parse(out.stdout) {
        Err(_) => Err(grant.malformed("could not parse lex check output as JSON")),
        Ok(parsed) => match grant.extract_effects(parsed) {
          Err(errs) => Err(errs),
          Ok(required) => grant.verdict(mode, required),
        },
      }
    },
  }
}

fn tool_for_mode(mode :: Str) -> t.Tool {
  t.define("os_check", grant.description_for_mode(mode), params(), fn (args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
    execute_for_mode(mode, args)
  })
}

# Build's grant forbids nothing, so this is the honest default for the
# unrestricted toolset. Every other mode goes through tool_for_mode.
fn tool() -> t.Tool {
  tool_for_mode("build")
}

