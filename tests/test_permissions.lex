# Tests for the per-mode permission Specs — the security boundary.
#
# `with_permission_gate` filters an agent's tool list through the Spec in
# src/permissions/rules.lex, so a Spec that silently widens is the worst
# regression this codebase can ship: a read-only mode that can suddenly
# write, edit or shell out looks identical from the outside until it does.
#
# Nothing tested this until now. It is cheap to test because both
# rules.lex and lex-spec's evaluator are PURE — this file declares no
# effects at all, so it runs under any `lex test` grant and needs no
# import of src/tools/index.lex, which would drag [proc, net, env] in
# and fail the runner's policy before a single assertion ran.
#
# The properties, in order of how much they would hurt:
#
#   1. READ-ONLY MEANS READ-ONLY — explore, plan, review and bar deny
#      write, edit and bash. Every one of them.
#   2. NO SPEC IS ACCIDENTALLY ALLOW-ALL — an invented tool name is
#      denied by every mode except build, which is allow-all on purpose.
#      This is the canary for a predicate collapsing to `true`.
#   3. THE MODES CAN STILL DO THEIR JOB — the write modes keep write and
#      edit; bar keeps bar_check. A boundary that denies everything
#      passes rule 1 and is useless.

import "std.list" as list

import "std.str" as str

import "std.io" as io

import "lex-spec/spec" as sp

import "lex-spec/eval" as ev

import "../src/permissions/rules" as rules

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn allows(spec :: sp.Spec, tool :: Str) -> Bool {
  sp.verdict_is_allow(ev.eval(spec, [("tool", VStr(tool))]))
}

fn denies_all(spec :: sp.Spec, tools :: List[Str]) -> Bool {
  list.fold(tools, true, fn (acc :: Bool, t :: Str) -> Bool {
    acc and not allows(spec, t)
  })
}

fn allows_all(spec :: sp.Spec, tools :: List[Str]) -> Bool {
  list.fold(tools, true, fn (acc :: Bool, t :: Str) -> Bool {
    acc and allows(spec, t)
  })
}

fn mutating_tools() -> List[Str] {
  ["write", "edit", "bash"]
}

# ── 1. Read-only means read-only ──────────────────────────────────────
fn test_readonly_modes_cannot_mutate() -> Result[Unit, Str] {
  check("explore, plan, review and bar all deny write/edit/bash", denies_all(rules.explore_permission(), mutating_tools()) and denies_all(rules.plan_permission(), mutating_tools()) and denies_all(rules.review_permission(), mutating_tools()) and denies_all(rules.bar_permission(), mutating_tools()))
}

# A bar walk that could edit is a walk that can quietly become a fix.
fn test_bar_is_read_only_but_can_probe() -> Result[Unit, Str] {
  let bar := rules.bar_permission()
  check("bar allows bar_check and read, denies write/edit/bash", allows(bar, "bar_check") and allows(bar, "read") and denies_all(bar, mutating_tools()))
}

# ── 2. No spec is accidentally allow-all ──────────────────────────────
# The canary: if a predicate collapses to `true`, every one of these
# starts allowing a tool name that does not exist.
fn test_no_spec_is_allow_all() -> Result[Unit, Str] {
  let invented := ["definitely_not_a_tool", "rm_rf", ""]
  check("only build allows an unknown tool name", denies_all(rules.explore_permission(), invented) and denies_all(rules.plan_permission(), invented) and denies_all(rules.review_permission(), invented) and denies_all(rules.bar_permission(), invented) and denies_all(rules.spec_permission(), invented) and denies_all(rules.test_permission(), invented) and denies_all(rules.refactor_permission(), invented))
}

# Build is allow-all deliberately — assert it, so that if the intent ever
# changes this test has to change with it rather than silently passing.
fn test_build_is_allow_all_on_purpose() -> Result[Unit, Str] {
  check("build allows anything, including a name nobody defined", allows(rules.build_permission(), "write") and allows(rules.build_permission(), "definitely_not_a_tool"))
}

# ── 3. The modes can still do their job ───────────────────────────────
fn test_write_modes_keep_their_tools() -> Result[Unit, Str] {
  check("refactor/test/spec keep write and edit; refactor keeps bash", allows_all(rules.refactor_permission(), ["write", "edit", "bash"]) and allows_all(rules.test_permission(), ["write", "edit", "lex_test"]) and allows_all(rules.spec_permission(), ["write", "edit", "lex_spec_check"]))
}

fn suite() -> List[Result[Unit, Str]] {
  [test_readonly_modes_cannot_mutate(), test_bar_is_read_only_but_can_probe(), test_no_spec_is_allow_all(), test_build_is_allow_all_on_purpose(), test_write_modes_keep_their_tools()]
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

