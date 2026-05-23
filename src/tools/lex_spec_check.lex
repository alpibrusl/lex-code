import "std.proc" as proc

import "std.str" as str

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexSpecCheckArgs", description: "Random property-check a lex-spec Spec", fields: [s.optional(s.required_str("path", [])), s.optional(s.required_int("count", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let target := util.field_str_or(args, "path", ".")
  let count := match util.field_int(args, "count") {
    None => 100,
    Some(n) => n,
  }
  match proc.spawn("lex", ["spec", "check", "--count", int.to_str(count), target]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => {
      let output := if out.exit_code == 0 {
        str.concat("spec passed (all ", str.concat(int.to_str(count), str.concat(" samples)\n", out.stdout)))
      } else {
        str.concat("spec falsified\n", str.concat(out.stdout, out.stderr))
      }
      Ok(jv.JStr(output))
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_spec_check", "Run `lex spec check` to random-test property specs. Returns 'spec passed' or a falsifying example.", params(), execute)
}

