# lex-code — Agent Client Protocol (ACP) server — Phase 1
#
# The name "ACP" is taken twice in this space: BeeAI's REST-based Agent
# Communication Protocol is a different, unrelated standard (lex-code
# carried a sketch of a server for it until it was removed — it never
# had a listener). This file speaks Zed's Agent Client Protocol —
# JSON-RPC 2.0 over stdin/stdout, NDJSON-framed (one JSON object per
# line, no Content-Length headers). It's the protocol
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
# WIRE FORMAT: validated against the published ACP schema —
# `schema/schema.json` from @zed-industries/agent-client-protocol 0.4.5 —
# by driving this server over stdio and checking each frame it emits with a
# JSON Schema validator. `initialize`, `session/new`, `session/prompt` and
# every `session/update` variant below pass.
#
# That schema is also where three defects came from. There is no ACP v2:
# `PROTOCOL_VERSION = 1`, and this file used to answer `initialize` with 2.
# And `tool_call` requires `toolCallId` alongside `title`, `tool_call_update`
# requires it too — both were dropped here, so a real client had nothing to
# correlate a result with the call it belonged to. The id was never missing
# from the data: lex-llm puts it in `StepToolExec(name, id)` and
# `StepToolResult(id, ok)`, and this file was discarding it with `_`.
#
# What remains unvalidated is behaviour rather than shape: a schema says
# nothing about whether a client is happy with the ORDER of these frames, or
# with a turn that emits no tool_call_update for a call it announced. Running
# against Zed itself is still worth doing (#62) — but it is no longer the
# only way to catch a malformed frame, and the ones it would have caught
# first are fixed.
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
# Defaults to litellm rather than a cloud provider: build/plan/explore
# tolerate a local model fine, and litellm needs no API key to start a
# server with. review/bar (where a wrong answer is expensive) can be
# routed to a frontier model per-mode instead — see
# provider_tag_for_mode in mcp_main.lex (#116) / LEX_CODE_PROVIDER_<MODE>.
fn provider_tag_from_env() -> [env] Str {
  match env.get("LEX_CODE_PROVIDER") {
    Some(t) => pick(t, "litellm"),
    None => "litellm",
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
# ---- #107: route <think>...</think> to agent_thought_chunk -------------
#
# The real ACP schema (@zed-industries/agent-client-protocol 0.4.5,
# SessionUpdate) has a dedicated "agent_thought_chunk" kind, the same
# shape as "agent_message_chunk", for exactly this. Without routing, a
# reasoning model's raw <think>...</think> text streamed straight through
# as agent_message_chunk, so a real client had no way to tell an agent's
# internal reasoning from its actual answer — it would render the literal
# tags in the chat.
#
# The open/close tags can land in different TextChunks (confirmed live:
# one chunk was exactly "<think>Simple", the matching close arrived later
# merged into "</think>Done"), so routing needs state that survives
# across chunks within one turn — "am I currently inside a think block".
# Lex has no mutable locals, and the streaming callback's type is fixed at
# `(d.Step) -> [io] Unit` by session.lex's run_turn_streaming_with_provider
# (shared with mcp_main.lex, the TUI, and session.lex itself, so widening
# it here isn't an option) — no `sql` or `fs_write` reaches this closure,
# only `io`. So the state lives in a scratch file under /tmp, read and
# written with plain `io.read`/`io.write`, both already `[io]`.
type Segment = Thought(Str) | Msg(Str)

fn think_state_path(session_id :: Str) -> Str {
  str.concat("/tmp/lex-acp-think-", session_id)
}

fn think_get(session_id :: Str) -> [io] Bool {
  match io.read(think_state_path(session_id)) {
    Err(_) => false,
    Ok(content) => content == "1",
  }
}

fn think_set(session_id :: Str, v :: Bool) -> [io] Unit {
  let content := if v {
    "1"
  } else {
    "0"
  }
  let __r := io.write(think_state_path(session_id), content)
  ()
}

fn think_open_tag() -> Str {
  "<think>"
}

fn think_close_tag() -> Str {
  "</think>"
}

# Some providers (e.g. a chat template that already opens the reasoning
# block, plus the model itself emitting its own opening marker) double up
# <think> right at the start of a think block. Strip every such redundant
# leading marker so it never leaks into a thought chunk's text.
fn strip_leading_think_open(text :: Str) -> Str {
  match str.find(text, think_open_tag(), 0) {
    Some(0) => strip_leading_think_open(str.slice(text, str.len(think_open_tag()), str.len(text))),
    _ => text,
  }
}

# Splits text on <think>/</think> markers given whether the stream STARTS
# inside a think block, returning the ordered segments and whether it ENDS
# inside one (fed back in as the next chunk's starting state). Empty
# segments (a tag at the very start, or two tags back to back) are
# dropped rather than emitted as blank chunks.
fn split_think(text :: Str, in_think :: Bool) -> (List[Segment], Bool) {
  if str.is_empty(text) {
    ([], in_think)
  } else {
    if in_think {
      let stripped := strip_leading_think_open(text)
      if str.is_empty(stripped) {
        ([], true)
      } else {
        match str.find(stripped, think_close_tag(), 0) {
          None => ([Thought(stripped)], true),
          Some(idx) => {
            let before := str.slice(stripped, 0, idx)
            let after := str.slice(stripped, idx + str.len(think_close_tag()), str.len(stripped))
            match split_think(after, false) {
              (rest, final_state) => (list.concat(as_thought(before), rest), final_state),
            }
          },
        }
      }
    } else {
      match str.find(text, think_open_tag(), 0) {
        None => ([Msg(text)], false),
        Some(idx) => {
          let before := str.slice(text, 0, idx)
          let after := str.slice(text, idx + str.len(think_open_tag()), str.len(text))
          match split_think(after, true) {
            (rest, final_state) => (list.concat(as_msg(before), rest), final_state),
          }
        },
      }
    }
  }
}

fn as_thought(text :: Str) -> List[Segment] {
  if str.is_empty(text) {
    []
  } else {
    [Thought(text)]
  }
}

fn as_msg(text :: Str) -> List[Segment] {
  if str.is_empty(text) {
    []
  } else {
    [Msg(text)]
  }
}

fn segment_update(session_id :: Str, seg :: Segment) -> jv.Json {
  match seg {
    Thought(t) => session_update(session_id, "agent_thought_chunk", [("content", JObj([("type", JStr("text")), ("text", JStr(t))]))]),
    Msg(t) => session_update(session_id, "agent_message_chunk", [("content", JObj([("type", JStr("text")), ("text", JStr(t))]))]),
  }
}

fn emit_text(session_id :: Str, text :: Str) -> [io] Unit {
  match split_think(text, think_get(session_id)) {
    (segments, final_state) => {
      let __set := think_set(session_id, final_state)
      let __sent := list.map(segments, fn (seg :: Segment) -> [io] Unit {
        send(segment_update(session_id, seg))
      })
      ()
    },
  }
}

fn handle_step(session_id :: Str, step :: d.Step) -> [io] Unit {
  match step {
    StepDelta(delta) => handle_delta(session_id, delta),
    StepToolExec(name, call_id) => send(session_update(session_id, "tool_call", [("toolCallId", JStr(call_id)), ("title", JStr(name)), ("status", JStr("in_progress"))])),
    StepToolResult(call_id, ok) => send(session_update(session_id, "tool_call_update", [("toolCallId", JStr(call_id)), ("status", JStr(tool_status(ok)))])),
    StepDone(_) => (),
  }
}

fn tool_status(ok :: Bool) -> Str {
  if ok {
    "completed"
  } else {
    "failed"
  }
}

fn handle_delta(session_id :: Str, delta :: d.Delta) -> [io] Unit {
  match delta {
    TextChunk(text) => emit_text(session_id, text),
    ToolCallBegin(id, name) => send(session_update(session_id, "tool_call", [("toolCallId", JStr(id)), ("title", JStr(name)), ("status", JStr("pending"))])),
    ToolArgChunk(_, _) => (),
    FinishDelta(_) => (),
    UsageDelta(_, _, _) => (),
  }
}

fn session_update(session_id :: Str, kind :: Str, fields :: List[(Str, jv.Json)]) -> jv.Json {
  jrpc_notification("session/update", JObj([("sessionId", JStr(session_id)), ("update", JObj(list.concat([("sessionUpdate", JStr(kind))], fields)))]))
}

# ---- Method handlers ----------------------------------------------------
fn handle_initialize(id :: jv.Json) -> [io] Unit {
  send(jrpc_result(id, JObj([("protocolVersion", JInt(1)), ("agentCapabilities", JObj([("loadSession", JBool(false)), ("promptCapabilities", JObj([("image", JBool(false)), ("audio", JBool(false))]))]))])))
}

fn handle_session_new(id :: jv.Json, params :: jv.Json, registry :: Registry, provider_tag :: Str) -> [sql, fs_read, fs_walk, fs_write, crypto, random, io, time] Registry {
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

fn handle_session_prompt(id :: jv.Json, params :: jv.Json, registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_read, fs_walk, fs_write, time, approval, stream] Registry {
  let sid := str_field(params, "sessionId")
  let prompt := extract_prompt_text(params)
  match map.get(registry, sid) {
    None => {
      let __sent := send(jrpc_error(id, -32001, str.concat("unknown sessionId: ", sid)))
      registry
    },
    Some(session) => {
      let __reset := think_set(sid, false)
      let result := sess.run_turn_streaming_with_provider(session, prompt, provider_tag, fn (step :: d.Step) -> [io] Unit {
        handle_step(sid, step)
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
fn dispatch(line :: Str, registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, crypto, random, fs_read, fs_walk, fs_write, approval, stream] Registry {
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

fn serve(registry :: Registry, provider_tag :: Str) -> [env, net, llm, io, proc, sql, time, crypto, random, fs_read, fs_walk, fs_write, approval, stream] Nil {
  match io.readline() {
    None => (),
    Some(line) => if str.is_empty(str.trim(line)) {
      serve(registry, provider_tag)
    } else {
      serve(dispatch(line, registry, provider_tag), provider_tag)
    },
  }
}

fn main() -> [env, net, llm, io, proc, sql, time, crypto, random, fs_read, fs_walk, fs_write, approval, stream] Nil {
  serve(map.new(), provider_tag_from_env())
}

