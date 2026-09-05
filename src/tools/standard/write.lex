import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.process" as proc

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

import "../linter" as linter

fn params() -> s.ModelSchema {
  { title: "WriteArgs", description: "Arguments for writing a file", fields: [s.required_str("path", []), s.required_str("content", [])] }
}

# The directory portion of a path, or "" if it has none (a bare filename,
# or a path already ending in "/"). "a/b/c.lex" -> "a/b"; "c.lex" -> "".
fn parent_dir(path :: Str) -> Str
  examples {
    parent_dir("a/b/c.lex") => "a/b",
    parent_dir("c.lex") => "",
    parent_dir(".lex/specs/foo.lex") => ".lex/specs"
  }
{
  let parts := str.split(path, "/")
  if list.len(parts) <= 1 {
    ""
  } else {
    str.join(list.reverse(list.tail(list.reverse(parts))), "/")
  }
}

# io.write fails outright if the path's parent directory doesn't exist —
# every agent prompt that tells a mode to write somewhere structured
# (spec_agent's `.lex/specs/<module>_specs.lex`, test_agent's
# `tests/<module>_test.lex`) runs into this the first time, burning a turn
# on a bare "No such file or directory (os error 2)" with no hint to
# mkdir first. `mkdir -p` under `proc` (already in this tool's effect row)
# fixes it structurally instead of leaving every prompt to route around it.
fn ensure_parent_dir(path :: Str) -> [proc] Result[Unit, Str] {
  let dir := parent_dir(path)
  if str.is_empty(dir) {
    Ok(())
  } else {
    match proc.run("mkdir", ["-p", dir]) {
      Err(msg) => Err(msg),
      Ok(out) => if out.exit_code == 0 {
        Ok(())
      } else {
        Err(out.stderr)
      },
    }
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "content") {
      None => Err(e.single("", "missing_field", "content is required")),
      Some(content) => match ensure_parent_dir(path) {
        Err(msg) => Err(e.single("", "io_error", str.concat("could not create directory for ", str.concat(path, str.concat(": ", msg))))),
        Ok(_) => match io.write(path, content) {
          Err(msg) => Err(e.single("", "io_error", msg)),
          Ok(_) => {
            let lint := linter.run(path)
            let __verified := linter.record_verified("write", path, lint)
            let header := str.concat("wrote ", path)
            if lint.failed {
              Err(e.single("", "lint_failed", str.concat(header, str.concat("\n", str.concat(lint.summary, "\nFix the errors above and rewrite.")))))
            } else {
              if str.is_empty(lint.summary) {
                Ok(JStr(header))
              } else {
                Ok(JStr(str.concat(header, str.concat("\n", lint.summary))))
              }
            }
          },
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("write", "Write content to a file, creating or overwriting it entirely. For .lex files, auto-formats and runs lex check — lint results are always returned so you know if formatting was auto-applied or if errors must be fixed.", params(), execute)
}

