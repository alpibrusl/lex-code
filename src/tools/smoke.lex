# lex-code — does each tool name a command that exists?
#
# The gap this closes: `examples {}` blocks are checked by CI and cover
# pure logic, and nothing anywhere checked that a tool's subprocess line
# is real. So #23 found three merge tools that had never run, and #83
# found seventeen more of the same kind — a `--json` flag `lex check` does
# not have, four `lex store` subcommands that do not exist, an AST diff
# pointed at the trace differ, and `--output json` in a position where the
# CLI either rejects it or silently drops it.
#
# Every one of those was discoverable in a second, by anyone who ran the
# tool once. Nobody did, because running a tool meant starting an agent
# session, and by then the failure is a confusing turn mid-task rather
# than a red build.
#
# ---- what this asserts, and what it deliberately does not -------------
#
# Only that the CLI *accepted the invocation*. Not that the output is
# right, not that the store has the data — those need fixtures this
# cannot carry, and a gate that needs a populated store is a gate that
# gets disabled. A tool run against an empty store returns an honest
# "not found", which passes; a tool that misspells its subcommand cannot.
#
# So the assertion is narrow on purpose: no tool's output may contain the
# vocabulary the lex CLI uses to refuse an invocation. That runs anywhere
# `lex` is on PATH, needs no network, and would have caught all twenty.
#
#   lex run --allow-effects ... src/tools/smoke.lex main
#
# Exit is via the summary line, which CI greps: a non-empty FAILING list
# is a red build.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "./index" as idx

import "./util" as util

# Arguments valid enough to reach the CLI. They do not have to find
# anything — `vcs_op_show` on an unknown op id is a pass, because the
# command parsed and answered. They do have to be well-formed, or the
# tool's own field check refuses before the CLI is ever reached, and the
# gate silently tests nothing.
fn args_for(name :: Str) -> Option[jv.Json] {
  match name {
    "lex_check" => Some(JObj([("path", JStr("src/tools/util.lex"))])),
    "os_check" => Some(JObj([("path", JStr("src/tools/util.lex"))])),
    "lex_test" => Some(JObj([("path", JStr("src/tools/util.lex"))])),
    "lex_run" => Some(JObj([("path", JStr("src/tools/util.lex")), ("fn_name", JStr("json_cmd")), ("fn_args", JStr("[]"))])),
    "lex_audit" => Some(JObj([("dimension", JStr("effect")), ("value", JStr("net")), ("path", JStr("src/tools/util.lex"))])),
    "effects_of" => Some(JObj([("fn_name", JStr("json_cmd")), ("path", JStr("src/tools/util.lex"))])),
    "attestation_query" => Some(JObj([("fn_name", JStr("json_cmd")), ("path", JStr("src/tools/util.lex"))])),
    "sigid_lookup" => Some(JObj([("sigid", JStr("0000000000000000000000000000000000000000000000000000000000000000"))])),
    "lex_store_merge" => Some(JObj([("src", JStr("main")), ("dst", JStr("main"))])),
    "lex_spec_check" => Some(JObj([("spec", JStr("examples/specs/absent.spec")), ("source", JStr("src/tools/util.lex"))])),
    "lex_spec_smt" => Some(JObj([("spec", JStr("examples/specs/absent.spec"))])),
    "propagate_effect" => Some(JObj([("root_fn", JStr("json_cmd")), ("new_effect", JStr("time")), ("path", JStr("src/tools/util.lex")), ("dry_run", JBool(true))])),
    "load_guidelines" => Some(JObj([])),
    "bar_check" => Some(JObj([("root", JStr("src"))])),
    "vcs_ast_diff" => Some(JObj([("file_a", JStr("src/tools/util.lex")), ("file_b", JStr("src/tools/index.lex"))])),
    "vcs_op_show" => Some(JObj([("op_id", JStr("0000000000000000000000000000000000000000000000000000000000000000"))])),
    "vcs_op_log" => Some(JObj([("limit", JStr("1"))])),
    "vcs_branch_list" => Some(JObj([])),
    "vcs_branch_current" => Some(JObj([])),
    "vcs_branch_show" => Some(JObj([("branch", JStr("main"))])),
    "vcs_branch_peek" => Some(JObj([("branch", JStr("main"))])),
    "vcs_branch_overlay" => Some(JObj([("other_branch", JStr("main"))])),
    "vcs_merge_status" => Some(JObj([("merge_id", JStr("no-such-session"))])),
    "vcs_merge_show_conflicts" => Some(JObj([("merge_id", JStr("no-such-session"))])),
    _ => None,
  }
}

# A tool that has no entry above is not silently skipped — an unlisted
# tool is exactly the one nobody has run, which is how this started.
# Adding a tool means adding its arguments here, and the summary says so.
fn is_covered(name :: Str) -> Bool {
  match args_for(name) {
    None => false,
    Some(_) => true,
  }
}

# The CLI refusing an invocation is the failure. Whether it refused
# through stdout, stderr, an Err from the tool, or a domain-shaped
# sentence the tool built around it, the vocabulary is the same — which
# is why `util.is_usage_error` is shared with the tools rather than
# duplicated here.
fn verdict(text :: Str) -> Bool {
  util.is_usage_error(text) == false
}

type Outcome = { name :: Str, passed :: Bool, detail :: Str }

fn text_of(j :: jv.Json) -> Str {
  match j {
    JStr(sv) => sv,
    _ => jv.stringify(j),
  }
}

fn check(tl :: t.Tool) -> [net, io, proc] Outcome {
  match args_for(tl.name) {
    None => { name: tl.name, passed: false, detail: "no arguments defined in smoke.lex — add them" },
    Some(a) => match tl.execute(a) {
      Err(errs) => { name: tl.name, passed: verdict(e.format(errs)), detail: e.format(errs) },
      Ok(j) => { name: tl.name, passed: verdict(text_of(j)), detail: text_of(j) },
    },
  }
}

fn first_line(s :: Str) -> Str {
  match list.head(str.split(s, "\n")) {
    None => "",
    Some(h) => h,
  }
}

fn render(o :: Outcome) -> Str {
  if o.passed {
    str.join(["  ok   ", o.name], "")
  } else {
    str.join(["  FAIL ", o.name, " — ", first_line(o.detail)], "")
  }
}

# Tools whose arguments would change the repository or reach the network
# are not run. They are still covered: their CLI line is the same shape as
# a sibling that is run, and #83 checked them against the flag parser by
# hand. A gate that pushed to a remote to prove push works would not be
# one anybody kept.
fn skipped() -> List[Str]
  examples {
    skipped() => ["read", "write", "edit", "grep", "glob", "bash", "todowrite", "remember", "semantic_search", "load_toolset", "vcs_branch_create", "vcs_branch_use", "vcs_merge_start", "vcs_merge_resolve", "vcs_merge_resolve_one", "vcs_merge_defer", "vcs_merge_commit", "vcs_op_push", "vcs_op_pull"]
  }
{
  ["read", "write", "edit", "grep", "glob", "bash", "todowrite", "remember", "semantic_search", "load_toolset", "vcs_branch_create", "vcs_branch_use", "vcs_merge_start", "vcs_merge_resolve", "vcs_merge_resolve_one", "vcs_merge_defer", "vcs_merge_commit", "vcs_op_push", "vcs_op_pull"]
}

fn is_skipped(name :: Str) -> Bool
  examples {
    is_skipped("bash") => true,
    is_skipped("lex_check") => false
  }
{
  list.fold(skipped(), false, fn (acc :: Bool, sk :: Str) -> Bool {
    if acc {
      true
    } else {
      sk == name
    }
  })
}

fn to_run() -> List[t.Tool] {
  list.filter(idx.all_tools(), fn (tl :: t.Tool) -> Bool {
    is_skipped(tl.name) == false
  })
}

fn summary(results :: List[Outcome]) -> Str {
  let failed := list.filter(results, fn (o :: Outcome) -> Bool {
    o.passed == false
  })
  if list.is_empty(failed) {
    str.join(["\nSMOKE OK — ", int.to_str(list.len(results)), " tools invoked a `lex` command that exists (", int.to_str(list.len(skipped())), " skipped)"], "")
  } else {
    str.join(["\nSMOKE FAILING — ", int.to_str(list.len(failed)), " of ", int.to_str(list.len(results)), ": ", str.join(list.map(failed, fn (o :: Outcome) -> Str {
      o.name
    }), ", ")], "")
  }
}

fn main() -> [net, io, proc] Unit {
  let results := list.map(to_run(), check)
  let __rows := io.print(str.join(list.map(results, render), "\n"))
  io.print(summary(results))
}

