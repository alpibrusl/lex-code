# lex-code — open a real GitHub pull request
#
# Every VCS tool in src/tools/vcs/ wraps `lex branch`/`lex merge` — lex-vcs,
# the structural, content-addressed system built into the `lex` CLI itself.
# None of them touch git or GitHub. Shipping a change has always meant a
# human (or Claude, driving `gh` by hand outside this codebase) taking the
# current branch the rest of the way: push, open the PR, wait for CI, merge.
# lex-code itself could build, test and verify a change end to end and then
# had no tool to hand it off with.
#
# This is deliberately the FIRST tool in the codebase to carry an
# approval_scope (`t.with_approval`, lex-llm#41 / lex-lang#737's std.approval
# effect) — plumbing that has existed since #41 landed but nothing here ever
# used: `grep -rln "approval_scope" src/tools/` returned nothing before this
# file. Opening a pull request is visible to everyone with access to the
# repo and cannot be un-opened the way a local edit can be un-written, so it
# is exactly the class of action every other "cutting edge" agent gates
# behind a human — this is lex-code's first one. `bin/lex-code` already
# passes `approval` in its default --allow-effects and never restricts
# --allow-approval, so this blocks on a real stdin prompt (lex-lang's
# StdinApprovalSink) the first time any mode actually calls it — not a
# no-op, and not silently denied by an unconfigured sink.
#
# Shells out to `gh pr create` rather than the GitHub REST API directly:
# every other tool in this codebase that needs a real external CLI (git,
# lex, docker) does the same, and `gh` already owns auth, remote detection
# and the "is this branch pushed" error message this tool would otherwise
# have to reproduce. Pushing the branch itself is deliberately NOT this
# tool's job — that is an ordinary `bash`/`git` action any mode with those
# tools already has, and folding it in here would hide a git push behind
# what looks like a PR-only approval prompt.

import "std.process" as proc

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "GithubPrCreateArgs", description: "Open a pull request on GitHub for the current (already-pushed) branch.", fields: [s.required_str("title", []), s.required_str("body", []), s.optional(s.required_str("base", []))] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "title") {
    None => Err(e.single("", "missing_field", "title is required")),
    Some(title) => match util.field_str(args, "body") {
      None => Err(e.single("", "missing_field", "body is required")),
      Some(body) => {
        let base_args := match util.field_str(args, "base") {
          None => [],
          Some(b) => ["--base", b],
        }
        let cmd := list.concat(["pr", "create", "--title", title, "--body", body], base_args)
        match proc.run("gh", cmd) {
          Err(msg) => Err(e.single("", "proc_error", msg)),
          Ok(out) => match util.cli_result(out) {
            Err(detail) => Err(e.single("", "gh_pr_create_failed", detail)),
            Ok(body_out) => Ok(JStr(body_out)),
          },
        }
      },
    },
  }
}

fn tool() -> t.Tool {
  t.with_approval(t.define("github_pr_create", "Open a pull request on GitHub for the CURRENT branch, which must already be pushed to the remote. Requires operator approval before it runs.", params(), execute), "github_pr_create")
}

