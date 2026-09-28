# find_packages — search existing Lex packages before building your own.
#
# The overlap problem this fixes: an agent with no view of what already
# exists rebuilds it (a router, a JWT parser, a crypto library that shipped as
# lex-crypto). The capability lives in the toolchain — `lex pkg search` — so
# every agent and every human gets it; this tool only exposes that command to
# the model and hands back its answer verbatim: matching packages, each with
# its description, git URL and the exact lex.toml line to add.
#
# It used to curl a hand-placed catalog.tsv off the console host and grep it.
# That file had no generator, went stale, and had no entry text for packages
# whose lex.toml lacks a description (lex-web), so "router" found nothing. The
# toolchain command searches the org's repos live, by name, description and
# README. Read-only, network-only (the network call is lex's, not ours).

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "FindPackagesArgs", description: "Search existing Lex packages by what they do (e.g. \"router\", \"http server\", \"jwt\", \"orm\", \"logging\") before writing that capability yourself", fields: [s.required_str("query", [])] }
}

# `lex pkg search` prints the same "no match" sentence at exit 0, so a clean
# "nothing to reuse" is an answer, not a failure. A non-zero exit means it
# could not ask (offline, rate-limited, or a toolchain that predates the
# subcommand) — say so rather than let it read as "no package exists".
fn failure_detail(stderr :: Str) -> Str {
  if str.contains(stderr, "unknown pkg subcommand") {
    str.concat("this `lex` toolchain predates `lex pkg search` — upgrade lex, or browse https://github.com/orgs/alpibrusl/repositories?q=lex-&type=public\n", stderr)
  } else {
    stderr
  }
}

fn execute(args :: jv.Json) -> [io, net, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "query") {
    None => Err(e.single("", "missing_field", "query is required")),
    Some(qraw) => if str.len(str.trim(qraw)) < 2 {
      Err(e.single("", "query_too_short", "query must be at least 2 characters — search for a capability like \"router\", \"jwt\", or \"orm\""))
    } else {
      match proc.run("lex", ["pkg", "search", "--", str.trim(qraw)]) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => if out.exit_code == 0 {
          Ok(JStr(out.stdout))
        } else {
          Err(e.single("", "search_unavailable", util.unavailable("lex pkg search", failure_detail(util.combined(out)))))
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("find_packages", "Search existing Lex packages by what they do (\"router\", \"http server\", \"jwt\", \"orm\") — wraps `lex pkg search`. CALL THIS FIRST, before writing any non-trivial capability (HTTP routing/serving, auth, database access, logging, protocol adapters): if a package exists, add its lex.toml line and reuse it instead of hand-rolling. Returns each match's description, git URL and the exact dependency line.", params(), execute)
}

