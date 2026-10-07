# Tests for the hand-built-JSON lint (src/tools/json_lint).
#
# The positive cases are lines copied from two real builds that answered with broken
# JSON (a reply missing its closing brace; a customer name spliced in unescaped). The
# negative cases are lines from the same builds that are fine, and the opposite of each
# rule, so a lint that flags everything or nothing fails here.

import "std.list" as list

import "std.io" as io

import "std.str" as str

import "../src/tools/json_lint" as jl

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn test_real_offending_lines_are_flagged() -> Result[Unit, Str] {
  let src := "fn hook_json(id :: Int, dup :: Str) -> Str {\n  str.concat(\"{\\\"id\\\":\", str.concat(int.to_str(id), str.concat(\",\\\"duplicate\\\":\", dup)))\n}\n\nfn b() -> Str {\n  let tail := str.concat(str.concat(\"\\\",\\\"paid\\\":false\", close), \"\")\n  tail\n}\n"
  check("webhooks and invoices lines are flagged, at their own line numbers", jl.hand_built_json_lines(src) == [2, 6])
}

fn test_constant_json_is_not_flagged() -> Result[Unit, Str] {
  let src := "fn unauth() -> resp.Response {\n  resp.json_status(401, \"{\\\"error\\\":\\\"unauthorized\\\"}\")\n}\n"
  check("a constant JSON string with no concatenation is fine", list.is_empty(jl.hand_built_json_lines(src)))
}

fn test_examples_and_comments_are_not_flagged() -> Result[Unit, Str] {
  let src := "# builds {\"a\":1} with str.concat(\n  f(\"x\") => str.concat(\"{\\\"a\\\":\", \"1\")\n"
  check("a comment and an example line are not code", list.is_empty(jl.hand_built_json_lines(src)))
}

fn test_plain_concat_is_not_flagged() -> Result[Unit, Str] {
  check("str.concat with no JSON fragment is fine", list.is_empty(jl.hand_built_json_lines("fn a() -> Str {\n  str.concat(\"hello \", name)\n}\n")))
}

fn test_the_warning_names_the_encoder_and_the_lines() -> Result[Unit, Str] {
  let w := jl.warning([3, 9])
  check("the warning lists the lines and names jv.stringify", str.contains(w, "lines 3, 9") and str.contains(w, "jv.stringify") and jl.warning([]) == "")
}

fn suite() -> List[Result[Unit, Str]] {
  [test_real_offending_lines_are_flagged(), test_constant_json_is_not_flagged(), test_examples_and_comments_are_not_flagged(), test_plain_concat_is_not_flagged(), test_the_warning_names_the_encoder_and_the_lines()]
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

