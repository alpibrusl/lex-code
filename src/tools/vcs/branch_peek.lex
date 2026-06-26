import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsBranchPeekArgs", description: "Read another branch's ops without switching to it.", fields: [s.required_str("branch", []), s.optional(s.required_str("vs", [])), s.optional(s.required_str("since_fork", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "branch") {
    None => Err(e.single("", "missing_field", "branch is required")),
    Some(name) => {
      let base := ["branch", "peek", name, "--output", "json"]
      let fork_args := match util.field_bool(args, "since_fork") {
        Some(true) => ["--since-fork"],
        _ => [],
      }
      let vs_args := match util.field_str(args, "vs") {
        None => [],
        Some(v) => ["--vs", v],
      }
      let cmd := list.concat(base, list.concat(fork_args, vs_args))
      match proc.run("lex", cmd) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => Ok(JStr(str.concat(out.stdout, out.stderr))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_branch_peek", "Read another branch's operations without switching to it. Use since_fork=true to see only divergence from a common ancestor.", params(), execute)
}

