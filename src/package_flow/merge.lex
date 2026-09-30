# lex-code — merge one function's body from an isolated copy back into
# the canonical scaffold, for parallel issue execution (see parallel.lex).
#
# A parallel build runs each ready issue's Build session against its own
# temp copy of the whole project, so concurrent sessions never touch the
# same file at the same time — no locks, no lost-update races. Once a
# batch finishes, the driver splices each issue's now-implemented
# function(s) out of its copy and into the one canonical
# `src/<project>.lex`, one issue at a time, in-process, before the next
# batch starts. This module is that splice: find a `fn name(...) { ... }`
# block by name and swap it for another block of the same name.
#
# String-aware on purpose: a naive brace counter would miscount a body
# whose string literals happen to contain `{`/`}` (an error message like
# `"unexpected token: {"` is entirely plausible in exprkit-shaped code).
# Not a proof of correctness by itself — `lex check` on the merged file,
# which the caller always runs right after, is the real backstop; this
# is the part that keeps a normal merge from needing that backstop at
# all.

import "std.str" as str

import "std.list" as list

# The index of `f` in the first `"fn ", name, "("` that appears outside
# any string literal, or None. Requires the exact `name(` boundary so
# `fn_start(src, "parse")` doesn't match `fn parse_extra(...)`.
fn fn_start(source :: Str, name :: Str) -> Option[Int]
  examples {
    fn_start("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  2\n}\n", "b") => Some(23),
    fn_start("fn ab() -> Int { 1 }", "a") => None,
    fn_start("no such fn here", "a") => None
  }
{
  let needle := str.join(["fn ", name, "("], "")
  let n := str.len(needle)
  let r := list.fold(list.range(0, str.len(source)), (None, false, false), fn (acc :: (Option[Int], Bool, Bool), i :: Int) -> (Option[Int], Bool, Bool) {
    match acc {
      (Some(found), in_str, esc) => (Some(found), in_str, esc),
      (None, in_str, esc) => {
        let c := str.char_at(source, i)
        if esc {
          (None, in_str, false)
        } else {
          if in_str {
            if c == "\\" {
              (None, true, true)
            } else {
              (None, not (c == "\""), false)
            }
          } else {
            if c == "\"" {
              (None, true, false)
            } else {
              if i + n <= str.len(source) and str.slice(source, i, i + n) == needle {
                (Some(i), false, false)
              } else {
                (None, false, false)
              }
            }
          }
        }
      },
    }
  })
  match r {
    (found, _, _) => found,
  }
}

# From `from` (the start of `"fn name("`), the index of the next `{` at
# signature-depth zero — the first unescaped, not-in-a-string `{` seen
# once paren/bracket depth (from a signature's own `(...)`/`[...]`) has
# returned to zero. Handles a signature whose params carry an inline
# record type (`{ x :: Int }`), which itself opens and closes braces
# before the next real `{`. Doesn't know or care whether that `{` opens
# the body or an `examples { }` clause — `body_open` is the one that
# tells those apart.
fn next_top_brace(source :: Str, from :: Int) -> Option[Int]
  examples {
    next_top_brace("fn f(x :: Int) -> Int {\n  x\n}", 0) => Some(22),
    next_top_brace("fn f(r :: { x :: Int }) -> Int {\n  r.x\n}", 0) => Some(31)
  }
{
  let r := list.fold(list.range(from, str.len(source)), (None, 0, false, false), fn (acc :: (Option[Int], Int, Bool, Bool), i :: Int) -> (Option[Int], Int, Bool, Bool) {
    match acc {
      (Some(found), depth, in_str, esc) => (Some(found), depth, in_str, esc),
      (None, depth, in_str, esc) => {
        let c := str.char_at(source, i)
        if esc {
          (None, depth, in_str, false)
        } else {
          if in_str {
            if c == "\\" {
              (None, depth, true, true)
            } else {
              (None, depth, not (c == "\""), false)
            }
          } else {
            if c == "\"" {
              (None, depth, true, false)
            } else {
              if c == "(" or c == "[" {
                (None, depth + 1, false, false)
              } else {
                if c == ")" or c == "]" {
                  (None, depth - 1, false, false)
                } else {
                  if c == "{" and depth == 0 {
                    (Some(i), depth, false, false)
                  } else {
                    (None, depth, false, false)
                  }
                }
              }
            }
          }
        }
      },
    }
  })
  match r {
    (found, _, _, _) => found,
  }
}

# From `open` (the index of the body's opening `{`), the index of its
# matching `}` — string-aware brace counting only (parens/brackets
# inside the body don't affect it; they always self-balance before any
# `}` that would close the function, in well-formed Lex source).
fn body_close(source :: Str, open :: Int) -> Option[Int]
  examples {
    body_close("{\n  x\n}", 0) => Some(6),
    body_close("{ io.print(\"a { b } c\") }", 0) => Some(24),
    body_close("{ never closes", 0) => None
  }
{
  let r := list.fold(list.range(open, str.len(source)), (None, 0, false, false), fn (acc :: (Option[Int], Int, Bool, Bool), i :: Int) -> (Option[Int], Int, Bool, Bool) {
    match acc {
      (Some(found), depth, in_str, esc) => (Some(found), depth, in_str, esc),
      (None, depth, in_str, esc) => {
        let c := str.char_at(source, i)
        if esc {
          (None, depth, in_str, false)
        } else {
          if in_str {
            if c == "\\" {
              (None, depth, true, true)
            } else {
              (None, depth, not (c == "\""), false)
            }
          } else {
            if c == "\"" {
              (None, depth, true, false)
            } else {
              if c == "{" {
                (None, depth + 1, false, false)
              } else {
                if c == "}" {
                  if depth == 1 {
                    (Some(i), depth, false, false)
                  } else {
                    (None, depth - 1, false, false)
                  }
                } else {
                  (None, depth, false, false)
                }
              }
            }
          }
        }
      },
    }
  })
  match r {
    (found, _, _, _) => found,
  }
}

# From `from` (the start of `"fn name("`), the index of the BODY's own
# opening `{` — skipping straight over an `examples { ... }` clause if
# the signature has one (`fn f(...) -> T examples { ... } { body }` is
# the idiom this whole codebase writes, `lex agent-guidelines` rule 3).
# `next_top_brace` alone can't tell those two blocks apart; this is the
# function that reads the word right before a candidate brace to decide
# whether to skip past it and keep looking. Reproduced live: without
# this, a real `replace_fn_block` call truncated a published function
# down to just its `examples {}` clause, silently dropping the body —
# caught by `lex issue verify` failing on the merged canonical file
# (`Panic("todo() reached")`, since nothing had actually replaced the
# stub), not by inspection.
fn body_open(source :: Str, from :: Int) -> Option[Int]
  examples {
    body_open("fn f(x :: Int) -> Int {\n  x\n}", 0) => Some(22),
    body_open("fn f(r :: { x :: Int }) -> Int {\n  r.x\n}", 0) => Some(31),
    body_open("fn double(x :: Int) -> Int\n  examples {\n    double(3) => 6,\n    double(0) => 0\n  }\n{\n  x * 2\n}", 0) => Some(83)
  }
{
  match next_top_brace(source, from) {
    None => None,
    Some(brace) => if str.ends_with(str.trim(str.slice(source, from, brace)), "examples") {
      match body_close(source, brace) {
        None => None,
        Some(close) => body_open(source, close + 1),
      }
    } else {
      Some(brace)
    },
  }
}

# The full `fn name(...) -> T { ... }` text (signature and body,
# nothing else), or None if `name` isn't found or its body never closes.
fn fn_block(source :: Str, name :: Str) -> Option[Str]
  examples {
    fn_block("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  io.print(\"x { y\")\n  2\n}\n", "b") => Some("fn b() -> Int {\n  io.print(\"x { y\")\n  2\n}"),
    fn_block("fn a() -> Int { 1 }", "missing") => None,
    fn_block("fn a() -> Int\n  examples {\n    a() => 5\n  }\n{\n  5\n}\n", "a") => Some("fn a() -> Int\n  examples {\n    a() => 5\n  }\n{\n  5\n}")
  }
{
  match fn_start(source, name) {
    None => None,
    Some(start) => match body_open(source, start) {
      None => None,
      Some(open) => match body_close(source, open) {
        None => None,
        Some(close) => Some(str.slice(source, start, close + 1)),
      },
    },
  }
}

# `canonical` with its `fn name(...) { ... }` block replaced by
# `replacement`'s own block for the same name — everything else in
# `canonical` byte-for-byte unchanged. `Err` (not a silent no-op) if
# either side doesn't have a well-formed block for `name`, so a caller
# that skips checking the result can't merge nothing and call it done.
fn replace_fn_block(canonical :: Str, name :: Str, replacement :: Str) -> Result[Str, Str]
  examples {
    replace_fn_block("fn a() -> Int {\n  todo()\n}\n\nfn b() -> Int {\n  todo()\n}\n", "a", "fn a() -> Int {\n  1\n}") => Ok("fn a() -> Int {\n  1\n}\n\nfn b() -> Int {\n  todo()\n}\n"),
    replace_fn_block("fn only() -> Int {\n  todo()\n}\n", "missing", "fn missing() -> Int {\n  1\n}") => Err("no `fn missing` block in the canonical source"),
    replace_fn_block("fn a() -> Int {\n  todo()\n}\n\nfn b() -> Int {\n  todo()\n}\n", "a", "fn a() -> Int\n  examples {\n    a() => 5\n  }\n{\n  5\n}\n") => Ok("fn a() -> Int\n  examples {\n    a() => 5\n  }\n{\n  5\n}\n\nfn b() -> Int {\n  todo()\n}\n")
  }
{
  match fn_start(canonical, name) {
    None => Err(str.join(["no `fn ", name, "` block in the canonical source"], "")),
    Some(start) => match body_open(canonical, start) {
      None => Err(str.join(["`fn ", name, "`'s body never opens in the canonical source"], "")),
      Some(open) => match body_close(canonical, open) {
        None => Err(str.join(["`fn ", name, "`'s body never closes in the canonical source"], "")),
        Some(close) => match fn_block(replacement, name) {
          None => Err(str.join(["no well-formed `fn ", name, "` block in the replacement source"], "")),
          Some(new_block) => Ok(str.join([str.slice(canonical, 0, start), new_block, str.slice(canonical, close + 1, str.len(canonical))], "")),
        },
      },
    },
  }
}

# Reproduced live: a real `--parallel` run's `gcd` used a private
# recursive helper, `gcd_loop`, alongside the declared `gcd` itself —
# exactly what `scaffold_guidance` tells an issue it may do ("you may
# add private helper functions below them"). `merge_issue` only knew to
# splice in the issue's own DECLARED api names, so `gcd_loop` was
# silently dropped on every merge: the canonical file type-checked
# `gcd`'s call to it as `unknown_identifier` every single time, seven
# merge attempts running (over half of one real recording) before the
# model happened to stop using a helper at all. This is the other half
# of the fix: find every function the child's copy declares that the
# canonical file doesn't have yet, and carry those over too — as
# additions, since there's no existing block of that name to replace.
fn is_ident_start_char(c :: Str) -> Bool {
  str.len(c) == 1 and str.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", c)
}

fn is_ident_char(c :: Str) -> Bool {
  is_ident_start_char(c) or str.len(c) == 1 and str.contains("0123456789", c)
}

fn ident_end(source :: Str, i :: Int) -> Int {
  if i < str.len(source) and is_ident_char(str.char_at(source, i)) {
    ident_end(source, i + 1)
  } else {
    i
  }
}

# The name of a real function DECLARATION starting at `at` (the index
# of `"fn "`), or None — the one thing that tells `fn double(x...` (a
# declaration) apart from `fn (x...` (an anonymous closure literal,
# constantly passed to `list.map`/`list.fold` in this very codebase):
# a declaration has an identifier, not `(`, immediately after `fn `.
fn named_fn_at(source :: Str, at :: Int) -> Option[Str] {
  let after := at + 3
  if after < str.len(source) and is_ident_start_char(str.char_at(source, after)) {
    let end := ident_end(source, after)
    if end < str.len(source) and str.char_at(source, end) == "(" {
      Some(str.slice(source, after, end))
    } else {
      None
    }
  } else {
    None
  }
}

# Every top-level `fn name(...) -> T { ... }` this source declares, in
# order — never an anonymous closure. Resumes scanning from just past
# each one's own closing `}`, so a closure literal *inside* that body
# (there is always at least one, in real Lex code) is never mistaken
# for another top-level declaration.
fn all_fn_names(source :: Str) -> List[Str]
  examples {
    all_fn_names("fn a() -> Int {\n  1\n}\n\nfn b(x :: Int) -> Int {\n  list.map([1], fn (y :: Int) -> Int {\n    y\n  })\n  x\n}\n") => ["a", "b"],
    all_fn_names("no functions here") => []
  }
{
  scan_fn_names(source, 0)
}

fn scan_fn_names(source :: Str, from :: Int) -> List[Str] {
  match str.find(source, "fn ", from) {
    None => [],
    Some(at) => match named_fn_at(source, at) {
      None => scan_fn_names(source, at + 3),
      Some(name) => match body_open(source, at) {
        None => scan_fn_names(source, at + 3),
        Some(open) => match body_close(source, open) {
          None => scan_fn_names(source, at + 3),
          Some(close) => list.cons(name, scan_fn_names(source, close + 1)),
        },
      },
    },
  }
}

fn list_has(xs :: List[Str], s :: Str) -> Bool
  examples {
    list_has(["a", "b"], "b") => true,
    list_has(["a"], "z") => false,
    list_has([], "a") => false
  }
{
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or x == s
  })
}

# Every function `child` declares that `canonical` doesn't have yet —
# a private helper an issue's own copy added alongside its declared api
# function(s), which `replace_fn_block` alone would silently drop.
fn extra_fn_names(canonical :: Str, child :: Str, declared :: List[Str]) -> List[Str] {
  let canonical_names := all_fn_names(canonical)
  list.filter(all_fn_names(child), fn (name :: Str) -> Bool {
    not list_has(canonical_names, name) and not list_has(declared, name)
  })
}

# `canonical` with every function in `extra_fn_names` appended, each
# one's full block taken verbatim from `child`. Order among the
# appended functions matches their order in `child`; every one of them
# is new to `canonical`, so there is nothing to replace — only to add.
fn append_extra_fns(canonical :: Str, child :: Str, declared :: List[Str]) -> Str {
  list.fold(extra_fn_names(canonical, child, declared), canonical, fn (acc :: Str, name :: Str) -> Str {
    match fn_block(child, name) {
      None => acc,
      Some(block) => str.join([acc, "\n", block, "\n"], ""),
    }
  })
}

