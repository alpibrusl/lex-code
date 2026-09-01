# Tests for os_check's trust-grant arithmetic (src/tools/os_grant.lex).
#
# os_check is the tool that answers "does this file exceed the grant my
# mode runs under". Three separate defects made it answer "no" when the
# honest answer was "yes" or "I cannot tell":
#
#   1. INCOMPLETE NETWORK DENY-LIST — it forbade `net` only, while the
#      trust lattice classifies net, http, mcp and llm_cloud all as
#      network egress. A file declaring [llm_cloud] cleared a net=none
#      grant.
#   2. FAIL-OPEN ON MALFORMED INPUT — a missing or non-list
#      `data.required_effects` yielded `[]`, which is indistinguishable
#      from "this file needs no effects" and so reported a pass.
#   3. VIOLATIONS RETURNED `Ok` — a GRANT VIOLATION arrived as a success
#      string the model could read past, not an error.
#
# Defect 1's fix also required the mode to stop being a model-supplied
# argument, which is why mode_of_spec is asserted here too: if it ever
# fell through to "build" — the mode that forbids nothing — every grant
# in the table below would silently evaporate.
#
# os_grant.lex is pure, so this file declares no effects beyond [io] for
# failure reporting. Importing os_check.lex instead would drag in
# [net, proc] and be refused by the `lex test` grant before any
# assertion ran.

import "std.list" as list

import "std.str" as str

import "std.io" as io

import "lex-schema/json_value" as jv

import "../src/tools/os_grant" as grant

import "../src/permissions/rules" as rules

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn forbids(mode :: Str, effect :: Str) -> Bool {
  grant.effect_in(effect, grant.forbidden_for_mode(mode))
}

fn extract_fails(j :: jv.Json) -> Bool {
  match grant.extract_effects(j) {
    Ok(_) => false,
    Err(_) => true,
  }
}

fn verdict_is_err(mode :: Str, required :: List[Str]) -> Bool {
  match grant.verdict(mode, required) {
    Ok(_) => false,
    Err(_) => true,
  }
}

fn check_output(effects :: jv.Json) -> jv.Json {
  JObj([("data", JObj([("required_effects", effects)]))])
}

fn strs(names :: List[Str]) -> jv.Json {
  JList(list.map(names, fn (n :: Str) -> jv.Json {
    JStr(n)
  }))
}

# ── 1. Every network effect is denied, not just `net` ─────────────────
fn test_all_network_effects_denied() -> Result[Unit, Str] {
  let net_effects := ["net", "http", "mcp", "llm_cloud"]
  let denied_everywhere := list.fold(["explore", "plan", "review", "bar", "spec", "test", "refactor"], true, fn (acc :: Bool, mode :: Str) -> Bool {
    acc and list.fold(net_effects, true, fn (inner :: Bool, eff :: Str) -> Bool {
      inner and forbids(mode, eff)
    })
  })
  check("every no-net mode forbids net, http, mcp and llm_cloud", denied_everywhere)
}

# The defect in its original form: refactor mode, a file declaring
# [llm_cloud]. This passed before.
fn test_llm_cloud_violates_refactor_grant() -> Result[Unit, Str] {
  check("refactor rejects llm_cloud and mcp", verdict_is_err("refactor", ["llm_cloud"]) and verdict_is_err("refactor", ["mcp"]) and verdict_is_err("refactor", ["fs_read", "http"]))
}

# Negative control. Without this, a forbidden_for_mode that returned
# every effect name for every mode would pass everything above.
fn test_permitted_effects_still_pass() -> Result[Unit, Str] {
  let refactor_ok := match grant.verdict("refactor", ["fs_read", "fs_write", "proc"]) {
    Ok(_) => true,
    Err(_) => false,
  }
  let build_ok := match grant.verdict("build", ["net", "llm_cloud", "mcp", "proc", "fs_write"]) {
    Ok(_) => true,
    Err(_) => false,
  }
  check("refactor allows fs+proc; build forbids nothing", refactor_ok and build_ok)
}

# ── 2. Malformed check output fails closed ────────────────────────────
fn test_malformed_output_is_an_error() -> Result[Unit, Str] {
  let no_data := JObj([("ok", JBool(true))])
  let no_field := JObj([("data", JObj([("other", JStr("x"))]))])
  let not_a_list := check_output(JStr("net"))
  let non_string_item := check_output(JList([JStr("net"), JInt(7)]))
  check("missing/malformed required_effects is Err, never an empty pass", extract_fails(no_data) and extract_fails(no_field) and extract_fails(not_a_list) and extract_fails(non_string_item))
}

# Negative control for the above: well-formed input must still parse,
# including the genuinely-empty case, which is a real pass and not a
# malformed one.
fn test_wellformed_output_still_parses() -> Result[Unit, Str] {
  let parsed := match grant.extract_effects(check_output(strs(["fs_read", "io"]))) {
    Ok(names) => str.join(names, ","),
    Err(_) => "ERR",
  }
  let empty := match grant.extract_effects(check_output(JList([]))) {
    Ok(names) => str.join(names, ","),
    Err(_) => "ERR",
  }
  check("a real effect list parses, and an empty list is a pass not an error", parsed == "fs_read,io" and empty == "")
}

# ── 3. A violation is an error, not a success string ──────────────────
fn test_violation_is_err_not_ok() -> Result[Unit, Str] {
  check("explore using net/proc/fs_write returns Err", verdict_is_err("explore", ["net"]) and verdict_is_err("explore", ["proc"]) and verdict_is_err("explore", ["fs_write"]) and verdict_is_err("spec", ["proc"]) and verdict_is_err("bar", ["fs_write"]))
}

# ── 4. The mode reaches the grant ─────────────────────────────────────
# os_check binds its mode from the permission spec instead of from a
# model-supplied argument. If this mapping fell through to "build" the
# whole table above would still pass while enforcing nothing.
fn test_mode_of_spec_maps_every_mode() -> Result[Unit, Str] {
  check("each permission spec resolves to its own mode", rules.mode_of_spec(rules.explore_permission()) == "explore" and rules.mode_of_spec(rules.plan_permission()) == "plan" and rules.mode_of_spec(rules.review_permission()) == "review" and rules.mode_of_spec(rules.bar_permission()) == "bar" and rules.mode_of_spec(rules.spec_permission()) == "spec" and rules.mode_of_spec(rules.refactor_permission()) == "refactor" and rules.mode_of_spec(rules.test_permission()) == "test" and rules.mode_of_spec(rules.build_permission()) == "build")
}

# Only build may forbid nothing. This is the canary for the fall-through:
# any mode silently resolving to "build" shows up here.
fn test_only_build_forbids_nothing() -> Result[Unit, Str] {
  let restricted := list.fold(["explore", "plan", "review", "bar", "spec", "test", "refactor"], true, fn (acc :: Bool, mode :: Str) -> Bool {
    acc and list.len(grant.forbidden_for_mode(mode)) > 0
  })
  check("every mode but build forbids something", restricted and list.len(grant.forbidden_for_mode("build")) == 0)
}

fn suite() -> List[Result[Unit, Str]] {
  [test_all_network_effects_denied(), test_llm_cloud_violates_refactor_grant(), test_permitted_effects_still_pass(), test_malformed_output_is_an_error(), test_wellformed_output_still_parses(), test_violation_is_err_not_ok(), test_mode_of_spec_maps_every_mode(), test_only_build_forbids_nothing()]
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

