# lex_guide — on-demand Lex language reference topics
#
# `lex_lang.reference()` (the always-present prompt core) keeps only what
# nearly every task needs; the syntax pitfalls table, list-processing
# idioms, and anti-patterns list moved out to named topics here, fetched
# only when actually wanted. Same "atomic, on demand" move `lex_stdlib`
# made for stdlib signatures, applied to the hand-written language guide
# instead of the compiler's builtin registry.

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

import "../prompts/lex_lang" as lex_lang

fn params() -> s.ModelSchema {
  { title: "LexGuideArgs", description: "Fetch one topic from the Lex language guide.", fields: [s.with_desc(s.required_str("topic", []), "One of: pitfalls, list-idioms, anti-patterns. Pass \"\" to list the available topics.")] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "topic") {
    None => Err(e.single("", "missing_field", "topic is required (pass \"\" to list available topics)")),
    Some(name) => if str.is_empty(name) {
      Ok(JStr(str.join(lex_lang.topic_names(), ", ")))
    } else {
      match lex_lang.topic(name) {
        Some(content) => Ok(JStr(content)),
        None => Ok(JStr(str.join(["no guide topic named \"", name, "\". Available: ", str.join(lex_lang.topic_names(), ", ")], ""))),
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_guide", "Fetch one topic from the Lex language guide: \"pitfalls\" (common syntax mistakes), \"list-idioms\" (list processing without pattern matching), or \"anti-patterns\". topic=\"\" lists the available topics. Call this instead of reading the full `lex agent-guidelines` document when you only need one specific thing.", params(), execute)
}

