# Tests for the parse-error hints (src/tools/linter: translate_lex_error / parse_error_hint).
#
# The inputs are the parser's real messages, copied from running `lex check` on the construct
# each hint is about (the same strings the failed tool calls of seven from-scratch builds
# carried). The check that matters most is the first: `expected expression, got Some(Comma)`
# used to be explained as a trailing comma after `let`, which is wrong (trailing commas are
# valid everywhere) and sent models looking in the wrong place 52 times.

import "std.list" as list

import "std.io" as io

import "std.str" as str

import "../src/tools/linter" as linter

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn hint(raw :: Str) -> Str {
  linter.translate_lex_error(raw)
}

fn test_comma_means_a_misplaced_brace() -> Result[Unit, Str] {
  let h := hint("parse error at byte 26: expected expression, got Some(Comma): parse error at byte 26: expected expression, got Some(Comma)")
  check("a stray comma is explained as a brace closed too early, not as a let-binding comma", str.contains(h, "`}` closed too early") and not str.contains(h, "NO trailing comma"))
}

fn test_tuple_index() -> Result[Unit, Str] {
  check("p.0 and let (a, b) are explained with the match-destructure form", str.contains(hint("parse error at byte 33: expected identifier after `.`, got Some(Int(0))"), "match p { (a, b) =>") and str.contains(hint("parse error at byte 37: expected identifier after `let`, got Some(LParen)"), "Destructure in a match"))
}

fn test_the_other_slips() -> Result[Unit, Str] {
  check("match arms, :=, no else, //, return, <>, ::, block brackets", str.contains(hint("parse error at byte 56: expected RBrace after match arms, got Ident(\"None\")"), "separated by commas") and str.contains(hint("parse error at byte 44: expected expression, got Some(ColonEq)"), "no assignment") and str.contains(hint("parse error at byte 39: expected Else expected `else`, got RBrace"), "needs an `else`") and str.contains(hint("parse error at byte 17: expected expression, got Some(Slash)"), "start with `#`") and str.contains(hint("parse error at byte 16: expected expression, got Some(Return)"), "no `return`") and str.contains(hint("parse error at byte 14: expected RParen after params, got Lt"), "square brackets") and str.contains(hint("parse error at byte 39: expected expression, got Some(ColonColon)"), "list.cons") and str.contains(hint("parse error at byte 36: expected LBrace before block, got LBracket"), "must start with `{`"))
}

fn test_existing_hints_survive() -> Result[Unit, Str] {
  check("else-if and list-pattern hints are unchanged", str.contains(hint("expected LBrace before block, got If"), "else if") and str.contains(hint("expected pattern, got Some(LBracket)"), "list pattern"))
}

fn test_unknown_text_passes_through() -> Result[Unit, Str] {
  check("an error nobody has a hint for is passed through, trimmed", hint("  parse error at byte 5: something new  ") == "parse error at byte 5: something new")
}

fn test_strparam() -> Result[Unit, Str] {
  check("sql.StrParam points at PStr/PInt", str.contains(hint("{\"kind\":\"unknown_field\",\"field\":\"StrParam\"}"), "PStr(s)"))
}

fn suite() -> List[Result[Unit, Str]] {
  [test_comma_means_a_misplaced_brace(), test_tuple_index(), test_the_other_slips(), test_existing_hints_survive(), test_unknown_text_passes_through(), test_strparam()]
}

fn run_all() -> [io] Unit {
  let results := suite()
  let __dbg := list.map(results, fn (r :: Result[Unit, Str]) -> [io] Unit {
    match r {
      Ok(_) => (),
      Err(e) => io.print(str.concat("FAIL: ", e)),
    }
  })
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __force_fail := 1 / 0
    ()
  }
}

