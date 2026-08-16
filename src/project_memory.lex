# project_memory.lex — Project-scoped persistent memory for lex-code agents.
#
# Opens a dedicated SQLite (or Postgres) store at .lex/project_memory.db,
# separate from session logs so memory outlives individual sessions and
# accumulates across every mode (Build, Explore, Refactor, Review, etc.).
#
# Wraps lex-memory/src/memory (extracted from lex-agent/src/memory, see
# alpibrusl/lex-memory#1) with project-specific entry points:
#
#   convention    — coding/style conventions, upserted by name
#   tech_stack    — technology/framework facts, upserted by name
#   recent_change — notable changes, appended (no key — accumulate)
#   known_issue   — open bugs / gotchas, upserted by id
#
# Usage in agent system prompts:
#
#   match project_memory.open() {
#     Err(_)  => ()    # silently skip if .lex/ doesn't exist yet
#     Ok(pm)  => {
#       let ctx := project_memory.recall_for_prompt(pm)
#       # prepend ctx to your system prompt
#       let _ := project_memory.close(pm)
#     }
#   }

import "lex-memory/src/memory" as mem

import "lex-orm/src/connection" as conn

import "std.str" as str

import "std.list" as list

# ── Types ─────────────────────────────────────────────────────────────────────
type ProjectMemory = { db :: conn.ConnDb }

fn db_path() -> Str {
  ".lex/project_memory.db"
}

fn agent_id() -> Str {
  "project"
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
fn open() -> [sql, fs_write] Result[ProjectMemory, Str] {
  match conn.connect_sqlite(db_path()) {
    Err(_) => Err("project_memory: failed to open db"),
    Ok(db) => match mem.init_schema(db) {
      Err(e) => Err(e),
      Ok(_) => Ok({ db: db }),
    },
  }
}

fn close(pm :: ProjectMemory) -> [sql] Unit {
  conn.close(pm.db)
}

# ── Write helpers ─────────────────────────────────────────────────────────────
fn store_convention(pm :: ProjectMemory, name :: Str, content :: Str) -> [sql, fs_write, time, crypto, random] Unit {
  mem.store(pm.db, agent_id(), "convention", name, content)
}

fn store_tech(pm :: ProjectMemory, name :: Str, content :: Str) -> [sql, fs_write, time, crypto, random] Unit {
  mem.store(pm.db, agent_id(), "tech_stack", name, content)
}

fn store_recent_change(pm :: ProjectMemory, content :: Str) -> [sql, fs_write, time, crypto, random] Unit {
  mem.store(pm.db, agent_id(), "recent_change", "", content)
}

fn store_known_issue(pm :: ProjectMemory, id :: Str, content :: Str) -> [sql, fs_write, time, crypto, random] Unit {
  mem.store(pm.db, agent_id(), "known_issue", id, content)
}

fn store_fact(pm :: ProjectMemory, kind :: Str, key :: Str, content :: Str) -> [sql, fs_write, time, crypto, random] Unit {
  mem.store(pm.db, agent_id(), kind, key, content)
}

# ── Read helpers ──────────────────────────────────────────────────────────────
fn recall_all(pm :: ProjectMemory) -> [sql, fs_read] List[mem.MemoryEntry] {
  mem.recall_all(pm.db, agent_id())
}

fn recall_kind(pm :: ProjectMemory, kind :: Str) -> [sql, fs_read] List[mem.MemoryEntry] {
  mem.recall_kind(pm.db, agent_id(), kind)
}

fn recall_by_key(pm :: ProjectMemory, kind :: Str, key :: Str) -> [sql, fs_read] Option[mem.MemoryEntry] {
  mem.recall_by_key(pm.db, agent_id(), kind, key)
}

# ── Prompt injection ──────────────────────────────────────────────────────────
fn recall_for_prompt(pm :: ProjectMemory) -> [sql, fs_read] Str {
  let entries := mem.recall_all(pm.db, agent_id())
  mem.to_context(entries)
}

fn recall_kind_for_prompt(pm :: ProjectMemory, kind :: Str) -> [sql, fs_read] Str {
  let entries := mem.recall_kind(pm.db, agent_id(), kind)
  mem.to_context(entries)
}

# ── Bulk snapshot helpers ─────────────────────────────────────────────────────
fn store_many(pm :: ProjectMemory, entries :: List[(Str, Str, Str)]) -> [sql, fs_write, time, crypto, random] Unit {
  let __r := list.map(entries, fn (e :: (Str, Str, Str)) -> [sql, fs_write, time, crypto, random] Unit {
    match e {
      (kind, key, content) => mem.store(pm.db, agent_id(), kind, key, content),
    }
  })
  ()
}

