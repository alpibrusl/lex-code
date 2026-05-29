import "lex-schema/json_value" as jv
import "std.http" as http
import "std.iter" as iter
import "std.list" as list
import "std.str"  as str
import "std.io"   as io
import "std.map"  as map
import "std.int"  as int

fn main() -> [net, io] Nil {
  let body := "{\"model\":\"qwen3.6:latest\",\"stream\":false,\"messages\":[{\"role\":\"system\",\"content\":\"You are a coding assistant. Use the write tool to write files immediately.\"},{\"role\":\"user\",\"content\":\"write fib.lex with a fibonacci function\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"write\",\"description\":\"Write a file\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}}}]}"
  let headers := map.from_list([
    ("content-type", "application/json"),
    ("accept", "application/json"),
  ])
  io.print("sending request...")
  let raw_lines := match http.stream_lines("http://localhost:11434/api/chat", headers, body) {
    Err(e) => { io.print(str.concat("HTTP ERROR: ", e)); iter.from_list([]) },
    Ok(it) => it,
  }
  let lines := iter.to_list(raw_lines)
  io.print(str.concat("lines received: ", int.to_str(list.len(lines))))
  let total_chars := list.fold(lines, 0, fn (acc :: Int, l :: Str) -> Int { acc + str.len(l) })
  io.print(str.concat("total chars: ", int.to_str(total_chars)))
  # Print raw content of each line (first 120 chars)
  let _ := list.map(lines, fn (line :: Str) -> [io] Nil {
    let preview := if str.len(line) > 120 { str.concat(str.slice(line, 0, 120), "...") } else { line }
    io.print(str.concat("RAW: ", preview))
  })
  let _ := list.map(lines, fn (line :: Str) -> [io] Nil {
    let t := str.trim(line)
    if str.is_empty(t) { io.print("  [empty line]") }
    else {
      match jv.parse_into_errors(t) {
        Err(_) => io.print(str.concat("  PARSE FAIL (len=", str.concat(int.to_str(str.len(t)), str.concat("): ", if str.len(t) > 60 { str.concat(str.slice(t, 0, 60), "...") } else { t })))),
        Ok(j)  => {
          let done := match jv.get_field(j, "done") { Some(JBool(b)) => b, _ => false }
          let content := match jv.get_field(j, "message") {
            None => "",
            Some(m) => match jv.get_field(m, "content") { Some(JStr(s)) => s, _ => "" }
          }
          let has_tc := match jv.get_field(j, "message") {
            None => false,
            Some(m) => match jv.get_field(m, "tool_calls") {
              Some(JList(calls)) => list.len(calls) > 0,
              _ => false,
            },
          }
          io.print(str.concat("  OK done=", str.concat(if done { "T" } else { "F" },
            str.concat(" tc=", str.concat(if has_tc { "Y" } else { "N" },
              str.concat(" content_len=", int.to_str(str.len(content))))))))
        },
      }
    }
  })
}
