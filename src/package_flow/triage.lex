# lex-code — why did this attempt not verify?
#
# A retry helps when the model's code was wrong. It cannot help when the thing
# that failed is not the code. Across five earlier invoices runs, ten units
# needed more than one attempt; nine used all four and failed, and the one that
# recovered did so on the third. Among them: examples the issue store could not
# even parse (an example is immutable once filed, so no edit by the model can
# change it), and a shared file left unparseable by an earlier merge. Each was
# retried the full budget anyway.
#
# This reads what `lex --output json issue verify ID` printed and says which
# kind of failure it was. It is deliberately conservative: it only calls
# something "not the code" when the store itself said so, never from how a
# value looks. A padding function that is off by one produces the same
# expected-versus-got shape as a miscounted example, so that distinction is
# not guessable from the text, and a wrong guess here would stop a unit that a
# retry could have fixed.
#
#   plan_defect — the store rejected an example before running anything. Fixing
#                 it means changing the plan, which only a human or the planner
#                 can do; stop spending attempts on it.
#   tooling     — the verify command itself failed for another reason; the
#                 model's code is not what is being judged.
#   code        — anything else (a failed example, a type error): retry.

import "std.str" as str

import "lex-schema/json_value" as jv

type Triage = { kind :: Str, why :: Str }

fn error_message(stdout :: Str) -> Option[Str] {
  match jv.parse(str.trim(stdout)) {
    Err(_) => None,
    Ok(j) => match jv.get_field(j, "error") {
      None => None,
      Some(e) => match jv.get_field(e, "message") {
        None => None,
        Some(m) => jv.as_str(m),
      },
    },
  }
}

fn triage_verify(stdout :: Str) -> Triage
  examples {
    triage_verify("{\"ok\":true,\"command\":\"issue-verify\",\"data\":{\"verdict\":\"failed\",\"detail\":\"x\"}}") => { kind: "code", why: "" },
    triage_verify("not json") => { kind: "code", why: "" },
    triage_verify("{\"ok\":false,\"error\":{\"code\":\"GENERAL_ERROR\",\"message\":\"parsing example `f(1).x => 2`: example case must be a call to the function under definition\"}}") => { kind: "plan_defect", why: "parsing example `f(1).x => 2`: example case must be a call to the function under definition" },
    triage_verify("{\"ok\":false,\"error\":{\"code\":\"X\",\"message\":\"store is locked\"}}") => { kind: "tooling", why: "store is locked" }
  }
{
  match error_message(stdout) {
    None => { kind: "code", why: "" },
    Some(m) => if str.contains(m, "parsing example") or str.contains(m, "example case must be") {
      { kind: "plan_defect", why: str.slice(m, 0, 300) }
    } else {
      { kind: "tooling", why: str.slice(m, 0, 300) }
    },
  }
}

