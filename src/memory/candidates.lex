# lex-code — candidate memory: what the agent proposes, before anything believes it
#
# A `remember` tool cannot write to project memory, and that is the design
# rather than a limitation to work around. lex-llm fixes the tool row:
#
#     execute :: (jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors]
#
# No `sql`, no `time`. Every one of lex-code's tools declares exactly that,
# and record-field effect rows unify by equality (AGENTS.md §1.6), so no tool
# can widen it. The agent therefore *cannot* commit a belief — the effect
# system enforces the gate that a policy would only ask for.
#
# So a candidate is an append to a file, which `[io]` does allow. It carries
# no authority: nothing that reaches a model's prompt reads this file.
# Consolidation (`src/memory/consolidate.lex`), which runs with the effects a
# durable write actually needs, is what promotes a candidate into memory and
# attests it in the trail.
#
# The file is JSONL rather than a table for the same reason: appending one
# line needs no schema, no migration and no lock, and a half-written line
# costs one dropped candidate rather than a corrupt store.

import "lex-schema/json_value" as jv

import "std.io" as io

import "std.str" as str

import "std.list" as list

type Candidate = { kind :: Str, key :: Str, content :: Str, why :: Str }

fn path() -> Str {
  ".lex/memory-candidates.jsonl"
}

fn dir() -> Str {
  ".lex"
}

# Kinds project memory understands. A candidate outside this set is dropped
# at consolidation rather than at proposal time, so the trail records that
# the agent tried — an agent inventing kinds is worth being able to see.
fn known_kinds() -> List[Str]
  examples {
    known_kinds() => ["convention", "tech_stack", "recent_change", "known_issue"]
  }
{
  ["convention", "tech_stack", "recent_change", "known_issue"]
}

fn is_known_kind(kind :: Str) -> Bool
  examples {
    is_known_kind("convention") => true,
    is_known_kind("known_issue") => true,
    is_known_kind("vibes") => false,
    is_known_kind("") => false
  }
{
  list.fold(known_kinds(), false, fn (acc :: Bool, k :: Str) -> Bool {
    if acc {
      true
    } else {
      k == kind
    }
  })
}

fn encode(c :: Candidate) -> Str
  examples {
    encode({ kind: "convention", key: "fmt", content: "run lex fmt", why: "AGENTS.md says so" }) => "{\"kind\":\"convention\",\"key\":\"fmt\",\"content\":\"run lex fmt\",\"why\":\"AGENTS.md says so\"}"
  }
{
  jv.stringify(JObj([("kind", JStr(c.kind)), ("key", JStr(c.key)), ("content", JStr(c.content)), ("why", JStr(c.why))]))
}

fn decode(line :: Str) -> Option[Candidate]
  examples {
    decode("{\"kind\":\"convention\",\"key\":\"fmt\",\"content\":\"run lex fmt\",\"why\":\"x\"}") => Some({ kind: "convention", key: "fmt", content: "run lex fmt", why: "x" }),
    decode("{\"kind\":\"convention\",\"key\":\"fmt\"}") => None,
    decode("not json") => None,
    decode("") => None
  }
{
  match jv.parse_into_errors(str.trim(line)) {
    Err(_) => None,
    Ok(j) => match field(j, "kind") {
      None => None,
      Some(kind) => match field(j, "content") {
        None => None,
        Some(content) => Some({ kind: kind, key: opt_field(j, "key"), content: content, why: opt_field(j, "why") }),
      },
    },
  }
}

fn field(j :: jv.Json, name :: Str) -> Option[Str] {
  match jv.get_field(j, name) {
    Some(JStr(s)) => Some(s),
    _ => None,
  }
}

fn opt_field(j :: jv.Json, name :: Str) -> Str {
  match field(j, name) {
    Some(s) => s,
    None => "",
  }
}

# Append one proposal. Read-concat-write rather than a real append, because
# std.io has no append mode; the file is small by construction because
# consolidation empties it.
#
# `[io]` and nothing else, deliberately: this is what the `remember` tool
# calls, and the tool row is `[net, io, proc]`. Creating `.lex/` would need
# `fs_write` and would put this out of the tool's reach, so the directory is
# ensured by `consolidate.ensure_dir`, which runs where that effect is
# already granted. A proposal made before the directory exists returns Err
# and is simply lost — the correct outcome for a store nothing has read yet.
fn propose(c :: Candidate) -> [io] Result[Unit, Str] {
  let prev := match io.read(path()) {
    Ok(s) => s,
    Err(_) => "",
  }
  match io.write(path(), str.join([prev, encode(c), "\n"], "")) {
    Err(m) => Err(m),
    Ok(_) => Ok(()),
  }
}

fn pending() -> [io] List[Candidate] {
  match io.read(path()) {
    Err(_) => [],
    Ok(content) => list.fold(str.split(content, "\n"), [], fn (acc :: List[Candidate], line :: Str) -> List[Candidate] {
      match decode(line) {
        None => acc,
        Some(c) => list.concat(acc, [c]),
      }
    }),
  }
}

# Consolidation calls this once it has durably recorded what it took. Losing
# the file after a crash mid-consolidation would re-propose, not lose: the
# same candidate reconciles to the same outcome.
fn clear() -> [io] Unit {
  let __w := io.write(path(), "")
  ()
}

