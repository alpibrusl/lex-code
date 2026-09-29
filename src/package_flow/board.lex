# lex-code — drive a project of typed issues to done
#
# `--project=P` loops over the project's board: ask `lex issue next` what
# can start, run one issue, verify it, re-verify the whole project, repeat.
# This module is the pure half — reading the board and deciding the next
# step — so the rules that stop a run from spinning forever are covered by
# examples instead of by a live model.
#
# The rules, each from something that actually went wrong:
#   - a bounded number of attempts per issue, then it is given up on;
#   - after a few failures with the primary model, the issue is handed to a
#     fallback (a stronger or different one) instead of repeating the same
#     mistake, and only then given up on;
#   - "nothing left to run" is either DONE (every issue verified) or STUCK
#     (work remains but nothing is ready), never a silent success.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

type Ready = { id :: Str, title :: Str }

type Board = { done :: Bool, ready :: List[Ready], total :: Int, verified :: Int }

# The decision. Constructor names are prefixed: Lex constructors share one
# flat namespace across imports, so a bare `Done` would collide.
type PkgStep = PkgRun((Str, Str)) | PkgDone | PkgStuck(Str)

fn parse_ready(j :: jv.Json) -> Ready {
  { id: ic.field_text(j, "issue_id"), title: ic.field_text(j, "title") }
}

fn count_of(j :: jv.Json, key :: Str) -> Int {
  match jv.get_field(j, key) {
    None => 0,
    Some(v) => match jv.as_int(v) {
      None => 0,
      Some(n) => n,
    },
  }
}

fn done_of(j :: jv.Json) -> Bool {
  match jv.get_field(j, "done") {
    None => false,
    Some(v) => match jv.as_bool(v) {
      None => false,
      Some(b) => b,
    },
  }
}

# `lex --output json issue next` → the board.
fn parse_board(stdout :: Str) -> Result[Board, Str]
  examples {
    parse_board("nope") => Err("`lex issue next` did not return JSON"),
    parse_board("{\"ok\": true, \"data\": {\"done\": true, \"counts\": {\"total\": 2, \"verified\": 2}, \"ready\": []}}") => Ok({ done: true, ready: [], total: 2, verified: 2 }),
    parse_board("{\"ok\": true, \"data\": {\"done\": false, \"counts\": {\"total\": 3, \"verified\": 1}, \"ready\": [{\"issue_id\": \"a\", \"title\": \"A\"}]}}") => Ok({ done: false, ready: [{ id: "a", title: "A" }], total: 3, verified: 1 })
  }
{
  match jv.parse(str.trim(stdout)) {
    Err(_) => Err("`lex issue next` did not return JSON"),
    Ok(env) => match jv.get_field(env, "data") {
      None => Err("`lex issue next` returned no data"),
      Some(d) => {
        let counts := match jv.get_field(d, "counts") {
          None => d,
          Some(c) => c,
        }
        Ok({ done: done_of(d), ready: list.map(ic.field_list(d, "ready"), parse_ready), total: count_of(counts, "total"), verified: count_of(counts, "verified") })
      },
    },
  }
}

fn attempts_of(attempts :: List[(Str, Int)], id :: Str) -> Int
  examples {
    attempts_of([("a", 2), ("b", 1)], "b") => 1,
    attempts_of([("a", 2)], "z") => 0,
    attempts_of([], "a") => 0
  }
{
  list.fold(attempts, 0, fn (acc :: Int, p :: (Str, Int)) -> Int {
    match p {
      (k, n) => if k == id {
        n
      } else {
        acc
      },
    }
  })
}

fn bump_attempts(attempts :: List[(Str, Int)], id :: Str) -> List[(Str, Int)]
  examples {
    bump_attempts([], "a") => [("a", 1)],
    bump_attempts([("a", 1)], "a") => [("a", 2)],
    bump_attempts([("a", 1)], "b") => [("a", 1), ("b", 1)]
  }
{
  let n := attempts_of(attempts, id)
  let rest := list.filter(attempts, fn (p :: (Str, Int)) -> Bool {
    match p {
      (k, _) => k != id,
    }
  })
  list.concat(rest, [(id, n + 1)])
}

# Which provider an attempt runs on: the primary until it has failed
# `switch_after` times on this issue, then the fallback if there is one.
fn provider_for(tried :: Int, primary :: Str, fallback :: Option[Str], switch_after :: Int) -> Str
  examples {
    provider_for(0, "ollama", Some("opencode"), 2) => "ollama",
    provider_for(1, "ollama", Some("opencode"), 2) => "ollama",
    provider_for(2, "ollama", Some("opencode"), 2) => "opencode",
    provider_for(5, "ollama", None, 2) => "ollama"
  }
{
  if tried >= switch_after {
    match fallback {
      Some(f) => f,
      None => primary,
    }
  } else {
    primary
  }
}

fn titles(rs :: List[Ready]) -> Str {
  str.join(list.map(rs, fn (r :: Ready) -> Str {
    r.title
  }), "; ")
}

# The next step. Ready issues are taken in the order the board lists them
# (creation order, so the planner's order). One that has used up its
# attempts is skipped — its dependents then never become ready, which is
# what `PkgStuck` reports.
fn decide(board :: Board, attempts :: List[(Str, Int)], primary :: Str, fallback :: Option[Str], switch_after :: Int, max_attempts :: Int) -> PkgStep
  examples {
    decide({ done: true, ready: [], total: 2, verified: 2 }, [], "ollama", None, 2, 4) => PkgDone,
    decide({ done: false, ready: [{ id: "a", title: "A" }], total: 2, verified: 0 }, [], "ollama", None, 2, 4) => PkgRun("a", "ollama"),
    decide({ done: false, ready: [{ id: "a", title: "A" }], total: 2, verified: 0 }, [("a", 2)], "ollama", Some("opencode"), 2, 4) => PkgRun("a", "opencode"),
    decide({ done: false, ready: [{ id: "a", title: "A" }, { id: "b", title: "B" }], total: 3, verified: 0 }, [("a", 4)], "ollama", None, 2, 4) => PkgRun("b", "ollama"),
    decide({ done: false, ready: [], total: 2, verified: 1 }, [], "ollama", None, 2, 4) => PkgStuck("nothing is ready but 1 of 2 issues are not verified — a dependency cannot be met"),
    decide({ done: false, ready: [{ id: "a", title: "A" }], total: 2, verified: 0 }, [("a", 4)], "ollama", None, 2, 4) => PkgStuck("gave up after 4 attempts on: A")
  }
{
  if board.done {
    PkgDone
  } else {
    let open := list.filter(board.ready, fn (r :: Ready) -> Bool {
      attempts_of(attempts, r.id) < max_attempts
    })
    match list.head(open) {
      Some(r) => PkgRun(r.id, provider_for(attempts_of(attempts, r.id), primary, fallback, switch_after)),
      None => if list.is_empty(board.ready) {
        PkgStuck(str.join(["nothing is ready but ", int.to_str(board.total - board.verified), " of ", int.to_str(board.total), " issues are not verified — a dependency cannot be met"], ""))
      } else {
        PkgStuck(str.join(["gave up after ", int.to_str(max_attempts), " attempts on: ", titles(board.ready)], ""))
      },
    }
  }
}

# `--flag=value` → value, when the value is non-empty.
fn flag_value(argv :: List[Str], prefix :: Str) -> Option[Str]
  examples {
    flag_value(["--project=asn1", "--ollama"], "--project=") => Some("asn1"),
    flag_value(["--project="], "--project=") => None,
    flag_value(["--ollama"], "--project=") => None,
    flag_value([], "--project=") => None
  }
{
  match list.head(list.filter(argv, fn (a :: Str) -> Bool {
    str.starts_with(a, prefix)
  })) {
    None => None,
    Some(tok) => match str.strip_prefix(tok, prefix) {
      None => None,
      Some(v) => if str.is_empty(v) {
        None
      } else {
        Some(v)
      },
    },
  }
}

# `--flag=N` → N, else the default. A bad number is the default, not a crash.
fn flag_int(argv :: List[Str], prefix :: Str, default :: Int) -> Int
  examples {
    flag_int(["--max-attempts=6"], "--max-attempts=", 4) => 6,
    flag_int(["--max-attempts=x"], "--max-attempts=", 4) => 4,
    flag_int([], "--max-attempts=", 4) => 4
  }
{
  match flag_value(argv, prefix) {
    None => default,
    Some(v) => match str.to_int(v) {
      None => default,
      Some(n) => n,
    },
  }
}

# What every issue of a project is told, on top of its contract. A package is
# ONE module: the store's head tracks a single module, so publishing a second
# file silently removes the first file's functions from it (an issue that had
# verified then reads "absent at head"). The units split the work, not the
# files.
fn module_guidance(project :: Str) -> Str
  examples {
    module_guidance("textkit") => "This package is ONE module: src/textkit.lex. Put every function in that one file — create it if it does not exist — and leave every function already in it exactly as it is. Do not create any other .lex file under src/: the store tracks a single module, so a second file would silently drop the first file's functions and un-verify earlier issues. Adding a function must not change or remove another."
  }
{
  str.join(["This package is ONE module: src/", project, ".lex. Put every function in that one file — create it if it does not exist — and leave every function already in it exactly as it is. Do not create any other .lex file under src/: the store tracks a single module, so a second file would silently drop the first file's functions and un-verify earlier issues. Adding a function must not change or remove another."], "")
}

# What every issue is told when the tool has already written the module.
fn scaffold_guidance(project :: Str) -> Str
  examples {
    scaffold_guidance("textkit") => "src/textkit.lex already exists and is the whole package: every shared type and every function is there with its FINAL signature over a placeholder body of todo(). Your task is to replace the body of the function(s) this issue declares — nothing else. Do not change any signature. Leave every other function exactly as it is. You may add private helper functions below them. Do not create any other .lex file under src/."
  }
{
  str.join(["src/", project, ".lex already exists and is the whole package: every shared type and every function is there with its FINAL signature over a placeholder body of todo(). Your task is to replace the body of the function(s) this issue declares — nothing else. Do not change any signature. Leave every other function exactly as it is. You may add private helper functions below them. Do not create any other .lex file under src/."], "")
}

