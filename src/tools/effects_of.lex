import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "EffectsOfArgs",
    description: "Get the effect row of a Lex function",
    fields: [
      s.required_str("fn_name", []),
      s.optional(s.required_str("path", [])),
    ] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "fn_name") {
    None => Err(e.single("", "missing_field", "fn_name is required")),
    Some(fn_name) => {
      let target := util.field_str_or(args, "path", ".")
      match proc.spawn("lex", ["check", "--json", "--effects", fn_name, target]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out)  =>
          if out.exit_code == 0 {
            Ok(jv.JStr(out.stdout))
          } else {
            Err(e.single("", "check_error", str.concat(out.stdout, out.stderr)))
          },
      }
    }
  }
}

fn tool() -> t.Tool {
  t.define(
    "effects_of",
    "Get the declared effect row for a function using `lex check --json --effects`. Returns e.g. \"[net, io]\".",
    params(),
    execute)
}
