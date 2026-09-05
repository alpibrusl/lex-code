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
# The issue asks for `AttestationExists(fn_name, kind)`. Two criteria get
# close, and neither is quite that.
#
# `VerifiedKindSeen(kind)` asserts a pass of that kind happened somewhere
# in this project. `VerifiedTargetSeen(target, kind)` asserts one happened
# on a given path.
#
# The path is as far as this goes. `verified.*` records name the argument
# the tool was given — `lex check src/list.lex` — and a file is not a
# function, so neither criterion can say `zip` in particular was checked.
#
# An earlier version of this comment said the records could not name a
# path at all, because lex-llm's dispatch "never sees the tool's
# arguments". That was wrong: `call.args_raw` sits two lines above the
# write, and the fix was one field (alpibrusl/lex-llm#48). Function-level
# evidence would need the store's attestation graph, which is what
# `lex blame --with-evidence` reads and what `attestation_query` calls the
# stronger signal.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "std.toml" as toml

import "std.io" as io

import "./verification" as verification

type SuccessCriterion = CheckPasses(Str) | SpecCheckPasses(Str) | TestPasses(Str) | VerifiedKindSeen(Str) | VerifiedTargetSeen((Str, Str)) | Malformed(Str)

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
#   goal        = "add zip to src/list.lex"
#   check       = ["src/list.lex"]
#   test        = ["tests/test_list.lex"]
#   verified    = ["verified.type_check"]
#   verified_on = ["src/list.lex:verified.type_check"]
#
# `verified_on` entries are "<path>:<kind>" — one string rather than a
# nested array, because TOML's nested-array shape reads worse than the
# colon and parses no better.
type TaskFile = { goal :: Str, check :: List[Str], spec_check :: List[Str], test :: List[Str], verified :: List[Str], verified_on :: List[Str] }

# Every array in the file becomes criteria. The `verified_on` arm was
# missing from an earlier draft of this function, and nothing caught it:
# an unread field in a TOML record is not a type error, so the spec
# type-checked, loaded, and quietly evaluated three fewer criteria than it
# declared — reporting SATISFIED. The example below counts them, because
# "the task passed" is exactly the answer that must not be reachable by
# dropping the checks.
fn criteria_of(tf :: TaskFile) -> List[SuccessCriterion]
  examples {
    criteria_of({ goal: "g", check: ["a"], spec_check: ["b"], test: ["c"], verified: ["d"], verified_on: ["e:f"] }) => [CheckPasses("a"), SpecCheckPasses("b"), TestPasses("c"), VerifiedKindSeen("d"), VerifiedTargetSeen("e", "f")],
    criteria_of({ goal: "g", check: [], spec_check: [], test: [], verified: [], verified_on: ["bad"] }) => [Malformed("bad")],
    criteria_of({ goal: "g", check: [], spec_check: [], test: [], verified: [], verified_on: [] }) => []
  }
{
  list.concat(list.map(tf.check, fn (p :: Str) -> SuccessCriterion {
    CheckPasses(p)
  }), list.concat(list.map(tf.spec_check, fn (p :: Str) -> SuccessCriterion {
    SpecCheckPasses(p)
  }), list.concat(list.map(tf.test, fn (p :: Str) -> SuccessCriterion {
    TestPasses(p)
  }), list.concat(list.map(tf.verified, fn (k :: Str) -> SuccessCriterion {
    VerifiedKindSeen(k)
  }), list.map(tf.verified_on, on_criterion)))))
}

# "<path>:<kind>". A malformed entry becomes a criterion that can never be
# met rather than being dropped: a typo in a spec should fail the task
# loudly, not silently shrink what it checks.
#
# It gets its own constructor rather than being squeezed into
# VerifiedTargetSeen with the complaint in the kind slot — which is what
# the first version did, and it rendered as "a malformed verified_on entry
# ... pass recorded on ", a sentence built out of two unrelated halves.
fn on_criterion(entry :: Str) -> SuccessCriterion
  examples {
    on_criterion("src/a.lex:verified.type_check") => VerifiedTargetSeen("src/a.lex", "verified.type_check"),
    on_criterion(" src/a.lex : verified.type_check ") => VerifiedTargetSeen("src/a.lex", "verified.type_check"),
    on_criterion("verified.type_check") => Malformed("verified.type_check"),
    on_criterion("a:b:c") => Malformed("a:b:c"),
    on_criterion("") => Malformed("")
  }
{
  let parts := str.split(entry, ":")
  if list.len(parts) == 2 {
    match (list.head(parts), list.head(list.tail(parts))) {
      (Some(p), Some(k)) => VerifiedTargetSeen(str.trim(p), str.trim(k)),
      _ => Malformed(entry),
    }
  } else {
    Malformed(entry)
  }
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
    label_of(VerifiedKindSeen("verified.test")) => "a verified.test pass recorded in this project",
    label_of(VerifiedTargetSeen("src/a.lex", "verified.test")) => "a verified.test pass recorded on src/a.lex",
    label_of(Malformed("oops")) => "malformed verified_on entry \"oops\""
  }
{
  match c {
    CheckPasses(p) => str.concat("lex check ", p),
    SpecCheckPasses(p) => str.concat("lex spec check ", p),
    TestPasses(p) => str.concat("lex test ", p),
    VerifiedKindSeen(k) => str.join(["a ", k, " pass recorded in this project"], ""),
    VerifiedTargetSeen(t, k) => str.join(["a ", k, " pass recorded on ", t], ""),
    Malformed(entry) => str.join(["malformed verified_on entry \"", entry, "\""], ""),
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
    VerifiedTargetSeen(t, k) => target_outcome(label_of(c), t, k),
    Malformed(entry) => malformed_outcome(entry),
  }
}

# Pure, so the "never met" part is pinned by examples rather than living
# only inside an effectful match arm nothing can check.
fn malformed_outcome(entry :: Str) -> Outcome
  examples {
    malformed_outcome("oops") => { label: "malformed verified_on entry \"oops\"", met: false, detail: "expected <path>:<kind>, e.g. src/list.lex:verified.type_check" },
    malformed_outcome("") => { label: "malformed verified_on entry \"\"", met: false, detail: "expected <path>:<kind>, e.g. src/list.lex:verified.type_check" }
  }
{
  { label: label_of(Malformed(entry)), met: false, detail: "expected <path>:<kind>, e.g. src/list.lex:verified.type_check" }
}

# A record's `sig` binds it to the content it was a pass of (#91). A record
# naming a specific target with no `sig`, or with a `sig` that no longer
# matches the target's current bytes, is not evidence the current code is
# right — it is evidence that *some* revision once was. Whole-project-scope
# records (`target == ""`) have no single file to hash against, so they are
# never stale by this check; that is the same limitation `sig_for` already
# documents, not a new one.
fn is_fresh(r :: verification.Record) -> [io] Bool {
  if str.is_empty(r.target) {
    true
  } else {
    if str.is_empty(r.sig) {
      false
    } else {
      r.sig == verification.sig_for(r.target)
    }
  }
}

# Three states, not two, because "no record" and "a record, but it's stale"
# call for different messages — a reader fixing a stale-record failure needs
# to know a check ran before and just needs re-running, not that nothing was
# ever checked. `Fresh` wins over `Stale` if both occur (an old stale record
# and a newer fresh one for the same target/kind can coexist in an
# append-only log); `Stale` wins over `Absent` otherwise.
type Presence = Absent | Fresh | Stale

fn upgrade(acc :: Presence, hit :: Bool, fresh :: Bool) -> [io] Presence {
  match acc {
    Fresh => Fresh,
    _ => if hit {
      if fresh {
        Fresh
      } else {
        Stale
      }
    } else {
      acc
    },
  }
}

fn presence_on(records :: List[verification.Record], target :: Str, kind :: Str) -> [io] Presence {
  list.fold(records, Absent, fn (acc :: Presence, r :: verification.Record) -> [io] Presence {
    let hit := r.kind == kind and r.target == target
    upgrade(acc, hit, if hit {
      is_fresh(r)
    } else {
      false
    })
  })
}

fn presence(records :: List[verification.Record], kind :: Str) -> [io] Presence {
  list.fold(records, Absent, fn (acc :: Presence, r :: verification.Record) -> [io] Presence {
    let hit := r.kind == kind
    upgrade(acc, hit, if hit {
      is_fresh(r)
    } else {
      false
    })
  })
}

fn target_outcome(label :: Str, target :: Str, kind :: Str) -> [io] Outcome {
  match presence_on(verification.all(), target, kind) {
    Fresh => { label: label, met: true, detail: "" },
    Stale => { label: label, met: false, detail: str.join(["a ", kind, " record exists for ", target, " but it no longer matches the file's current content — re-run the check"], "") },
    Absent => { label: label, met: false, detail: str.join(["no ", kind, " record for ", target, " in ", verification.path()], "") },
  }
}

fn verified_outcome(label :: Str, kind :: Str) -> [io] Outcome {
  match presence(verification.all(), kind) {
    Fresh => { label: label, met: true, detail: "" },
    Stale => { label: label, met: false, detail: str.join(["a ", kind, " record exists in this project but no longer matches its target's current content — re-run the check"], "") },
    Absent => { label: label, met: false, detail: str.join(["no ", kind, " record in ", verification.path()], "") },
  }
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

