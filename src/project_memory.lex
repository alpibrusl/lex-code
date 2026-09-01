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

import "std.fs" as fs

import "std.str" as str

import "std.list" as list

import "std.int" as int

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

# ── Summary for prompt injection ──────────────────────────────────────────────
#
# What a session opens with is a SUMMARY, not the store. `recall_for_prompt`
# renders every entry, which is fine for a project with nine facts and wrong
# for one with nine hundred: memory that crowds out the conversation has
# stopped being an advantage. So each kind contributes at most `per_kind_cap`
# entries and the header says how many were left out — a model that can see
# the store is larger than its excerpt can ask, where one shown a silently
# truncated list cannot.
fn per_kind_cap() -> Int
  examples {
    per_kind_cap() => 5
  }
{
  5
}

fn kind_order() -> List[Str]
  examples {
    kind_order() => ["convention", "tech_stack", "known_issue", "recent_change"]
  }
{
  ["convention", "tech_stack", "known_issue", "recent_change"]
}

fn kind_label(kind :: Str) -> Str
  examples {
    kind_label("convention") => "Conventions",
    kind_label("tech_stack") => "Tech stack",
    kind_label("known_issue") => "Known issues",
    kind_label("recent_change") => "Recent changes",
    kind_label("other") => "other"
  }
{
  match kind {
    "convention" => "Conventions",
    "tech_stack" => "Tech stack",
    "known_issue" => "Known issues",
    "recent_change" => "Recent changes",
    other => other,
  }
}

# Last `n` of a list — the newest entries, since the store appends.
fn last_n[T](xs :: List[T], n :: Int) -> List[T] {
  let drop := list.len(xs) - n
  if drop <= 0 {
    xs
  } else {
    match list.fold(xs, (0, []), fn (acc :: (Int, List[T]), x :: T) -> (Int, List[T]) {
      match acc {
        (i, out) => if i < drop {
          (i + 1, out)
        } else {
          (i + 1, list.concat(out, [x]))
        },
      }
    }) {
      (_, out) => out,
    }
  }
}

fn render_fact(f :: (Str, Str, Str)) -> Str
  examples {
    render_fact(("convention", "fmt", "run lex fmt")) => "- fmt: run lex fmt",
    render_fact(("recent_change", "", "added streaming")) => "- added streaming"
  }
{
  match f {
    (_, key, content) => if str.is_empty(key) {
      str.concat("- ", content)
    } else {
      str.join(["- ", key, ": ", content], "")
    },
  }
}

# The pure shaping. Takes (kind, key, content) triples rather than
# MemoryEntry so the rules can be exercised without a database.
fn summary_of(facts :: List[(Str, Str, Str)]) -> Str
  examples {
    summary_of([]) => "",
    summary_of([("convention", "fmt", "run lex fmt")]) => "## PROJECT MEMORY (1 fact)\n\nConventions\n- fmt: run lex fmt",
    summary_of([("vibes", "x", "y")]) => "",
    summary_of([("convention", "a", "1"), ("convention", "b", "2"), ("convention", "c", "3"), ("convention", "d", "4"), ("convention", "e", "5"), ("convention", "f", "6")]) => "## PROJECT MEMORY (5 of 6 facts shown, newest per kind — ask if you need the rest)\n\nConventions\n- b: 2\n- c: 3\n- d: 4\n- e: 5\n- f: 6"
  }
{
  let sections := list.fold(kind_order(), [], fn (acc :: List[Str], kind :: Str) -> List[Str] {
    let of_kind := list.filter(facts, fn (f :: (Str, Str, Str)) -> Bool {
      match f {
        (k, _, _) => k == kind,
      }
    })
    if list.is_empty(of_kind) {
      acc
    } else {
      let shown := last_n(of_kind, per_kind_cap())
      list.concat(acc, [str.join([kind_label(kind), "\n", str.join(list.map(shown, render_fact), "\n")], "")])
    }
  })
  if list.is_empty(sections) {
    ""
  } else {
    str.join([header(facts, sections), "\n\n", str.join(sections, "\n\n")], "")
  }
}

# Says how much was left out. Silence about omission is the failure mode:
# a model told "here is the memory" reasons as if it has all of it.
fn header(facts :: List[(Str, Str, Str)], sections :: List[Str]) -> Str {
  let total := known_count(facts)
  let shown := shown_count(facts)
  if shown == total {
    str.join(["## PROJECT MEMORY (", int.to_str(total), " fact", plural(total), ")"], "")
  } else {
    str.join(["## PROJECT MEMORY (", int.to_str(shown), " of ", int.to_str(total), " facts shown, newest per kind — ask if you need the rest)"], "")
  }
}

fn plural(n :: Int) -> Str
  examples {
    plural(1) => "",
    plural(3) => "s"
  }
{
  if n == 1 {
    ""
  } else {
    "s"
  }
}

fn known_count(facts :: List[(Str, Str, Str)]) -> Int {
  list.len(list.filter(facts, fn (f :: (Str, Str, Str)) -> Bool {
    match f {
      (k, _, _) => in_order(k),
    }
  }))
}

fn shown_count(facts :: List[(Str, Str, Str)]) -> Int {
  list.fold(kind_order(), 0, fn (acc :: Int, kind :: Str) -> Int {
    let n := list.len(list.filter(facts, fn (f :: (Str, Str, Str)) -> Bool {
      match f {
        (k, _, _) => k == kind,
      }
    }))
    if n < per_kind_cap() {
      acc + n
    } else {
      acc + per_kind_cap()
    }
  })
}

fn in_order(kind :: Str) -> Bool {
  list.fold(kind_order(), false, fn (acc :: Bool, k :: Str) -> Bool {
    if acc {
      true
    } else {
      k == kind
    }
  })
}

# ── One-shot recall for prompt injection ──────────────────────────────────────
# The entry point session.lex uses, and the only one that has to be safe to
# call unconditionally: memory is a convenience, so every failure path returns
# "" and the session proceeds without it. A project that has never stored
# anything must not pay for the feature, so this checks for the store before
# opening it — `conn.connect_sqlite` CREATES the file it is pointed at, and
# starting lex-code in a directory should not leave a database behind.
#
# Every fact here reached the store through consolidation, which attests it
# in the trail. Nothing else writes to it, so there is no unattested belief
# to disclaim — a candidate the agent proposed and consolidation refused
# never gets this far.
fn recall_context() -> [sql, fs_read, fs_write, fs_walk] Str {
  if fs.exists(db_path()) {
    match open() {
      Err(_) => "",
      Ok(pm) => {
        let facts := list.map(recall_all(pm), fn (e :: mem.MemoryEntry) -> (Str, Str, Str) {
          (e.kind, e.key, e.content)
        })
        let __closed := close(pm)
        summary_of(facts)
      },
    }
  } else {
    ""
  }
}

