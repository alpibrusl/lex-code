# lex_stdlib — authoritative std.* module lookup
#
# A local/reasoning model without lex-lang training data has no way to
# know a stdlib function's real name or return type short of guessing and
# reading `lex check`'s error, or writing throwaway probe files to
# reverse-engineer a signature one function at a time (observed live: a
# from-scratch RLP build against qwen3.8 spent ~10 of its steps rebuilding
# std.bytes/std.crypto's shape this way before writing anything).
#
# This shells out to `lex docs --stdlib-index` (function names, every
# module — always available) and `--stdlib-spec` (typed signatures, only
# for modules migrated onto the declarative builtin catalogue, #778 —
# currently std.str and std.list; more arrive over time with zero change
# needed here). Both are generated straight from the compiler's own
# builtin registry, so the answer can't drift from what `lex check`
# actually accepts the way a hand-maintained prompt table could.
#
# Reproduced live (2026-09-30): a Build session needed a function to
# round a Float to the nearest cent, never called this tool at all, and
# guessed at a string of nonexistent module names across many retries
# (decimal, dec, flt, cents_via_decimal) before the real answer
# (std.math.round) got documented by hand in a prompt. That fix helped,
# but it only helps for the ONE gap someone happened to notice and write
# a sentence about; it does nothing for the next module a model guesses
# wrong. The actual failure wasn't "the model doesn't know math has a
# round function" -- it's "the model had no way to search FOR a function
# by what it does, only look one up once it already had the exact right
# module name" -- module="round" against the old exact-match lookup
# just returned "no stdlib module named std.round", as unhelpful as the
# compiler error that sent it here in the first place.
#
# keyword_search does the other half: if `module` doesn't name a real
# module, search every module's own function list in --stdlib-index for
# one whose NAME contains the query (case-insensitive) and return just
# those hits instead of either nothing or the entire undifferentiated
# index. module="round" now finds std.math's `round`; module="decimal"
# finds std.decimal itself. Still never guesses — every match comes from
# the same compiler-generated index the exact-match path already trusted.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStdlibArgs", description: "Look up a std.* module's real function names and (where migrated) exact typed signatures, OR search every module's function names for a capability by keyword.", fields: [s.with_desc(s.required_str("module", []), "A module name (with or without the \"std.\" prefix, e.g. \"bytes\" or \"std.bytes\") for an exact lookup, OR a capability keyword (e.g. \"round\", \"decimal\", \"parse\") to search every module's function names for a match. Pass \"\" to list every module.")] }
}

fn short_name(module :: Str) -> Str {
  match str.strip_prefix(module, "std.") {
    Some(rest) => rest,
    None => module,
  }
}

fn index_line_for(index_text :: Str, name :: Str) -> Option[Str] {
  let needle := str.join(["`std.", name, "`"], "")
  list.fold(str.split(index_text, "\n"), None, fn (acc :: Option[Str], line :: Str) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => if str.contains(line, needle) {
        Some(line)
      } else {
        None
      },
    }
  })
}

fn contains_ci(haystack :: Str, needle :: Str) -> Bool
  examples {
    contains_ci("std.math: round, floor", "round") => true,
    contains_ci("std.math: round, floor", "ROUND") => true,
    contains_ci("std.str: concat, len", "round") => false
  }
{
  str.contains(str.to_lower(haystack), str.to_lower(needle))
}

# Every index line whose function-name list contains `query` as a
# substring (case-insensitive) — not an exact module name, a capability
# search over every module's real function names at once. Blank/empty
# queries never match anything (avoids `query=""` degrading into "every
# line").
fn keyword_lines(index_text :: Str, query :: Str) -> List[Str]
  examples {
    keyword_lines("| `std.math` | `round`, `floor` |\n| `std.str` | `concat` |", "round") => ["| `std.math` | `round`, `floor` |"],
    keyword_lines("| `std.math` | `round`, `floor` |", "") => []
  }
{
  if str.is_empty(str.trim(query)) {
    []
  } else {
    list.filter(str.split(index_text, "\n"), fn (line :: Str) -> Bool {
      contains_ci(line, query)
    })
  }
}

fn spec_lines_for(spec_text :: Str, name :: Str) -> List[Str] {
  let needle := str.join(["`", name, "."], "")
  list.filter(str.split(spec_text, "\n"), fn (line :: Str) -> Bool {
    str.contains(line, needle)
  })
}

fn run_docs(flag :: Str) -> [proc] Result[Str, Str] {
  match proc.run("lex", ["docs", flag]) {
    Err(msg) => Err(msg),
    Ok(out) => util.cli_result(out),
  }
}

# Modules where the index alone sends a worker into a probing rabbit hole:
# std.json's function names are listed with no types, so a worker that needs
# to read a JSON body writes throwaway files to learn the shape of `parse`'s
# result (20+ steps, observed). Point it at the typed alternative up front.
fn module_note(name :: Str) -> Str
  examples {
    module_note("json") => "\n\nNote: std.json lists no types, and the shape of `json.parse`'s result cannot be learned by probing. To read fields from a JSON string use lex-schema (add it to lex.toml, `lex pkg install`): `import \"lex-schema/json_value\" as jv`, `jv.parse(src)` returns `Result[Json, ParseErr]` with `Json = JNull | JBool(Bool) | JInt(Int) | JFloat(Float) | JStr(Str) | JList(List[Json]) | JObj(List[(Str, Json)])` — match on those. `package_api(\"lex-schema\", \"json_value\")` lists the extractors.",
    module_note("str") => ""
  }
{
  if name == "json" {
    "\n\nNote: std.json lists no types, and the shape of `json.parse`'s result cannot be learned by probing. To read fields from a JSON string use lex-schema (add it to lex.toml, `lex pkg install`): `import \"lex-schema/json_value\" as jv`, `jv.parse(src)` returns `Result[Json, ParseErr]` with `Json = JNull | JBool(Bool) | JInt(Int) | JFloat(Float) | JStr(Str) | JList(List[Json]) | JObj(List[(Str, Json)])` — match on those. `package_api(\"lex-schema\", \"json_value\")` lists the extractors."
  } else {
    ""
  }
}

fn with_signatures(line :: Str, name :: Str) -> [proc] Result[jv.Json, e.Errors] {
  let note := module_note(name)
  match run_docs("--stdlib-spec") {
    Err(_) => Ok(JStr(str.concat(line, note))),
    Ok(spec_text) => {
      let sig_lines := spec_lines_for(spec_text, name)
      if list.is_empty(sig_lines) {
        Ok(JStr(str.concat(line, note)))
      } else {
        Ok(JStr(str.join([line, "\n\nSignatures:\n", str.join(sig_lines, "\n"), note], "")))
      }
    },
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "module") {
    None => Err(e.single("", "missing_field", "module is required (pass \"\" to list every module)")),
    Some(raw_module) => match run_docs("--stdlib-index") {
      Err(msg) => Err(e.single("", "proc_error", util.unavailable("lex docs --stdlib-index", msg))),
      Ok(index_text) => if str.is_empty(raw_module) {
        Ok(JStr(index_text))
      } else {
        let name := short_name(raw_module)
        match index_line_for(index_text, name) {
          Some(line) => with_signatures(line, name),
          None => {
            let hits := keyword_lines(index_text, name)
            if list.is_empty(hits) {
              Ok(JStr(str.join(["no stdlib module named \"std.", name, "\", and no function name contains \"", name, "\" either. Full index:\n\n", index_text], "")))
            } else {
              Ok(JStr(str.join(["no stdlib module named \"std.", name, "\", but this looks like a capability search — these modules have a function whose name contains \"", name, "\":\n\n", str.join(hits, "\n")], "")))
            }
          },
        }
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_stdlib", "Look up a std.* module's real function names and (when available) exact typed signatures, straight from the compiler's own builtin registry — never guesses. module=\"bytes\" for an exact std.bytes lookup, module=\"\" to list every module. Don't know which module has what you need? Pass a capability keyword instead of a module name — module=\"round\" finds every module with a `round`-named function, module=\"decimal\" finds std.decimal itself. Call this before probing a stdlib call with a throwaway file, guessing a return type, or guessing which module might have what you need.", params(), execute)
}

