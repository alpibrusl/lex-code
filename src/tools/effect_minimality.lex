# effect_minimality — flag a declared effect row wider than the body needs
#
# `lex check` (even --strict) only verifies a declared row is a SUPERSET of
# what a function's body actually uses — it never flags a superset that is
# too generous. `lex audit --json` (what effects_of.lex reads) reports the
# same declared row, not a computed minimal one. Neither tool answers "is
# this row minimal", which is the gap #119 exists to close — no general
# tool can do this for Lex's effect system except one built for it, which
# is exactly the kind of depth no general-purpose coding assistant has.
#
# Method: for each function with a non-empty declared row, try removing one
# declared effect at a time and re-checking a scratch copy of the file. If
# it still type-checks without that effect, the effect was unnecessary —
# proven, not guessed, since `lex check` itself is the judge.
#
# Signatures come from `grep` over the source directly (the pattern
# bar/checks.lex's own probes already use), not `lex audit --json`. An
# earlier version used the audit JSON, which walks the FULL dependency
# closure reachable from the target — auditing this repo's own ~50-file
# src/tools/ pulled in 18,194 hits (5.1 MB) from lex-llm/lex-schema/etc,
# almost all of them re-exported names from imported packages. Parsing
# that much JSON in a hand-rolled, interpreted Lex parser exhausted the
# VM's cumulative step budget for the whole run (not any one file — each
# file's own JSON was well under the limit on its own, but the budget is
# tracked for the process's whole lifetime, so many small parses added
# up). Grepping the file's own text sidesteps JSON entirely: only lines
# actually written in that file can match, so there is nothing to filter
# out, and nothing here parses more than one line at a time.
#
# The scan is still capped (see `cap`) — one `lex check` subprocess per
# (function, declared effect) pair adds up even without a JSON parser
# in the loop.

import "std.int" as int

import "std.io" as io

import "std.list" as list

import "std.process" as proc

import "std.str" as str

fn cap() -> Int {
  60
}

type Candidate = { file :: Str, name :: Str, signature :: Str, effect :: Str }

type Violation = { file :: Str, name :: Str, effect :: Str, remaining :: Str }

fn nonempty_lines(out :: Str) -> List[Str] {
  list.filter(str.split(out, "\n"), fn (l :: Str) -> Bool {
    not str.is_empty(l)
  })
}

fn take_candidates(xs :: List[Candidate], n :: Int) -> List[Candidate] {
  if n <= 0 {
    []
  } else {
    match list.head(xs) {
      None => [],
      Some(x) => list.cons(x, take_candidates(list.tail(xs), n - 1)),
    }
  }
}

fn files_under(target :: Str) -> [proc] List[Str] {
  match proc.run("find", [target, "-name", "*.lex"]) {
    Err(_) => [],
    Ok(out) => nonempty_lines(out.stdout),
  }
}

# `lex fmt` normalizes every declaration onto one line, so a signature
# with a declared effect row is always fully captured by one grep match.
fn signature_lines_of(file :: Str) -> [proc] List[Str] {
  match proc.run("grep", ["-E", "^fn [A-Za-z_][A-Za-z0-9_]*(\\[[A-Za-z_, ]+\\])? ?\\(.*\\) -> \\[", file]) {
    Err(_) => [],
    Ok(out) => nonempty_lines(out.stdout),
  }
}

fn extract_name(signature :: Str) -> Str {
  match str.find(signature, "fn ", 0) {
    None => "",
    Some(fn_idx) => {
      let after_fn := fn_idx + 3
      match str_find_stop(signature, after_fn) {
        None => str.slice(signature, after_fn, str.len(signature)),
        Some(stop) => str.slice(signature, after_fn, stop),
      }
    },
  }
}

# The first of "(" or "[" after `fn NAME` ends the name — "[" for a
# generic function's type-parameter list, "(" for a plain one.
fn str_find_first_of(signature :: Str, chars :: List[Str], from :: Int) -> Option[Int] {
  list.fold(chars, None, fn (acc :: Option[Int], c :: Str) -> Option[Int] {
    match str.find(signature, c, from) {
      None => acc,
      Some(idx) => match acc {
        None => Some(idx),
        Some(best) => if idx < best {
          Some(idx)
        } else {
          Some(best)
        },
      },
    }
  })
}

fn str_find_stop(signature :: Str, from :: Int) -> Option[Int] {
  str_find_first_of(signature, ["(", "["], from)
}

fn extract_effects(signature :: Str) -> List[Str] {
  match str.find(signature, "-> [", 0) {
    None => [],
    Some(arrow_idx) => {
      let bracket_start := arrow_idx + 4
      match str.find(signature, "]", bracket_start) {
        None => [],
        Some(bracket_end) => list.map(str.split(str.slice(signature, bracket_start, bracket_end), ","), fn (s :: Str) -> Str {
          str.trim(s)
        }),
      }
    },
  }
}

fn candidates_of_line(file :: Str, signature :: Str) -> List[Candidate] {
  let name := extract_name(signature)
  list.map(extract_effects(signature), fn (eff :: Str) -> Candidate {
    { file: file, name: name, signature: signature, effect: eff }
  })
}

fn candidates_of_file(file :: Str) -> [proc] List[Candidate] {
  list.reverse(list.fold(signature_lines_of(file), [], fn (acc :: List[Candidate], line :: Str) -> List[Candidate] {
    list.fold(candidates_of_line(file, line), acc, fn (acc2 :: List[Candidate], c :: Candidate) -> List[Candidate] {
      list.cons(c, acc2)
    })
  }))
}

fn candidates_from_files(files :: List[Str]) -> [proc] List[Candidate] {
  list.reverse(list.fold(files, [], fn (acc :: List[Candidate], f :: Str) -> [proc] List[Candidate] {
    list.fold(candidates_of_file(f), acc, fn (acc2 :: List[Candidate], c :: Candidate) -> List[Candidate] {
      list.cons(c, acc2)
    })
  }))
}

# One (function, declared effect) pair to probe — a function declaring
# [io, sql] yields two candidates, one per effect, so each is tested in
# isolation rather than trying every subset of the row.
fn candidates_of(target :: Str) -> [proc] List[Candidate] {
  take_candidates(candidates_from_files(files_under(target)), cap())
}

# The declared row always renders as `-> [a, b, c] Type` or, once fully
# pure, `-> Type` with no bracket at all — the case this returns None for.
fn narrow_signature(signature :: Str, drop :: Str) -> Option[Str] {
  match str.find(signature, "-> [", 0) {
    None => None,
    Some(arrow_idx) => narrow_at(signature, arrow_idx, drop),
  }
}

fn narrow_at(signature :: Str, arrow_idx :: Int, drop :: Str) -> Option[Str] {
  let bracket_start := arrow_idx + 4
  match str.find(signature, "]", bracket_start) {
    None => None,
    Some(bracket_end) => narrow_with_bracket(signature, arrow_idx, bracket_start, bracket_end, drop),
  }
}

fn narrow_with_bracket(signature :: Str, arrow_idx :: Int, bracket_start :: Int, bracket_end :: Int, drop :: Str) -> Option[Str] {
  let inner := str.slice(signature, bracket_start, bracket_end)
  let effects := list.map(str.split(inner, ","), fn (s :: Str) -> Str {
    str.trim(s)
  })
  let narrowed := list.filter(effects, fn (e :: Str) -> Bool {
    e != drop
  })
  if list.len(narrowed) == list.len(effects) {
    None
  } else {
    let before := str.slice(signature, 0, arrow_idx)
    let after := str.slice(signature, bracket_end + 1, str.len(signature))
    if list.is_empty(narrowed) {
      Some(str.concat(before, str.concat("->", after)))
    } else {
      Some(str.concat(before, str.concat("-> [", str.concat(str.join(narrowed, ", "), str.concat("]", after)))))
    }
  }
}

fn scratch_path(file :: Str) -> Str {
  str.concat(file, ".effect_minimality_probe_tmp.lex")
}

# A signature that fails to narrow (already pure, or the string surgery
# didn't find a bracket) or fails to appear verbatim in the file (should
# not happen — the signature is read straight from that file's own
# text — but checked rather than assumed) is skipped rather than
# reported as a false positive.
fn probe_one(c :: Candidate) -> [io, proc] Option[Violation] {
  match narrow_signature(c.signature, c.effect) {
    None => None,
    Some(narrowed) => probe_narrowed(c, narrowed),
  }
}

fn probe_narrowed(c :: Candidate, narrowed :: Str) -> [io, proc] Option[Violation] {
  match io.read(c.file) {
    Err(_) => None,
    Ok(content) => probe_content(c, narrowed, content),
  }
}

fn probe_content(c :: Candidate, narrowed :: Str, content :: Str) -> [io, proc] Option[Violation] {
  let modified := str.replace(content, c.signature, narrowed)
  if modified == content {
    None
  } else {
    let tmp := scratch_path(c.file)
    let __written := io.write(tmp, modified)
    let checked := proc.run("lex", ["check", tmp])
    let __cleanup := proc.run("rm", ["-f", tmp])
    still_typechecks(checked, c, narrowed)
  }
}

fn still_typechecks(checked :: Result[{ stdout :: Str, stderr :: Str, exit_code :: Int }, Str], c :: Candidate, narrowed :: Str) -> Option[Violation] {
  match checked {
    Ok(r) => if r.exit_code == 0 {
      Some({ file: c.file, name: c.name, effect: c.effect, remaining: narrowed })
    } else {
      None
    },
    Err(_) => None,
  }
}

fn probe_all(cs :: List[Candidate]) -> [io, proc] List[Violation] {
  list.reverse(list.fold(cs, [], fn (acc :: List[Violation], c :: Candidate) -> [io, proc] List[Violation] {
    match probe_one(c) {
      None => acc,
      Some(v) => list.cons(v, acc),
    }
  }))
}

fn scan(target :: Str) -> [io, proc] List[Violation] {
  probe_all(candidates_of(target))
}

fn render(v :: Violation) -> Str {
  str.join([v.file, ": ", v.name, " declares [", v.effect, "] but still type-checks without it — narrowed signature: ", v.remaining], "")
}

fn report(target :: Str) -> [io, proc] Str {
  let checked := candidates_of(target)
  let violations := probe_all(checked)
  let bound := str.join(["checked ", int.to_str(list.len(checked)), " (function, declared-effect) pair(s), capped at ", int.to_str(cap()), " — a full-repo sweep is slower than a CI step should be; this is a sample, not a guarantee the rest of the tree is clean"], "")
  if list.is_empty(violations) {
    str.join(["effect_minimality: no over-declared effect found\n  bound: ", bound], "")
  } else {
    str.join(["effect_minimality: ", int.to_str(list.len(violations)), " over-declared effect(s) found\n", str.join(list.map(violations, render), "\n"), "\n  bound: ", bound], "")
  }
}

