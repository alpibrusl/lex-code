import "std.proc" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsBranchOverlayArgs", description: "Preview what a merge would produce without persisting anything.", fields: [s.required_str("other_branch", []), s.optional(s.required_str("on_branch", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "other_branch") {
    None => Err(e.single("", "missing_field", "other_branch is required")),
    Some(other) => {
      let base := ["branch", "overlay", other, "--output", "json"]
      let on_args := match util.field_str(args, "on_branch") {
        None => [],
        Some(b) => ["--on", b],
      }
      let cmd := list.concat(base, on_args)
      match proc.spawn("lex", cmd) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_branch_overlay", "Preview what the current (or on_branch) branch would look like if other_branch were merged. Pure read — nothing is persisted.", params(), execute)
}

