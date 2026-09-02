# effects_of — the declared effect row of one function
#
# This asked `lex check` for `--json --effects`. `lex check` has neither
# flag; its only argument is a file. The tool had never run (#83).
#
# `lex audit --json <path>` is what actually carries the information: it
# emits one hit per stage with `name`, `effects` and `signature`, which is
# a superset of what this needs. Filtering client-side costs one pass over
# a list the CLI already built.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "EffectsOfArgs", description: "Get the effect row of a Lex function", fields: [s.required_str("fn_name", []), s.optional(s.required_str("path", []))] }
}

# Imported stages are qualified with a content hash — `error_df8a28a1.single`
# — while locally defined ones are bare. A caller who asks for `single`
# means either, so the last segment is what is compared.
fn base_name(qualified :: Str) -> Str
  examples {
    base_name("execute") => "execute",
    base_name("error_df8a28a1.code_missing") => "code_missing",
    base_name("") => ""
  }
{
  list.fold(str.split(qualified, "."), "", fn (_acc :: Str, seg :: Str) -> Str {
    seg
  })
}

fn matches(hit_name :: Str, wanted :: Str) -> Bool
  examples {
    matches("execute", "execute") => true,
    matches("error_df8a28a1.single", "single") => true,
    matches("error_df8a28a1.single", "error_df8a28a1.single") => true,
    matches("execute", "params") => false
  }
{
  if hit_name == wanted {
    true
  } else {
    base_name(hit_name) == wanted
  }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(v)) => v,
    _ => "",
  }
}

# The signature already spells the effect row the way a Lex programmer
# reads it, so it is returned verbatim rather than reassembled from the
# `effects` array — the two cannot then disagree.
fn render_hit(h :: jv.Json) -> Str {
  str.join([str_field(h, "name"), "  in ", str_field(h, "file"), "\n  ", str_field(h, "signature")], "")
}

fn hits_of(body :: Str) -> List[jv.Json] {
  match jv.parse_into_errors(body) {
    Err(_) => [],
    Ok(j) => match jv.get_field(j, "hits") {
      Some(JList(items)) => items,
      _ => [],
    },
  }
}

fn found(body :: Str, wanted :: Str) -> List[Str] {
  list.map(list.filter(hits_of(body), fn (h :: jv.Json) -> Bool {
    matches(str_field(h, "name"), wanted)
  }), render_hit)
}

# No hit is an honest negative — the audit ran and that name is not in
# scope — and says so in those words. It is not the same sentence as the
# one printed when the audit itself could not run.
fn report(body :: Str, wanted :: Str, target :: Str) -> Str {
  let rows := found(body, wanted)
  if list.is_empty(rows) {
    str.join(["no stage named '", wanted, "' under ", target, ". `lex audit --json ", target, "` ran and returned no match, so this is a real absence, not a failed lookup."], "")
  } else {
    str.join(rows, "\n")
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "fn_name") {
    None => Err(e.single("", "missing_field", "fn_name is required")),
    Some(fn_name) => {
      let target := util.field_str_or(args, "path", ".")
      match proc.run("lex", ["audit", "--json", target]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => match util.cli_result(out) {
          Err(detail) => Err(e.single("", "audit_failed", util.unavailable(str.concat("lex audit --json ", target), detail))),
          Ok(body) => Ok(JStr(report(body, fn_name, target))),
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("effects_of", "Report the declared effect row of a Lex function, via `lex audit --json`. Returns the full signature, e.g. \"fn execute(args :: Json) -> [net, io, proc] Result[...]\".", params(), execute)
}

