# lex-code — wait for a pull request's checks, then merge it
#
# github_pr_create (lex-code#152) got a change as far as "a PR exists".
# Landing it always meant a human (or Claude, driving `gh` by hand outside
# this codebase) polling `gh pr checks`, then running `gh pr merge` once
# green -- exactly the pattern GitHub Copilot's "Agent Merge" and Codex's
# automatic pre-merge approval reviews both shipped in 2026, and exactly
# what a real dogfooding session ended up doing by hand for six PRs in a
# row before this tool existed.
#
# Approval-gated for the same reason github_pr_create is: merging is
# visible to everyone with repo access and cannot be un-merged the way a
# local edit can be un-written. The approval prompt covers the whole
# conditional intent ("merge this once checks pass"), asked BEFORE the
# outcome is known -- the same shape as a human reviewer saying "LGTM,
# merge when CI is green" without re-approving after the fact.
#
# Deliberately verifies checks itself rather than trusting the caller's
# own judgment that they're green: `gh pr checks --watch --fail-fast`
# blocks until resolution and this tool refuses to call `gh pr merge` at
# all unless that reports success, regardless of whether the repo's own
# branch protection would have caught a bad merge anyway. A CI failure's
# output is returned as the error detail (not swallowed) so the failure
# can actually be diagnosed and fixed, not just reported as "didn't
# merge".
#
# `pr` accepts anything `gh` itself accepts for a PR -- a number, a URL,
# or a branch name (github_pr_create's own stdout is the PR's URL) --
# rather than forcing this tool to parse one shape out of another.

import "std.process" as proc

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "GithubPrMergeArgs", description: "Wait for a pull request's checks to finish, then merge it if (and only if) they pass. Requires operator approval before it runs.", fields: [s.required_str("pr", []), s.optional(s.required_str("merge_method", []))] }
}

fn merge_flag(method :: Str) -> Str
  examples {
    merge_flag("squash") => "--squash",
    merge_flag("rebase") => "--rebase",
    merge_flag("merge") => "--merge",
    merge_flag("") => "--squash",
    merge_flag("bogus") => "--squash"
  }
{
  if method == "rebase" {
    "--rebase"
  } else {
    if method == "merge" {
      "--merge"
    } else {
      "--squash"
    }
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "pr") {
    None => Err(e.single("", "missing_field", "pr is required (a PR number, URL, or branch name)")),
    Some(pr) => match proc.run("gh", ["pr", "checks", pr, "--watch", "--fail-fast"]) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(checks_out) => match util.cli_result(checks_out) {
        Err(detail) => Err(e.single("", "checks_failed", detail)),
        Ok(_) => {
          let method := merge_flag(util.field_str_or(args, "merge_method", "squash"))
          match proc.run("gh", ["pr", "merge", pr, method, "--delete-branch"]) {
            Err(msg) => Err(e.single("", "proc_error", msg)),
            Ok(merge_out) => match util.cli_result(merge_out) {
              Err(detail) => Err(e.single("", "gh_pr_merge_failed", detail)),
              Ok(body_out) => Ok(JStr(body_out)),
            },
          }
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.with_approval(t.define("github_pr_merge", "Wait for a pull request's CI checks to finish (gh pr checks --watch), then merge it only if they pass, deleting the branch afterward. Requires operator approval before it runs.", params(), execute), "github_pr_merge")
}

