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

import "./lex_store_diff" as store_diff_tool

import "./lex_store_apply" as store_apply_tool

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
  list.concat([read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(), remember_tool.tool(), check_tool.tool(), os_check_tool.tool_for_mode(mode), audit_tool.tool(), semantic_search_tool.tool(), run_tool.tool(), test_tool.tool(), spec_check_tool.tool(), spec_smt_tool.tool(), sigid_tool.tool(), attest_tool.tool(), effects_tool.tool(), store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool(), propagate_tool.tool(), guidelines_tool.tool(), bar_check_tool.tool()], vcs_tools())
}

# The build agent's own toolset: build's grant forbids nothing, so this
# is also the right mode for the unrestricted list.
fn all_tools() -> List[t.Tool] {
  all_tools_for_mode("build")
}

# Curated minimal toolset for local models (LiteLLM/Ollama). Full all_tools()
# ships 38 tool schemas, which overwhelms small local models. This is the
# read/write/inspect core needed for most build tasks.
fn minimal_tools() -> List[t.Tool] {
  [read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(), check_tool.tool(), run_tool.tool()]
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
  [store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool(), propagate_tool.tool()]
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

