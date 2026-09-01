# lex-code — propagate an effect up the call graph until the project type-checks
#
# Adding an effect to a function means adding it to every caller, transitively.
# Doing that by hand is the failure mode #22 was filed about: the refactor
# agent walks `lex_audit --calls` hop by hop and misses callers.
#
# ---- why this is not built on `lex audit --calls` -------------------
#
# The issue proposed driving the walk from `lex audit --calls`. That cannot
# work. `qualified_callee` in the audit pass only records a callee written as
# `module.field`; a call to a top-level function in the *same file* is
# recorded as nothing at all. Measured on this repo:
#
#   lex audit --calls str.concat  src/tools/standard/write.lex  -> 54 hits
#   lex audit --calls readback_block src/tools/linter.lex       ->  0 hits
#
# `readback_block` is called by `run_for_lex` one screen below it. Effects
# propagate through local helpers constantly, so a walk that cannot see an
# intra-module edge is not a propagation tool — it is a propagation tool with
# a silent hole in it, which is worse than none.
#
# The type checker already knows the answer. `lex check` reports
# `effect_not_declared` with the offending effect and the line of the
# signature that needs widening, and it sees every edge because it is the
# thing that computes the rows in the first place. So the loop is:
#
#   1. widen the root function's row with the new effect
#   2. run `lex check`; for each `effect_not_declared`, widen that signature
#   3. repeat until the project is clean, nothing changed, or the budget runs out
#
# The checker is the fixed point. One error surfaces per round per file, so
# the round count is the depth of the call chain, not its width.
#
# ---- what it cannot reach ------------------------------------------
#
# Top-level signatures only. `lex check` reports `effect_not_declared` with
# `at_node: n_0` and `col: 1` — the position is normalised to the ENCLOSING
# declaration, not the node that needs the effect. So when the row that is
# actually too narrow belongs to a closure inside the function:
#
#     fn run_parallel(...) -> [..., crypto] MultiResult {          # line 21
#       let results := list.par_map(pairs, fn (p :: P) -> [...] R { # line 23
#
# the error points at line 21, whose row already declares the effect. Nothing
# a line rewriter can do with that. This was found running the tool over this
# repo: it widened 30 signatures across 6 files and then stopped on three
# closures, which is why the stall check exists and why it reports rather
# than looping. Fix those by hand — the message names the file and line, and
# the closure is a few lines below it.
#
# `lex repair --apply --transform` is likewise not usable here: it takes an
# `op_id` — a failed operation already recorded in lex-store — not a file and
# a line, and no `add_effect_to_sig` transform is reachable from a plain
# source tree.

import "std.process" as proc

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "PropagateEffectArgs", description: "Add an effect to a function and widen every caller until the project type-checks.", fields: [s.required_str("root_fn", []), s.required_str("new_effect", []), s.required_str("path", []), s.optional(s.required_bool("dry_run"))] }
}

fn dry_run_is_bool() -> Bool
  examples {
    dry_run_is_bool() => true
  }
{
  util.declares_bool(params(), "dry_run")
}

fn max_rounds() -> Int
  examples {
    max_rounds() => 40
  }
{
  40
}

# ---- signature rewriting -------------------------------------------
#
# All of this is pure and carries examples, because it is the part that can
# corrupt a source file. The checker tells us *which* line to widen; getting
# the widening itself wrong on a line it named is how a propagation tool
# turns one missing effect into a broken parse.
type Widen = { line :: Str, changed :: Bool }

# Index just past the `)` that closes the parameter list.
#
# Scans from the first `(` matching parens, so a closure-typed parameter —
# `fn f(cb :: (Int) -> [io] Unit) -> Unit` — does not end the list early.
fn param_end(line :: Str, i :: Int, depth :: Int) -> Int {
  if i >= str.len(line) {
    i
  } else {
    let c := str.char_at(line, i)
    if c == "(" {
      param_end(line, i + 1, depth + 1)
    } else {
      if c == ")" {
        if depth <= 1 {
          i + 1
        } else {
          param_end(line, i + 1, depth - 1)
        }
      } else {
        param_end(line, i + 1, depth)
      }
    }
  }
}

# The first `->` at or after `i`. This is the RETURN arrow only because the
# caller starts the scan past the parameter list — searching the whole line
# would find the arrow inside `(Int) -> Unit`, and searching from the end
# would find the inner arrow of a function-returning signature such as
# `fn make_handler(b :: Brains) -> (Message) -> [...] Outcome` (mcp_main.lex
# has exactly that shape).
fn find_arrow(line :: Str, i :: Int) -> Option[Int] {
  if i + 1 >= str.len(line) {
    None
  } else {
    if str.char_at(line, i) == "-" {
      if str.char_at(line, i + 1) == ">" {
        Some(i)
      } else {
        find_arrow(line, i + 1)
      }
    } else {
      find_arrow(line, i + 1)
    }
  }
}

fn skip_spaces(line :: Str, i :: Int) -> Int {
  if i >= str.len(line) {
    i
  } else {
    if str.char_at(line, i) == " " {
      skip_spaces(line, i + 1)
    } else {
      i
    }
  }
}

fn index_of_from(line :: Str, needle :: Str, i :: Int) -> Option[Int] {
  if i >= str.len(line) {
    None
  } else {
    if str.char_at(line, i) == needle {
      Some(i)
    } else {
      index_of_from(line, needle, i + 1)
    }
  }
}

# Is `effect` already named in a row body like "io, proc"?
#
# Compares whole entries, so `fs_read` is not read as already covering
# `fs_readdir` and `io` is not found inside `llm`.
fn row_has(row :: Str, effect :: Str) -> Bool
  examples {
    row_has("io, proc", "io") => true,
    row_has("io, proc", "proc") => true,
    row_has("io, proc", "net") => false,
    row_has("fs_read", "fs") => false,
    row_has("llm", "lm") => false,
    row_has("", "io") => false
  }
{
  list.fold(str.split(row, ","), false, fn (acc :: Bool, part :: Str) -> Bool {
    if acc {
      true
    } else {
      str.trim(part) == effect
    }
  })
}

# Widen one `fn` line's effect row with `effect`.
#
# Returns the line unchanged, with changed=false, for anything that is not a
# function signature or that already declares the effect — so a caller can
# treat "nothing to do" and "done" the same way and detect a stalled round.
fn widen_line(line :: Str, effect :: Str) -> Widen
  examples {
    widen_line("fn mid() -> Unit {", "io") => { line: "fn mid() -> [io] Unit {", changed: true },
    widen_line("fn top() -> [proc] Unit {", "io") => { line: "fn top() -> [proc, io] Unit {", changed: true },
    widen_line("fn leaf() -> [io] Unit {", "io") => { line: "fn leaf() -> [io] Unit {", changed: false },
    widen_line("fn f(a :: Str) -> Result[A, B] {", "net") => { line: "fn f(a :: Str) -> [net] Result[A, B] {", changed: true },
    widen_line("fn f(cb :: (Int) -> [io] Unit) -> Unit {", "net") => { line: "fn f(cb :: (Int) -> [io] Unit) -> [net] Unit {", changed: true },
    widen_line("fn h(b :: B) -> (M) -> [io] Out {", "net") => { line: "fn h(b :: B) -> [net] (M) -> [io] Out {", changed: true },
    widen_line("  let x := 1", "io") => { line: "  let x := 1", changed: false },
    widen_line("fn noarrow()", "io") => { line: "fn noarrow()", changed: false }
  }
{
  if str.starts_with(str.trim(line), "fn ") {
    let after_params := param_end(line, 0, 0)
    match find_arrow(line, after_params) {
      None => { line: line, changed: false },
      Some(a) => {
        let rest := skip_spaces(line, a + 2)
        if str.char_at(line, rest) == "[" {
          match index_of_from(line, "]", rest) {
            None => { line: line, changed: false },
            Some(close) => {
              let row := str.slice(line, rest + 1, close)
              if row_has(row, effect) {
                { line: line, changed: false }
              } else {
                { line: str.join([str.slice(line, 0, close), ", ", effect, str.slice(line, close, str.len(line))], ""), changed: true }
              }
            },
          }
        } else {
          { line: str.join([str.slice(line, 0, rest), "[", effect, "] ", str.slice(line, rest, str.len(line))], ""), changed: true }
        }
      },
    }
  } else {
    { line: line, changed: false }
  }
}

# Replace line `n` (1-based) of `content` with its widened form.
fn widen_at(content :: Str, n :: Int, effect :: Str) -> Widen
  examples {
    widen_at("a\nfn f() -> Unit {\nb", 2, "io") => { line: "a\nfn f() -> [io] Unit {\nb", changed: true },
    widen_at("fn f() -> [io] Unit {", 1, "io") => { line: "fn f() -> [io] Unit {", changed: false },
    widen_at("only", 9, "io") => { line: "only", changed: false }
  }
{
  let lines := str.split(content, "\n")
  let folded := list.fold(lines, (1, [], false), fn (acc :: (Int, List[Str], Bool), l :: Str) -> (Int, List[Str], Bool) {
    match acc {
      (i, out, hit) => if i == n {
        let w := widen_line(l, effect)
        (i + 1, list.concat(out, [w.line]), w.changed)
      } else {
        (i + 1, list.concat(out, [l]), hit)
      },
    }
  })
  match folded {
    (_, out, hit) => { line: str.join(out, "\n"), changed: hit },
  }
}

# ---- driving the checker --------------------------------------------
type Miss = { file :: Str, line :: Int, effect :: Str }

fn list_lex_files(path :: Str) -> [proc] List[Str] {
  match proc.run("bash", ["-c", str.join(["find ", path, " -name '*.lex' -type f | sort"], "")]) {
    Err(_) => [],
    Ok(out) => list.filter(str.split(str.trim(out.stdout), "\n"), fn (l :: Str) -> Bool {
      str.is_empty(str.trim(l)) == false
    }),
  }
}

# The `effect_not_declared` errors `lex check` reports for one file.
#
# `lex --output json check` wraps the result: the outer `ok` means the
# command ran, and the real verdict is `data.ok` with `data.errors`. Reading
# the outer field would report every failing file as clean.
fn check_file(path :: Str) -> [proc] List[Miss] {
  match proc.run("bash", ["-c", str.join(["\"${LEX:-lex}\" --output json check ", path], "")]) {
    Err(_) => [],
    Ok(out) => match jv.parse_into_errors(out.stdout) {
      Err(_) => [],
      Ok(j) => match jv.get_field(j, "data") {
        None => [],
        Some(d) => match jv.get_field(d, "errors") {
          Some(JList(errs)) => list.fold(errs, [], fn (acc :: List[Miss], ej :: jv.Json) -> List[Miss] {
            match miss_of(ej) {
              None => acc,
              Some(m) => list.concat(acc, [m]),
            }
          }),
          _ => [],
        },
      },
    },
  }
}

fn miss_of(ej :: jv.Json) -> Option[Miss] {
  match jv.get_field(ej, "kind") {
    Some(JStr("effect_not_declared")) => match jv.get_field(ej, "effect") {
      Some(JStr(eff)) => match jv.get_field(ej, "position") {
        None => None,
        Some(pos) => match jv.get_field(pos, "file") {
          Some(JStr(f)) => match jv.get_field(pos, "line") {
            Some(JInt(n)) => Some({ file: f, line: n, effect: eff }),
            _ => None,
          },
          _ => None,
        },
      },
      _ => None,
    },
    _ => None,
  }
}

fn check_all(files :: List[Str]) -> [proc] List[Miss] {
  list.fold(files, [], fn (acc :: List[Miss], f :: Str) -> [proc] List[Miss] {
    list.concat(acc, check_file(f))
  })
}

fn render_miss(m :: Miss) -> Str {
  str.join([m.file, ":", int.to_str(m.line), " += ", m.effect], "")
}

# Apply one widening. Returns whether the file actually changed, so a round
# that reports misses but changes nothing can stop rather than spin.
fn apply_miss(m :: Miss, write :: Bool) -> [io] Bool {
  match io.read(m.file) {
    Err(_) => false,
    Ok(content) => {
      let w := widen_at(content, m.line, m.effect)
      if w.changed {
        if write {
          match io.write(m.file, w.line) {
            Err(_) => false,
            Ok(_) => true,
          }
        } else {
          true
        }
      } else {
        false
      }
    },
  }
}

fn apply_all(misses :: List[Miss], write :: Bool) -> [io] Int {
  list.fold(misses, 0, fn (acc :: Int, m :: Miss) -> [io] Int {
    if apply_miss(m, write) {
      acc + 1
    } else {
      acc
    }
  })
}

# The fixed point: check, widen, repeat.
#
# Stops when the project is clean, when a round changes nothing (so the
# remaining misses are ones widen_line will not touch — a signature shape it
# does not recognise), or when the budget runs out. Each of the three is
# reported distinctly, because "clean" and "gave up" must not look alike to
# the agent reading the result.
#
# This runs only when writing. A dry run cannot enter it: the cascade is
# discovered by type-checking a tree that has the root widening applied, so
# with nothing written the checker sees the original tree, reports no
# missing effects, and the loop would announce DONE having simulated
# precisely nothing. Saying DONE for work not done is the failure this tool
# exists to avoid, so the dry-run path reports what it actually knows —
# which function it would seed — and says the rest is undetermined.
fn run_rounds(files :: List[Str], write :: Bool, budget :: Int, log :: List[Str]) -> [io, proc] List[Str] {
  if budget <= 0 {
    list.concat(log, [str.join(["STOPPED: budget of ", int.to_str(max_rounds()), " rounds exhausted; the project still does not type-check"], "")])
  } else {
    let misses := check_all(files)
    if list.is_empty(misses) {
      list.concat(log, ["DONE: no effect_not_declared errors remain"])
    } else {
      let applied := apply_all(misses, write)
      let entries := list.map(misses, render_miss)
      if applied == 0 {
        list.concat(list.concat(log, entries), ["STOPPED: a round reported misses but changed nothing. The lines above already declare the effect, which means it is a CLOSURE inside them that needs it — lex check reports the enclosing function's line, not the closure's. Widen those by hand; everything else is done."])
      } else {
        run_rounds(files, write, budget - 1, list.concat(log, entries))
      }
    }
  }
}

fn dry_run_note() -> List[Str] {
  ["DRY RUN: nothing was written, so the transitive set is undetermined — it is", "found by type-checking a tree that already has the root widening applied.", "Re-run without dry_run to apply it and see every caller that follows."]
}

# Widen the root function itself, wherever it is declared.
fn seed_root(files :: List[Str], root_fn :: Str, effect :: Str, write :: Bool) -> [io] List[Str] {
  list.fold(files, [], fn (acc :: List[Str], f :: Str) -> [io] List[Str] {
    match io.read(f) {
      Err(_) => acc,
      Ok(content) => {
        let n := line_of_fn(content, root_fn)
        if n == 0 {
          acc
        } else {
          let w := widen_at(content, n, effect)
          if w.changed {
            let wrote := if write {
              match io.write(f, w.line) {
                Err(_) => false,
                Ok(_) => true,
              }
            } else {
              true
            }
            if wrote {
              list.concat(acc, [str.join([f, ":", int.to_str(n), " += ", effect, " (root)"], "")])
            } else {
              acc
            }
          } else {
            list.concat(acc, [str.join([f, ":", int.to_str(n), " already declares ", effect, " (root)"], "")])
          }
        }
      },
    }
  })
}

# 1-based line of `fn <name>(`, or 0 when the file does not declare it.
fn line_of_fn(content :: Str, name :: Str) -> Int
  examples {
    line_of_fn("fn a() -> Unit {\nfn b() -> Unit {", "b") => 2,
    line_of_fn("fn a() -> Unit {", "a") => 1,
    line_of_fn("fn ab() -> Unit {", "a") => 0,
    line_of_fn("# fn a() -> Unit {", "a") => 0,
    line_of_fn("nothing", "a") => 0
  }
{
  let needle := str.concat("fn ", str.concat(name, "("))
  match list.fold(str.split(content, "\n"), (1, 0), fn (acc :: (Int, Int), l :: Str) -> (Int, Int) {
    match acc {
      (i, found) => if found > 0 {
        (i + 1, found)
      } else {
        if str.starts_with(l, needle) {
          (i + 1, i)
        } else {
          (i + 1, found)
        }
      },
    }
  }) {
    (_, found) => found,
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "root_fn") {
    None => Err(e.single("", "missing_field", "root_fn is required")),
    Some(root_fn) => match util.field_str(args, "new_effect") {
      None => Err(e.single("", "missing_field", "new_effect is required")),
      Some(effect) => match util.field_str(args, "path") {
        None => Err(e.single("", "missing_field", "path is required")),
        Some(path) => {
          let write := match util.field_bool(args, "dry_run") {
            Some(true) => false,
            _ => true,
          }
          let files := list_lex_files(path)
          if list.is_empty(files) {
            Err(e.single("", "no_files", str.concat("no .lex files under ", path)))
          } else {
            let seeded := seed_root(files, root_fn, effect, write)
            if list.is_empty(seeded) {
              Err(e.single("", "unknown_fn", str.join(["no file under ", path, " declares `fn ", root_fn, "(`"], "")))
            } else {
              let tail := if write {
                run_rounds(files, write, max_rounds(), [])
              } else {
                dry_run_note()
              }
              Ok(JStr(str.join(list.concat(seeded, tail), "\n")))
            }
          }
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("propagate_effect", "Add an effect to a function's row and widen every caller transitively until the project type-checks again. Driven by lex check rather than a call-graph walk, so intra-module callers are covered. Use dry_run=true to see the first round without writing.", params(), execute)
}

