# lex-code — turn candidates into memory, or refuse to
#
# The gate the `remember` tool cannot cross. Candidates are proposals with no
# authority; this is where one becomes a fact the next session will read, and
# where the trail records that it did.
#
# Every promotion writes two things:
#
#   a trail event      what was recorded, and the candidate's own stated why
#   an attestation     the rule that accepted it, chained to that event
#
# so `attest.chain(log, event_id)` answers "why does the agent believe this"
# with something better than "it said so once". A fact in the store is
# attested by construction: nothing else writes there. That is what lets the
# prompt carry memory without carrying a disclaimer — an unattested belief
# never leaves the candidates file.
#
# ---- why this opens its own log ------------------------------------------
#
# Not the session's. `persist.open_ephemeral` is `trail_log.open_memory` — a
# session's trail is IN MEMORY and gone when the process exits. Writing
# memory provenance there would have produced attestations that satisfy the
# design on paper and are unreadable an hour later, which is worse than not
# claiming provenance at all.
#
# Memory is project-scoped and outlives every session, so its trail is too:
# `.lex/memory_trail.db`, opened here and closed here. The session id goes in
# the payload rather than as a parent link, because a parent pointing into a
# different database is a dangling reference dressed as a chain.
#
# ---- the reconciliation rules --------------------------------------------
#
# Deliberately mechanical, not model-judged. A model deciding which of two
# contradictory beliefs to keep is the failure this whole mechanism exists to
# contain, and it would need an LLM call on a path that must run at session
# start. The rules:
#
#   unknown kind        REJECTED  — the agent invented a category
#   empty content       REJECTED  — nothing to record
#   no existing fact    ACCEPTED
#   identical content   SKIPPED   — already known, no event, no noise
#   different content   SUPERSEDED — the candidate wins, and the trail keeps
#                                    the previous value so the change is
#                                    inspectable rather than silent
#   keyless kinds       ACCEPTED  — recent_change accumulates by design
#
# Superseding on conflict rather than keeping the old value is the one
# judgement here. A project's conventions change, and memory that cannot be
# corrected is worse than memory that can be corrected wrongly — but only
# because the correction is recorded. Take away the trail event and the
# opposite choice would be right.

import "./candidates" as cand

import "../project_memory" as pm

import "lex-trail/log" as trail_log

import "lex-trail/attest" as attest

import "lex-schema/json_value" as jv

import "std.fs" as fs

import "std.str" as str

import "std.list" as list

import "std.int" as int

type Verdict = Accepted | Superseded(Str) | Skipped | Rejected(Str)

type Outcome = { candidate :: cand.Candidate, verdict :: Verdict }

fn trail_path() -> Str
  examples {
    trail_path() => ".lex/memory_trail.db"
  }
{
  ".lex/memory_trail.db"
}

fn kind_event() -> Str {
  "memory.recorded"
}

fn kind_attestation() -> Str {
  "memory.reconciled"
}

# Kinds that accumulate rather than upsert: a change log has no key to
# collide on, so every candidate is new information.
fn is_keyless(kind :: Str) -> Bool
  examples {
    is_keyless("recent_change") => true,
    is_keyless("convention") => false,
    is_keyless("known_issue") => false
  }
{
  kind == "recent_change"
}

fn verdict_label(v :: Verdict) -> Str
  examples {
    verdict_label(Accepted) => "accepted",
    verdict_label(Skipped) => "skipped (already known)",
    verdict_label(Superseded("old text")) => "superseded (was: old text)",
    verdict_label(Rejected("bad kind")) => "rejected (bad kind)"
  }
{
  match v {
    Accepted => "accepted",
    Skipped => "skipped (already known)",
    Superseded(prev) => str.join(["superseded (was: ", prev, ")"], ""),
    Rejected(why) => str.join(["rejected (", why, ")"], ""),
  }
}

fn wrote(v :: Verdict) -> Bool
  examples {
    wrote(Accepted) => true,
    wrote(Superseded("x")) => true,
    wrote(Skipped) => false,
    wrote(Rejected("x")) => false
  }
{
  match v {
    Accepted => true,
    Superseded(_) => true,
    _ => false,
  }
}

# The pure half of the decision: given a candidate and whatever the store
# already holds for its (kind, key), what should happen. Separated from the
# writing so the rules are testable without a database.
fn decide(c :: cand.Candidate, existing :: Option[Str]) -> Verdict
  examples {
    decide({ kind: "vibes", key: "", content: "x", why: "" }, None) => Rejected("unknown kind: vibes"),
    decide({ kind: "convention", key: "fmt", content: "   ", why: "" }, None) => Rejected("empty content"),
    decide({ kind: "convention", key: "fmt", content: "run lex fmt", why: "" }, None) => Accepted,
    decide({ kind: "convention", key: "fmt", content: "run lex fmt", why: "" }, Some("run lex fmt")) => Skipped,
    decide({ kind: "convention", key: "fmt", content: "run lex fmt --check", why: "" }, Some("run lex fmt")) => Superseded("run lex fmt"),
    decide({ kind: "recent_change", key: "", content: "added streaming", why: "" }, Some("anything")) => Accepted
  }
{
  if cand.is_known_kind(c.kind) {
    if str.is_empty(str.trim(c.content)) {
      Rejected("empty content")
    } else {
      if is_keyless(c.kind) {
        Accepted
      } else {
        match existing {
          None => Accepted,
          Some(prev) => if prev == c.content {
            Skipped
          } else {
            Superseded(prev)
          },
        }
      }
    }
  } else {
    Rejected(str.concat("unknown kind: ", c.kind))
  }
}

fn event_payload(c :: cand.Candidate, v :: Verdict, session_id :: Str) -> Str {
  jv.stringify(JObj([("kind", JStr(c.kind)), ("key", JStr(c.key)), ("content", JStr(c.content)), ("why", JStr(c.why)), ("verdict", JStr(verdict_label(v))), ("session", JStr(session_id))]))
}

fn ensure_dir() -> [fs_write] Unit {
  let __d := fs.mkdir_p(cand.dir())
  ()
}

# Reconcile every pending candidate, then clear the file.
#
# Returns a human-readable report rather than writing one: the caller decides
# whether a session start is the right place to say "3 candidates, 2
# accepted", and a silent consolidation is a valid choice for a server.
fn run(session_id :: Str) -> [io, sql, fs_read, fs_write, time, crypto, random] List[Str] {
  let __d := ensure_dir()
  let pending := cand.pending()
  if list.is_empty(pending) {
    []
  } else {
    match trail_log.open(trail_path()) {
      Err(e) => [str.concat("memory trail unavailable, candidates kept: ", e)],
      Ok(log) => match pm.open() {
        Err(e) => [str.concat("memory unavailable, candidates kept: ", e)],
        Ok(store) => {
          let lines := list.map(pending, fn (c :: cand.Candidate) -> [io, sql, fs_read, fs_write, time, crypto, random] Str {
            reconcile_one(store, log, session_id, c)
          })
          let __c := pm.close(store)
          let __x := cand.clear()
          lines
        },
      },
    }
  }
}

fn reconcile_one(store :: pm.ProjectMemory, log :: trail_log.Log, session_id :: Str, c :: cand.Candidate) -> [io, sql, fs_read, fs_write, time, crypto, random] Str {
  let existing := if is_keyless(c.kind) {
    None
  } else {
    match pm.recall_by_key(store, c.kind, c.key) {
      None => None,
      Some(entry) => Some(entry.content),
    }
  }
  let v := decide(c, existing)
  let __w := if wrote(v) {
    pm.store_fact(store, c.kind, c.key, c.content)
  } else {
    ()
  }
  let __t := record(log, session_id, c, v)
  str.join(["  ", c.kind, "/", c.key, ": ", verdict_label(v)], "")
}

# A rejected candidate is recorded too. An agent repeatedly proposing a kind
# that does not exist is a prompt problem, and it is only visible if the
# refusals are written down somewhere.
fn record(log :: trail_log.Log, session_id :: Str, c :: cand.Candidate, v :: Verdict) -> [sql, time] Unit {
  match trail_log.append(log, kind_event(), None, event_payload(c, v, session_id)) {
    Err(_) => (),
    Ok(evt) => {
      let __a := attest.add(log, evt.id, kind_attestation(), jv.stringify(JObj([("rule", JStr(verdict_label(v))), ("wrote", JBool(wrote(v)))])))
      ()
    },
  }
}

fn report(lines :: List[Str]) -> Str
  examples {
    report([]) => "",
    report(["  convention/fmt: accepted"]) => "memory: 1 candidate reconciled\n  convention/fmt: accepted"
  }
{
  if list.is_empty(lines) {
    ""
  } else {
    str.join([str.join(["memory: ", int.to_str(list.len(lines)), " candidate", plural(list.len(lines)), " reconciled"], ""), "\n", str.join(lines, "\n")], "")
  }
}

fn plural(n :: Int) -> Str
  examples {
    plural(1) => "",
    plural(2) => "s",
    plural(0) => "s"
  }
{
  if n == 1 {
    ""
  } else {
    "s"
  }
}

