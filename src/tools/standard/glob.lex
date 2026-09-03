import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "GlobArgs", description: "Find files matching a pattern", fields: [s.required_str("pattern", []), s.optional(s.required_str("directory", []))] }
}

# `-name` matches only a file's basename, so any pattern containing "/" —
# "**/*.lex", "src/*", "lex/specs/**" — can never match anything: find
# silently reports no results instead of erroring, so the caller has no
# signal anything went wrong. `-path` matches against the full path find is
# already walking (BSD and GNU find both apply it without FNM_PATHNAME, so
# "*" matches "/" too), which handles the recursive-glob and nested-prefix
# forms models actually send while still behaving identically to `-name`
# for a plain slash-free pattern like "*.lex".
fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "pattern") {
    None => Err(e.single("", "missing_field", "pattern is required")),
    Some(pattern) => {
      let dir := util.field_str_or(args, "directory", ".")
      match proc.run("find", [dir, "-path", pattern, "-type", "f"]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => {
          let result := if str.is_empty(out.stdout) {
            "no files found"
          } else {
            out.stdout
          }
          Ok(JStr(result))
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("glob", "Find files matching a pattern. Returns newline-separated file paths.", params(), execute)
}

