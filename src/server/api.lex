import "lex-agent/server" as a2a_srv

import "lex-agent/agent_card" as card

import "lex-agent/task" as atask

import "lex-spec/capability" as cap

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-agent/message" as amsg

import "./session" as sess

import "std.str" as str

import "std.list" as list

fn chat_capability() -> cap.Capability {
  cap.inbound("chat", "Send a message to lex-code and receive an assistant response.", { title: "ChatArgs", description: "", fields: [s.required_str("message", []), s.optional(s.required_str("mode", [])), s.optional(s.required_str("session_id", []))] })
}

fn mode_from_str(mode_str :: Str) -> sess.AgentMode {
  match mode_str {
    "plan" => Plan,
    "explore" => Explore,
    _ => Build,
  }
}

fn handle_chat(message :: amsg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] a2a_srv.HandlerOutcome {
  match list.head(message.parts) {
    Some(TextPart(text)) => match sess.new_session("api", Build) {
      Err(e) => { next_state: TSFailed, reply: Some(amsg.agent_text(str.concat("session error: ", e))), artifacts: [] },
      Ok(_) => { next_state: TSCompleted, reply: Some(amsg.agent_text(str.concat("received: ", text))), artifacts: [] },
    },
    _ => { next_state: TSCompleted, reply: Some(amsg.agent_text("expected a text message")), artifacts: [] },
  }
}

fn agent_def(base_url :: Str) -> a2a_srv.AgentDef {
  a2a_srv.make_agent_def(card.make("lex-code", "Lex-specialized coding assistant", "0.1.0", base_url, [chat_capability()]), [{ capability: chat_capability(), handle: handle_chat }])
}

