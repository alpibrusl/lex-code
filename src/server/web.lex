# web.lex — HTTP server for lex-code.
#
# Static files (src/web/) are served through the router.
# POST /a2a and GET /sessions are both intercepted before the router: the
# router's route handler type fixes its effect row exactly, and neither
# carries the effect these two need ([env] for /a2a's API key reads,
# [fs_walk] for /sessions' directory listing).
#
# Run:
#   lex run --allow-effects env,net,io,llm,proc,sql,fs_read,fs_write,time,crypto,random,concurrent \
#     src/server/web.lex serve_web
#
# Environment:
#   PORT    — HTTP port  (default: 7700)
#   WEB_DIR — static dir (default: src/web)

import "std.net" as net

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.env" as env

import "std.int" as int

import "std.time" as time

import "std.crypto" as crypto

import "lex-web/src/router" as router

import "lex-web/src/ctx" as ctx

import "lex-web/src/response" as resp

import "lex-web/src/static_files" as sf

import "lex-web/src/middleware" as mw

import "lex-schema/json_value" as jv

import "lex-llm/delta" as d

import "./session" as sess

import "./persist" as persist

import "std.sql" as sql

import "lex-trail/log" as trail_log

# ── Helpers ───────────────────────────────────────────────────────────────────
fn get_env_w(key :: Str, fallback :: Str) -> [env] Str {
  match env.get(key) {
    None => fallback,
    Some(v) => if str.is_empty(v) {
      fallback
    } else {
      v
    },
  }
}

fn parse_int_or_w(s :: Str, fallback :: Int) -> Int {
  match str.to_int(s) {
    Some(n) => n,
    None => fallback,
  }
}

fn mode_from_str(s :: Str) -> sess.AgentMode {
  if s == "plan" {
    Plan
  } else {
    if s == "explore" {
      Explore
    } else {
      if s == "refactor" {
        Refactor
      } else {
        if s == "spec" {
          Spec
        } else {
          if s == "test" {
            Test
          } else {
            if s == "review" {
              Review
            } else {
              if s == "bar" {
                Bar
              } else {
                Build
              }
            }
          }
        }
      }
    }
  }
}

fn get_nested_str(j :: jv.Json, parent_key :: Str, child_key :: Str) -> Str {
  match jv.get_field(j, parent_key) {
    None => "",
    Some(p) => match jv.get_field(p, child_key) {
      Some(JStr(s)) => s,
      _ => "",
    },
  }
}

fn extract_req_id(j :: jv.Json) -> Str {
  match jv.get_field(j, "id") {
    Some(JInt(n)) => int.to_str(n),
    Some(JStr(s)) => str.concat("\"", str.concat(s, "\"")),
    _ => "null",
  }
}

fn json_error(id :: Str, msg :: Str) -> Str {
  str.join(["{\"jsonrpc\":\"2.0\",\"id\":", id, ",\"error\":{\"code\":-32603,\"message\":", jv.stringify(JStr(msg)), "}}"], "")
}

fn with_cors(r :: resp.Response) -> resp.Response {
  resp.with_header(resp.with_header(resp.with_header(r, "Access-Control-Allow-Origin", "*"), "Access-Control-Allow-Methods", "GET,POST,OPTIONS"), "Access-Control-Allow-Headers", "content-type")
}

# ── Step → JSON ───────────────────────────────────────────────────────────────
type WebStep = { role :: Str, content :: Str }

type StepAcc = { web_steps :: List[WebStep], text_buf :: Str }

fn web_step_json(ws :: WebStep) -> Str {
  str.join(["{\"role\":", jv.stringify(JStr(ws.role)), ",\"content\":", jv.stringify(JStr(ws.content)), "}"], "")
}

fn flush_acc(a :: StepAcc) -> StepAcc {
  if str.is_empty(a.text_buf) {
    a
  } else {
    { web_steps: list.concat(a.web_steps, [{ role: "agent", content: a.text_buf }]), text_buf: "" }
  }
}

fn fold_step(a :: StepAcc, step :: d.Step) -> StepAcc {
  match step {
    StepDelta(delta) => match delta {
      TextChunk(t) => { web_steps: a.web_steps, text_buf: str.concat(a.text_buf, t) },
      _ => a,
    },
    StepToolExec(name, _) => {
      let flushed := flush_acc(a)
      { web_steps: list.concat(flushed.web_steps, [{ role: "tool", content: str.concat("[running: ", str.concat(name, "]")) }]), text_buf: "" }
    },
    StepToolResult(_, ok) => {
      let icon := if ok {
        "[ok]"
      } else {
        "[error]"
      }
      { web_steps: list.concat(a.web_steps, [{ role: "tool", content: icon }]), text_buf: a.text_buf }
    },
    StepDone(_) => flush_acc(a),
  }
}

fn steps_to_json(steps :: List[d.Step]) -> Str {
  let final := flush_acc(list.fold(steps, { web_steps: [], text_buf: "" }, fold_step))
  str.concat("[", str.concat(str.join(list.map(final.web_steps, web_step_json), ","), "]"))
}

# The client's session id, or a fresh one.
#
# `src/web/app.js` has always sent `params.session_id` and stored what came
# back; this handler minted a new id per request and ignored it, so every
# message started a new session and the page only looked conversational. #54
# derives a durable record per session, and the web client was throwing it
# away each turn.
#
# An id from the client is honoured as-is rather than checked against a
# registry of known sessions: `resume_session` derives the conversation from
# the log at `.lex/sessions/<id>.db`, and a log with no events derives an
# empty conversation. An unknown id is therefore a working empty session, not
# an error — one fewer failure mode, and the id is opaque to the server
# either way.
fn session_id_for(j :: jv.Json) -> [crypto, random] Str {
  let claimed := str.trim(get_nested_str(j, "params", "session_id"))
  if is_safe_id(claimed) {
    claimed
  } else {
    crypto.random_str_hex(8)
  }
}

# The id becomes a path: `.lex/sessions/<id>.db`. A client controls it, so
# anything but lowercase hex is refused and replaced with a fresh one —
# without this, `session_id: "../../etc/passwd"` picks the file the server
# opens. Length is bounded for the same reason.
fn is_safe_id(id :: Str) -> Bool
  examples {
    is_safe_id("a1b2c3d4") => true,
    is_safe_id("") => false,
    is_safe_id("../../etc/passwd") => false,
    is_safe_id("a1b2c3d4/x") => false,
    is_safe_id("A1B2C3D4") => false,
    is_safe_id("g1b2c3d4") => false,
    is_safe_id("0123456789012345678901234567890123456789012345678901234567890123456789") => false
  }
{
  let n := str.len(id)
  if n < 4 {
    false
  } else {
    if n > 64 {
      false
    } else {
      all_hex(id, 0)
    }
  }
}

fn all_hex(id :: Str, i :: Int) -> Bool {
  if i >= str.len(id) {
    true
  } else {
    if is_hex_char(str.char_at(id, i)) {
      all_hex(id, i + 1)
    } else {
      false
    }
  }
}

fn is_hex_char(c :: Str) -> Bool
  examples {
    is_hex_char("0") => true,
    is_hex_char("9") => true,
    is_hex_char("a") => true,
    is_hex_char("f") => true,
    is_hex_char("g") => false,
    is_hex_char("A") => false,
    is_hex_char("/") => false,
    is_hex_char(".") => false
  }
{
  match c {
    "0" => true,
    "1" => true,
    "2" => true,
    "3" => true,
    "4" => true,
    "5" => true,
    "6" => true,
    "7" => true,
    "8" => true,
    "9" => true,
    "a" => true,
    "b" => true,
    "c" => true,
    "d" => true,
    "e" => true,
    "f" => true,
    _ => false,
  }
}

# ── A2A handler (carries [env] — bypasses router) ─────────────────────────────
fn handle_a2a_body(body :: Str) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] resp.Response {
  match jv.parse(body) {
    Err(_) => resp.bad_request("invalid JSON"),
    Ok(j) => {
      let req_id := extract_req_id(j)
      let input := get_nested_str(j, "params", "input")
      let mode_str := get_nested_str(j, "params", "mode")
      let provider := get_nested_str(j, "params", "provider")
      let prov := if str.is_empty(provider) {
        "anthropic"
      } else {
        provider
      }
      let mode := mode_from_str(mode_str)
      let sid := session_id_for(j)
      if str.is_empty(input) {
        resp.json(json_error(req_id, "params.input is required"))
      } else {
        match sess.resume_session(sid, mode, prov) {
          Err(e) => resp.json(json_error(req_id, e)),
          Ok(session) => {
            let turn := sess.run_turn_with_provider(session, input, prov)
            let steps_json := steps_to_json(turn.steps)
            resp.json(str.join(["{\"jsonrpc\":\"2.0\",\"id\":", req_id, ",\"result\":{\"session_id\":", jv.stringify(JStr(sid)), ",\"steps\":", steps_json, "}}"], ""))
          },
        }
      }
    },
  }
}

# ── Live progress feed (GET /events) ─────────────────────────────────────────
# The trail that `run_turn_with_provider` writes lands in the session's
# persistent log (.lex/sessions/<id>.db) as it happens: a `cap.invoked`
# before every tool call and `cap.completed`/`cap.failed` after, plus the
# user/assistant message events. This endpoint tails that log — a second,
# read-only connection to the same db — so the browser can render the
# agent's tool-by-tool progress live while the /a2a turn is still running,
# instead of only seeing the buffered result at the end. Cursor is the
# monotonic rowid; the caller polls with the last `seq` it saw.
# Pull the tool name out of a cap.* payload by string-scanning the
# `"capability":"<name>"` field rather than parsing the whole payload:
# cap.completed / cap.failed splice the raw tool result/error in after it,
# which is often not valid JSON, so a full parse would fail and drop the
# label. The capability field is always the well-formed prefix.
fn extract_capability(payload :: Str) -> Str {
  let key := "\"capability\":\""
  match str.find(payload, key, 0) {
    None => "",
    Some(i) => {
      let rest := str.slice(payload, i + str.len(key), str.len(payload))
      match str.find(rest, "\"", 0) {
        None => "",
        Some(j) => str.slice(rest, 0, j),
      }
    },
  }
}

# cap.* → the tool name. A `*_message` event carries a well-formed
# {"role":..,"text":..} payload (valid JSON here, unlike cap.* payloads) —
# surface its text so a watcher sees the conversation, not just the feed.
fn event_label(kind :: Str, payload :: Str) -> Str {
  if str.starts_with(kind, "cap.") {
    extract_capability(payload)
  } else {
    if str.contains(kind, "_message") {
      match jv.parse(payload) {
        Err(_) => "",
        Ok(p) => match jv.get_field(p, "text") {
          Some(JStr(t)) => t,
          _ => "",
        },
      }
    } else {
      ""
    }
  }
}

fn jstr_or(obj :: jv.Json, key :: Str, fallback :: Str) -> Str {
  match jv.get_field(obj, key) {
    None => fallback,
    Some(v) => match jv.as_str(v) {
      Some(s) => s,
      None => fallback,
    },
  }
}

# For a `write`/`edit` call, the file-change data a diff view needs — the
# path plus either the new content (write) or the old/new strings (edit)
# — as its own well-formed JSON value, or the literal `null` when there is
# none to show.
#
# Only `cap.invoked` is ever parsed here. `cap.completed`/`cap.failed`
# splice the raw tool *result* in after the capability field (see
# `extract_capability` above), which is often not valid JSON; but
# `cap.invoked`'s payload is exactly `{"capability":..,"args":<the
# model's own tool-call JSON>}` — always well-formed, because it's what
# the provider's function-calling API sent, not a tool's freeform output.
fn write_edit_diff_json(kind :: Str, payload :: Str) -> Str
  examples {
    write_edit_diff_json("cap.completed", "{\"capability\":\"write\",\"result\":not json}") => "null",
    write_edit_diff_json("cap.invoked", "{\"capability\":\"read\",\"args\":{\"path\":\"x\"}}") => "null",
    write_edit_diff_json("cap.invoked", "{\"capability\":\"write\",\"args\":{\"path\":\"a.lex\",\"content\":\"fn f() {}\"}}") => "{\"kind\":\"write\",\"path\":\"a.lex\",\"new\":\"fn f() {}\"}",
    write_edit_diff_json("cap.invoked", "{\"capability\":\"edit\",\"args\":{\"path\":\"a.lex\",\"old_str\":\"1\",\"new_str\":\"2\"}}") => "{\"kind\":\"edit\",\"path\":\"a.lex\",\"old\":\"1\",\"new\":\"2\"}"
  }
{
  if kind != "cap.invoked" {
    "null"
  } else {
    match jv.parse(payload) {
      Err(_) => "null",
      Ok(p) => match (jv.get_field(p, "capability"), jv.get_field(p, "args")) {
        (Some(JStr(cap)), Some(args)) => if cap == "write" {
          jv.stringify(JObj([("kind", JStr("write")), ("path", JStr(jstr_or(args, "path", ""))), ("new", JStr(jstr_or(args, "content", "")))]))
        } else {
          if cap == "edit" {
            jv.stringify(JObj([("kind", JStr("edit")), ("path", JStr(jstr_or(args, "path", ""))), ("old", JStr(jstr_or(args, "old_str", ""))), ("new", JStr(jstr_or(args, "new_str", "")))]))
          } else {
            "null"
          }
        },
        _ => "null",
      },
    }
  }
}

fn event_to_json(r :: sql.Row) -> Str {
  let seq := match sql.get_int(r, "seq") {
    Some(n) => n,
    None => 0,
  }
  let kind := match sql.get_str(r, "kind") {
    Some(k) => k,
    None => "",
  }
  let payload := match sql.get_str(r, "payload_json") {
    Some(p) => p,
    None => "{}",
  }
  let ts := match sql.get_int(r, "ts_ms") {
    Some(t) => t,
    None => 0,
  }
  str.join(["{\"seq\":", int.to_str(seq), ",\"kind\":", jv.stringify(JStr(kind)), ",\"label\":", jv.stringify(JStr(event_label(kind, payload))), ",\"diff\":", write_edit_diff_json(kind, payload), ",\"ts\":", int.to_str(ts), "}"], "")
}

fn max_seq(rows :: List[sql.Row], start :: Int) -> Int {
  list.fold(rows, start, fn (acc :: Int, r :: sql.Row) -> Int {
    match sql.get_int(r, "seq") {
      Some(n) => if n > acc {
        n
      } else {
        acc
      },
      None => acc,
    }
  })
}

fn handle_events(sid :: Str, after :: Int) -> [sql, fs_read, fs_write] resp.Response {
  if not is_safe_id(sid) {
    resp.json("{\"events\":[],\"last\":0}")
  } else {
    match persist.open_persistent(sid) {
      Err(_) => resp.json("{\"events\":[],\"last\":0}"),
      Ok(log) => {
        let q := str.join(["SELECT rowid AS seq, kind, payload_json, ts_ms FROM events WHERE rowid > ", int.to_str(after), " ORDER BY rowid ASC LIMIT 300"], "")
        match trail_log.xquery(log.db, q, []) {
          Err(_) => resp.json("{\"events\":[],\"last\":0}"),
          Ok(rows) => {
            let items := str.join(list.map(rows, fn (r :: sql.Row) -> Str {
              event_to_json(r)
            }), ",")
            resp.json(str.join(["{\"events\":[", items, "],\"last\":", int.to_str(max_seq(rows, after)), "}"], ""))
          },
        }
      },
    }
  }
}

# ── Session listing (GET /sessions) — the web sidebar ────────────────────────
# A short, human-usable sidebar label: the session's first user message,
# trimmed and capped. A session with no messages yet (freshly opened, or a
# foreign/stray id under the directory) falls back to its own id, so no row
# is ever blank.
fn session_title(id :: Str, first_message :: Str) -> Str
  examples {
    session_title("abc", "please add gcd") => "please add gcd",
    session_title("abc", "   ") => "abc",
    session_title("abc", "") => "abc",
    session_title("abc", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890") => "0123456789012345678901234567890123456789012345678901234567890123456789012345678…"
  }
{
  let trimmed := str.trim(first_message)
  if str.is_empty(trimmed) {
    id
  } else {
    if str.len(trimmed) > 80 {
      str.concat(str.slice(trimmed, 0, 79), "…")
    } else {
      trimmed
    }
  }
}

# One entry of the sidebar, or "null" — for an id whose database could not
# be opened (removed by the sweep between the listing and this open, most
# likely), or one with no user message yet (opened but never talked to,
# not worth a row) — the caller filters those out either way.
#
# The title comes from the session's own first user message. Its payload is
# `{"role":"user","text":..}` — well-formed JSON, unlike a cap.* payload, the
# same fact `event_label` above already relies on for a `*_message` event.
# Queried inline, not through a helper that takes `log.db` as a parameter:
# its type is `lex-orm/connection`'s `ConnDb`, which would need importing a
# module solely to name — `trail_log.xquery` doesn't need it named, only in
# scope, exactly as `handle_events` above already relies on.
fn session_summary_json(id :: Str, last_ts :: Int) -> [sql, fs_read, fs_write] Str {
  match persist.open_persistent(id) {
    Err(_) => "null",
    Ok(log) => {
      let first_message := match trail_log.xquery(log.db, "SELECT payload_json FROM events WHERE kind='code.session.user_message' ORDER BY rowid ASC LIMIT 1", []) {
        Err(_) => "",
        Ok(rows) => match list.head(rows) {
          None => "",
          Some(r) => match sql.get_str(r, "payload_json") {
            None => "",
            Some(p) => match jv.parse(p) {
              Err(_) => "",
              Ok(j) => match jv.get_field(j, "text") {
                Some(JStr(t)) => t,
                _ => "",
              },
            },
          },
        },
      }
      if str.is_empty(str.trim(first_message)) {
        "null"
      } else {
        jv.stringify(JObj([("id", JStr(id)), ("title", JStr(session_title(id, first_message))), ("last_ts", JInt(last_ts))]))
      }
    },
  }
}

fn handle_sessions() -> [sql, fs_read, fs_walk, fs_write] resp.Response {
  let items := list.filter(list.map(persist.recent_sessions(), fn (p :: (Str, Int)) -> [sql, fs_read, fs_write] Str {
    match p {
      (id, last_ts) => session_summary_json(id, last_ts),
    }
  }), fn (s :: Str) -> Bool {
    s != "null"
  })
  resp.json(str.join(["{\"sessions\":[", str.join(items, ","), "]}"], ""))
}

# ── Static-only router (no [env] routes) ─────────────────────────────────────
# Every route on one `router.GenericRouter[e]` (lex-web#55), `e` inferred
# as this whole file's own wide effect row from the handlers registered
# below — including `/a2a` ([env], for API key reads) and `/sessions`
# ([fs_walk], for `persist.recent_sessions`'s directory listing), neither
# of which `router.Router`'s fixed `route_effectful` row can carry (rows
# unify by equality, not subtyping — lex-lang#756). No bypass: every
# request goes through `router.dispatch_generic`, including these two.
fn build_router[e](web_dir :: Str) -> [| e] router.GenericRouter[e] {
  let r0 := router.new_generic()
  let r1 := router.route_generic(r0, "GET", "/", fn (c :: ctx.Ctx) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    match io.read(str.concat(web_dir, "/index.html")) {
      Ok(html) => resp.html(html),
      Err(_) => resp.not_found(),
    }
  })
  let r2 := router.route_generic(r1, "GET", "/events", fn (c :: ctx.Ctx) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    let sid := ctx.query_param_or(c, "session", "")
    let after := parse_int_or_w(ctx.query_param_or(c, "after", "0"), 0)
    with_cors(handle_events(sid, after))
  })
  let r3 := router.route_generic(r2, "GET", "/sessions", fn (c :: ctx.Ctx) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    with_cors(handle_sessions())
  })
  let r4 := router.route_generic(r3, "POST", "/a2a", fn (c :: ctx.Ctx) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    with_cors(handle_a2a_body(c.body))
  })
  sf.mount_dir_generic(r4, "/", web_dir)
}

# `net.serve_fn`'s handler must be a NAMED top-level function here, not an
# inline lambda literal — found the hard way: an inline `fn (req) -> [...]
# Response { ... router.dispatch_generic(build_router(...), ...) ... }`
# passed directly as `net.serve_fn`'s second argument fails to type-check
# ("open effect row"), even with every row fully concrete and no genuine
# polymorphism left unresolved. `net.serve_fn` is itself effect-row
# polymorphic (`serve_fn[Eff] :: (Int, (Request) -> [Eff] Response) -> [net,
# Eff] Unit`, the same mechanism `list.map`'s own `E` uses) — the checker
# doesn't correctly compose that with a call to another row-polymorphic
# function from *inside* a lambda literal it is itself checking as the
# argument to a row-polymorphic HOF, regardless of naming or annotation.
# Extracting the handler to a name works because a named function is
# checked and generalized as its own scheme first, then referenced — never
# body-checked in place as part of `net.serve_fn`'s own call. Rebuilding
# the router per request is deliberate, not incidental to the fix: it's
# pure, in-memory route registration, cheap enough that "once at startup"
# would be premature optimisation, and it keeps `handle_request`'s
# signature an exact, plain `(Request) -> [...] Response` match for
# `net.serve_fn` — no captured router value, nothing for the checker to
# get confused about a second time.
fn handle_request(req :: Request) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] Response {
  let web_dir := get_env_w("WEB_DIR", "src/web")
  if req.method == "OPTIONS" {
    let rsp := with_cors(resp.no_content())
    { status: rsp.status, body: BodyStr(rsp.body), headers: rsp.headers }
  } else {
    let raw := { body: req.body, method: req.method, path: req.path, query: req.query, headers: req.headers }
    let rsp := router.dispatch_generic(build_router(web_dir), raw)
    { status: rsp.status, body: BodyStr(rsp.body), headers: rsp.headers }
  }
}

# ── Entry point ───────────────────────────────────────────────────────────────
fn serve_web() -> [env, net, io, llm, proc, sql, fs_read, fs_walk, fs_write, time, crypto, random, concurrent, approval] Unit {
  let port := parse_int_or_w(get_env_w("PORT", "7700"), 7700)
  let web_dir := get_env_w("WEB_DIR", "src/web")
  let swept := persist.sweep_old_sessions(time.now_ms())
  let __s := if swept > 0 {
    io.print(str.join(["[lex-code] swept ", int.to_str(swept), " session log(s) older than ", int.to_str(persist.max_session_age_days()), " days"], ""))
  } else {
    ()
  }
  let __p := io.print(str.join(["[lex-code] web on :", int.to_str(port), "  static=", web_dir], ""))
  net.serve_fn(port, handle_request)
}

