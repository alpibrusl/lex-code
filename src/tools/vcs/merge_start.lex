import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeStartArgs", description: "Start a lex-vcs merge session between two branches.", fields: [s.required_str("src", []), s.required_str("dst", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "src") {
    None => Err(e.single("", "missing_field", "src is required")),
    Some(src) => match util.field_str(args, "dst") {
      None => Err(e.single("", "missing_field", "dst is required")),
      Some(dst) => match proc.run("lex", ["merge", "start", "--src", src, "--dst", dst]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_merge_start", "Start a lex-vcs merge session merging src branch into dst. Returns a merge_id and the list of conflicts to resolve.", params(), execute)
}

