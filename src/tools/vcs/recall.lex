import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsRecallArgs", description: "Query the lex-vcs op log by intent, session, or predicate. With no selector, returns all ops.", fields: [s.optional(s.required_str("intent", [])), s.optional(s.required_str("session", [])), s.optional(s.required_str("predicate", [])), s.optional(s.required_str("limit", []))] }
}

# Pick the single selector flag from whichever field the model supplied,
# in priority order; fall back to --all when none is given (recall
# requires exactly one selector, and --all is the harmless default).
fn selector(args :: jv.Json) -> List[Str] {
  match util.field_str(args, "intent") {
    Some(v) => ["--intent", v],
    None => match util.field_str(args, "session") {
      Some(v) => ["--session", v],
      None => match util.field_str(args, "predicate") {
        Some(v) => ["--predicate", v],
        None => ["--all"],
      },
    },
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let base := util.json_cmd(list.concat(["recall"], selector(args)))
  let cmd := match util.field_str(args, "limit") {
    None => base,
    Some(n) => list.concat(base, ["--limit", n]),
  }
  match proc.run("lex", cmd) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => match util.cli_result(out) {
      Err(detail) => Err(e.single("", "cli_failed", detail)),
      Ok(body) => Ok(JStr(body)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_recall", "Query the lex-vcs op log by intent id, session id, or predicate JSON (no selector => all ops). Answers 'everything done under intent/session X' — the op-log's memory surface beyond blame/log.", params(), execute)
}

