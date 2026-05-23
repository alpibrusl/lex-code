import "lex-agent/server" as a2a_srv

import "lex-agent/agent_card" as card

import "lex-agent/capability" as cap

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-llm/message" as msg

import "./session" as sess

import "std.str" as str

import "std.list" as list

fn chat_capability() -> cap.Capability {
  cap.inbound("chat", "Send a message to lex-code and receive an assistant response.", { title: "ChatArgs", description: "", fields: [s.required_str("message", []), s.optional_str("mode", []), s.optional_str("session_id", [])] })
}

fn mode_from_str(s :: Str) -> sess.AgentMode {
  match s {
    "plan" => sess.Plan,
    "explore" => sess.Explore,
    _ => sess.Build,
  }
}

fn handle_chat(message :: msg.Message) -> [net, llm, io, proc, sql, time] a2a_srv.HandlerOutcome {
  match message {
    UserMsg(text) => match sess.new_session("api", sess.Build) {
      Err(e) => { next_state: "failed", reply: Some(msg.user(str.concat("session error: ", e))), artifacts: [] },
      Ok(session) => { next_state: "completed", reply: Some(msg.user(match sess.find_done_msg(sess.run_turn(session, text).steps) {
        None => "(no response)",
        Some(m) => msg.content(m),
      })), artifacts: [] },
    },
    _ => { next_state: "completed", reply: Some(msg.user("expected a user message")), artifacts: [] },
  }
}

fn agent_def(base_url :: Str) -> a2a_srv.AgentDef {
  a2a_srv.make_agent_def(card.make("lex-code", "Lex-specialized coding assistant", "0.1.0", base_url, [chat_capability()]), [{ capability: chat_capability(), handle: handle_chat }])
}

