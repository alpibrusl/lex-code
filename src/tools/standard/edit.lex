import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

import "../linter" as linter

fn params() -> s.ModelSchema {
  { title: "EditArgs", description: "Edit a file by exact string replacement. old_str must appear exactly once.", fields: [s.required_str("path", []), s.required_str("old_str", []), s.required_str("new_str", [])] }
}

fn first_line(text :: Str) -> Str
  examples {
    first_line("\n  a b \nc") => "a b",
    first_line("") => ""
  }
{
  match list.head(list.filter(str.split(text, "\n"), fn (l :: Str) -> Bool {
    not str.is_empty(str.trim(l))
  })) {
    None => "",
    Some(l) => str.trim(l),
  }
}

type Scan = { i :: Int, at :: Int, out :: List[Str] }

fn window(lines :: List[Str], needle :: Str) -> List[Str]
  examples {
    window(["x", "  b", "c", "d", "e", "f"], "b") => ["  b", "c", "d", "e"],
    window(["x"], "q") => []
  }
{
  let hit := list.fold(lines, { i: 0, at: -1, out: [] }, fn (acc :: Scan, l :: Str) -> Scan {
    let at := if acc.at < 0 and str.contains(l, needle) {
      acc.i
    } else {
      acc.at
    }
    let keep := at >= 0 and acc.i < at + 4
    { i: acc.i + 1, at: at, out: if keep {
      list.concat(acc.out, [l])
    } else {
      acc.out
    } }
  })
  hit.out
}

fn nth(lines :: List[Str], i :: Int) -> Option[Str]
  examples {
    nth(["a", "b"], 1) => Some("b"),
    nth(["a"], 3) => None
  }
{
  list.fold(list.enumerate(lines), None, fn (acc :: Option[Str], p :: (Int, Str)) -> Option[Str] {
    match p {
      (j, l) => if j == i {
        Some(l)
      } else {
        acc
      },
    }
  })
}

fn index_of_line(lines :: List[Str], needle :: Str) -> Int
  examples {
    index_of_line(["x", "  b"], "b") => 1,
    index_of_line(["x"], "q") => -1
  }
{
  list.fold(list.enumerate(lines), -1, fn (acc :: Int, p :: (Int, Str)) -> Int {
    match p {
      (j, l) => if acc < 0 and str.contains(l, needle) {
        j
      } else {
        acc
      },
    }
  })
}

# The first line where old_str and the file part ways, starting at the file
# line that matches old_str's first line. A 4-line window is not enough: a
# worker's old_str can agree for the first dozen lines and differ on the
# closing brace, because `lex fmt` re-indents after every edit.
fn first_mismatch(file_lines :: List[Str], old_lines :: List[Str], start :: Int) -> Option[Str]
  examples {
    first_mismatch(["a", "  b", "c"], ["a", "b", "c"], 0) => Some("line 2 of old_str is \"b\" but the file has \"  b\" (same text, different whitespace)"),
    first_mismatch(["a", "b"], ["a", "b"], 0) => None,
    first_mismatch(["a", "b", "c"], ["a", "x"], 0) => Some("line 2 of old_str is \"x\" but the file has \"b\""),
    first_mismatch(["a"], ["a", "x"], 0) => Some("line 2 of old_str is \"x\" but the file ends before it")
  }
{
  list.fold(list.enumerate(old_lines), None, fn (acc :: Option[Str], p :: (Int, Str)) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => match p {
        (k, ol) => match nth(file_lines, start + k) {
          None => Some(str.join(["line ", int.to_str(k + 1), " of old_str is \"", ol, "\" but the file ends before it"], "")),
          Some(fl) => if fl == ol {
            None
          } else {
            if str.trim(fl) == str.trim(ol) {
              Some(str.join(["line ", int.to_str(k + 1), " of old_str is \"", ol, "\" but the file has \"", fl, "\" (same text, different whitespace)"], ""))
            } else {
              Some(str.join(["line ", int.to_str(k + 1), " of old_str is \"", ol, "\" but the file has \"", fl, "\""], ""))
            }
          },
        },
      },
    }
  })
}

# old_str is matched byte for byte, so a multi-line old_str written from
# memory fails on indentation alone. Show where it first disagrees with the
# file, and what the file really has there, so the retry fixes that line
# instead of guessing again.
fn not_found_hint(content :: Str, old_str :: Str) -> Str {
  let needle := first_line(old_str)
  let file_lines := str.split(content, "\n")
  let shown := if str.is_empty(needle) {
    []
  } else {
    window(file_lines, needle)
  }
  if list.is_empty(shown) {
    "old_str not found in file — its first line is not in the file at all; read the file and copy the text exactly (or use one short line as old_str)"
  } else {
    let start := index_of_line(file_lines, needle)
    let where := match first_mismatch(file_lines, str.split(old_str, "\n"), start) {
      Some(m) => str.join(["First difference: ", m, ". "], ""),
      None => "",
    }
    str.join(["old_str not found in file. ", where, "The file has, from the line your old_str starts with:\n", str.join(shown, "\n"), "\nCopy it exactly, or use one short single line as old_str — or rewrite the whole file with write."], "")
  }
}

fn matches_at(file_t :: List[Str], old_t :: List[Str], start :: Int) -> Bool
  examples {
    matches_at(["a", "b", "c"], ["b", "c"], 1) => true,
    matches_at(["a", "b"], ["b", "c"], 1) => false
  }
{
  list.fold(list.enumerate(old_t), true, fn (acc :: Bool, p :: (Int, Str)) -> Bool {
    match p {
      (k, ol) => {
        let same := match nth(file_t, start + k) {
          None => false,
          Some(fl) => fl == ol,
        }
        acc and same
      },
    }
  })
}

fn match_starts(file_t :: List[Str], old_t :: List[Str]) -> List[Int]
  examples {
    match_starts(["a", "b", "a", "b"], ["a", "b"]) => [0, 2],
    match_starts(["a"], ["z"]) => []
  }
{
  list.fold(list.enumerate(file_t), [], fn (acc :: List[Int], p :: (Int, Str)) -> List[Int] {
    match p {
      (i, _) => if matches_at(file_t, old_t, i) {
        list.concat(acc, [i])
      } else {
        acc
      },
    }
  })
}

fn splice_lines(lines :: List[Str], start :: Int, count :: Int, repl :: List[Str]) -> List[Str]
  examples {
    splice_lines(["a", "b", "c"], 1, 1, ["x", "y"]) => ["a", "x", "y", "c"]
  }
{
  let before := list.fold(list.enumerate(lines), [], fn (acc :: List[Str], p :: (Int, Str)) -> List[Str] {
    match p {
      (j, l) => if j < start {
        list.concat(acc, [l])
      } else {
        acc
      },
    }
  })
  let after := list.fold(list.enumerate(lines), [], fn (acc :: List[Str], p :: (Int, Str)) -> List[Str] {
    match p {
      (j, l) => if j >= start + count {
        list.concat(acc, [l])
      } else {
        acc
      },
    }
  })
  list.concat(list.concat(before, repl), after)
}

# `lex fmt` re-indents the file after every edit, so a worker's old_str
# written from memory misses on whitespace alone and it loops. For .lex files
# (where indentation carries no meaning, fmt rewrites it) an old_str whose
# lines all match one window of the file ignoring leading/trailing whitespace
# is applied there; fmt then re-indents the replacement.
fn replace_ignoring_indent(content :: Str, old_str :: Str, new_str :: Str) -> Option[Str] {
  let old_t := list.map(str.split(str.trim(old_str), "\n"), fn (l :: Str) -> Str {
    str.trim(l)
  })
  if str.is_empty(str.trim(old_str)) {
    None
  } else {
    let file_lines := str.split(content, "\n")
    let file_t := list.map(file_lines, fn (l :: Str) -> Str {
      str.trim(l)
    })
    let hits := match_starts(file_t, old_t)
    if list.len(hits) == 1 {
      match list.head(hits) {
        None => None,
        Some(only) => Some(str.join(splice_lines(file_lines, only, list.len(old_t), str.split(str.trim(new_str), "\n")), "\n")),
      }
    } else {
      None
    }
  }
}

fn replace_once(content :: Str, old_str :: Str, new_str :: Str, lenient :: Bool) -> Result[Str, Str] {
  let parts := str.split(content, old_str)
  let n := list.len(parts)
  match n {
    1 => if lenient {
      match replace_ignoring_indent(content, old_str, new_str) {
        Some(updated) => Ok(updated),
        None => Err(not_found_hint(content, old_str)),
      }
    } else {
      Err(not_found_hint(content, old_str))
    },
    2 => match list.head(parts) {
      None => Err("internal error"),
      Some(head) => match list.head(list.tail(parts)) {
        None => Err("internal error"),
        Some(tail) => Ok(str.concat(str.concat(head, new_str), tail)),
      },
    },
    _ => Err("old_str is not unique — found multiple occurrences"),
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "old_str") {
      None => Err(e.single("", "missing_field", "old_str is required")),
      Some(old_str) => match util.field_str(args, "new_str") {
        None => Err(e.single("", "missing_field", "new_str is required")),
        Some(new_str) => match io.read(path) {
          Err(msg) => Err(e.single("", "io_error", msg)),
          Ok(content) => match replace_once(content, old_str, new_str, str.ends_with(path, ".lex")) {
            Err(reason) => Err(e.single("", "edit_error", reason)),
            Ok(updated) => match io.write(path, updated) {
              Err(msg) => Err(e.single("", "io_error", msg)),
              Ok(_) => {
                let lint := linter.run(path)
                let __verified := linter.record_verified("edit", path, lint)
                let header := str.concat("edited ", path)
                if lint.failed {
                  Err(e.single("", "lint_failed", str.concat(header, str.concat("\n", str.concat(lint.summary, "\nFix the errors above.")))))
                } else {
                  match linter.publish_with_intent(path) {
                    Some(refused) => Err(e.single("", "publish_refused", str.concat(header, str.concat("\n", str.concat(refused, "\nThe change type-checks but the store's gate refused it (declared examples fail). Fix and rewrite."))))),
                    None => if str.is_empty(lint.summary) {
                      Ok(JStr(str.concat(header, linter.readback(path))))
                    } else {
                      Ok(JStr(str.concat(header, str.concat("\n", lint.summary))))
                    },
                  }
                }
              },
            },
          },
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("edit", "Edit a file by replacing old_str with new_str. old_str must be unique in the file. For .lex files, auto-formats and runs lex check after the edit. Returns the file's on-disk content after the edit, so a follow-up edit matches what is actually there.", params(), execute)
}

