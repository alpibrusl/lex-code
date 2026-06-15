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

import "std.crypto" as crypto

import "lex-web/src/router" as router

import "lex-web/src/ctx" as ctx

import "lex-web/src/response" as resp

import "lex-web/src/static_files" as sf

import "lex-web/src/middleware" as mw

import "lex-schema/json_value" as jv

import "lex-llm/delta" as d

import "./session" as sess

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
              Build
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

# ── A2A handler (carries [env] — bypasses router) ─────────────────────────────
fn handle_a2a_body(body :: Str) -> [env, io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
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
      let sid := crypto.random_str_hex(8)
      if str.is_empty(input) {
        resp.json(json_error(req_id, "params.input is required"))
      } else {
        match sess.new_session_with_provider(sid, mode, prov) {
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

# ── Static-only router (no [env] routes) ─────────────────────────────────────
fn build_static_router(web_dir :: Str) -> router.Router {
  let r0 := router.new()
  let r1 := router.route_effectful(r0, "GET", "/", fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] resp.Response {
    match io.read(str.concat(web_dir, "/index.html")) {
      Ok(html) => resp.html(html),
      Err(_) => resp.not_found(),
    }
  })
  sf.mount_dir(r1, "/", web_dir)
}

# ── Entry point ───────────────────────────────────────────────────────────────
fn serve_web() -> [env, net, io, llm, proc, sql, fs_read, fs_write, time, crypto, random, concurrent] Unit {
  let port := parse_int_or_w(get_env_w("PORT", "7700"), 7700)
  let web_dir := get_env_w("WEB_DIR", "src/web")
  let r := build_static_router(web_dir)
  let __p := io.print(str.join(["[lex-code] web on :", int.to_str(port), "  static=", web_dir], ""))
  net.serve_fn(port, fn (req :: Request) -> [env, io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Response {
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

