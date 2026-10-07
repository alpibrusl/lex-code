# lex-code — a non-blocking lint for JSON built by joining strings
#
# Two of the backlog's fast builds that ended `done` answered with broken JSON:
# a webhook reply `{"id":1,"duplicate":false` with no closing brace, and an
# invoice whose customer name was spliced between quotes without escaping, so a
# name containing a quote came back as invalid JSON. Both assembled the text with
# `str.concat` on fragments like `"{\"id\":"`. The unit examples pass (they use
# plain names) and nothing else looks at it. `jv.stringify(JObj([...]))` escapes
# and closes correctly, so the model is told right when it writes such a line.
#
# Heuristic, on purpose: a line that calls str.concat or str.join and contains a
# JSON-looking fragment (`{"` or `":` written inside a Lex string). Example lines
# (`=>`) and comments are skipped, as is a plain constant string with no concat.

import "std.str" as str

import "std.list" as list

import "std.int" as int

fn suspicious(line :: Str) -> Bool
  examples {
    suspicious("  str.concat(\"{\\\"id\\\":\", int.to_str(id))") => true,
    suspicious("  let b := str.join([\"\\\"name\\\":\\\"\", n, \"\\\"\"], \"\")") => true,
    suspicious("  resp.json_status(401, \"{\\\"error\\\":\\\"unauthorized\\\"}\")") => false,
    suspicious("    f(\"{\\\"a\\\":1}\") => \"x\"") => false,
    suspicious("  # str.concat(\"{\\\"id\\\":\", x)") => false,
    suspicious("  str.concat(a, b)") => false
  }
{
  let t := str.trim(line)
  not str.starts_with(t, "#") and not str.contains(t, "=>") and (str.contains(t, "str.concat(") or str.contains(t, "str.join(")) and (str.contains(t, "{\\\"") or str.contains(t, "\\\":"))
}

fn numbered(lines :: List[Str], n :: Int) -> List[Int] {
  match list.head(lines) {
    None => [],
    Some(l) => if suspicious(l) {
      list.cons(n, numbered(list.tail(lines), n + 1))
    } else {
      numbered(list.tail(lines), n + 1)
    },
  }
}

# 1-based line numbers of lines that look like hand-built JSON.
fn hand_built_json_lines(source :: Str) -> List[Int]
  examples {
    hand_built_json_lines("") => [],
    hand_built_json_lines("fn a() -> Int {\n  1\n}") => [],
    hand_built_json_lines("fn a() -> Str {\n  str.concat(\"{\\\"id\\\":\", \"1\")\n}") => [2]
  }
{
  numbered(str.split(source, "\n"), 1)
}

fn warning(lines :: List[Int]) -> Str
  examples {
    warning([]) => "",
    warning([5]) => "JSON built by joining strings (line 5): quotes and backslashes in a value are not escaped and a closing brace is easy to drop, so a reply can be invalid JSON for some inputs. Build it with `jv.stringify(JObj([(\"key\", JStr(v)), (\"n\", JInt(n))]))` (import \"lex-schema/json_value\" as jv; JBool, JNull and JList exist too)."
  }
{
  if list.is_empty(lines) {
    ""
  } else {
    str.join(["JSON built by joining strings (line", if list.len(lines) > 1 {
      "s "
    } else {
      " "
    }, str.join(list.map(lines, fn (n :: Int) -> Str {
      int.to_str(n)
    }), ", "), "): quotes and backslashes in a value are not escaped and a closing brace is easy to drop, so a reply can be invalid JSON for some inputs. Build it with `jv.stringify(JObj([(\"key\", JStr(v)), (\"n\", JInt(n))]))` (import \"lex-schema/json_value\" as jv; JBool, JNull and JList exist too)."], "")
  }
}

