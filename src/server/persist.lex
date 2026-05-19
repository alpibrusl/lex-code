import "lex-trail/log"   as trail_log
import "lex-trail/kinds" as kinds
import "lex-trail/event" as ev

import "std.str" as str

fn session_db_path(session_id :: Str) -> Str {
  str.concat(".lex/sessions/", str.concat(session_id, ".db"))
}

fn open_persistent(session_id :: Str) -> [sql, fs_write] Result[trail_log.Log, Str] {
  trail_log.open(session_db_path(session_id))
}

fn open_ephemeral() -> [sql, fs_write] Result[trail_log.Log, Str] {
  trail_log.open_memory()
}

fn log_turn_start(log :: trail_log.Log, parent :: Option[Str], user_text :: Str)
  -> [sql, time] Result[ev.Event, Str] {
  let payload := str.concat("{\"role\":\"user\",\"text\":\"", str.concat(user_text, "\"}" ))
  trail_log.append(log, kinds.llm_step(), parent, payload)
}

fn log_turn_done(log :: trail_log.Log, parent :: Option[Str], assistant_text :: Str)
  -> [sql, time] Result[ev.Event, Str] {
  let payload := str.concat("{\"role\":\"assistant\",\"text\":\"", str.concat(assistant_text, "\"}"))
  trail_log.append(log, kinds.llm_step(), parent, payload)
}
