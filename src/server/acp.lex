# ACP (Agent Communication Protocol) server for lex-code.
#
# Endpoints:
#   GET  /            — agent info JSON
#   POST /runs        — sync run: one turn, returns JSON
#   POST /runs/stream — streaming run: SSE events
#
# Run with:
#   lex run src/server/acp.lex
#
# Test:
#   curl -X POST http://localhost:8080/runs \
#     -H 'Content-Type: application/json' \
#     -d '{"input":[{"role":"user","content":[{"type":"text","text":"write list.zip"}]}]}'

import "lex-agent/acp_server" as acp
import "lex-llm/message"      as msg

import "std.str"  as str

import "./session" as sess

let agent_id := "lex-code"
let version  := "0.4.0"

fn info(base_url :: Str) -> Str {
  acp.agent_info_json({
    name:        agent_id,
    description: "Lex-specialized coding assistant",
    version:     version,
    url:         base_url,
  })
}

# Synchronous run — one session turn, returns completed JSON.
fn handle_run(body :: Str) -> [net, llm, io, proc, sql, time] Str {
  let run_id := msg.gen_message_id()
  match acp.parse_run_request(body) {
    Err(e)   => acp.run_response_error(run_id, agent_id, e),
    Ok(text) =>
      if str.is_empty(text) then
        acp.run_response_error(run_id, agent_id, "empty input")
      else
        match sess.new_session("acp", sess.Build) {
          Err(e)      =>
            acp.run_response_error(run_id, agent_id, str.concat("session error: ", e)),
          Ok(session) =>
            let result := sess.run_turn(session, text)
            let reply  := match sess.find_done_msg(result.steps) {
              None    => "(no response)",
              Some(m) => msg.content(m),
            }
            acp.run_response_ok(run_id, agent_id, reply),
        },
  }
}

# Streaming run — emits SSE frames: run.started → run.completed (or run.failed).
# The session runs synchronously; true delta streaming can be layered later
# by passing step deltas through sse_text_chunk_frame as they arrive.
fn handle_run_stream(body :: Str) -> [net, llm, io, proc, sql, time] Str {
  let run_id  := msg.gen_message_id()
  let started := acp.sse_started_frame(run_id)
  match acp.parse_run_request(body) {
    Err(e)   =>
      str.concat(started, acp.sse_error_frame(run_id, agent_id, e)),
    Ok(text) =>
      if str.is_empty(text) then
        str.concat(started, acp.sse_error_frame(run_id, agent_id, "empty input"))
      else
        match sess.new_session("acp-stream", sess.Build) {
          Err(e)      =>
            str.concat(started,
              acp.sse_error_frame(run_id, agent_id, str.concat("session error: ", e))),
          Ok(session) =>
            let result := sess.run_turn(session, text)
            let reply  := match sess.find_done_msg(result.steps) {
              None    => "(no response)",
              Some(m) => msg.content(m),
            }
            str.concat(started, acp.sse_completed_frame(run_id, agent_id, reply)),
        },
  }
}
