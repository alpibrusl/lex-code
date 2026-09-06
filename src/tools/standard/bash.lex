import "std.process" as proc

import "std.str" as str

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "BashArgs", description: "Run a bash command in the project directory", fields: [s.required_str("command", [])] }
}

# Reproduced live: `grep -R "Unit" ~/.lex/store | head -5` returned 422 MB —
# `head -5` didn't help, because the store's trace files are minified,
# single-line JSON, so five "lines" were five whole files. That result went
# straight into the tool-result JSON handed back to the model; the turn
# after it came back with an empty response, almost certainly from the
# context it blew out. Nothing bounds `bash`'s captured output, and a
# model choosing to grep somewhere broad (a global store, a large log, the
# wrong directory entirely) is a realistic, not adversarial, way to trigger
# this. Each stream is truncated separately, before concatenation, so a
# huge stdout doesn't need to be combined with stderr just to be cut down.
fn max_output_chars() -> Int {
  30000
}

fn truncate_output(s :: Str) -> Str {
  let len := str.len(s)
  if len <= max_output_chars() {
    s
  } else {
    str.join([str.slice(s, 0, max_output_chars()), "\n\n[... output truncated: ", int.to_str(len), " total characters, showing the first ", int.to_str(max_output_chars()), " ...]"], "")
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "command") {
    None => Err(e.single("", "missing_field", "command is required")),
    Some(cmd) => match proc.run("bash", ["-c", cmd]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => {
        let combined := str.concat(truncate_output(out.stdout), truncate_output(out.stderr))
        Ok(JStr(combined))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("bash", "Run a bash command and return combined stdout and stderr.", params(), execute)
}

