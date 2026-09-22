# lex-code — typed issues as agent tools (#173, lex-lang #949)
#
# `issue_show` reads an issue's declared acceptance — the contract to
# satisfy. `issue_verify` evaluates it at the store's head and records an
# `IssueVerified` attestation: done is a proof the gate checks, never a
# status the agent sets. Together they let the fix loop iterate against
# the issue's own oracle rather than against the agent's reading of it.
#
# A `failed` verdict exits 1 but is still an answer (`"ok": true` with a
# `detail` naming the wrong signature or example), so it reaches the
# model as a successful tool result it can act on. Only a command that
# could not answer — unknown issue, no store — is an Err.

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../issue_contract" as ic

import "./util" as util

fn id_params(title :: Str, description :: Str) -> s.ModelSchema {
  { title: title, description: description, fields: [s.required_str("issue_id", [])] }
}

fn show(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "issue_id") {
    None => Err(e.single("issue_id", "missing", "issue_id is required")),
    Some(id) => match proc.run("lex", util.json_cmd(["issue", "show", id])) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match util.cli_result(out) {
        Err(detail) => Err(e.single("", "cli_failed", detail)),
        Ok(body) => match jv.parse(str.trim(body)) {
          Err(_) => Ok(JStr(body)),
          Ok(issue) => Ok(JStr(ic.contract_prompt(issue))),
        },
      },
    },
  }
}

fn verify(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "issue_id") {
    None => Err(e.single("issue_id", "missing", "issue_id is required")),
    Some(id) => match proc.run("lex", util.json_cmd(["issue", "verify", id])) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match ic.verdict_of(out.stdout) {
        Some(_) => Ok(JStr(str.trim(out.stdout))),
        None => Err(e.single("", "cli_failed", util.combined(out))),
      },
    },
  }
}

fn show_tool() -> t.Tool {
  t.define("issue_show", "Read a typed issue's declared acceptance (lex issue show) and render it as the contract to implement: exact signatures to add/change/remove, the examples that are its oracle, or the failing example to fix.", id_params("IssueShowArgs", "Show a typed issue's acceptance."), show)
}

fn verify_tool() -> t.Tool {
  t.define("issue_verify", "Evaluate a typed issue's acceptance at the store head (lex issue verify) and record an IssueVerified attestation. Verdict: verified | failed (with detail naming the wrong signature or example) | inconclusive (shape not machine-evaluable). Call it to prove an issue done; iterate until verified.", id_params("IssueVerifyArgs", "Verify a typed issue at head."), verify)
}

