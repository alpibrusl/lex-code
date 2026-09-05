# session_events — the session's durable conversation record (#54).
#
# Principle (from the deepseek-harness review): MODEL-VISIBLE MEANS LOGGED.
# Every message that reaches a provider request must be reconstructable from
# the lex-trail log alone. This module owns that vocabulary: two event kinds
# (`code.session.user_message`, `code.session.assistant_message`) whose
# payloads are proper lex-schema JSON — never string concatenation, so
# quotes, newlines and backslashes in message text round-trip losslessly,
# and tool calls are recorded, not dropped.
#
# `session_history(log)` is the projection: replaying those events oldest-
# first yields exactly the cross-turn context lex-code feeds the model (user
# inputs + final assistant messages — the same policy session.lex has always
# used, now derived instead of merely accumulated). A payload that fails to
# decode is an ERROR, not a skip: a reader that cannot reconstruct history
# must refuse rather than silently hand the model a different conversation
# than the record claims.
#
# run_turn (session.lex) checks the in-memory cache against this projection
# before every provider call and refuses the turn on divergence — the trail
# is hash-chained, so "what did the model see" is now an auditable fact.

import "lex-llm/message" as msg

import "lex-schema/json_value" as jv

import "lex-trail/log" as trail_log

import "lex-trail/event" as ev

import "std.list" as list

import "std.sql" as sql

import "std.str" as str

fn user_kind() -> Str
  examples {
    user_kind() => "code.session.user_message"
  }
{
  "code.session.user_message"
}

fn assistant_kind() -> Str
  examples {
    assistant_kind() => "code.session.assistant_message"
  }
{
  "code.session.assistant_message"
}

# ── Encoding ────────────────────────────────────────────────────────────────
fn tool_call_json(c :: msg.ToolCall) -> jv.Json {
  JObj([("id", JStr(c.id)), ("name", JStr(c.name)), ("args", c.args)])
}

# Total over the message type so any message has one canonical encoding —
# events only ever record user/assistant, but equality (below) compares via
# this same encoding and must handle whatever a conversation contains.
fn message_json(m :: msg.Message) -> jv.Json {
  match m {
    UserMsg(text) => JObj([("role", JStr("user")), ("text", JStr(text))]),
    SystemMsg(text) => JObj([("role", JStr("system")), ("text", JStr(text))]),
    AssistantMsg(text, calls) => JObj([("role", JStr("assistant")), ("text", JStr(text)), ("tool_calls", JList(list.map(calls, fn (c :: msg.ToolCall) -> jv.Json {
      tool_call_json(c)
    })))]),
    ToolMsg(call_id, content) => JObj([("role", JStr("tool")), ("call_id", JStr(call_id)), ("text", JStr(content))]),
  }
}

fn encode_message(m :: msg.Message) -> Str
  examples {
    encode_message(UserMsg("say \"hi\"")) => "{\"role\":\"user\",\"text\":\"say \\\"hi\\\"\"}",
    encode_message(AssistantMsg("done", [])) => "{\"role\":\"assistant\",\"text\":\"done\",\"tool_calls\":[]}"
  }
{
  jv.encode(message_json(m))
}

# ── Recording ───────────────────────────────────────────────────────────────
fn record_user(log :: trail_log.Log, text :: Str) -> [sql, time] Result[ev.Event, Str] {
  trail_log.append(log, user_kind(), None, encode_message(UserMsg(text)))
}

# Only an AssistantMsg is a valid assistant event; anything else is a caller
# bug and is refused rather than encoded as something it isn't.
fn record_assistant(log :: trail_log.Log, m :: msg.Message) -> [sql, time] Result[ev.Event, Str] {
  match m {
    AssistantMsg(_, _) => trail_log.append(log, assistant_kind(), None, encode_message(m)),
    _ => Err("record_assistant requires an AssistantMsg"),
  }
}

# ── Decoding ────────────────────────────────────────────────────────────────
fn json_str_field(j :: jv.Json, key :: Str) -> Result[Str, Str] {
  match jv.get_field(j, key) {
    Some(JStr(s)) => Ok(s),
    _ => Err(str.concat("missing or non-string field: ", key)),
  }
}

fn decode_tool_call(j :: jv.Json) -> Result[msg.ToolCall, Str] {
  match json_str_field(j, "id") {
    Err(e) => Err(e),
    Ok(id) => match json_str_field(j, "name") {
      Err(e) => Err(e),
      Ok(name) => match jv.get_field(j, "args") {
        None => Err("tool call missing args"),
        Some(args) => Ok({ id: id, name: name, args: args }),
      },
    },
  }
}

fn decode_tool_calls(items :: List[jv.Json]) -> Result[List[msg.ToolCall], Str] {
  list.fold(items, Ok([]), fn (acc :: Result[List[msg.ToolCall], Str], j :: jv.Json) -> Result[List[msg.ToolCall], Str] {
    match acc {
      Err(e) => Err(e),
      Ok(done) => match decode_tool_call(j) {
        Err(e) => Err(e),
        Ok(c) => Ok(list.concat(done, [c])),
      },
    }
  })
}

fn decode_message(payload_json :: Str) -> Result[msg.Message, Str] {
  match jv.parse(payload_json) {
    Err(_) => Err(str.concat("unparseable session event payload: ", payload_json)),
    Ok(j) => match json_str_field(j, "role") {
      Err(e) => Err(e),
      Ok(role) => match role {
        "user" => match json_str_field(j, "text") {
          Err(e) => Err(e),
          Ok(text) => Ok(UserMsg(text)),
        },
        "assistant" => match json_str_field(j, "text") {
          Err(e) => Err(e),
          Ok(text) => match jv.get_field(j, "tool_calls") {
            Some(JList(items)) => match decode_tool_calls(items) {
              Err(e) => Err(e),
              Ok(calls) => Ok(AssistantMsg(text, calls)),
            },
            _ => Err("assistant event missing tool_calls"),
          },
        },
        _ => Err(str.concat("unknown session event role: ", role)),
      },
    },
  }
}

# ── The projection ──────────────────────────────────────────────────────────
# Oldest-first by insertion order (rowid, not ts_ms: two events in the same
# millisecond must not reorder). Any undecodable payload fails the WHOLE
# derivation — refuse, don't skip.
fn session_history(log :: trail_log.Log) -> [sql] Result[List[msg.Message], Str] {
  let q := str.join(["SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE kind IN ('", user_kind(), "', '", assistant_kind(), "') ORDER BY rowid ASC"], "")
  match trail_log.xquery(log.db, q, []) {
    Err(e) => Err(e.message),
    Ok(rows) => {
      let events := list.map(rows, fn (r :: sql.Row) -> ev.Event {
        trail_log.decode_event_row(r)
      })
      list.fold(events, Ok([]), fn (acc :: Result[List[msg.Message], Str], evt :: ev.Event) -> Result[List[msg.Message], Str] {
        match acc {
          Err(e) => Err(e),
          Ok(done) => match decode_message(evt.payload_json) {
            Err(e) => Err(e),
            Ok(m) => Ok(list.concat(done, [m])),
          },
        }
      })
    },
  }
}

# A cheap alternative to session_history for the one thing session.lex's
# per-turn check actually needs to catch: finish_turn's own comment notes
# that a FAILED evs.record_assistant append is deliberately not patched
# over, so the in-memory cache and the trail silently disagree until the
# next turn's check refuses. That disagreement always shows up as a row
# count behind what the cache expects -- decoding every prior message's
# JSON to compare its *text* catches the same divergence but costs O(total
# history) per turn, which makes a long session O(n^2) overall. Reproduced
# live: a real multi-file package build hit the interpreter's step limit
# by turn ~46 purely from re-deriving an ever-growing history on every
# turn, independent of any one message being unusually large.
#
# This does not re-verify that already-recorded content hasn't silently
# changed underneath (the trail is append-only and nothing in this
# codebase ever updates or deletes an event row, so that risk is already
# assumed away elsewhere) -- only that nothing has gone missing.
# session_history itself is unchanged and still used where its full,
# content-verifying cost is paid once rather than per turn (session
# resumption, and its own tests).
fn event_count(log :: trail_log.Log) -> [sql] Result[Int, Str] {
  let q := str.join(["SELECT COUNT(*) AS n FROM events WHERE kind IN ('", user_kind(), "', '", assistant_kind(), "')"], "")
  match trail_log.xquery(log.db, q, []) {
    Err(e) => Err(e.message),
    Ok(rows) => match list.head(rows) {
      None => Ok(0),
      Some(r) => match sql.get_int(r, "n") {
        None => Ok(0),
        Some(n) => Ok(n),
      },
    },
  }
}

# ── Equality ────────────────────────────────────────────────────────────────
# Two histories are equal iff their canonical encodings are equal — the same
# encoder writes the events, so this is exact, not heuristic.
fn message_eq(a :: msg.Message, b :: msg.Message) -> Bool
  examples {
    message_eq(UserMsg("x"), UserMsg("x")) => true,
    message_eq(UserMsg("x"), UserMsg("y")) => false,
    message_eq(AssistantMsg("d", []), UserMsg("d")) => false
  }
{
  encode_message(a) == encode_message(b)
}

# Encoded JSON never contains a literal newline (escape_str escapes them),
# so a newline-joined encoding is an injective fingerprint of the history.
fn history_fingerprint(h :: List[msg.Message]) -> Str {
  str.join(list.map(h, fn (m :: msg.Message) -> Str {
    encode_message(m)
  }), "\n")
}

fn history_eq(a :: List[msg.Message], b :: List[msg.Message]) -> Bool
  examples {
    history_eq([], []) => true,
    history_eq([UserMsg("x")], [UserMsg("x")]) => true,
    history_eq([UserMsg("x")], []) => false,
    history_eq([UserMsg("x")], [UserMsg("y")]) => false
  }
{
  history_fingerprint(a) == history_fingerprint(b)
}

