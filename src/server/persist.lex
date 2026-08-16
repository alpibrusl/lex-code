# persist — where a session's trail log lives.
#
# Message recording moved to session_events.lex (#54): the old
# log_turn_start/log_turn_done helpers here were lossy (string-concatenated
# JSON that never escaped quotes) and had no readers — the durable
# conversation record is now the session_events vocabulary, written and
# derived by session.lex on every turn.

import "lex-trail/log" as trail_log

import "std.str" as str

fn session_db_path(session_id :: Str) -> Str
  examples {
    session_db_path("abc") => ".lex/sessions/abc.db"
  }
{
  str.concat(".lex/sessions/", str.concat(session_id, ".db"))
}

fn open_persistent(session_id :: Str) -> [sql, fs_write] Result[trail_log.Log, Str] {
  trail_log.open(session_db_path(session_id))
}

fn open_ephemeral() -> [sql, fs_write] Result[trail_log.Log, Str] {
  trail_log.open_memory()
}

