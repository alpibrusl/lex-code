# lex_audit — structural search over the codebase
#
# The tool took a free-text `query` and passed it to `lex audit` as a
# positional argument, where it landed in the `paths` list: asking for
# effects named `net` produced `stat net: No such file or directory`. Its
# description advertised `--calls`, `--effects`, `--impure` and
# `--unattested`; none of the four has ever existed (#83).
#
# `lex audit` takes a named filter and a value. Exposing the dimension and
# the value as separate arguments makes the four real filters legible to
# the model, and makes an unknown one a refusal here rather than a
# mis-parse three layers down.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn dimensions() -> List[Str]
  examples {
    dimensions() => ["effect", "call", "host", "kind"]
  }
{
  ["effect", "call", "host", "kind"]
}

fn is_dimension(name :: Str) -> Bool
  examples {
    is_dimension("effect") => true,
    is_dimension("kind") => true,
    is_dimension("effects") => false,
    is_dimension("impure") => false,
    is_dimension("") => false
  }
{
  list.fold(dimensions(), false, fn (acc :: Bool, d :: Str) -> Bool {
    if acc {
      true
    } else {
      d == name
    }
  })
}

fn params() -> s.ModelSchema {
  { title: "LexAuditArgs", description: "Structural search by effect, call, hostname or AST kind", fields: [s.required_str("dimension", []), s.required_str("value", []), s.optional(s.required_str("path", []))] }
}

# An unrecognised dimension is refused, not forwarded. `lex audit` would
# read `--impure` as a path and report a missing file, which reads to the
# model as "that directory is not there" rather than "that filter does
# not exist".
#
# "call" and "host" are not `--call`/`--host` on the real CLI (`lex audit`
# usage: `[paths...] [--effect KIND] [--calls FN] [--uses-host HOST]
# [--kind NODE] ...`) — a second flag-name mismatch #83's own fix didn't
# catch, since `--effect`/`--kind` happened to already match dimension()'s
# names and nothing exercised `call`/`host` against the real binary.
# Found live: a refactor-mode call with dimension=call failed with
# `stat --call: No such file or directory`, `lex audit` reading its own
# unrecognised `--call` flag as a path to stat. The model correctly
# self-diagnosed it and fell back to grep — but the tool should not need
# a model to route around it.
fn flag_for(dimension :: Str) -> Str
  examples {
    flag_for("effect") => "--effect",
    flag_for("call") => "--calls",
    flag_for("host") => "--uses-host",
    flag_for("kind") => "--kind"
  }
{
  match dimension {
    "call" => "--calls",
    "host" => "--uses-host",
    _ => str.concat("--", dimension),
  }
}

fn cmd_for(dimension :: Str, value :: Str, target :: Str) -> Result[List[Str], Str]
  examples {
    cmd_for("effect", "net", "src") => Ok(["audit", "--json", "--effect", "net", "src"]),
    cmd_for("call", "shout", "src") => Ok(["audit", "--json", "--calls", "shout", "src"]),
    cmd_for("host", "api.example.com", ".") => Ok(["audit", "--json", "--uses-host", "api.example.com", "."]),
    cmd_for("impure", "x", "src") => Err("unknown audit dimension 'impure'. Use one of: effect, call, host, kind")
  }
{
  if is_dimension(dimension) {
    Ok(["audit", "--json", flag_for(dimension), value, target])
  } else {
    Err(str.join(["unknown audit dimension '", dimension, "'. Use one of: ", str.join(dimensions(), ", ")], ""))
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "dimension") {
    None => Err(e.single("", "missing_field", "dimension is required")),
    Some(dimension) => match util.field_str(args, "value") {
      None => Err(e.single("", "missing_field", "value is required")),
      Some(value) => run(dimension, value, util.field_str_or(args, "path", ".")),
    },
  }
}

fn run(dimension :: Str, value :: Str, target :: Str) -> [proc] Result[jv.Json, e.Errors] {
  match cmd_for(dimension, value, target) {
    Err(msg) => Err(e.single("", "unknown_dimension", msg)),
    Ok(cmd) => match proc.run("lex", cmd) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match util.cli_result(out) {
        Err(detail) => Err(e.single("", "audit_failed", detail)),
        Ok(body) => Ok(JStr(body)),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_audit", "Structural search over Lex source with `lex audit`. dimension is one of effect, call, host, kind; value is the thing to look for (e.g. dimension=effect value=net). Returns JSON hits with file, name, effects and signature.", params(), execute)
}

