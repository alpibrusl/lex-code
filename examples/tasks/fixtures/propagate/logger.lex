# lex-code — eval fixture: effect propagation, leaf function
#
# record_event is pure today. examples/tasks/widen_effect.task asks an
# agent to make it print each event via std.io.print, widening its row to
# [io] — and, since an effectful fn can't carry an examples{} block, that
# block has to go too. Both callers (audit.lex, report.lex) need widening
# to match, transitively — the checker-driven fixed-point loop
# src/tools/propagate_effect.lex's own header describes.

fn record_event(msg :: Str) -> Str
  examples {
    record_event("build ok") => "build ok"
  }
{
  msg
}

