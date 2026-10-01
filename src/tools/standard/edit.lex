import "std.io" as io

import "std.str" as str

import "std.list" as list

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

# old_str is matched byte for byte, so a multi-line old_str written from
# memory fails on indentation alone. Show what the file really has at the
# first line of old_str so the retry copies it instead of guessing again.
fn not_found_hint(content :: Str, old_str :: Str) -> Str {
  let needle := first_line(old_str)
  let shown := if str.is_empty(needle) {
    []
  } else {
    window(str.split(content, "\n"), needle)
  }
  if list.is_empty(shown) {
    "old_str not found in file — its first line is not in the file at all; read the file and copy the text exactly (or use one short line as old_str)"
  } else {
    str.join(["old_str not found in file — only the whitespace or a later line differs. The file has, from the line your old_str starts with:\n", str.join(shown, "\n"), "\nCopy it exactly, or use one short single line as old_str."], "")
  }
}

fn replace_once(content :: Str, old_str :: Str, new_str :: Str) -> Result[Str, Str] {
  let parts := str.split(content, old_str)
  let n := list.len(parts)
  match n {
    1 => Err(not_found_hint(content, old_str)),
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
          Ok(content) => match replace_once(content, old_str, new_str) {
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

