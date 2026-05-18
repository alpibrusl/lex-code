# lex-code — per-agent permission rules
#
# Phase 1 (current): tool-list enforcement via index.lex tool subsets.
# Phase 2 (next): wire these Spec values into lex-llm run_loop so
# the agent cannot call out-of-policy tools even if the model tries.

import "lex-spec/spec" as sp
import "std.list"      as list

# ---- Helpers -------------------------------------------------------

fn tool_eq(name :: Str) -> sp.SpecExpr {
  sp.EBinop({
    op:  sp.op_eq(),
    lhs: sp.EVar("tool"),
    rhs: sp.EConst(sp.VStr(name)),
  })
}

fn any_of(exprs :: List[sp.SpecExpr]) -> sp.SpecExpr {
  match list.head(exprs) {
    None    => sp.EConst(sp.VBool(false)),
    Some(e) =>
      list.fold(list.tail(exprs), e,
        fn (acc :: sp.SpecExpr, x :: sp.SpecExpr) -> sp.SpecExpr {
          sp.EOr(acc, x)
        })
  }
}

fn allow_tools(rule_name :: Str, allowed :: List[Str]) -> sp.Spec {
  { name:        rule_name,
    quantifiers: [sp.QStr("tool")],
    predicate:   any_of(list.map(allowed, tool_eq)) }
}

# ---- Per-agent rules -----------------------------------------------

fn explore_permission() -> sp.Spec {
  allow_tools("explore_tools", [
    "read", "grep", "glob",
    "lex_check", "lex_audit",
    "sigid_lookup", "effects_of", "attestation_query",
  ])
}

fn plan_permission() -> sp.Spec {
  allow_tools("plan_tools", [
    "read", "grep", "glob",
    "lex_check", "lex_audit", "todowrite",
  ])
}

fn review_permission() -> sp.Spec {
  allow_tools("review_tools", [
    "read", "grep", "glob",
    "lex_check", "lex_audit",
    "sigid_lookup", "effects_of", "attestation_query",
  ])
}

fn spec_permission() -> sp.Spec {
  allow_tools("spec_tools", [
    "read", "write", "edit", "grep", "glob",
    "lex_check", "lex_spec_check", "lex_spec_smt",
  ])
}

fn refactor_permission() -> sp.Spec {
  allow_tools("refactor_tools", [
    "read", "write", "edit", "grep", "glob", "bash",
    "lex_check", "lex_audit",
    "sigid_lookup", "effects_of",
    "lex_store_diff", "lex_store_apply", "lex_store_merge",
  ])
}

fn test_permission() -> sp.Spec {
  allow_tools("test_tools", [
    "read", "write", "edit", "grep", "glob",
    "lex_check", "lex_run", "lex_test",
  ])
}

fn build_permission() -> sp.Spec {
  # Build agent is unrestricted — allow everything (tautology)
  { name:        "build_all",
    quantifiers: [sp.QStr("tool")],
    predicate:   sp.EConst(sp.VBool(true)) }
}
