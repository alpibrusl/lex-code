# lex-code — task specifications that can be checked
#
# A task is a `Str` today: "implement list.zip". Whether it got done is
# whatever the model says at the end, which is the one claim in this
# system with nothing behind it (#33). A TaskSpec pairs the goal with
# criteria a machine can evaluate, so "done" becomes a result rather than
# an opinion.
#
# ---- what this deliberately leaves out --------------------------------
#
# The issue's TaskSpec also carries `inputs` and `allowed_effects`.
#
# `allowed_effects` is omitted because it would be the THIRD mechanism
# constraining effects, after `os_check` (a file's effects against the
# mode's grant) and `permissions/rules.lex` (which tools a mode may call).
# Every place this codebase has kept two mechanisms over one set of facts,
# they drifted: `attestation_query` read a store nothing wrote (#32), the
# merge tools passed a flag the CLI rejects (#23), `run.lex` carried its
# own copy of the graph runner (#30). A third would drift too, and it is
# the one that would drift silently, because a declaration nothing
# enforces still reads as a guarantee.
#
# `inputs` is omitted because nothing consumes a type hint. It would be a
# field the model writes and no code reads.
#
# Both are additive if wanted later; neither is load-bearing for the thing
# that makes this worth having, which is `is_satisfied`.
#
# ---- what a criterion can honestly assert -----------------------------
#
# `VerifiedKindSeen` is the issue's `AttestationExists(fn_name, kind)`,
# renamed for what it can actually check. The `verified.*` records carry a
# kind and the TOOL that produced the pass, never the function — lex-llm's
# dispatch loop writes them from the tool's result and never sees its
# arguments (the open half of #32). So this asserts "a check of this kind
# passed in this project", not "this function is verified", and the name
# says so rather than implying the stronger claim.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "std.toml" as toml

import "std.io" as io

import "./verification" as verification

type SuccessCriterion = CheckPasses(Str) | SpecCheckPasses(Str) | TestPasses(Str) | VerifiedKindSeen(Str)

type TaskSpec = { goal :: Str, success :: List[SuccessCriterion] }

type Outcome = { label :: Str, met :: Bool, detail :: Str }

type Verdict = { satisfied :: Bool, outcomes :: List[Outcome] }

fn tasks_dir() -> Str
  examples {
    tasks_dir() => ".lex/tasks"
  }
{
  ".lex/tasks"
}

fn spec_path(name :: Str) -> Str
  examples {
    spec_path("zip") => ".lex/tasks/zip.task",
    spec_path("zip.task") => ".lex/tasks/zip.task",
    spec_path(".lex/tasks/zip.task") => ".lex/tasks/zip.task"
  }
{
  if str.contains(name, "/") {
    name
  } else {
    if str.ends_with(name, ".task") {
      str.join([tasks_dir(), "/", name], "")
    } else {
      str.join([tasks_dir(), "/", name, ".task"], "")
    }
  }
}

# ---- the file format --------------------------------------------------
#
# TOML rather than the issue's "Lex literal syntax": there is no runtime
# parser for Lex literals, and `std.toml` parses straight into a typed
# record — the same route `.lex/mcp.toml` takes, so a project has one
# config language rather than two.
#
#   goal     = "add zip to src/list.lex"
#   check    = ["src/list.lex"]
#   test     = ["tests/test_list.lex"]
#   verified = ["verified.type_check"]
type TaskFile = { goal :: Str, check :: List[Str], spec_check :: List[Str], test :: List[Str], verified :: List[Str] }

fn criteria_of(tf :: TaskFile) -> List[SuccessCriterion] {
  list.concat(list.map(tf.check, fn (p :: Str) -> SuccessCriterion {
    CheckPasses(p)
  }), list.concat(list.map(tf.spec_check, fn (p :: Str) -> SuccessCriterion {
    SpecCheckPasses(p)
  }), list.concat(list.map(tf.test, fn (p :: Str) -> SuccessCriterion {
    TestPasses(p)
  }), list.map(tf.verified, fn (k :: Str) -> SuccessCriterion {
    VerifiedKindSeen(k)
  }))))
}

fn of_file(tf :: TaskFile) -> TaskSpec {
  { goal: tf.goal, success: criteria_of(tf) }
}

fn parse(text :: Str) -> Result[TaskSpec, Str] {
  match toml.parse(text) {
    Err(m) => Err(m),
    Ok(tf) => Ok(of_file(tf)),
  }
}

fn load(name :: Str) -> [io] Result[TaskSpec, Str] {
  let path := spec_path(name)
  match io.read(path) {
    Err(_) => Err(str.join(["no task spec at ", path], "")),
    Ok(text) => match parse(text) {
      Err(m) => Err(str.join([path, " is not valid TOML: ", m], "")),
      Ok(spec) => Ok(spec),
    },
  }
}

# ---- evaluating -------------------------------------------------------
fn label_of(c :: SuccessCriterion) -> Str
  examples {
    label_of(CheckPasses("src/a.lex")) => "lex check src/a.lex",
    label_of(SpecCheckPasses("src/a.lex")) => "lex spec check src/a.lex",
    label_of(TestPasses("tests/t.lex")) => "lex test tests/t.lex",
    label_of(VerifiedKindSeen("verified.test")) => "a verified.test pass recorded in this project"
  }
{
  match c {
    CheckPasses(p) => str.concat("lex check ", p),
    SpecCheckPasses(p) => str.concat("lex spec check ", p),
    TestPasses(p) => str.concat("lex test ", p),
    VerifiedKindSeen(k) => str.join(["a ", k, " pass recorded in this project"], ""),
  }
}

# Exit code zero, and nothing else, is a pass.
#
# These examples exist because the obvious loosenings are invisible: a
# `>=` here, or reading stdout for the word "passed", would make every
# shelled-out criterion succeed unconditionally and the whole mechanism
# would report SATISFIED for work that was never done — the exact claim
# it was built to stop taking on faith.
fn ran(label :: Str, out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Outcome
  examples {
    ran("c", { stdout: "", stderr: "", exit_code: 0 }) => { label: "c", met: true, detail: "" },
    ran("c", { stdout: "type check passed", stderr: "", exit_code: 0 }) => { label: "c", met: true, detail: "" },
    ran("c", { stdout: "boom", stderr: "", exit_code: 1 }) => { label: "c", met: false, detail: "boom" },
    ran("c", { stdout: "", stderr: "bad", exit_code: 2 }) => { label: "c", met: false, detail: "bad" },
    ran("c", { stdout: "ok anyway", stderr: "", exit_code: 1 }) => { label: "c", met: false, detail: "ok anyway" }
  }
{
  if out.exit_code == 0 {
    { label: label, met: true, detail: "" }
  } else {
    { label: label, met: false, detail: str.trim(str.concat(out.stdout, out.stderr)) }
  }
}

fn shell(label :: Str, args :: List[Str]) -> [proc] Outcome {
  match proc.run("lex", args) {
    Err(msg) => { label: label, met: false, detail: str.concat("could not run lex: ", msg) },
    Ok(out) => ran(label, out),
  }
}

# A criterion that could not be evaluated is NOT met. The alternative —
# treating an unrunnable check as satisfied — turns a broken toolchain
# into a passing task, which is the failure mode this whole mechanism
# exists to prevent.
fn evaluate(c :: SuccessCriterion) -> [io, proc] Outcome {
  match c {
    CheckPasses(p) => shell(label_of(c), ["check", p]),
    SpecCheckPasses(p) => shell(label_of(c), ["spec", "check", p]),
    TestPasses(p) => shell(label_of(c), ["run", p, "run_all"]),
    VerifiedKindSeen(k) => verified_outcome(label_of(c), k),
  }
}

fn verified_outcome(label :: Str, kind :: Str) -> [io] Outcome {
  if seen(verification.all(), kind) {
    { label: label, met: true, detail: "" }
  } else {
    { label: label, met: false, detail: str.join(["no ", kind, " record in ", verification.path()], "") }
  }
}

fn seen(records :: List[verification.Record], kind :: Str) -> Bool {
  list.fold(records, false, fn (acc :: Bool, r :: verification.Record) -> Bool {
    if acc {
      true
    } else {
      r.kind == kind
    }
  })
}

# Every criterion is evaluated, not just up to the first failure. A task
# with three unmet criteria should report three, so one round of work can
# address all of them; short-circuiting would turn that into three rounds.
fn is_satisfied(spec :: TaskSpec) -> [io, proc] Verdict {
  let outcomes := list.map(spec.success, evaluate)
  { satisfied: all_met(outcomes), outcomes: outcomes }
}

# A spec with no criteria is NOT satisfied.
#
# `list.fold` over an empty list returns the seed, so the natural writing
# of "all met" says true here — vacuous truth, and exactly wrong: a task
# nobody wrote criteria for is unverified, not verified. Saying so is the
# difference between "nothing failed" and "nothing was checked".
fn all_met(outcomes :: List[Outcome]) -> Bool
  examples {
    all_met([]) => false,
    all_met([{ label: "a", met: true, detail: "" }]) => true,
    all_met([{ label: "a", met: true, detail: "" }, { label: "b", met: false, detail: "x" }]) => false
  }
{
  if list.is_empty(outcomes) {
    false
  } else {
    list.fold(outcomes, true, fn (acc :: Bool, o :: Outcome) -> Bool {
      if acc {
        o.met
      } else {
        false
      }
    })
  }
}

fn render(spec :: TaskSpec, v :: Verdict) -> Str {
  if list.is_empty(v.outcomes) {
    str.concat(header(spec, v), footer(v))
  } else {
    str.join([header(spec, v), "\n", str.join(list.map(v.outcomes, render_one), "\n"), footer(v)], "")
  }
}

fn header(spec :: TaskSpec, v :: Verdict) -> Str {
  if list.is_empty(v.outcomes) {
    str.join(["task \"", spec.goal, "\": UNVERIFIED — the spec declares no success criteria"], "")
  } else {
    str.join(["task \"", spec.goal, "\": ", verdict_word(v)], "")
  }
}

fn verdict_word(v :: Verdict) -> Str
  examples {
    verdict_word({ satisfied: true, outcomes: [] }) => "SATISFIED",
    verdict_word({ satisfied: false, outcomes: [] }) => "NOT SATISFIED"
  }
{
  if v.satisfied {
    "SATISFIED"
  } else {
    "NOT SATISFIED"
  }
}

fn render_one(o :: Outcome) -> Str {
  if o.met {
    str.join(["  ok    ", o.label], "")
  } else {
    str.join(["  FAIL  ", o.label, "\n          ", first_line(o.detail)], "")
  }
}

fn first_line(detail :: Str) -> Str
  examples {
    first_line("one\ntwo") => "one",
    first_line("") => "(no output)"
  }
{
  if str.is_empty(detail) {
    "(no output)"
  } else {
    match list.head(str.split(detail, "\n")) {
      None => detail,
      Some(l) => l,
    }
  }
}

fn footer(v :: Verdict) -> Str {
  if v.satisfied {
    ""
  } else {
    "\n\nThe agent's report that a task is complete is a claim; these are the checks. A criterion that could not be run counts as unmet."
  }
}

