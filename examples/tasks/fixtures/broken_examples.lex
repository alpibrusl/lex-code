# lex-code — eval fixture: a correct pure fn with a deliberately wrong example
#
# `lex check examples/tasks/fixtures/broken_examples.lex` FAILS by design —
# example-mismatch on the second `clamp` case (asserts 5, the real result
# is 0). examples/tasks/repair_examples.task asks an agent to read that
# failure and fix the wrong case; clamp's behavior itself should not change.
#
# clamp is lifted verbatim from src/prompts/lex_lang.lex's own canonical
# example — only the expected value on one example line is wrong.
#
# Modeled on examples/manifesto_parallel_bad.lex, which keeps its own
# deliberately-failing file outside src/ and tests/ so CI's blanket
# `git ls-files src/ tests/` sweep (.github/workflows/ci.yml) never
# touches it.
#
#   lex check examples/tasks/fixtures/broken_examples.lex   # → FAILS (by design)

fn clamp(n :: Int, lo :: Int, hi :: Int) -> Int
  examples {
    clamp(5, 0, 10) => 5,
    clamp(-1, 0, 10) => 5,
    clamp(99, 0, 10) => 10
  }
{
  if n < lo {
    lo
  } else {
    if n > hi {
      hi
    } else {
      n
    }
  }
}

