# lex-code — repository probes for the `Repo` tier of the bar ledger
#
# Six probes, one per `Repo`-tier item in ./ledger. Every one of them
# answers a question about the repository it is pointed at, and none of
# them reaches a cloud account, a dashboard or a backup — that is the
# tier boundary, and it is why `Attested` items exist.
#
# Two rules the probes hold to, both borrowed from the books:
#
#   1. Report the bound, always. `Probe.bound` says what the probe did
#      NOT look at: the history depth it stopped at, the branch
#      protection it cannot see. A checklist that overstates its own
#      coverage is worse than no checklist, because it retires a
#      question that is still open.
#   2. Be conservative about what counts as a hit. The books' term
#      linter scans only distinctive names, on the grounds that a gate
#      which cries wolf trains everyone to ignore it. The secret scan
#      takes the same line: five patterns that are unambiguously
#      credentials, not every long string.
#
# Effects are [io, proc] — file reads and git/find. That is a subset of
# the [net, io, proc] row Tool.execute pins (lex-llm/tool.lex), so
# ../tools/bar_check can call these directly.

import "./probe_ids" as pid

import "std.io" as io

import "std.int" as int

import "std.list" as list

import "std.process" as proc

import "std.regex" as regex

import "std.str" as str

import "std.toml" as toml

type Verdict = Pass | Fail | Partial | Unknown

type Probe = { id :: Str, verdict :: Verdict, detail :: Str, bound :: Str }

type Pattern = { name :: Str, re :: Str }

type PkgTable = { lex :: Str }

type LexToml = { package :: PkgTable }

fn verdict_label(v :: Verdict) -> Str
  examples {
    verdict_label(Pass) => "pass",
    verdict_label(Fail) => "fail",
    verdict_label(Partial) => "partial",
    verdict_label(Unknown) => "unknown"
  }
{
  match v {
    Pass => "pass",
    Fail => "fail",
    Partial => "partial",
    Unknown => "unknown",
  }
}

# How far back the secret scan reads. Deep enough to cover the whole
# history of a young repository, shallow enough that the probe answers
# in seconds on an old one — and named in `bound` either way.
fn history_depth() -> Int
  examples {
    history_depth() => 500
  }
{
  500
}

# Credential shapes, not "things that look random". Each of these is a
# vendor-issued prefix or an armoured key header; a match is a finding,
# not a prompt to go and look.
# No examples block: the only expected value an example could state
# here is the literal list itself, which tests the transcription rather
# than the behaviour.
fn secret_patterns() -> List[Pattern] {
  [{ name: "private key block", re: "BEGIN [A-Z ]*PRIVATE KEY" }, { name: "openai/anthropic key", re: "sk-[A-Za-z0-9_-]{20,}" }, { name: "aws access key id", re: "AKIA[0-9A-Z]{16}" }, { name: "github token", re: "gh[pousr]_[A-Za-z0-9]{30,}" }, { name: "slack token", re: "xox[baprs]-[A-Za-z0-9-]{10,}" }]
}

fn joined(root :: Str, rel :: Str) -> Str
  examples {
    joined(".", "lex.toml") => "./lex.toml",
    joined("/srv/app", "lex.toml") => "/srv/app/lex.toml"
  }
{
  str.join([root, "/", rel], "")
}

fn nonempty_lines(text :: Str) -> List[Str]
  examples {
    nonempty_lines("a\nb\n") => ["a", "b"],
    nonempty_lines("  \n") => []
  }
{
  list.filter(str.split(text, "\n"), fn (l :: Str) -> Bool {
    not str.is_empty(str.trim(l))
  })
}

fn lines_containing(text :: Str, needle :: Str) -> List[Str]
  examples {
    lines_containing("a: 1\nb: 2\n", "b") => ["b: 2"]
  }
{
  list.filter(nonempty_lines(text), fn (l :: Str) -> Bool {
    str.contains(l, needle)
  })
}

# First semver-shaped token on a line. Used on both sides of the pin
# comparison so the two are read the same way.
fn first_version(line :: Str) -> Option[Str]
  examples {
    first_version("          LEX_VERSION=\"0.10.11\"") => Some("0.10.11"),
    first_version("no version here") => None
  }
{
  match regex.compile("[0-9]+\\.[0-9]+\\.[0-9]+") {
    Err(_) => None,
    Ok(re) => match regex.find(re, line) {
      None => None,
      Some(m) => Some(m.text),
    },
  }
}

fn git(root :: Str, args :: List[Str]) -> [proc] Result[Str, Str] {
  match proc.run("git", list.concat(["-C", root], args)) {
    Err(msg) => Err(msg),
    Ok(out) => if out.exit_code == 0 {
      Ok(out.stdout)
    } else {
      Err(str.join([out.stdout, out.stderr], ""))
    },
  }
}

# ── prod.no-secrets ─────────────────────────────────────────────────────
# `git log -G<re>` matches the added and removed lines of every commit
# in range, which is the "checked in the history, not just the current
# files" half of the book's item — a key deleted last week still shows.
fn secret_scan(root :: Str) -> [proc] Probe {
  let depth := history_depth()
  let reachable := commits_in_range(root, depth)
  let hits := list.fold(secret_patterns(), [], fn (acc :: List[Str], p :: Pattern) -> [proc] List[Str] {
    match git(root, ["log", str.concat("--max-count=", int.to_str(depth)), str.concat("-G", p.re), "--format=%h %s"]) {
      Err(_) => acc,
      Ok(out) => {
        let found := nonempty_lines(out)
        if list.is_empty(found) {
          acc
        } else {
          list.concat(acc, [str.join([p.name, ": ", int.to_str(list.len(found)), " commit(s) — ", str.join(found, "; ")], "")])
        }
      },
    }
  })
  let bound := str.join(["scanned ", reachable, " commit(s) — the last ", int.to_str(depth), " reachable from HEAD — for ", int.to_str(list.len(secret_patterns())), " credential patterns; a secret in an unrecognised format, or outside that range, is not covered. On a shallow clone (CI checkouts default to depth 1) that range is most of the history short of everything, which is why this number is reported rather than the depth asked for."], "")
  if list.is_empty(hits) {
    { id: pid.secret_scan(), verdict: Pass, detail: "no commit in range adds or removes a line matching a known credential pattern", bound: bound }
  } else {
    { id: pid.secret_scan(), verdict: Fail, detail: str.join(list.concat(["credential-shaped lines in history:"], hits), "\n  "), bound: bound }
  }
}

# How much history the scan could actually see. A shallow clone makes
# the requested depth a fiction, and a bound that overstates coverage is
# the one thing these probes must not do.
fn commits_in_range(root :: Str, depth :: Int) -> [proc] Str {
  match git(root, ["rev-list", "--count", str.concat("--max-count=", int.to_str(depth)), "HEAD"]) {
    Err(_) => "an unknown number of",
    Ok(out) => str.trim(out),
  }
}

# ── prod.remote-copy ────────────────────────────────────────────────────
fn git_remote(root :: Str) -> [proc] Probe {
  let bound := "a configured remote is not proof the remote is reachable, or that anything has been pushed to it recently"
  match git(root, ["remote", "-v"]) {
    Err(e) => { id: pid.git_remote(), verdict: Unknown, detail: str.concat("git remote failed: ", e), bound: bound },
    Ok(out) => {
      let remotes := nonempty_lines(out)
      if list.is_empty(remotes) {
        { id: pid.git_remote(), verdict: Fail, detail: "no git remote configured — the only copy of this work is this machine", bound: bound }
      } else {
        { id: pid.git_remote(), verdict: Pass, detail: str.join(["remote(s) configured: ", str.join(remotes, "; ")], ""), bound: bound }
      }
    },
  }
}

# ── prod.tests-exist ────────────────────────────────────────────────────
# Presence, not coverage. The book's item is about the paths that must
# not break, and no probe can tell which those are.
fn tests_present(root :: Str) -> [proc] Probe {
  let bound := "counts test files; says nothing about whether they cover signup, payment, or whatever this project's must-not-break path is"
  match proc.run("find", [joined(root, "tests"), "-name", "test_*.lex", "-type", "f"]) {
    Err(msg) => { id: pid.tests_present(), verdict: Unknown, detail: str.concat("find failed: ", msg), bound: bound },
    Ok(out) => {
      let files := nonempty_lines(out.stdout)
      let n := list.len(files)
      if n == 0 {
        { id: pid.tests_present(), verdict: Fail, detail: "no tests/test_*.lex files found", bound: bound }
      } else {
        { id: pid.tests_present(), verdict: Partial, detail: str.join([int.to_str(n), " test file(s): ", str.join(files, "; ")], ""), bound: bound }
      }
    },
  }
}

# ── prod.ci-on-pr ───────────────────────────────────────────────────────
# The item has two halves and the repository holds only one of them.
# Passing it whole on the strength of a workflow file would retire the
# branch-protection question silently, so the best verdict here is
# Partial by construction.
fn ci_on_pr(root :: Str) -> [io, proc] Probe {
  let bound := "the workflow file shows CI runs on pull requests; whether a red run BLOCKS the merge is branch protection, which lives in the forge and cannot be read from the repository"
  match proc.run("find", [joined(root, ".github/workflows"), "-name", "*.yml", "-type", "f"]) {
    Err(msg) => { id: pid.ci_on_pr(), verdict: Unknown, detail: str.concat("find failed: ", msg), bound: bound },
    Ok(out) => {
      let files := nonempty_lines(out.stdout)
      let on_pr := list.filter(files, fn (f :: Str) -> [io] Bool {
        match io.read(f) {
          Err(_) => false,
          Ok(content) => str.contains(content, "pull_request"),
        }
      })
      if list.is_empty(on_pr) {
        { id: pid.ci_on_pr(), verdict: Fail, detail: "no workflow triggers on pull_request", bound: bound }
      } else {
        { id: pid.ci_on_pr(), verdict: Partial, detail: str.join(["runs on pull_request: ", str.join(on_pr, "; "), " — branch protection still unverified"], ""), bound: bound }
      }
    },
  }
}

# ── prod.pins-honest ────────────────────────────────────────────────────
# The lex-* packages float on purpose while they move fast; only the
# lex-lang toolchain is pinned. So the rule worth enforcing is not "pin
# everything" but "the one pin that exists must agree everywhere it is
# written down" — lex.toml against the version CI installs.
fn toolchain_pin(root :: Str) -> [io, proc] Probe {
  let bound := "compares the toolchain pin in lex.toml against the version CI installs; the lex-* package dependencies are deliberately unpinned and are not checked"
  match io.read(joined(root, "lex.toml")) {
    Err(e) => { id: pid.toolchain_pin(), verdict: Unknown, detail: str.concat("cannot read lex.toml: ", e), bound: bound },
    Ok(manifest) => {
      let declared :: Result[LexToml, Str] := toml.parse(manifest)
      match declared {
        Err(e) => { id: pid.toolchain_pin(), verdict: Unknown, detail: str.concat("lex.toml has no [package] lex pin: ", e), bound: bound },
        Ok(parsed) => compare_pin(root, parsed.package.lex, bound),
      }
    },
  }
}

fn compare_pin(root :: Str, declared :: Str, bound :: Str) -> [io, proc] Probe {
  match ci_version(root) {
    None => { id: pid.toolchain_pin(), verdict: Unknown, detail: str.join(["lex.toml pins ", declared, "; no LEX_VERSION found in .github/workflows to compare it against"], ""), bound: bound },
    Some(installed) => if declared == installed {
      { id: pid.toolchain_pin(), verdict: Pass, detail: str.join(["lex.toml and CI agree on toolchain ", declared], ""), bound: bound }
    } else {
      { id: pid.toolchain_pin(), verdict: Fail, detail: str.join(["pin drift: lex.toml says ", declared, ", CI installs ", installed, " — the version this project is checked against is not the version it claims"], ""), bound: bound }
    },
  }
}

fn ci_version(root :: Str) -> [io, proc] Option[Str] {
  match proc.run("find", [joined(root, ".github/workflows"), "-name", "*.yml", "-type", "f"]) {
    Err(_) => None,
    Ok(out) => list.fold(nonempty_lines(out.stdout), None, fn (acc :: Option[Str], f :: Str) -> [io] Option[Str] {
      match acc {
        Some(v) => Some(v),
        None => match io.read(f) {
          Err(_) => None,
          Ok(content) => match list.head(lines_containing(content, "LEX_VERSION")) {
            None => None,
            Some(line) => first_version(line),
          },
        },
      }
    }),
  }
}

# ── ev.known-answer ─────────────────────────────────────────────────────
# An `examples {}` block IS the book's known-answer test: a case whose
# answer you already know, run every time the file is checked. The probe
# counts blocks against function definitions. It cannot tell which fns
# are pure — effectful fns cannot carry examples at all (#369) — so the
# ceiling here is Partial, never Pass.
fn examples_coverage(root :: Str, path :: Str) -> [proc] Probe {
  let bound := "grep-level counts over the target path; it cannot tell a pure fn (which should carry examples) from an effectful one (which cannot), so the ratio is a floor, not a coverage figure"
  let target := joined(root, path)
  let fns := count_matches(target, "^fn ")
  let egs := count_matches(target, "^  examples \\{")
  if egs == 0 {
    { id: pid.examples_coverage(), verdict: Fail, detail: str.join([int.to_str(fns), " fn(s) under ", target, " and not one examples {} block — nothing here is tested against an answer known in advance"], ""), bound: bound }
  } else {
    { id: pid.examples_coverage(), verdict: Partial, detail: str.join([int.to_str(egs), " examples {} block(s) across ", int.to_str(fns), " fn(s) under ", target], ""), bound: bound }
  }
}

fn count_matches(target :: Str, pattern :: Str) -> [proc] Int {
  match proc.run("grep", ["-r", "-E", "--include=*.lex", "-h", pattern, target]) {
    Err(_) => 0,
    Ok(out) => list.len(nonempty_lines(out.stdout)),
  }
}

fn render(p :: Probe) -> Str {
  str.join(["probe ", p.id, ": ", verdict_label(p.verdict), "\n  ", p.detail, "\n  bound: ", p.bound], "")
}

fn run_all(root :: Str, examples_path :: Str) -> [io, proc] List[Probe] {
  [secret_scan(root), git_remote(root), tests_present(root), ci_on_pr(root), toolchain_pin(root), examples_coverage(root, examples_path)]
}

# CI entry point. Prints the probe report and fails the build on any
# `fail`, which is how lex-code stays subject to the bar it walks other
# projects against. `partial` and `unknown` do not fail: they are the
# honest verdicts for items only a person can close, and a gate that
# treated them as errors would push the next author to weaken the probe
# rather than answer the question.
fn gate(root :: Str, examples_path :: Str) -> [io, proc] Unit {
  let probes := run_all(root, examples_path)
  let __printed := list.map(probes, fn (p :: Probe) -> [io] Unit {
    io.print(str.concat(render(p), "\n"))
  })
  let failed := list.filter(probes, fn (p :: Probe) -> Bool {
    verdict_label(p.verdict) == "fail"
  })
  if list.is_empty(failed) {
    ()
  } else {
    let __report := io.print(str.join(["\nminimum bar: ", int.to_str(list.len(failed)), " probe(s) failed\n"], ""))
    let __force_fail := 1 / 0
    ()
  }
}

