# lex-code — per-agent permission rules
#
# Phase 1 (current): tool-list enforcement via index.lex tool subsets.
# Phase 2 (next): wire these Spec values into lex-llm run_loop so
# the agent cannot call out-of-policy tools even if the model tries.

import "lex-spec/spec" as sp

import "std.list" as list

# ---- Helpers -------------------------------------------------------
fn tool_eq(name :: Str) -> sp.SpecExpr {
  EBinop({ op: sp.op_eq(), lhs: EVar("tool"), rhs: EConst(VStr(name)) })
}

fn any_of(exprs :: List[sp.SpecExpr]) -> sp.SpecExpr {
  match list.head(exprs) {
    None => EConst(VBool(false)),
    Some(e) => list.fold(list.tail(exprs), e, fn (acc :: sp.SpecExpr, x :: sp.SpecExpr) -> sp.SpecExpr {
      EOr(acc, x)
    }),
  }
}

# ---- MCP tools and this file ---------------------------------------
#
# #27 asked for an `mcp_tool(name)` predicate here. There is deliberately
# none, for two reasons.
#
# It is not expressible: lex-spec has `op_eq`, the comparisons and
# arithmetic, and no string-prefix operator, so "any name beginning
# mcp__" cannot be written as a Spec. Enumerating the names would be —
# and is the better shape regardless, since a prefix rule silently
# extends to whatever a server starts offering next week.
#
# It is not yet load-bearing either. Per the header above, enforcement is
# still Phase 1: what an agent may call is the tool list index.lex hands
# it, not the Spec. `.lex/mcp.toml`'s `modes` controls exactly that list,
# so the gate is real today and lives where the enforcement is.
#
# When Phase 2 wires these Specs into lex-llm's run_loop, the loaded MCP
# names have to be added to each mode's allow list at construction — the
# loading is over the network and these constructors are pure, so that
# will need the names threaded in rather than fetched here.
fn allow_tools(rule_name :: Str, allowed :: List[Str]) -> sp.Spec {
  { name: rule_name, quantifiers: [QStr("tool")], predicate: any_of(list.map(allowed, tool_eq)) }
}

# ---- VCS name lists (canonical, reused below) ----------------------
fn vcs_read_names() -> List[Str] {
  ["vcs_ast_diff", "vcs_op_show", "vcs_op_log", "vcs_branch_list", "vcs_branch_current", "vcs_branch_show", "vcs_branch_peek", "vcs_branch_overlay", "vcs_merge_status", "vcs_merge_show_conflicts"]
}

fn vcs_write_names() -> List[Str] {
  ["vcs_branch_create", "vcs_branch_use", "vcs_merge_start", "vcs_merge_resolve", "vcs_merge_resolve_one", "vcs_merge_defer", "vcs_merge_commit"]
}

# ---- Per-agent rules -----------------------------------------------
fn explore_permission() -> sp.Spec {
  allow_tools("explore_tools", list.concat(["read", "grep", "glob", "lex_check", "lex_audit", "sigid_lookup", "effects_of", "attestation_query", "semantic_search", "load_guidelines"], vcs_read_names()))
}

fn plan_permission() -> sp.Spec {
  allow_tools("plan_tools", list.concat(["read", "grep", "glob", "lex_check", "lex_audit", "todowrite", "remember", "semantic_search", "load_guidelines"], vcs_read_names()))
}

fn review_permission() -> sp.Spec {
  allow_tools("review_tools", list.concat(["read", "grep", "glob", "lex_check", "lex_audit", "sigid_lookup", "effects_of", "attestation_query", "semantic_search", "load_guidelines"], vcs_read_names()))
}

# BAR mode reads and reports; it never edits. The tool list is
# review's, plus the bar_check probe runner — deliberately without
# write, edit or bash, so a walk cannot quietly turn into a fix.
fn bar_permission() -> sp.Spec {
  allow_tools("bar_tools", list.concat(["bar_check", "read", "grep", "glob", "lex_check", "lex_audit", "sigid_lookup", "effects_of", "attestation_query", "load_guidelines"], vcs_read_names()))
}

fn spec_permission() -> sp.Spec {
  allow_tools("spec_tools", ["read", "write", "edit", "grep", "glob", "lex_check", "lex_spec_check", "lex_spec_smt"])
}

fn refactor_permission() -> sp.Spec {
  allow_tools("refactor_tools", list.concat(["read", "write", "edit", "grep", "glob", "bash", "remember", "lex_check", "os_check", "lex_audit", "sigid_lookup", "effects_of", "lex_store_merge", "propagate_effect"], list.concat(vcs_read_names(), vcs_write_names())))
}

fn test_permission() -> sp.Spec {
  allow_tools("test_tools", ["read", "write", "edit", "grep", "glob", "lex_check", "lex_run", "lex_test"])
}

fn build_permission() -> sp.Spec {
  { name: "build_all", quantifiers: [QStr("tool")], predicate: EConst(VBool(true)) }
}

# The agent mode a permission spec belongs to. Kept next to the
# constructors above so a renamed spec is caught here rather than
# silently falling through to "build", the mode that forbids nothing.
# os_check binds its grant from this at construction time.
fn mode_of_spec(spec :: sp.Spec) -> Str {
  if spec.name == "explore_tools" {
    "explore"
  } else {
    if spec.name == "plan_tools" {
      "plan"
    } else {
      if spec.name == "review_tools" {
        "review"
      } else {
        if spec.name == "bar_tools" {
          "bar"
        } else {
          if spec.name == "spec_tools" {
            "spec"
          } else {
            if spec.name == "refactor_tools" {
              "refactor"
            } else {
              if spec.name == "test_tools" {
                "test"
              } else {
                "build"
              }
            }
          }
        }
      }
    }
  }
}

