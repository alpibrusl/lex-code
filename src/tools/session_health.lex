# lex-code — a mechanical audit of one session's own trail, so "how's it
# doing" answers from one command instead of a manual SQLite session.
#
# Built after a real --auto trial silently burned 4.5 hours on a bash-
# tool bug (every call taking almost exactly its 300s watchdog ceiling,
# real work or not) that only per-call timestamps in the trail exposed —
# the log text alone read like ordinary, if verbose, agent reasoning.
# `cap.invoked`/`cap.completed`/`cap.failed` events are already written
# for every tool call (`session_events.lex`'s own event kinds), and
# `parent` already links a completion back to its own invocation — this
# just joins that pairing and reports on it, rather than requiring
# anyone to write that join by hand under time pressure.
#
# Deliberately mechanical: known hardcoded timeout ceilings are named
# explicitly (`known_ceilings_ms`) and a cluster of calls landing near
# one is flagged as "probably hitting this timeout repeatedly", not
# scored by any model's judgment of what looks slow.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.io" as io

import "std.sql" as sql

import "lex-trail/log" as trail_log

import "lex-schema/json_value" as jv

# Known hardcoded timeout ceilings in this codebase. A run of calls that
# cluster near one of these is a specific, checkable claim ("probably
# hitting this timeout"), not just "the numbers look high" — update this
# list if a new hardcoded timeout is added elsewhere.
fn known_ceilings_ms() -> List[(Str, Int)] {
  [("the bash tool's 300s watchdog", 300000)]
}

type CallStat = { capability :: Str, start_ts :: Int, end_ts :: Int, outcome :: Str }

fn capability_of(payload :: Str) -> Str {
  match jv.parse(payload) {
    Err(_) => "?",
    Ok(j) => match jv.get_field(j, "capability") {
      None => "?",
      Some(v) => match jv.as_str(v) {
        None => "?",
        Some(s) => s,
      },
    },
  }
}

# Every capability call this session made, oldest first, paired with its
# own outcome via `parent` (not adjacency — two calls can interleave).
fn load_calls(path :: Str) -> [sql, fs_write] Result[List[CallStat], Str] {
  match trail_log.open(path) {
    Err(e) => Err(e),
    Ok(log) => {
      let q := "SELECT a.ts_ms AS start_ts, b.ts_ms AS end_ts, b.kind AS outcome, a.payload_json AS args FROM events a JOIN events b ON b.parent = a.id WHERE a.kind = 'cap.invoked' AND b.kind IN ('cap.completed', 'cap.failed') ORDER BY a.ts_ms ASC"
      match trail_log.xquery(log.db, q, []) {
        Err(e) => Err(e.message),
        Ok(rows) => Ok(list.map(rows, fn (r :: sql.Row) -> CallStat {
          { capability: capability_of(match sql.get_str(r, "args") {
            None => "{}",
            Some(s) => s,
          }), start_ts: match sql.get_int(r, "start_ts") {
            None => 0,
            Some(n) => n,
          }, end_ts: match sql.get_int(r, "end_ts") {
            None => 0,
            Some(n) => n,
          }, outcome: match sql.get_str(r, "outcome") {
            None => "?",
            Some(s) => s,
          } }
        })),
      }
    },
  }
}

fn latency_ms(c :: CallStat) -> Int {
  c.end_ts - c.start_ts
}

# Within 10% of a ceiling, on the slow side only — a call that's merely
# quick is never "near" a timeout it never approached.
fn near_ceiling(ms :: Int, ceiling :: Int) -> Bool {
  ms * 100 >= ceiling * 90
}

fn max_int(xs :: List[Int]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, x :: Int) -> Int {
    if x > acc {
      x
    } else {
      acc
    }
  })
}

fn min_int(xs :: List[Int], ceiling :: Int) -> Int {
  list.fold(xs, ceiling, fn (acc :: Int, x :: Int) -> Int {
    if x < acc {
      x
    } else {
      acc
    }
  })
}

fn sum_int(xs :: List[Int]) -> Int {
  list.fold(xs, 0, fn (acc :: Int, x :: Int) -> Int {
    acc + x
  })
}

fn ms_to_s(ms :: Int) -> Str {
  str.concat(int.to_str(ms / 1000), "s")
}

# Per-capability call count, oldest-appearance order, no external sort
# dependency: a hand-rolled stable "first occurrence" walk.
fn capability_counts(calls :: List[CallStat]) -> List[(Str, Int)] {
  list.fold(calls, [], fn (acc :: List[(Str, Int)], c :: CallStat) -> List[(Str, Int)] {
    if list.fold(acc, false, fn (found :: Bool, kv :: (Str, Int)) -> Bool {
      match kv {
        (k, _) => found or k == c.capability,
      }
    }) {
      list.map(acc, fn (kv :: (Str, Int)) -> (Str, Int) {
        match kv {
          (k, n) => if k == c.capability {
            (k, n + 1)
          } else {
            (k, n)
          },
        }
      })
    } else {
      list.concat(acc, [(c.capability, 1)])
    }
  })
}

fn ceiling_flags(calls :: List[CallStat]) -> List[Str] {
  list.fold(known_ceilings_ms(), [], fn (acc :: List[Str], kv :: (Str, Int)) -> List[Str] {
    match kv {
      (label, ceiling) => {
        let near := list.filter(calls, fn (c :: CallStat) -> Bool {
          near_ceiling(latency_ms(c), ceiling)
        })
        if list.is_empty(near) {
          acc
        } else {
          let caps := list.map(capability_counts(near), fn (kv2 :: (Str, Int)) -> Str {
            match kv2 {
              (k, n) => str.join([k, " (", int.to_str(n), ")"], ""),
            }
          })
          list.concat(acc, [str.join([int.to_str(list.len(near)), "/", int.to_str(list.len(calls)), " calls landed within 10% of ", label, " — probably hitting this timeout repeatedly, not just slow: ", str.join(caps, ", ")], "")])
        }
      },
    }
  })
}

fn report(calls :: List[CallStat]) -> Str {
  if list.is_empty(calls) {
    "no capability calls recorded in this session"
  } else {
    let n := list.len(calls)
    let latencies := list.map(calls, latency_ms)
    let total := sum_int(latencies)
    let mx := max_int(latencies)
    let mn := min_int(latencies, mx)
    let avg := total / n
    let failed := list.len(list.filter(calls, fn (c :: CallStat) -> Bool {
      c.outcome == "cap.failed"
    }))
    let by_cap := list.map(capability_counts(calls), fn (kv :: (Str, Int)) -> Str {
      match kv {
        (k, count) => str.join(["  ", k, ": ", int.to_str(count)], ""),
      }
    })
    let flags := ceiling_flags(calls)
    let flag_section := if list.is_empty(flags) {
      ""
    } else {
      str.join(["\n\n⚠ ", str.join(flags, "\n⚠ ")], "")
    }
    str.join([int.to_str(n), " calls, ", int.to_str(failed), " failed. latency: min ", ms_to_s(mn), " avg ", ms_to_s(avg), " max ", ms_to_s(mx), "\nby capability:\n", str.join(by_cap, "\n"), flag_section], "")
  }
}

fn run_session_health(path :: Str) -> [sql, fs_write, io] Nil {
  match load_calls(path) {
    Err(e) => io.print(str.join(["error: ", e], "")),
    Ok(calls) => io.print(report(calls)),
  }
}

