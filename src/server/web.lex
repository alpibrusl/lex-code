# web.lex — HTTP server for lex-code.
#
# Static files (src/web/) are served through the router.
# POST /a2a is intercepted before the router so that it can carry the
# [env] effect needed by sess.run_turn_with_provider (API key reads).
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
  str.join(["{\"seq\":", int.to_str(seq), ",\"kind\":", jv.stringify(JStr(kind)), ",\"label\":", jv.stringify(JStr(event_label(kind, payload))), ",\"ts\":", int.to_str(ts), "}"], "")
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

# ── Static-only router (no [env] routes) ─────────────────────────────────────
fn build_static_router(web_dir :: Str) -> router.Router {
  let r0 := router.new()
  let r1 := router.route_effectful(r0, "GET", "/", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    match io.read(str.concat(web_dir, "/index.html")) {
      Ok(html) => resp.html(html),
      Err(_) => resp.not_found(),
    }
  })
  let r2 := router.route_effectful(r1, "GET", "/events", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, approval] resp.Response {
    let sid := ctx.query_param_or(c, "session", "")
    let after := parse_int_or_w(ctx.query_param_or(c, "after", "0"), 0)
    with_cors(handle_events(sid, after))
  })
  sf.mount_dir(r2, "/", web_dir)
}

# ── Entry point ───────────────────────────────────────────────────────────────
fn serve_web() -> [env, net, io, llm, proc, sql, fs_read, fs_walk, fs_write, time, crypto, random, concurrent, approval] Unit {
  let port := parse_int_or_w(get_env_w("PORT", "7700"), 7700)
  let web_dir := get_env_w("WEB_DIR", "src/web")
  let r := build_static_router(web_dir)
  let swept := persist.sweep_old_sessions(time.now_ms())
  let __s := if swept > 0 {
    io.print(str.join(["[lex-code] swept ", int.to_str(swept), " session log(s) older than ", int.to_str(persist.max_session_age_days()), " days"], ""))
  } else {
    ()
  }
  let __p := io.print(str.join(["[lex-code] web on :", int.to_str(port), "  static=", web_dir], ""))
  net.serve_fn(port, fn (req :: Request) -> [env, io, time, crypto, random, sql, fs_read, fs_walk, fs_write, net, concurrent, llm, proc, approval] Response {
    if req.method == "OPTIONS" {
      let rsp := with_cors(resp.no_content())
      { status: rsp.status, body: BodyStr(rsp.body), headers: rsp.headers }
    } else {
      if req.method == "POST" and req.path == "/a2a" {
        let rsp := with_cors(handle_a2a_body(req.body))
        { status: rsp.status, body: BodyStr(rsp.body), headers: rsp.headers }
      } else {
        let raw := { body: req.body, method: req.method, path: req.path, query: req.query, headers: req.headers }
        let rsp := router.dispatch(r, raw)
        { status: rsp.status, body: BodyStr(rsp.body), headers: rsp.headers }
      }
    }
  })
}

