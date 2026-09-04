import "./standard/read" as read_tool

import "./standard/write" as write_tool

import "./standard/edit" as edit_tool

import "./standard/grep" as grep_tool

import "./standard/glob" as glob_tool

import "./standard/bash" as bash_tool

import "./standard/todowrite" as todo_tool

import "./lex_check" as check_tool

import "./os_check" as os_check_tool

import "./lex_audit" as audit_tool

import "./bar_check" as bar_check_tool

import "./lex_run" as run_tool

import "./lex_test" as test_tool

import "./lex_spec_check" as spec_check_tool

import "./lex_spec_smt" as spec_smt_tool

import "./lex_cli" as lex_cli_tool

import "./sigid_lookup" as sigid_tool

import "./attestation_query" as attest_tool

import "./effects_of" as effects_tool

import "./propagate_effect" as propagate_tool

import "./remember" as remember_tool

import "./lex_store_merge" as store_merge_tool

import "./vcs/ast_diff" as vcs_ast_diff_tool

import "./vcs/op_show" as vcs_op_show_tool

import "./vcs/op_log" as vcs_op_log_tool

import "./vcs/op_push" as vcs_op_push_tool

import "./vcs/op_pull" as vcs_op_pull_tool

import "./vcs/branch_list" as vcs_branch_list_tool

import "./vcs/branch_current" as vcs_branch_current_tool

import "./vcs/branch_show" as vcs_branch_show_tool

import "./vcs/branch_create" as vcs_branch_create_tool

import "./vcs/branch_use" as vcs_branch_use_tool

import "./vcs/branch_peek" as vcs_branch_peek_tool

import "./vcs/branch_overlay" as vcs_branch_overlay_tool

import "./vcs/merge_start" as vcs_merge_start_tool

import "./semantic_search" as semantic_search_tool

import "./vcs/merge_status" as vcs_merge_status_tool

import "./vcs/merge_show_conflicts" as vcs_merge_show_conflicts_tool

import "./vcs/merge_resolve" as vcs_merge_resolve_tool

import "./vcs/merge_resolve_one" as vcs_merge_resolve_one_tool

import "./vcs/merge_defer" as vcs_merge_defer_tool

import "./vcs/merge_commit" as vcs_merge_commit_tool

import "./load_guidelines" as guidelines_tool

import "./load_toolset" as load_toolset_tool

import "lex-llm/tool" as t

import "lex-spec/spec" as sp

import "lex-spec/eval" as ev

import "../permissions/rules" as rules

import "std.env" as env

fn vcs_read_tools() -> List[t.Tool] {
  [vcs_ast_diff_tool.tool(), vcs_op_show_tool.tool(), vcs_op_log_tool.tool(), vcs_branch_list_tool.tool(), vcs_branch_current_tool.tool(), vcs_branch_show_tool.tool(), vcs_branch_peek_tool.tool(), vcs_branch_overlay_tool.tool(), vcs_merge_status_tool.tool(), vcs_merge_show_conflicts_tool.tool()]
}

fn vcs_write_tools() -> List[t.Tool] {
  [vcs_branch_create_tool.tool(), vcs_branch_use_tool.tool(), vcs_merge_start_tool.tool(), vcs_merge_resolve_tool.tool(), vcs_merge_resolve_one_tool.tool(), vcs_merge_defer_tool.tool(), vcs_merge_commit_tool.tool()]
}

fn vcs_network_tools() -> List[t.Tool] {
  [vcs_op_push_tool.tool(), vcs_op_pull_tool.tool()]
}

fn vcs_tools() -> List[t.Tool] {
  list.concat(vcs_read_tools(), list.concat(vcs_write_tools(), vcs_network_tools()))
}

# os_check is the one tool whose behaviour depends on which mode is
# calling it — it compares a file's effects against that mode's grant —
# so the toolset has to be built per mode rather than shared.
fn all_tools_for_mode(mode :: Str) -> List[t.Tool] {
  list.concat([read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(), remember_tool.tool(), check_tool.tool(), os_check_tool.tool_for_mode(mode), audit_tool.tool(), semantic_search_tool.tool(), run_tool.tool(), test_tool.tool(), spec_check_tool.tool(), spec_smt_tool.tool(), sigid_tool.tool(), attest_tool.tool(), effects_tool.tool(), store_merge_tool.tool(), propagate_tool.tool(), guidelines_tool.tool(), bar_check_tool.tool()], vcs_tools())
}

# The build agent's own toolset: build's grant forbids nothing, so this
# is also the right mode for the unrestricted list.
fn all_tools() -> List[t.Tool] {
  all_tools_for_mode("build")
}

# Curated minimal toolset for local models (LiteLLM/Ollama). Full all_tools()
# ships 38 tool schemas, which overwhelms small local models. This is the
# read/write/inspect core needed for most build tasks.
#
# test_tool (lex_test) belongs here, not just in the cloud-only lex_tools()
# group: test_agent.lex's own prompt names it as the way to verify a test
# suite ("lex_test: run `lex run tests/... run_all`"), but dynamic_tools()
# (what every local-model agent variant actually calls) never included it —
# a local-model test run had no way to call the tool its own instructions
# told it to use, so it fell back to lex_run(fn_name: "run_all") instead.
# That works, but lex_run isn't recognised as a verification call the way
# lex_check/lex_spec_check/lex_test are (see lex-llm#51's
# is_verification_tool), so the run never got credit for actually finishing
# and burned its full step budget regardless.
#
# remember belongs here for the same reason: build_permission() allows it
# unconditionally, but it was missing from dynamic_tools() (#110), so a
# local-model build agent had no way to propose a memory candidate at
# all — confirmed live, the model correctly reported it had no such tool
# and declined to fabricate a call. A single [net, io, proc] tool that
# appends one JSONL line (see remember.lex/candidates.lex) is cheap
# enough for the curated core; it doesn't need load_toolset gating the
# way the heavier vcs/spec/store groups do.
fn minimal_tools() -> List[t.Tool] {
  [read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(), remember_tool.tool(), check_tool.tool(), run_tool.tool(), test_tool.tool()]
}

# Model name advertised to the LiteLLM proxy (must match a model_name in
# litellm_config.yaml). Override with LITELLM_MODEL.
fn litellm_model() -> [env] Str {
  match env.get("LITELLM_MODEL") {
    None => "qwen3-coder:30b",
    Some(m) => m,
  }
}

# Model name for the native OpenCode Go provider (providers.opencode_go(),
# hits https://opencode.ai/zen/go/v1 directly — no local proxy needed).
# Default is a coding-oriented model on the Go plan; override with
# OPENCODE_MODEL. See litellm/config.yaml for the full Go-plan model list
# (also reachable via --litellm once the proxy is running).
fn opencode_model() -> [env] Str {
  match env.get("OPENCODE_MODEL") {
    None => "kimi-k2.7-code",
    Some(m) => m,
  }
}

# ── Dynamic toolset loading ─────────────────────────────────────────────────
# Each gate is a lex-spec predicate that is `Allow` only when the matching
# `loaded_*` binding is true. lex-llm sets those bindings by scanning the
# conversation for the LOADED_TOOLSET marker emitted by the load_toolset tool,
# so a gated tool stays hidden until the model explicitly loads its group.
fn gate_vcs() -> sp.Spec {
  { name: "gate_vcs", quantifiers: [QBool("loaded_vcs")], predicate: EVar("loaded_vcs") }
}

fn gate_spec() -> sp.Spec {
  { name: "gate_spec", quantifiers: [QBool("loaded_spec")], predicate: EVar("loaded_spec") }
}

fn gate_store() -> sp.Spec {
  { name: "gate_store", quantifiers: [QBool("loaded_store")], predicate: EVar("loaded_store") }
}

fn spec_group_tools() -> List[t.Tool] {
  [spec_check_tool.tool(), spec_smt_tool.tool()]
}

fn store_group_tools() -> List[t.Tool] {
  [store_merge_tool.tool(), propagate_tool.tool()]
}

fn gate_all(group :: List[t.Tool], spec :: sp.Spec) -> List[t.Tool] {
  list.map(group, fn (tool :: t.Tool) -> t.Tool {
    t.with_precondition(tool, spec)
  })
}

# Curated minimal core + the load_toolset meta-tool + gated extra groups that
# only become callable once the model loads them. This is the toolset for
# local/LiteLLM build agents: small visible surface, full capability on demand.
fn dynamic_tools() -> List[t.Tool] {
  list.concat(minimal_tools(), list.concat([load_toolset_tool.tool()], list.concat(gate_all(vcs_tools(), gate_vcs()), list.concat(gate_all(spec_group_tools(), gate_spec()), gate_all(store_group_tools(), gate_store())))))
}

# review.lex's own prompt is built entirely around these four tools —
# "Attestation is the trust anchor here, not your own reading" — so unlike
# vcs/spec/store (genuinely optional extras other modes reach for
# occasionally), review's local variant needs attestation_query/effects_of/
# lex_audit/sigid_lookup unconditionally to do its actual job, not gated
# behind a load_toolset call. Found missing (#89) when a local review run
# hit "unknown tool: effects_of" five times in a row and had to fall back
# to lex_check + grep instead.
fn review_dynamic_tools() -> List[t.Tool] {
  list.concat(dynamic_tools(), [attest_tool.tool(), effects_tool.tool(), audit_tool.tool(), sigid_tool.tool()])
}

# explore/plan/refactor's local variants had `tools: []` and
# `max_steps: Some(3)` — not curated-minimal, just entirely unwired,
# unlike every other local mode. Confirmed live: an explore-mode call
# said "Let me locate the `shout` function in `widget.lex`" and then
# stopped, having no tool to do it with.
#
# Each mode below is built to match its own permissions/rules.lex spec
# exactly (explore_permission/plan_permission/refactor_permission) —
# not dynamic_tools(), and not shared with each other, because the
# three permission specs genuinely differ (explore gets
# sigid_lookup/effects_of/attestation_query, plan gets
# todowrite/remember instead, refactor gets the full edit+vcs surface).
# A tool outside the mode's own permission allowlist would just be
# silently dropped again by with_permission_gate, so listing it here
# would be dead weight in the schema a small model still pays for.
fn explore_dynamic_tools() -> List[t.Tool] {
  [read_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), audit_tool.tool(), sigid_tool.tool(), effects_tool.tool(), attest_tool.tool(), guidelines_tool.tool()]
}

fn plan_dynamic_tools() -> List[t.Tool] {
  [read_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), audit_tool.tool(), todo_tool.tool(), remember_tool.tool(), guidelines_tool.tool()]
}

# refactor's own prompt makes lex_audit a MANDATORY first step (find
# every caller before editing) and separately lists sigid_lookup,
# effects_of, lex_store_merge, and propagate_effect as core to its
# workflow, plus the vcs_merge_* tools for its own "RESOLVING A MERGE"
# section — none of which dynamic_tools() carries un-gated. Built
# directly from vcs_read_tools()/vcs_write_tools() (matching
# refactor_permission()'s vcs_read_names()+vcs_write_names(), which
# excludes vcs_network_names() — refactor doesn't push/pull, syncing is
# a build-mode/explicit-user-action concern) rather than extending
# dynamic_tools(), which would have duplicated propagate_effect and
# lex_store_merge (they're already in dynamic_tools()'s gated store
# group) — a real bug in an earlier version of this function, caught by
# inspecting the actual tool list rather than trusting a live run.
#
# remember_tool belongs here too: refactor_permission() already lists
# "remember" in its allowlist, but this hand-built list omitted the
# actual tool (#110) — a local refactor agent was permitted to propose a
# memory candidate and had no way to.
fn refactor_dynamic_tools() -> List[t.Tool] {
  list.concat([read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), remember_tool.tool(), check_tool.tool(), audit_tool.tool(), sigid_tool.tool(), effects_tool.tool(), store_merge_tool.tool(), propagate_tool.tool(), guidelines_tool.tool()], list.concat(vcs_read_tools(), vcs_write_tools()))
}

fn tools_for_spec(spec :: sp.Spec) -> List[t.Tool] {
  list.filter(all_tools_for_mode(rules.mode_of_spec(spec)), fn (tool :: t.Tool) -> Bool {
    let bindings := [("tool", VStr(tool.name))]
    sp.verdict_is_allow(ev.eval(spec, bindings))
  })
}

fn read_only_tools() -> List[t.Tool] {
  tools_for_spec(rules.explore_permission())
}

fn standard_tools() -> List[t.Tool] {
  [read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool()]
}

fn lex_tools() -> List[t.Tool] {
  [check_tool.tool(), audit_tool.tool(), run_tool.tool(), test_tool.tool(), spec_check_tool.tool(), spec_smt_tool.tool()]
}

fn lex_cli_tools() -> List[t.Tool] {
  [lex_cli_tool.tool()]
}

fn refactor_tools() -> List[t.Tool] {
  tools_for_spec(rules.refactor_permission())
}

fn spec_tools() -> List[t.Tool] {
  tools_for_spec(rules.spec_permission())
}

fn test_tools() -> List[t.Tool] {
  tools_for_spec(rules.test_permission())
}

fn review_tools() -> List[t.Tool] {
  tools_for_spec(rules.review_permission())
}

fn bar_tools() -> List[t.Tool] {
  tools_for_spec(rules.bar_permission())
}

# Curated bar toolset for local models. bar_tools() ships 19 schemas, 9 of
# them lex-vcs tools a bar walk never calls — exactly the overload
# minimal_tools() exists to avoid. A walk needs the probe runner and enough
# to confirm what it reports; everything else is noise a 7B model pays for
# on every turn.
fn bar_minimal_tools() -> List[t.Tool] {
  [bar_check_tool.tool(), read_tool.tool(), grep_tool.tool(), glob_tool.tool()]
}

