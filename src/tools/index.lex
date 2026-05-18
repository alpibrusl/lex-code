import "./standard/read"      as read_tool
import "./standard/write"     as write_tool
import "./standard/edit"      as edit_tool
import "./standard/grep"      as grep_tool
import "./standard/glob"      as glob_tool
import "./standard/bash"      as bash_tool
import "./standard/todowrite" as todo_tool
import "./lex_check"          as check_tool
import "./lex_audit"          as audit_tool
import "./lex_run"            as run_tool
import "./lex_test"           as test_tool
import "./lex_spec_check"     as spec_check_tool
import "./lex_spec_smt"       as spec_smt_tool
import "./sigid_lookup"       as sigid_tool
import "./attestation_query"  as attest_tool
import "./effects_of"         as effects_tool
import "./lex_store_diff"     as store_diff_tool
import "./lex_store_apply"    as store_apply_tool
import "./lex_store_merge"    as store_merge_tool

import "lex-llm/tool" as t

fn all_tools() -> List[t.Tool] {
  [ read_tool.tool(), write_tool.tool(), edit_tool.tool(),
    grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(),
    check_tool.tool(), audit_tool.tool(), run_tool.tool(), test_tool.tool(),
    spec_check_tool.tool(), spec_smt_tool.tool(),
    sigid_tool.tool(), attest_tool.tool(), effects_tool.tool(),
    store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool(),
  ]
}

fn read_only_tools() -> List[t.Tool] {
  [ read_tool.tool(), grep_tool.tool(), glob_tool.tool(),
    check_tool.tool(), audit_tool.tool(),
    sigid_tool.tool(), effects_tool.tool(), attest_tool.tool(),
  ]
}

fn standard_tools() -> List[t.Tool] {
  [ read_tool.tool(), write_tool.tool(), edit_tool.tool(),
    grep_tool.tool(), glob_tool.tool(), bash_tool.tool(), todo_tool.tool(),
  ]
}

fn lex_tools() -> List[t.Tool] {
  [ check_tool.tool(), audit_tool.tool(), run_tool.tool(), test_tool.tool(),
    spec_check_tool.tool(), spec_smt_tool.tool(),
  ]
}

fn refactor_tools() -> List[t.Tool] {
  [ read_tool.tool(), write_tool.tool(), edit_tool.tool(),
    grep_tool.tool(), glob_tool.tool(), bash_tool.tool(),
    check_tool.tool(), audit_tool.tool(),
    sigid_tool.tool(), effects_tool.tool(),
    store_diff_tool.tool(), store_apply_tool.tool(), store_merge_tool.tool(),
  ]
}

fn spec_tools() -> List[t.Tool] {
  [ read_tool.tool(), write_tool.tool(), edit_tool.tool(),
    grep_tool.tool(), glob_tool.tool(),
    check_tool.tool(),
    spec_check_tool.tool(), spec_smt_tool.tool(),
  ]
}

fn test_tools() -> List[t.Tool] {
  [ read_tool.tool(), write_tool.tool(), edit_tool.tool(),
    grep_tool.tool(), glob_tool.tool(),
    check_tool.tool(), run_tool.tool(), test_tool.tool(),
  ]
}

fn review_tools() -> List[t.Tool] {
  [ read_tool.tool(), grep_tool.tool(), glob_tool.tool(),
    check_tool.tool(), audit_tool.tool(),
    sigid_tool.tool(), effects_tool.tool(), attest_tool.tool(),
  ]
}
