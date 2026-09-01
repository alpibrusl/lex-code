# lex-code — verification evidence that outlives the session that produced it
#
# lex-llm's `dispatch_one_traced` already writes a `verified.type_check`,
# `verified.spec_check` or `verified.test` event when a verification tool's
# own output says it passed. That is the right shape — the loop reads the
# tool's result rather than asking the model to assert it, so the model
# cannot attest to a check it never ran.
#
# It writes them into the SESSION log, which is where the gap is. #32 wants
# attestations that "replace human code review", and evidence scoped to one
# session cannot: a review agent in a later session opens a different
# database and finds nothing. Verification is a property of the project, so
# the record has to be too.
#
# ---- why a file rather than a table ---------------------------------
#
# Because a tool has to read it. `Tool.execute` is fixed at
# `[net, io, proc]` — no `sql` — so `attestation_query` cannot open a
# database. The same wall that stops `remember` from writing memory stops a
# query tool from reading a trail. A JSONL file under `.lex/` is what both
# sides can reach: `[sql, time]` writes it at turn end, `[io]` reads it back.
#
# Append-only and never rewritten. Evidence that a check passed at 10:03 does
# not stop being true at 11:00; what changes is whether it still applies to
# the current code, which is what `sig` is for.

import "lex-trail/log" as trail_log

import "lex-trail/event" as ev

import "lex-schema/json_value" as jv

import "std.io" as io

import "std.str" as str

import "std.list" as list

type Record = { kind :: Str, tool :: Str, target :: Str, ts_ms :: Int }

fn path() -> Str
  examples {
    path() => ".lex/verified.jsonl"
  }
{
  ".lex/verified.jsonl"
}

# The event kinds lex-llm writes when a verification tool reports a pass.
fn verified_kinds() -> List[Str]
  examples {
    verified_kinds() => ["verified.type_check", "verified.spec_check", "verified.test"]
  }
{
  ["verified.type_check", "verified.spec_check", "verified.test"]
}

fn is_verified_kind(kind :: Str) -> Bool
  examples {
    is_verified_kind("verified.type_check") => true,
    is_verified_kind("verified.test") => true,
    is_verified_kind("cap.completed") => false,
    is_verified_kind("verified") => false,
    is_verified_kind("") => false
  }
{
  list.fold(verified_kinds(), false, fn (acc :: Bool, k :: Str) -> Bool {
    if acc {
      true
    } else {
      k == kind
    }
  })
}

fn encode(r :: Record) -> Str
  examples {
    encode({ kind: "verified.type_check", tool: "lex_check", target: "src/a.lex", ts_ms: 17 }) => "{\"kind\":\"verified.type_check\",\"tool\":\"lex_check\",\"target\":\"src/a.lex\",\"ts_ms\":17}"
  }
{
  jv.stringify(JObj([("kind", JStr(r.kind)), ("tool", JStr(r.tool)), ("target", JStr(r.target)), ("ts_ms", JInt(r.ts_ms))]))
}

fn decode(line :: Str) -> Option[Record] {
  match jv.parse_into_errors(str.trim(line)) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "kind") {
      Some(JStr(k)) => Some({ kind: k, tool: str_field(j, "tool"), target: str_field(j, "target"), ts_ms: int_field(j, "ts_ms") }),
      _ => None,
    },
  }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

fn int_field(j :: jv.Json, name :: Str) -> Int {
  match jv.get_field(j, name) {
    Some(JInt(n)) => n,
    _ => 0,
  }
}

# One pass, from the event payload lex-llm writes:
#
#   {"tool":"lex_check","target":"src/list.lex","result":"pass"}
#
# This used to store the TOOL under `target`, because the payload carried
# nothing else. The comment here claimed the loop could not see the tool's
# arguments and that naming the file would need them threaded through
# lex-llm's dispatch. That was wrong on both counts: `call.args_raw` sits
# two lines above the write, and the fix was one field
# (alpibrusl/lex-llm#48).
#
# `target` is the tool's `path` argument, so it names a FILE or directory,
# not a function — `lex check src/list.lex` says nothing about which
# function in it. Empty means the tool was called with no path and the
# pass covers the whole project.
#
# Records written before lex-llm#48 decode with an empty `tool` and the
# tool name in `target`. They are historical and simply less precise;
# nothing rewrites them, because a record is evidence of what was observed
# at the time.
fn record_of(e :: ev.Event) -> Option[Record]
  examples {
    record_of({ id: "x", kind: "verified.type_check", parent: None, payload_json: "{\"tool\":\"lex_check\",\"target\":\"src/a.lex\",\"result\":\"pass\"}", ts_ms: 7 }) => Some({ kind: "verified.type_check", tool: "lex_check", target: "src/a.lex", ts_ms: 7 }),
    record_of({ id: "x", kind: "verified.test", parent: None, payload_json: "{\"tool\":\"lex_test\",\"result\":\"pass\"}", ts_ms: 8 }) => Some({ kind: "verified.test", tool: "lex_test", target: "", ts_ms: 8 }),
    record_of({ id: "x", kind: "cap.completed", parent: None, payload_json: "{}", ts_ms: 9 }) => None
  }
{
  if is_verified_kind(e.kind) {
    match jv.parse_into_errors(e.payload_json) {
      Err(_) => None,
      Ok(j) => Some({ kind: e.kind, tool: str_field(j, "tool"), target: str_field(j, "target"), ts_ms: e.ts_ms }),
    }
  } else {
    None
  }
}

# Copy this turn's verification passes out of the session log.
#
# `since_ms` bounds it to the turn that just ran, so a long session does not
# re-append every earlier pass on every turn. A duplicate would not be wrong
# — the same check really did pass twice — but it would bury the file.
fn harvest(log :: trail_log.Log, since_ms :: Int, now_ms :: Int) -> [sql] List[Record] {
  match trail_log.range(log, since_ms, now_ms) {
    Err(_) => [],
    Ok(events) => list.fold(events, [], fn (acc :: List[Record], e :: ev.Event) -> List[Record] {
      match record_of(e) {
        None => acc,
        Some(r) => list.concat(acc, [r]),
      }
    }),
  }
}

fn append_all(records :: List[Record]) -> [io] Int {
  if list.is_empty(records) {
    0
  } else {
    let prev := match io.read(path()) {
      Ok(s) => s,
      Err(_) => "",
    }
    let lines := str.join(list.map(records, encode), "\n")
    match io.write(path(), str.join([prev, lines, "\n"], "")) {
      Err(_) => 0,
      Ok(_) => list.len(records),
    }
  }
}

fn all() -> [io] List[Record] {
  match io.read(path()) {
    Err(_) => [],
    Ok(content) => list.fold(str.split(content, "\n"), [], fn (acc :: List[Record], line :: Str) -> List[Record] {
      match decode(line) {
        None => acc,
        Some(r) => list.concat(acc, [r]),
      }
    }),
  }
}

# An empty target is rendered as what it means — the whole project — not
# as a blank, so a reader is never left guessing whether the scope is
# missing or unbounded.
fn scope_of(r :: Record) -> Str
  examples {
    scope_of({ kind: "k", tool: "lex_check", target: "src/a.lex", ts_ms: 1 }) => "src/a.lex",
    scope_of({ kind: "k", tool: "lex_check", target: "", ts_ms: 1 }) => "the whole project",
    scope_of({ kind: "k", tool: "", target: "lex_check", ts_ms: 1 }) => "lex_check"
  }
{
  if str.is_empty(r.target) {
    "the whole project"
  } else {
    r.target
  }
}

fn render(records :: List[Record]) -> Str
  examples {
    render([]) => "",
    render([{ kind: "verified.type_check", tool: "lex_check", target: "src/a.lex", ts_ms: 17 }]) => "- verified.type_check on src/a.lex (lex_check)",
    render([{ kind: "verified.test", tool: "", target: "", ts_ms: 1 }]) => "- verified.test on the whole project"
  }
{
  str.join(list.map(records, fn (r :: Record) -> Str {
    if str.is_empty(r.tool) {
      str.join(["- ", r.kind, " on ", scope_of(r)], "")
    } else {
      str.join(["- ", r.kind, " on ", scope_of(r), " (", r.tool, ")"], "")
    }
  }), "\n")
}

