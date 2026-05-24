import "std.proc" as proc

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

fn params() -> s.ModelSchema {
  { title: "LoadGuidelinesArgs", description: "No arguments — fetches the full Lex agent guidelines.", fields: [] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match proc.spawn("lex", ["agent-guidelines"]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => if out.exit_code == 0 {
      Ok(JStr(out.stdout))
    } else {
      Err(e.single("", "proc_error", out.stderr))
    },
  }
}

fn tool() -> t.Tool {
  t.define("load_guidelines", "Fetch the full `lex agent-guidelines` reference document. Call this when you need detailed Lex idioms, stdlib signatures, or the pre-done checklist.", params(), execute)
}

