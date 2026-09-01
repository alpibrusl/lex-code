# lex-code — the `remember` tool: propose a fact, do not install one
#
# This tool cannot write to project memory. lex-llm fixes the tool row at
# `[net, io, proc]` and record-field rows unify by equality (§1.6), so no
# tool can widen it to the `[sql, time]` a durable write needs. What it does
# is append a candidate; `src/memory/consolidate.lex` decides whether that
# candidate becomes a fact, and attests it in the trail when it does.
#
# The result string says so plainly. An agent that believes `remember`
# committed something will reason from a fact that may never exist, and the
# cheapest place to prevent that is the sentence it reads back.

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../memory/candidates" as cand

import "../tools/util" as util

import "std.str" as str

fn params() -> s.ModelSchema {
  { title: "RememberArgs", description: "Propose a durable fact about this project. It is reviewed before it becomes memory.", fields: [s.required_str("kind", []), s.required_str("content", []), s.optional(s.required_str("key", [])), s.optional(s.required_str("why", []))] }
}

# `kind` is checked here as well as at consolidation. Rejecting it now gives
# the model an error it can act on in the same turn; consolidation's later
# check is what catches a candidate written by anything else.
fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "kind") {
    None => Err(e.single("", "missing_field", "kind is required")),
    Some(kind) => if cand.is_known_kind(kind) {
      match util.field_str(args, "content") {
        None => Err(e.single("", "missing_field", "content is required")),
        Some(content) => if str.is_empty(str.trim(content)) {
          Err(e.single("", "empty_content", "content is empty — nothing to remember"))
        } else {
          propose_one(kind, content, util.field_str_or(args, "key", ""), util.field_str_or(args, "why", ""))
        },
      }
    } else {
      Err(e.single("", "unknown_kind", str.join(["kind must be one of ", str.join(cand.known_kinds(), ", "), " — got ", kind], "")))
    },
  }
}

fn propose_one(kind :: Str, content :: Str, key :: Str, why :: Str) -> [io] Result[jv.Json, e.Errors] {
  match cand.propose({ kind: kind, key: key, content: content, why: why }) {
    Err(m) => Err(e.single("", "io_error", str.concat("could not record the candidate: ", m))),
    Ok(_) => Ok(JStr(str.join(["proposed (", kind, "/", key, "): ", content, "\n\nThis is a candidate, not memory. It is reconciled against what the project already knows before anything believes it, and it will not appear in a later session's context unless it survives that. Do not treat it as recorded."], ""))),
  }
}

fn tool() -> t.Tool {
  t.define("remember", "Propose a durable fact about this project (kind: convention | tech_stack | recent_change | known_issue). The proposal is reconciled against existing memory and attested before it becomes memory — it is not saved directly.", params(), execute)
}

