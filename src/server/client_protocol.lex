# lex-code — Agent Client Protocol (ACP) server — Phase 1
#
# NOT the same protocol as src/server/acp.lex, which speaks BeeAI's
# REST-based Agent Communication Protocol. This file speaks Zed's Agent
# Client Protocol — JSON-RPC 2.0 over stdin/stdout, NDJSON-framed (one
# JSON object per line, no Content-Length headers). It's the protocol
# editors use to launch and drive a coding agent as a subprocess: Zed,
# JetBrains (IntelliJ/PyCharm/GoLand/WebStorm), Neovim, and Emacs all
# support it, and opencode is one of the agents already listed in the
# shared ACP Registry (zed.dev/blog/acp-registry). See zed.dev/acp for
# the protocol itself.
#
# Phase 1 (this file): initialize, session/new, session/prompt (with
# streaming session/update notifications), session/close.
#
# Deliberately NOT yet implemented — see the scoping discussion, not
# silently skipped:
#   - session/request_permission: today's permission_spec is a static
#     filter at agent construction (src/permissions/rules.lex), not an
#     interactive round-trip. Wiring this in changes when/how that
#     check fires, not just adding a handler.
#   - $/cancel_request: the current turn loop is one blocking call to
#     completion or max_steps. Honoring a cancel notification that
#     arrives mid-turn needs the turn running as a std.conc actor (the
#     same pattern src/server/multi_agent.lex already uses for
#     --multi) so the stdin-read loop stays free to receive it.
#   - fs/* and terminal/*: optional in ACP — an agent may still touch
#     the filesystem/shell directly if it declares that capability,
#     which is what lex-code's own read_file/write_file/bash tools
#     already do. Skipped for Phase 1, not required for correctness.
#   - auth/login / auth/logout: lex-code reads provider keys from the
#     environment at launch; no interactive auth flow exists to wire.
#
# WIRE-FORMAT CAVEAT: the exact field names below (sessionId,
# protocolVersion, the session/update variant shapes) are this file's
# best-effort reconstruction of the ACP v2 schema from available
# documentation — not a byte-for-byte trace against a reference SDK.
# Validate against a real client (e.g. Zed) before relying on this for
# production interop; the JSON-RPC 2.0 envelope and NDJSON framing
# themselves are unambiguous and were verified directly.
#
# CRITICAL: once serve() starts, stdout carries ONLY protocol frames.
# Unlike mcp_main.lex, there is deliberately no startup banner — any
# non-protocol byte on stdout corrupts the stream from the client's
# point of view.
#
# Run (an editor would spawn this same command as a subprocess):
#   LEX_CODE_PROVIDER=anthropic ANTHROPIC_API_KEY=… \
#     lex run --allow-effects env,io,net,llm,proc,sql,fs_write,time,crypto,random,approval \
#     src/server/client_protocol.lex main

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.map" as map

import "std.env" as env

import "std.crypto" as crypto

import "lex-schema/json_value" as jv

import "lex-llm/delta" as d

import "./session" as sess

type Registry = Map[Str, sess.Session]

fn pick(cur :: Str, fallback :: Str) -> Str {
  if str.is_empty(cur) {
    fallback
  } else {
    cur
  }
}

# Same env-var convention as src/server/mcp_main.lex's provider_tag_from_env
# — provider is a launch-time choice for a long-running server, not a
# per-call argument.
fn provider_tag_from_env() -> [env] Str {
  match env.get("LEX_CODE_PROVIDER") {
    Some(t) => pick(t, "anthropic"),
    None => "anthropic",
  }
}

# ---- JSON-RPC envelope -----------------------------------------------
fn jrpc_result(id :: jv.Json, result :: jv.Json) -> jv.Json {
  JObj([("jsonrpc", JStr("2.0")), ("id", id), ("result", result)])
}

fn jrpc_error(id :: jv.Json, code :: Int, message :: Str) -> jv.Json {
  JObj([("jsonrpc", JStr("2.0")), ("id", id), ("error", JObj([("code", JInt(code)), ("message", JStr(message))]))])
}

fn jrpc_notification(method :: Str, params :: jv.Json) -> jv.Json {
  JObj([("jsonrpc", JStr("2.0")), ("method", JStr(method)), ("params", params)])
}

fn send(j :: jv.Json) -> [io] Unit {
  io.print(jv.stringify(j))
}

fn req_id(req :: jv.Json) -> jv.Json {
  match jv.get_field(req, "id") {
    Some(i) => i,
    None => JNull,
  }
}

fn req_method(req :: jv.Json) -> Str {
  match jv.get_field(req, "method") {
    Some(JStr(m)) => m,
    _ => "",
  }
}

fn req_params(req :: jv.Json) -> jv.Json {
  match jv.get_field(req, "params") {
    Some(p) => p,
    None => JObj([]),
  }
}

fn str_field(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    Some(JStr(s)) => s,
    _ => "",
  }
}

# ---- Step -> session/update translation --------------------------------
# Best-effort mapping onto ACP's session/update "sessionUpdate" variants;
# see the wire-format caveat above. Covers the two updates a human (or an
# editor's chat panel) actually needs to see live: assistant text and tool
# call lifecycle. ToolArgChunk/UsageDelta/StepDone produce no visible update
# (StepDone's content lands in the final session/prompt response instead).
fn step_to_update(session_id :: Str, step :: d.Step) -> Option[jv.Json] {
  match step {
    StepDelta(delta) => delta_to_update(session_id, delta),
    StepToolExec(name, _) => Some(session_update(session_id, "tool_call", [("title", JStr(name)), ("status", JStr("in_progress"))])),
    StepToolResult(_, ok) => Some(session_update(session_id, "tool_call_update", [("status", JStr(tool_status(ok)))])),
    StepDone(_) => None,
  }
}

fn tool_status(ok :: Bool) -> Str {
  if ok {
    "completed"
  } else {
    "failed"
  }
}

fn delta_to_update(session_id :: Str, delta :: d.Delta) -> Option[jv.Json] {
  match delta {
    TextChunk(text) => Some(session_update(session_id, "agent_message_chunk", [("content", JObj([("type", JStr("text")), ("text", JStr(text))]))])),
    ToolCallBegin(id, name) => Some(session_update(session_id, "tool_call", [("toolCallId", JStr(id)), ("title", JStr(name)), ("status", JStr("pending"))])),
    ToolArgChunk(_, _) => None,
    FinishDelta(_) => None,
    UsageDelta(_, _, _) => None,
  }
}

fn session_update(session_id :: Str, kind :: Str, fields :: List[(Str, jv.Json)]) -> jv.Json {
  jrpc_notification("session/update", JObj([("sessionId", JStr(session_id)), ("update", JObj(list.concat([("sessionUpdate", JStr(kind))], fields)))]))
}

# ---- Method handlers ----------------------------------------------------
fn handle_initialize(id :: jv.Json) -> [io] Unit {
  send(jrpc_result(id, JObj([("protocolVersion", JInt(2)), ("agentCapabilities", JObj([("loadSession", JBool(false)), ("promptCapabilities", JObj([("image", JBool(false)), ("audio", JBool(false))]))]))])))
}

fn handle_session_new(id :: jv.Json, params :: jv.Json, registry :: Registry, provider_tag :: Str) -> [sql, fs_write, crypto, random, io] Registry {
  let sid := crypto.random_str_hex(16)
  match sess.new_session_with_provider(sid, Build, provider_tag) {
    Err(e) => {
      let __sent := send(jrpc_error(id, -32000, str.concat("session/new failed: ", e)))
      registry
    },
    Ok(s) => {
      let __sent := send(jrpc_result(id, JObj([("sessionId", JStr(sid))])))
      map.set(registry, sid, s)
    },
  }
}

fn handle_session_prompt(id :: jv.Json, params :: jv.Json, registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, approval] Registry {
  let sid := str_field(params, "sessionId")
  let prompt := extract_prompt_text(params)
  match map.get(registry, sid) {
    None => {
      let __sent := send(jrpc_error(id, -32001, str.concat("unknown sessionId: ", sid)))
      registry
    },
    Some(session) => {
      let result := sess.run_turn_streaming_with_provider(session, prompt, provider_tag, fn (step :: d.Step) -> [io] Unit {
        match step_to_update(sid, step) {
          None => (),
          Some(update) => send(update),
        }
      })
      let __sent := send(jrpc_result(id, JObj([("stopReason", JStr("end_turn"))])))
      map.set(registry, sid, result.session)
    },
  }
}

# ACP's prompt param is a list of content blocks (usually one {"type":"text",
# "text":...}); concatenate any text blocks so a multi-block prompt still
# reaches the agent as one turn instead of silently dropping blocks 2..n.
fn extract_prompt_text(params :: jv.Json) -> Str {
  match jv.get_field(params, "prompt") {
    Some(JList(blocks)) => str.join(list.map(blocks, block_text), ""),
    _ => "",
  }
}

fn block_text(block :: jv.Json) -> Str {
  str_field(block, "text")
}

fn handle_session_close(id :: jv.Json, params :: jv.Json, registry :: Registry) -> [io] Registry {
  let sid := str_field(params, "sessionId")
  let __sent := send(jrpc_result(id, JObj([])))
  map.delete(registry, sid)
}

# ---- Dispatch + main loop ------------------------------------------------
fn dispatch(line :: Str, registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, crypto, random, fs_write, approval] Registry {
  match jv.parse_into_errors(line) {
    Err(_) => {
      let __sent := send(jrpc_error(JNull, -32700, "parse error"))
      registry
    },
    Ok(req) => {
      let id := req_id(req)
      match req_method(req) {
        "initialize" => {
          let __sent := handle_initialize(id)
          registry
        },
        "session/new" => handle_session_new(id, req_params(req), registry, provider_tag),
        "session/prompt" => handle_session_prompt(id, req_params(req), registry, provider_tag),
        "session/close" => handle_session_close(id, req_params(req), registry),
        "" => registry,
        other => {
          let __sent := send(jrpc_error(id, -32601, str.concat("method not found: ", other)))
          registry
        },
      }
    },
  }
}

fn serve(registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, crypto, random, fs_write, approval] Nil {
  match io.readline() {
    None => (),
    Some(line) => if str.is_empty(str.trim(line)) {
      serve(registry, provider_tag)
    } else {
      serve(dispatch(line, registry, provider_tag), provider_tag)
    },
  }
}

fn main() -> [env, net, llm, io, proc, sql, time, crypto, random, fs_write, approval] Nil {
  serve(map.new(), provider_tag_from_env())
}

