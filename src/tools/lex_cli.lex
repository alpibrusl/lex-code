import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexCliArgs", description: "Arguments for the lex CLI", fields: [s.required_str("command", [])] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "command") {
    None => Err(e.single("", "missing_field", "command is required")),
    Some(cmd) => match proc.run("bash", ["-c", str.concat("lex ", cmd)]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => {
        let combined := str.concat(out.stdout, out.stderr)
        Ok(JStr(combined))
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex", "Run any `lex` CLI command. Pass the subcommand and arguments as `command`.\n\nAvailable subcommands:\n- `check [path]` — type-check a file or directory (default: current dir)\n- `audit [path]` — audit effect annotations\n- `run <file> [fn] [-- args...]` — run a Lex function\n- `test [path]` — run example-based tests\n- `spec check [path]` — check specifications\n- `spec smt [path]` — SMT-based verification\n- `skill` — list available skills\n\nExamples: `check src/`, `run main.lex main`, `test src/`", params(), execute)
}

