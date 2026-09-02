import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeCommitArgs", description: "Commit a fully-resolved lex-vcs merge session, advancing the dst branch head.", fields: [s.required_str("merge_id", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "merge_id") {
    None => Err(e.single("", "missing_field", "merge_id is required")),
    Some(id) => match proc.run("lex", ["merge", "commit", id]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match util.cli_result(out) {
        Err(detail) => Err(e.single("", "cli_failed", detail)),
        Ok(body) => Ok(JStr(body)),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_merge_commit", "Commit a fully-resolved lex-vcs merge session, advancing the dst branch's head op to the new merge op.", params(), execute)
}

