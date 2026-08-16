# Tests for session_events (#54): the durable conversation record.
#
# The properties under test are the module's whole point:
#   1. LOSSLESS — quotes/newlines/backslashes and tool calls round-trip.
#   2. REFUSE, DON'T SKIP — an undecodable payload fails the derivation.
#   3. DESYNC IS DETECTABLE — history_eq catches a cache that diverges
#      from the trail-derived history.
#   4. FOREIGN KINDS STAY OUT — lex-llm's own trace events in the same log
#      never leak into the conversation projection.

import "lex-llm/message" as msg

import "lex-trail/log" as trail_log

import "std.crypto" as crypto

import "std.io" as io

import "std.list" as list

import "std.str" as str

import "../src/server/session_events" as evs

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn fresh_log() -> [sql, fs_write, random, crypto] Result[trail_log.Log, Str] {
  trail_log.open(str.join(["/tmp/lexcode-t-", crypto.random_str_hex(8), ".db"], ""))
}

fn test_roundtrip_lossless() -> [sql, fs_write, time, random, crypto] Result[Unit, Str] {
  match fresh_log() {
    Err(e) => Err(str.concat("open log: ", e)),
    Ok(log) => {
      let tricky := "say \"hi\",\nthen C:\\path\\to\\file"
      let call :: msg.ToolCall := { id: "c1", name: "lex_check", args: JObj([("file", JStr("src/x.lex"))]) }
      let __u := evs.record_user(log, tricky)
      let __a := evs.record_assistant(log, AssistantMsg("done \"ok\"", [call]))
      match evs.session_history(log) {
        Err(e) => Err(str.concat("derive: ", e)),
        Ok(hist) => check("tricky text and tool calls round-trip exactly", evs.history_eq(hist, [msg.user(tricky), AssistantMsg("done \"ok\"", [call])])),
      }
    },
  }
}

fn test_assistant_event_requires_assistant_msg() -> [sql, fs_write, time, random, crypto] Result[Unit, Str] {
  match fresh_log() {
    Err(e) => Err(str.concat("open log: ", e)),
    Ok(log) => match evs.record_assistant(log, UserMsg("not an assistant msg")) {
      Ok(_) => Err("recording a UserMsg as an assistant event must be refused"),
      Err(_) => Ok(()),
    },
  }
}

fn test_refuses_malformed_payload() -> [sql, fs_write, time, random, crypto] Result[Unit, Str] {
  match fresh_log() {
    Err(e) => Err(str.concat("open log: ", e)),
    Ok(log) => {
      let __u := evs.record_user(log, "fine")
      let __rogue := trail_log.append(log, evs.user_kind(), None, "{not json")
      match evs.session_history(log) {
        Ok(_) => Err("derivation over a malformed payload must refuse"),
        Err(e) => check(str.concat("refusal names the cause: ", e), str.contains(e, "unparseable")),
      }
    },
  }
}

fn test_desync_detectable() -> [sql, fs_write, time, random, crypto] Result[Unit, Str] {
  match fresh_log() {
    Err(e) => Err(str.concat("open log: ", e)),
    Ok(log) => {
      let __u := evs.record_user(log, "turn one")
      let __a := evs.record_assistant(log, AssistantMsg("reply one", []))
      match evs.session_history(log) {
        Err(e) => Err(str.concat("derive: ", e)),
        Ok(hist) => {
          let stale := evs.history_eq(hist, [msg.user("turn one")])
          let tampered := evs.history_eq(hist, [msg.user("turn one"), AssistantMsg("a different reply", [])])
          let intact := evs.history_eq(hist, [msg.user("turn one"), AssistantMsg("reply one", [])])
          check("desync detection: missing/tampered rejected, intact accepted", not stale and not tampered and intact)
        },
      }
    },
  }
}

fn test_projection_ignores_foreign_kinds() -> [sql, fs_write, time, random, crypto] Result[Unit, Str] {
  match fresh_log() {
    Err(e) => Err(str.concat("open log: ", e)),
    Ok(log) => {
      let __s := trail_log.append(log, "llm.step", None, "{\"model\":\"m\"}")
      let __u := evs.record_user(log, "hello")
      match evs.session_history(log) {
        Err(e) => Err(str.concat("derive: ", e)),
        Ok(hist) => check("only session-event kinds project into history", evs.history_eq(hist, [msg.user("hello")])),
      }
    },
  }
}

fn suite() -> [sql, fs_write, time, random, crypto] List[Result[Unit, Str]] {
  [test_roundtrip_lossless(), test_assistant_event_requires_assistant_msg(), test_refuses_malformed_payload(), test_desync_detectable(), test_projection_ignores_foreign_kinds()]
}

fn run_all() -> [io, sql, fs_write, time, random, crypto] Unit {
  let results := suite()
  let __dbg := list.map(results, fn (r :: Result[Unit, Str]) -> [io] Unit {
    match r {
      Ok(_) => (),
      Err(e) => io.print(str.concat("FAIL: ", e)),
    }
  })
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __force_fail := 1 / 0
    ()
  }
}

