# read — a file, or a window into one
#
# The schema has advertised `offset` and `limit` since it was written, and
# `execute` read neither: every call returned the whole file. A caller
# asking for five lines of a 182-line file got 182, with no way to tell
# its request had been dropped (#83's shape again — the schema promising
# what the implementation does not do).
#
# It matters most where the tool matters most. The Ollama path runs on
# `minimal_tools()` because a local 7B has a small context window; handing
# it an entire file when it asked for a window is how that window gets
# spent in one call.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "ReadArgs", description: "Arguments for reading a file", fields: [s.required_str("path", []), s.optional(s.required_int("offset", [])), s.optional(s.required_int("limit", []))] }
}

# `offset` is 0-based and `limit` is a count, which is what the schema's
# own field names imply and what the model sends. A negative offset is
# clamped to 0 rather than refused: it is a caller slip, not a reason to
# fail a read.
fn window(lines :: List[Str], offset :: Int, limit :: Option[Int]) -> List[Str]
  examples {
    window(["a", "b", "c", "d"], 0, Some(2)) => ["a", "b"],
    window(["a", "b", "c", "d"], 2, Some(2)) => ["c", "d"],
    window(["a", "b", "c", "d"], 2, None) => ["c", "d"],
    window(["a", "b", "c", "d"], 0, None) => ["a", "b", "c", "d"],
    window(["a", "b", "c", "d"], 3, Some(99)) => ["d"],
    window(["a", "b", "c", "d"], 99, Some(2)) => [],
    window(["a", "b", "c", "d"], -5, Some(2)) => ["a", "b"],
    window([], 0, Some(3)) => []
  }
{
  let start := if offset < 0 {
    0
  } else {
    offset
  }
  let stop := match limit {
    None => list.len(lines),
    Some(n) => if n < 0 {
      start
    } else {
      start + n
    },
  }
  list.reverse(list.fold(indexed(lines), [], fn (acc :: List[Str], pair :: (Int, Str)) -> List[Str] {
    match pair {
      (i, line) => if i >= start {
        if i < stop {
          list.cons(line, acc)
        } else {
          acc
        }
      } else {
        acc
      },
    }
  }))
}

fn indexed(lines :: List[Str]) -> List[(Int, Str)]
  examples {
    indexed(["a", "b"]) => [(0, "a"), (1, "b")],
    indexed([]) => []
  }
{
  list.reverse(match list.fold(lines, ([], 0), fn (acc :: (List[(Int, Str)], Int), line :: Str) -> (List[(Int, Str)], Int) {
    match acc {
      (out, i) => (list.cons((i, line), out), i + 1),
    }
  }) {
    (out, _) => out,
  })
}

# A window says so. Returning five lines that look like a whole file is
# how a model concludes a function is missing when it simply was not sent.
fn render(lines :: List[Str], total :: Int, offset :: Int, limit :: Option[Int]) -> Str
  examples {
    render(["a", "b"], 2, 0, None) => "a\nb",
    render(["a", "b"], 9, 0, Some(2)) => "# lines 1-2 of 9\na\nb",
    render([], 9, 99, Some(2)) => "# lines 100-101 of 9 — past the end of the file, nothing to show"
  }
{
  match limit {
    None => if offset == 0 {
      str.join(lines, "\n")
    } else {
      banner_and_body(lines, total, offset, list.len(lines))
    },
    Some(n) => banner_and_body(lines, total, offset, n),
  }
}

fn banner_and_body(lines :: List[Str], total :: Int, offset :: Int, span :: Int) -> Str {
  let first := offset + 1
  let last := offset + span
  let banner := str.join(["# lines ", int.to_str(first), "-", int.to_str(last), " of ", int.to_str(total)], "")
  if list.is_empty(lines) {
    str.concat(banner, " — past the end of the file, nothing to show")
  } else {
    str.join([banner, "\n", str.join(lines, "\n")], "")
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match io.read(path) {
      Err(msg) => Err(e.single("", "io_error", msg)),
      Ok(content) => {
        let lines := str.split(content, "\n")
        let offset := match util.field_int(args, "offset") {
          None => 0,
          Some(n) => n,
        }
        let limit := util.field_int(args, "limit")
        Ok(JStr(render(window(lines, offset, limit), list.len(lines), offset, limit)))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("read", "Read a file. Returns the whole file by default; pass offset (0-based line) and limit (line count) to read a window, which is reported in the output.", params(), execute)
}

