# Tests for the OPTIONAL verify judgment.
#
# The property that matters most is not what the judgment decides — it is that
# it is OFF unless deliberately turned on, and that when off, nothing about the
# existing verdict changes. A security-adjacent gate that quietly starts
# consulting a third party because a module was imported would be the worst
# regression this addition could ship.
#
# So these run with no judge configured, which is how every existing checkout
# and CI job runs, and assert the off-path exactly. They declare `[env, net]`
# because the functions under test do — but with nothing configured, `net` is
# never exercised: `judged_failure` short-circuits before any call, which is
# itself one of the assertions below.

import "std.list" as list

import "std.str" as str

import "std.io" as io

import "../src/server/judgment" as judgment

fn expect(cond :: Bool, msg :: Str) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(msg)
  }
}

# ── off by default ───────────────────────────────────────────────────────────
#
# With LEX_CODE_JUDGE_URL / _KEY unset — the state of every checkout that has
# not opted in — there is no judge at all.
fn no_judge_is_configured_by_default() -> [env] Result[Unit, Str] {
  match judgment.configured() {
    None => Ok(()),
    Some(_) => Err("a judge was configured from a bare environment — this must be opt-in"),
  }
}

# The whole claim of the off-path: with nothing configured, `judged_failure` is
# exactly `verify_found_failure`. Both verdicts pass through untouched.
fn with_no_judge_the_mechanical_verdict_passes_through() -> [env, net] Result[Unit, Str] {
  if not judgment.judged_failure(false, "OK selector\nOK encode_call") {
    if judgment.judged_failure(true, "FAIL encode_call got=x want=y") {
      Ok(())
    } else {
      Err("a mechanical failure must stay a failure")
    }
  } else {
    Err("a mechanical pass must stay a pass when no judge is configured")
  }
}

# ── the mechanical check keeps the authority to fail ─────────────────────────
#
# A mechanical failure short-circuits: no call is made, so the verdict cannot
# depend on a third party being reachable, and no judge can ever turn a real
# failure into a pass. This holds whether or not one is configured — which is
# why it is safe to assert here with none.
fn a_mechanical_failure_never_consults_the_judge() -> [env, net] Result[Unit, Str] {
  expect(judgment.judged_failure(true, "anything at all"), "a mechanical failure must be returned directly, without asking anyone")
}

# ── no opinion is not a failure ──────────────────────────────────────────────
#
# Empty output means there is nothing to judge. It must not become a failure by
# default: `attest_verify_pass_if_clean` already guards the empty-events case
# separately, and inventing a failure here would double-count it.
fn empty_output_yields_no_opinion() -> [env, net] Result[Unit, Str] {
  match judgment.opinion("") {
    None => Ok(()),
    Some(_) => Err("empty output must produce no opinion, not a judgment"),
  }
}

fn whitespace_output_yields_no_opinion() -> [env, net] Result[Unit, Str] {
  match judgment.opinion("   \n  ") {
    None => Ok(()),
    Some(_) => Err("whitespace-only output must produce no opinion"),
  }
}

# ── the threshold is high on purpose ─────────────────────────────────────────
#
# Measured on a 1,165-item corpus, this class of model was well calibrated
# below 0.5 and above 0.9 and badly overconfident between — 56 predictions in
# that band, one of them true. A default of 0.5 would import the whole band,
# and here that means spending a paid agent turn on a fix that was not needed.
fn the_default_threshold_is_not_one_half() -> Result[Unit, Str] {
  if judgment.default_threshold() >= 0.9 {
    Ok(())
  } else {
    Err("the default threshold must stay high; 0.5 sits inside the band where this model is overconfident")
  }
}

# ── the override record says which layer decided ─────────────────────────────
fn an_override_record_names_its_source_and_number() -> Result[Unit, Str] {
  let d := judgment.override_detail(0.97, 0.9)
  if not str.contains(d, "judgment") {
    Err(str.concat("the record must name the source: ", d))
  } else {
    expect(str.contains(d, "0.97") and str.contains(d, "0.9"), str.concat("the record must carry the probability and the threshold: ", d))
  }
}

# ── harness ──────────────────────────────────────────────────────────────────
type Case = { name :: Str, result :: Result[Unit, Str] }

fn c(name :: Str, result :: Result[Unit, Str]) -> Case {
  { name: name, result: result }
}

fn cases() -> [env, net] List[Case] {
  [c("no_judge_is_configured_by_default", no_judge_is_configured_by_default()), c("with_no_judge_the_mechanical_verdict_passes_through", with_no_judge_the_mechanical_verdict_passes_through()), c("a_mechanical_failure_never_consults_the_judge", a_mechanical_failure_never_consults_the_judge()), c("empty_output_yields_no_opinion", empty_output_yields_no_opinion()), c("whitespace_output_yields_no_opinion", whitespace_output_yields_no_opinion()), c("the_default_threshold_is_not_one_half", the_default_threshold_is_not_one_half()), c("an_override_record_names_its_source_and_number", an_override_record_names_its_source_and_number())]
}

fn run_all() -> [env, io, net] Unit {
  let results := cases()
  let failures := list.fold(results, 0, fn (n :: Int, k :: Case) -> [io] Int {
    match k.result {
      Ok(_) => n,
      Err(e) => {
        let __p := io.print(str.join(["FAIL  ", k.name, ": ", e], ""))
        n + 1
      },
    }
  })
  let __s := io.print(str.join(["judgment: ", int_str(list.len(results) - failures), "/", int_str(list.len(results)), " passed"], ""))
  if failures == 0 {
    ()
  } else {
    let __boom := 1 / 0
    ()
  }
}

fn int_str(i :: Int) -> Str {
  match i {
    0 => "0",
    _ => int_to_str_go(i, ""),
  }
}

fn int_to_str_go(i :: Int, acc :: Str) -> Str {
  if i <= 0 {
    acc
  } else {
    int_to_str_go(i / 10, str.concat(digit(i % 10), acc))
  }
}

fn digit(d :: Int) -> Str {
  match d {
    0 => "0",
    1 => "1",
    2 => "2",
    3 => "3",
    4 => "4",
    5 => "5",
    6 => "6",
    7 => "7",
    8 => "8",
    9 => "9",
    _ => "?",
  }
}

