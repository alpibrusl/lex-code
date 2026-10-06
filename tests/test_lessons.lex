# Tests for the lessons miner (src/package_flow/lessons).
#
# The point of it is that the SAME failure on different attempts lands in one
# group (so recurrence is visible) and DIFFERENT failures do not (so a common
# error does not swallow a rare, important one). Each check has its opposite.

import "std.list" as list

import "std.io" as io

import "std.str" as str

import "../src/package_flow/lessons" as lessons

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn mismatch(fn_name :: Str, n :: Int) -> Str {
  str.join(["tool argument validation failed:\n<root>: edited src/p.lex\nlint[lex fmt]: auto-formatted\nlint[lex check]: FAILED — [example-mismatch] A case inside an `examples { ... }` block (#369) ran successfully but the function body differs.\nin ", fn_name, " at case ", int_text(n)], "")
}

fn int_text(n :: Int) -> Str {
  if n == 1 {
    "1"
  } else {
    "27"
  }
}

fn f(session :: Str, cap :: Str, text :: Str) -> lessons.Failure {
  { session: session, capability: cap, text: text }
}

fn test_same_failure_different_details_is_one_group() -> Result[Unit, Str] {
  let gs := lessons.group_failures([f("a", "edit", mismatch("month_of", 1)), f("b", "edit", mismatch("day_of_week", 27)), f("c", "edit", mismatch("civil", 1))], 3)
  check("one failure with different names and numbers groups once, across 3 sessions", list.len(gs) == 1 and list.fold(gs, false, fn (x :: Bool, g :: lessons.Group) -> Bool {
    x or g.sessions == 3 and g.count == 3
  }))
}

fn test_different_failures_stay_apart() -> Result[Unit, Str] {
  let gs := lessons.group_failures([f("a", "edit", mismatch("m", 1)), f("b", "edit", mismatch("m", 1)), f("c", "edit", "tool argument validation failed:\n<root>: old_str not found in file."), f("a", "edit", "tool argument validation failed:\n<root>: old_str not found in file."), f("b", "edit", "tool argument validation failed:\n<root>: old_str not found in file.")], 2)
  check("a mismatch and an old_str-not-found are two groups", list.len(gs) == 2)
}

fn test_same_text_other_tool_is_another_group() -> Result[Unit, Str] {
  let gs := lessons.group_failures([f("a", "edit", "error: boom"), f("b", "edit", "error: boom"), f("a", "write", "error: boom"), f("b", "write", "error: boom")], 2)
  check("the tool is part of the key", list.len(gs) == 2)
}

fn test_one_session_is_not_a_lesson() -> Result[Unit, Str] {
  let gs := lessons.group_failures([f("a", "bash", "error: boom"), f("a", "bash", "error: boom"), f("a", "bash", "error: boom")], 2)
  check("many failures in ONE session do not reach a threshold of 2 sessions", list.is_empty(gs))
}

fn test_widest_first() -> Result[Unit, Str] {
  let gs := lessons.group_failures([f("a", "bash", "error: rare"), f("b", "bash", "error: rare"), f("a", "bash", "error: common"), f("b", "bash", "error: common"), f("c", "bash", "error: common")], 2)
  check("the failure seen in more sessions is listed first", match list.head(gs) {
    Some(g) => g.sig == "bash: error: common",
    None => false,
  })
}

fn test_raw_newlines_in_a_payload_are_read() -> Result[Unit, Str] {
  let p := "{\"capability\":\"edit\",\"error\":{\"error\":\"tool argument validation failed:\n<root>: old_str not found in file.\"}}"
  let r := lessons.failure_of("s", p)
  check("a payload that is not valid JSON (raw newline in a string) still yields tool and text", r.capability == "edit" and str.contains(r.text, "old_str not found"))
}

fn test_valid_json_payload_is_read() -> Result[Unit, Str] {
  let r := lessons.failure_of("s", "{\"capability\":\"bash\",\"error\":{\"error\":\"timed out\"}}")
  check("a valid payload yields tool and text", r.capability == "bash" and r.text == "timed out")
}

fn suite() -> List[Result[Unit, Str]] {
  [test_same_failure_different_details_is_one_group(), test_different_failures_stay_apart(), test_same_text_other_tool_is_another_group(), test_one_session_is_not_a_lesson(), test_widest_first(), test_raw_newlines_in_a_payload_are_read(), test_valid_json_payload_is_read()]
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

