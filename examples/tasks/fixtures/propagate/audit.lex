import "./logger" as logger

import "std.list" as list

fn record_all(msgs :: List[Str]) -> List[Str] {
  if list.is_empty(msgs) {
    []
  } else {
    let h := match list.head(msgs) {
      Some(v) => v,
      None => "",
    }
    let t := list.tail(msgs)
    list.cons(logger.record_event(h), record_all(t))
  }
}

