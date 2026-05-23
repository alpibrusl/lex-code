import "./standard/read" as read_tool

import "./standard/write" as write_tool

import "./standard/edit" as edit_tool

import "./standard/grep" as grep_tool

import "./standard/glob" as glob_tool

import "./standard/bash" as bash_tool

import "./standard/todowrite" as todo_tool

import "./lex_check" as check_tool

import "./lex_audit" as audit_tool

import "./lex_run" as run_tool

import "./lex_test" as test_tool

import "./lex_spec_check" as spec_check_tool

import "./lex_spec_smt" as spec_smt_tool

import "./lex_cli" as lex_cli_tool

import "./sigid_lookup" as sigid_tool

import "./attestation_query" as attest_tool

import "./effects_of" as effects_tool

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

import "./vcs/merge_status" as vcs_merge_status_tool

import "./vcs/merge_resolve" as vcs_merge_resolve_tool

import "./vcs/merge_defer" as vcs_merge_defer_tool

import "./vcs/merge_commit" as vcs_merge_commit_tool

import "./load_guidelines" as guidelines_tool

import "lex-llm/tool" as t

fn vcs_read_tools() -> List[t.Tool] {
  [vcs_ast_diff_tool.tool(), vcs_op_show_tool.tool(), vcs_op_log_tool.tool(), vcs_branch_list_tool.tool(), vcs_branch_current_tool.tool(), vcs_branch_show_tool.tool(), vcs_branch_peek_tool.tool(), vcs_branch_overlay_tool.tool(), vcs_merge_status_tool.tool()]
}

fn vcs_write_tools() -> List[t.Tool] {
  [vcs_branch_create_tool.tool(), vcs_branch_use_tool.tool(), vcs_merge_start_tool.tool(), vcs_merge_resolve_tool.tool(), vcs_merge_defer_tool.tool(), vcs_merge_commit_tool.tool()]
}

fn vcs_network_tools() -> List[t.Tool] {
  [vcs_op_push_tool.tool(), vcs_op_pull_tool.tool()]
}

fn vcs_tools() -> List[t.Tool] {
  list.concat(vcs_read_tools(), list.concat(vcs_write_tools(), vcs_network_tools()))
}

fn all_tools() -> List[t.Tool] {
  list.concat([read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(), check_tool.tool(), audit_tool.tool(), run_tool.tool(), test_tool.tool(), spec_check_tool.tool(), spec_smt_tool.tool(), sigid_tool.tool(), attest_tool.tool(), effects_tool.tool(), store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool(), guidelines_tool.tool()], vcs_tools())
}

fn read_only_tools() -> List[t.Tool] {
  list.concat([read_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), audit_tool.tool(), sigid_tool.tool(), effects_tool.tool(), attest_tool.tool(), guidelines_tool.tool()], vcs_read_tools())
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
  list.concat([read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), check_tool.tool(), audit_tool.tool(), sigid_tool.tool(), effects_tool.tool(), store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool()], vcs_tools())
}

fn spec_tools() -> List[t.Tool] {
  [read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), spec_check_tool.tool(), spec_smt_tool.tool()]
}

fn test_tools() -> List[t.Tool] {
  [read_tool.tool(), write_tool.tool(), edit_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), run_tool.tool(), test_tool.tool()]
}

fn review_tools() -> List[t.Tool] {
  list.concat([read_tool.tool(), grep_tool.tool(), glob_tool.tool(), check_tool.tool(), audit_tool.tool(), sigid_tool.tool(), effects_tool.tool(), attest_tool.tool()], vcs_read_tools())
}

