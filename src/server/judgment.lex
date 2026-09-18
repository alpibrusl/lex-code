# judgment.lex — an OPTIONAL second opinion on "did verify actually pass?".
#
# OFF BY DEFAULT, AND OFF IS THE DEFAULT PATH. With no endpoint configured
# this module makes no call, adds no latency, and returns the mechanical
# verdict unchanged. lex-code gains no package dependency and no service it
# has to be able to reach; `judged_failure` with nothing configured is exactly
# `verify_found_failure`.
#
# WHAT IT IS FOR. `verify_found_failure` decides whether an independent verify
# pass failed by looking for the literal substring "FAIL" in tool output. That
# is a good cheap heuristic and it has the blind spots a substring match always
# has: a run that reports "2 tests errored", "panicked at", or "1 failed"
# contains no "FAIL" and reads as a pass. The consequence is specific — the
# loop stops, `attest_verify_pass_if_clean` writes an independent-check
# attestation, and a broken implementation acquires a passing verdict.
#
# So the judgment is consulted ONLY when the mechanical check says PASS. It
# can turn a pass into a failure; it can never turn a failure into a pass. The
# cheap, deterministic, dependency-free check keeps the authority to fail, and
# the model only ever adds suspicion.
#
# THRESHOLD. A judgment model's probabilities are worth thresholding only where
# they are calibrated, and the default here is deliberately high. Measured on a
# 1,165-item corpus in a sibling project, the same class of model was well
# calibrated below 0.5 and above 0.9 and badly overconfident between: 56
# predictions in the 0.5-0.9 band, of which one was true. A default of 0.5
# would import that band, and here importing it means spending another paid,
# unbounded agent turn on a fix that was not needed.
#
# FAILS OPEN. Unreachable, slow, or an unparseable answer means the mechanical
# verdict stands. A third party being down is not evidence that code is broken,
# and a verify gate that fails closed on an API outage would block every merge
# for reasons unrelated to the code.
#
# CONFIGURE (all three, or it stays off):
#   LEX_CODE_JUDGE_URL        e.g. https://api.typesafe.ai/v1/systemone
#   LEX_CODE_JUDGE_KEY        bearer credential
#   LEX_CODE_JUDGE_THRESHOLD  optional, default 0.9
#
# The wire shape is a System One request — one `noul` question over the verify
# output, answered with a probability. Pointing this at a different provider
# means changing `ask` and nothing else.

import "std.str" as str

import "std.map" as map

import "std.env" as env

import "std.http" as http

import "std.bytes" as bytes

# `lex-schema/json_value`, not `std.json`: lex-code already imports json_value
# throughout, and Lex shares ONE constructor namespace across imported modules.
# A module here using the builtin `Json` would put two types named `Json` with
# the same `JStr`/`JObj`/`JFloat` constructors in one scope, and every
# constructor in this file would resolve to the other one — a type error at
# best. No new dependency: lex-schema is already in lex.toml.
import "lex-schema/json_value" as jv

type Judge = { url :: Str, key :: Str, threshold :: Float }

fn default_threshold() -> Float {
  0.9
}

fn question() -> Str {
  "This is the output of an independent verification run over a code change. Does it indicate the implementation is broken — tests failing, errors, panics, assertion mismatches, or wrong values? Answer about whether the code is broken, not about whether the output mentions the possibility of failure."
}

fn env_str(name :: Str) -> [env] Str {
  match env.get(name) {
    None => "",
    Some(v) => str.trim(v),
  }
}

# The configured judge, or `None`. `None` is the default and the quiet path:
# every caller below turns it into "no opinion".
fn configured() -> [env] Option[Judge] {
  let url := env_str("LEX_CODE_JUDGE_URL")
  let key := env_str("LEX_CODE_JUDGE_KEY")
  if str.is_empty(url) or str.is_empty(key) {
    None
  } else {
    Some({ url: url, key: key, threshold: threshold_from_env() })
  }
}

fn threshold_from_env() -> [env] Float {
  let raw := env_str("LEX_CODE_JUDGE_THRESHOLD")
  if str.is_empty(raw) {
    default_threshold()
  } else {
    match jv.parse(raw) {
      Ok(JFloat(f)) => f,
      Ok(JInt(i)) => int_to_float(i),
      _ => default_threshold(),
    }
  }
}

fn int_to_float(i :: Int) -> Float {
  match jv.parse(str.concat(jv.stringify(JInt(i)), ".0")) {
    Ok(JFloat(f)) => f,
    _ => default_threshold(),
  }
}

fn num(j :: jv.Json) -> Float {
  match j {
    JFloat(f) => f,
    JInt(i) => int_to_float(i),
    _ => 0.0,
  }
}

# One question over the verify output. `None` for anything that is not a
# probability we can read — unreachable, non-2xx, unparseable, or a shape we do
# not recognise. Every one of those means "no opinion", never "broken".
fn ask(j :: Judge, output :: Str) -> [net] Option[Float] {
  let body := JObj([("state", JStr(output)), ("model", JStr("jev-latest")), ("questions", JObj([("broken", JObj([("type", JStr("noul")), ("instructions", JStr(question()))]))]))])
  let base := { method: "POST", url: j.url, headers: map.new(), body: Some(bytes.from_str(jv.stringify(body))), timeout_ms: Some(20000) }
  let req := http.with_header(http.with_auth(base, "Bearer", j.key), "Content-Type", "application/json")
  match http.send(req) {
    Err(_) => None,
    Ok(r) => if r.status >= 400 {
      None
    } else {
      match bytes.to_str(r.body) {
        Err(_) => None,
        Ok(t) => match jv.parse(t) {
          Err(_) => None,
          Ok(parsed) => match jv.get_field(parsed, "answers") {
            None => None,
            Some(answers) => match jv.get_field(answers, "broken") {
              None => None,
              Some(a) => match jv.get_field(a, "noul") {
                None => None,
                Some(p) => Some(num(p)),
              },
            },
          },
        },
      }
    },
  }
}

# The probability that this output means the code is broken, or `None` when no
# judge is configured, the output is empty, or the call did not produce one.
fn opinion(output :: Str) -> [env, net] Option[Float] {
  if str.is_empty(str.trim(output)) {
    None
  } else {
    match configured() {
      None => None,
      Some(j) => ask(j, output),
    }
  }
}

# Should this verify output be treated as a failure?
#
# `mechanical` is the existing substring verdict and keeps the authority to
# fail: when it says the run failed, that stands and no call is made. The
# judgment is consulted only over a PASS, and can only ever turn a pass into a
# failure — never the reverse. A model that cannot be reached, or that is
# unsure, leaves the mechanical verdict exactly as it was.
fn judged_failure(mechanical :: Bool, output :: Str) -> [env, net] Bool {
  if mechanical {
    true
  } else {
    match opinion(output) {
      None => false,
      Some(p) => match configured() {
        None => false,
        Some(j) => p >= j.threshold,
      },
    }
  }
}

# Why a judgment overrode a mechanical pass, for the trail. Written only when
# it actually overrides, so a reader can tell a judged failure from a
# mechanical one and can see the number that caused it.
fn override_detail(p :: Float, threshold :: Float) -> Str {
  jv.stringify(JObj([("verdict", JStr("failure")), ("source", JStr("judgment")), ("p", JFloat(p)), ("threshold", JFloat(threshold)), ("note", JStr("mechanical check found no FAIL; judgment disagreed"))]))
}

