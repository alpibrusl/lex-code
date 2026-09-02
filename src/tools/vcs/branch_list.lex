import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsBranchListArgs", description: "List all lex-vcs branches.", fields: [] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match proc.run("lex", util.json_cmd(["branch", "list"])) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => match util.cli_result(out) {
      Err(detail) => Err(e.single("", "cli_failed", detail)),
      Ok(body) => Ok(JStr(body)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_branch_list", "List all lex-vcs branches, indicating which is current.", params(), execute)
}

