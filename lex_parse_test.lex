import "lex-schema/json_value" as jv
import "std.http" as http
import "std.iter" as iter
import "std.list" as list
import "std.str"  as str
import "std.io"   as io
import "std.map"  as map
import "std.int"  as int

import "./src/prompts/build" as bp

fn main() -> [net, io] Nil {
  let sys := bp.system()
  io.print(str.concat("system_prompt_chars=", int.to_str(str.len(sys))))
  let body_parts := [
    "{\"model\":\"mistral-small:latest\",\"stream\":true,\"messages\":[{\"role\":\"system\",\"content\":",
    jv.stringify(JStr(sys)),
    "},{\"role\":\"user\",\"content\":\"write a pure Lex function that computes the nth Fibonacci number recursively, with examples\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"write\",\"description\":\"Write content to a file\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"lex_check\",\"description\":\"Type-check Lex files\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[]}}}]}",
  ]
  let body := str.join(body_parts, "")
  io.print(str.concat("body_chars=", int.to_str(str.len(body))))
  let headers := map.from_list([
    ("content-type", "application/json"),
    ("accept", "application/json"),
  ])
  let raw_lines := match http.stream_lines("http://localhost:11434/api/chat", headers, body) {
    Err(e) => { io.print(str.concat("HTTP ERROR: ", e)); iter.from_list([]) },
    Ok(it) => it,
  }
  let lines := iter.to_list(raw_lines)
  io.print(str.concat("lines received: ", int.to_str(list.len(lines))))
  let counts := list.fold(lines,
    (0, 0, 0, 0),
    fn (acc :: (Int, Int, Int, Int), line :: Str) -> (Int, Int, Int, Int) {
      let ok_text  := match acc { (a, _, _, _) => a }
      let ok_tc    := match acc { (_, b, _, _) => b }
      let ok_empty := match acc { (_, _, c, _) => c }
      let fail     := match acc { (_, _, _, d) => d }
      let t := str.trim(line)
      if str.is_empty(t) { (ok_text, ok_tc, ok_empty + 1, fail) }
      else { match jv.parse_into_errors(t) {
        Err(_) => (ok_text, ok_tc, ok_empty, fail + 1),
        Ok(j)  => {
          let has_tc := match jv.get_field(j, "message") {
            None => false,
            Some(m) => match jv.get_field(m, "tool_calls") {
              Some(JList(calls)) => list.len(calls) > 0,
              _ => false,
            },
          }
          let content := match jv.get_field(j, "message") {
            None => "",
            Some(m) => match jv.get_field(m, "content") {
              Some(JStr(s)) => s,
              _ => "",
            },
          }
          if has_tc { (ok_text, ok_tc + 1, ok_empty, fail) }
          else { if str.is_empty(content) { (ok_text, ok_tc, ok_empty + 1, fail) }
          else { (ok_text + 1, ok_tc, ok_empty, fail) } }
        },
      } }
    })
  let ok_text  := match counts { (a, _, _, _) => a }
  let ok_tc    := match counts { (_, b, _, _) => b }
  let ok_empty := match counts { (_, _, c, _) => c }
  let fail     := match counts { (_, _, _, d) => d }
  io.print(str.concat("text_chunks_ok=", int.to_str(ok_text)))
  io.print(str.concat("tool_call_lines=", int.to_str(ok_tc)))
  io.print(str.concat("empty_content=", int.to_str(ok_empty)))
  io.print(str.concat("parse_fail=", int.to_str(fail)))
}
