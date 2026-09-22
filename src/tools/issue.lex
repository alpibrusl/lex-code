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
#
# `issue_propose` (#956) is the agent's half of refining a free-form issue:
# it proposes a typed acceptance, signed with the model that wrote it.
# There is deliberately no approve tool — the human is the arbiter, and
# `lex issue approve <proposal> --by WHO` is theirs to run.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "std.io" as io

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

# One entry per non-blank line — how a model passes a list through a
# string field without inventing a JSON-in-JSON encoding.
fn lines(s :: Str) -> List[Str]
  examples {
    lines("a\n\n  b  \n") => ["a", "b"],
    lines("") => []
  }
{
  list.filter(list.map(str.split(s, "\n"), fn (l :: Str) -> Str {
    str.trim(l)
  }), fn (l :: Str) -> Bool {
    not str.is_empty(l)
  })
}

fn repeat_flag(flag :: Str, values :: List[Str]) -> List[Str]
  examples {
    repeat_flag("--api", ["a", "b"]) => ["--api", "a", "--api", "b"],
    repeat_flag("--api", []) => []
  }
{
  list.fold(values, [], fn (acc :: List[Str], v :: Str) -> List[Str] {
    list.concat(acc, [flag, v])
  })
}

fn opt_flag(flag :: Str, value :: Option[Str]) -> List[Str] {
  match value {
    None => [],
    Some(v) => [flag, v],
  }
}

type ProposeInput = { issue_id :: Str, shape :: Str, api :: Str, examples :: Str, predicate :: Option[Str], window :: Option[Str], subject :: Option[Str], invariants :: Str, rationale :: Str, by :: Str }

# The `lex issue propose` argv for a proposal.
fn propose_argv(p :: ProposeInput) -> List[Str]
  examples {
    propose_argv({ issue_id: "i1", shape: "typed_delta", api: "clamp:(x :: Int) -> Int", examples: "clamp(5) => 3\nclamp(0) => 0", predicate: None, window: None, subject: None, invariants: "", rationale: "r", by: "ollama/qwen" }) => ["--output", "json", "issue", "propose", "i1", "--shape", "typed_delta", "--api", "clamp:(x :: Int) -> Int", "--example", "clamp(5) => 3", "--example", "clamp(0) => 0", "--rationale", "r", "--by", "ollama/qwen"],
    propose_argv({ issue_id: "i1", shape: "metric_invariant", api: "", examples: "", predicate: Some("p99 < 200"), window: Some("7d"), subject: None, invariants: "", rationale: "", by: "" }) => ["--output", "json", "issue", "propose", "i1", "--shape", "metric_invariant", "--predicate", "p99 < 200", "--window", "7d", "--rationale", "", "--by", ""]
  }
{
  list.concat(util.json_cmd(["issue", "propose", p.issue_id, "--shape", p.shape]), list.concat(repeat_flag("--api", lines(p.api)), list.concat(repeat_flag("--example", lines(p.examples)), list.concat(opt_flag("--predicate", p.predicate), list.concat(opt_flag("--window", p.window), list.concat(opt_flag("--subject", p.subject), list.concat(repeat_flag("--invariant", lines(p.invariants)), ["--rationale", p.rationale, "--by", p.by])))))))
}

# Who is proposing: the turn's provider/model, as session.lex recorded it.
fn proposer() -> [io] Str {
  match io.read(".lex/intent/model") {
    Err(_) => "lex-code",
    Ok(m) => str.concat("lex-code/", str.trim(m)),
  }
}

fn propose_params() -> s.ModelSchema {
  { title: "IssueProposeArgs", description: "Propose a typed acceptance for a free_form issue; a human approves or rejects it.", fields: [s.required_str("issue_id", []), s.required_str("shape", []), s.optional(s.required_str("api", [])), s.optional(s.required_str("examples", [])), s.optional(s.required_str("predicate", [])), s.optional(s.required_str("window", [])), s.optional(s.required_str("subject", [])), s.optional(s.required_str("invariants", [])), s.required_str("rationale", [])] }
}

fn propose(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match (util.field_str(args, "issue_id"), util.field_str(args, "shape")) {
    (Some(id), Some(shape)) => {
      let argv := propose_argv({ issue_id: id, shape: shape, api: util.field_str_or(args, "api", ""), examples: util.field_str_or(args, "examples", ""), predicate: util.field_str(args, "predicate"), window: util.field_str(args, "window"), subject: util.field_str(args, "subject"), invariants: util.field_str_or(args, "invariants", ""), rationale: util.field_str_or(args, "rationale", ""), by: proposer() })
      match proc.run("lex", argv) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => match util.cli_result(out) {
          Err(detail) => Err(e.single("", "cli_failed", detail)),
          Ok(body) => Ok(JStr(str.trim(body))),
        },
      }
    },
    _ => Err(e.single("", "missing", "issue_id and shape are required")),
  }
}

fn propose_tool() -> t.Tool {
  t.define("issue_propose", "Propose a typed acceptance for a free_form issue (lex issue propose). shape: typed_delta (api: one `name:signature[:added|changed|removed]` per line, e.g. `clamp:(x :: Int, lo :: Int, hi :: Int) -> Int`; examples: one `name(args) => expected` per line) | failing_example (examples: exactly one line) | metric_invariant (predicate, window) | evidence (subject, invariants one per line). rationale: why this captures the issue. Nothing changes until a HUMAN approves it; you cannot approve it yourself.", propose_params(), propose)
}

fn show_tool() -> t.Tool {
  t.define("issue_show", "Read a typed issue's declared acceptance (lex issue show) and render it as the contract to implement: exact signatures to add/change/remove, the examples that are its oracle, or the failing example to fix.", id_params("IssueShowArgs", "Show a typed issue's acceptance."), show)
}

fn verify_tool() -> t.Tool {
  t.define("issue_verify", "Evaluate a typed issue's acceptance at the store head (lex issue verify) and record an IssueVerified attestation. Verdict: verified | failed (with detail naming the wrong signature or example) | inconclusive (shape not machine-evaluable). Call it to prove an issue done; iterate until verified.", id_params("IssueVerifyArgs", "Verify a typed issue at head."), verify)
}

