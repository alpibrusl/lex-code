import "lex-agent/acp_server" as acp

import "./session" as sess

import "lex-llm/message" as msg

import "std.str" as str

fn handle_run(body :: Str, provider_tag :: Str) -> [env, net, llm, io, proc, sql, fs_write, time, approval] Str {
  match acp.parse_run_request(body) {
    Err(e) => acp.run_response_error("", "lex-code", str.concat("bad request: ", e)),
    Ok(input) => match sess.new_session_with_provider("acp", Build, provider_tag) {
      Err(e) => acp.run_response_error("", "lex-code", str.concat("session error: ", e)),
      Ok(session) => {
        let result := sess.run_turn_with_provider(session, input, provider_tag)
        let reply := match sess.find_done_msg(result.steps) {
          None => "(no response)",
          Some(m) => msg.content(m),
        }
        acp.run_response_ok("run-1", "lex-code", reply)
      },
    },
  }
}

