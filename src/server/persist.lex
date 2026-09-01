# persist — where a session's trail log lives.
#
# Message recording moved to session_events.lex (#54): the old
# log_turn_start/log_turn_done helpers here were lossy (string-concatenated
# JSON that never escaped quotes) and had no readers — the durable
# conversation record is now the session_events vocabulary, written and
# derived by session.lex on every turn.

import "lex-trail/log" as trail_log

import "std.str" as str

import "std.fs" as fs

import "std.list" as list

fn session_db_path(session_id :: Str) -> Str
  examples {
    session_db_path("abc") => ".lex/sessions/abc.db"
  }
{
  str.concat(".lex/sessions/", str.concat(session_id, ".db"))
}

# Creates `.lex/sessions/` first. `trail_log.open` does not, and sqlite will
# not create a database under a directory that does not exist — so without
# this the very first web request fails with "unable to open database file"
# on a clean checkout. `mkdir_p` is [fs_write], which this row already
# carries, so the fix costs nothing at the type level.
fn open_persistent(session_id :: Str) -> [sql, fs_write] Result[trail_log.Log, Str] {
  let __d := fs.mkdir_p(sessions_dir())
  trail_log.open(session_db_path(session_id))
}

fn open_ephemeral() -> [sql, fs_write] Result[trail_log.Log, Str] {
  trail_log.open_memory()
}

# ── Housekeeping ──────────────────────────────────────────────────────────────
#
# A web session's log is a file now, not an in-memory handle, so the
# directory grows one database per conversation and nothing removes them.
# That is the cost of surviving a restart, and it is only acceptable with a
# bound.
#
# The sweep runs once at server start rather than per request: it touches the
# whole directory, and doing that on a request path would put a linear cost
# on every turn to reclaim bytes that are not urgent. A long-running server
# accumulates for as long as it runs and clears on the next start, which is
# the right trade for a file that is a few dozen KB.
#
# Age, not count. An LRU by count would evict the oldest conversation while a
# user is still in it; age at least maps to "nobody has touched this", and
# `stat.mtime` moves on every turn because the log is appended to.
fn max_session_age_days() -> Int
  examples {
    max_session_age_days() => 30
  }
{
  30
}

fn ms_per_day() -> Int
  examples {
    ms_per_day() => 86400000
  }
{
  86400000
}

fn sessions_dir() -> Str
  examples {
    sessions_dir() => ".lex/sessions"
  }
{
  ".lex/sessions"
}

# Is a log old enough to remove, given now and its mtime?
#
# Pure, so the boundary is testable without waiting a month. A future mtime
# (clock skew, a restored backup) yields a negative age and is kept — never
# delete on a timestamp that makes no sense.
fn is_expired(now_ms :: Int, mtime_ms :: Int, max_age_days :: Int) -> Bool
  examples {
    is_expired(1000000000, 1000000000, 30) => false,
    is_expired(1000000000, 0, 30) => false,
    is_expired(2592000000, 0, 30) => false,
    is_expired(2592000001, 0, 30) => true,
    is_expired(1000, 999999999, 30) => false
  }
{
  let age := now_ms - mtime_ms
  if age < 0 {
    false
  } else {
    age > max_age_days * ms_per_day()
  }
}

# Two things here are easy to get wrong and were, until this was run against
# a real directory:
#
#   `fs.list_dir` returns FULL PATHS, not bare names. Joining the directory
#   onto them produced `.lex/sessions/.lex/sessions/x.db`, every stat failed,
#   and the sweep quietly removed nothing — a no-op that reports success.
#
#   `stat.mtime` is in SECONDS; `time.now_ms` is milliseconds. Subtracting one
#   from the other makes every file look ~56 years old, so fixing only the
#   path bug would have turned a silent no-op into deleting every session log
#   on the next start. The conversion is here, and `mtime_secs_to_ms` carries
#   an example so the unit cannot drift back.
fn mtime_secs_to_ms(secs :: Int) -> Int
  examples {
    mtime_secs_to_ms(1784829857) => 1784829857000,
    mtime_secs_to_ms(0) => 0
  }
{
  secs * 1000
}

fn sweep_old_sessions(now_ms :: Int) -> [fs_walk, fs_write] Int {
  match fs.list_dir(sessions_dir()) {
    Err(_) => 0,
    Ok(paths) => list.fold(paths, 0, fn (removed :: Int, full :: Str) -> [fs_walk, fs_write] Int {
      if str.ends_with(full, ".db") {
        match fs.stat(full) {
          Err(_) => removed,
          Ok(st) => if is_expired(now_ms, mtime_secs_to_ms(st.mtime), max_session_age_days()) {
            match fs.remove(full) {
              Err(_) => removed,
              Ok(_) => removed + 1,
            }
          } else {
            removed
          },
        }
      } else {
        removed
      }
    }),
  }
}

