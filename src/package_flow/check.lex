# lex-code — check a package plan by validation, not by prose
#
# `plan.lex` checks a plan's structure. This module checks that its contracts
# are CONSISTENT with each other, so a bad contract is rejected before anything
# is filed and before any model spends a token on it:
#
#   layer 2 (pure, here)   dangling types; Result/Option functions whose
#                          examples cover only one outcome; a project policy
#                          (e.g. one error type everywhere) applied to every unit
#   layer 1 (stub compile) the plan is turned into a module in which every
#                          function's body is `todo()` (lex-lang#1080) —
#                          well-typed for any signature — plus one checker
#                          function per example, and the real `lex check`
#                          judges it. That catches malformed signatures and
#                          examples whose arguments or expected value do not
#                          fit the signature, with the checker's own error
#                          and position.
#
# `stub_program` is also the scaffold: the same text, published, is the
# starting point of every task — signatures already in place, an agent only
# replaces bodies.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "./plan" as plan

# ---- text scanning ----------------------------------------------------
fn is_ident_char(c :: Str) -> Bool {
  str.len(c) == 1 and str.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.", c)
}

fn starts_upper(t :: Str) -> Bool {
  str.len(t) > 0 and str.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", str.char_at(t, 0))
}

# Identifier-like tokens; a dot stays inside a token, so `jv.Json` is one.
fn identifiers(s :: Str) -> List[Str]
  examples {
    identifiers("(x :: List[Token]) -> Result[Int, Str]") => ["x", "List", "Token", "Result", "Int", "Str"],
    identifiers("(j :: jv.Json) -> Int") => ["j", "jv.Json", "Int"],
    identifiers("") => []
  }
{
  let spaced := list.fold(list.range(0, str.len(s)), "", fn (acc :: Str, i :: Int) -> Str {
    let c := str.char_at(s, i)
    if is_ident_char(c) {
      str.concat(acc, c)
    } else {
      str.concat(acc, " ")
    }
  })
  list.filter(str.split(spaced, " "), fn (t :: Str) -> Bool {
    not str.is_empty(t)
  })
}

fn uniq(xs :: List[Str]) -> List[Str]
  examples {
    uniq(["a", "b", "a"]) => ["a", "b"],
    uniq([]) => []
  }
{
  list.fold(xs, [], fn (acc :: List[Str], x :: Str) -> List[Str] {
    if plan.has(acc, x) {
      acc
    } else {
      list.concat(acc, [x])
    }
  })
}

# Capitalized, unqualified names in a signature — the type names it uses.
fn type_names_in(sig :: Str) -> List[Str]
  examples {
    type_names_in("(x :: List[Token], y :: Int) -> Result[Token, Str]") => ["List", "Token", "Int", "Result", "Str"],
    type_names_in("(j :: jv.Json) -> Bool") => ["Bool"]
  }
{
  uniq(list.filter(identifiers(sig), fn (t :: Str) -> Bool {
    starts_upper(t) and not str.contains(t, ".")
  }))
}

fn builtin_types() -> List[Str] {
  ["SqlParam", "Int", "Float", "Str", "Bool", "Nil", "Unit", "Bytes", "List", "Map", "Set", "Option", "Result", "Iter", "Stream", "Request", "Response"]
}

# The text between an already-consumed opener and its matching `close`,
# counting nesting of all bracket kinds. None if it never closes.
fn until_close(rest :: Str, close :: Str) -> Option[Str]
  examples {
    until_close("a, List[Int]) -> Int", ")") => Some("a, List[Int]"),
    until_close("Int, Str] tail", "]") => Some("Int, Str"),
    until_close("never closes", ")") => None
  }
{
  let r := list.fold(list.range(0, str.len(rest)), ("", 0, false), fn (acc :: (Str, Int, Bool), i :: Int) -> (Str, Int, Bool) {
    match acc {
      (buf, depth, done) => if done {
        acc
      } else {
        let c := str.char_at(rest, i)
        if c == close and depth == 0 {
          (buf, depth, true)
        } else {
          if c == "(" or c == "[" or c == "{" {
            (str.concat(buf, c), depth + 1, false)
          } else {
            if c == ")" or c == "]" or c == "}" {
              (str.concat(buf, c), depth - 1, false)
            } else {
              (str.concat(buf, c), depth, false)
            }
          }
        }
      },
    }
  })
  match r {
    (buf, _, done) => if done {
      Some(buf)
    } else {
      None
    },
  }
}

# Split on commas that are not inside any bracket.
fn top_split(s :: Str) -> List[Str]
  examples {
    top_split("a :: Int, b :: Map[Str, Int]") => ["a :: Int", "b :: Map[Str, Int]"],
    top_split("") => [""],
    top_split("Int, (Str, Str)") => ["Int", "(Str, Str)"]
  }
{
  let r := list.fold(list.range(0, str.len(s)), ([], "", 0), fn (acc :: (List[Str], Str, Int), i :: Int) -> (List[Str], Str, Int) {
    match acc {
      (parts, cur, depth) => {
        let c := str.char_at(s, i)
        if c == "(" or c == "[" or c == "{" {
          (parts, str.concat(cur, c), depth + 1)
        } else {
          if c == ")" or c == "]" or c == "}" {
            (parts, str.concat(cur, c), depth - 1)
          } else {
            if c == "," and depth == 0 {
              (list.concat(parts, [str.trim(cur)]), "", depth)
            } else {
              (parts, str.concat(cur, c), depth)
            }
          }
        }
      },
    }
  })
  match r {
    (parts, cur, _) => list.concat(parts, [str.trim(cur)]),
  }
}

# ---- signature pieces -------------------------------------------------
# Everything after the first `->`.
fn return_type(sig :: Str) -> Str
  examples {
    return_type("(a :: Int) -> Result[Int, Str]") => "Result[Int, Str]",
    return_type("() -> [net] Nil") => "[net] Nil",
    return_type("no arrow") => ""
  }
{
  match list.tail(str.split(sig, "->")) {
    rest => str.trim(str.join(rest, "->")),
  }
}

# The arguments of `Head[...]` when `t` starts with it.
fn generic_args(t :: Str, head :: Str) -> Option[List[Str]]
  examples {
    generic_args("Result[Int, Str]", "Result") => Some(["Int", "Str"]),
    generic_args("Option[List[Int]]", "Option") => Some(["List[Int]"]),
    generic_args("Int", "Result") => None
  }
{
  match str.strip_prefix(str.trim(t), str.concat(head, "[")) {
    None => None,
    Some(rest) => match until_close(rest, "]") {
      None => None,
      Some(body) => Some(top_split(body)),
    },
  }
}

# ---- examples ---------------------------------------------------------
fn example_call(e :: Str) -> Str
  examples {
    example_call("gcd(12, 8) => 4") => "gcd(12, 8)",
    example_call("f(\"a\") => Ok(\"b\")") => "f(\"a\")"
  }
{
  match list.head(str.split(e, " => ")) {
    Some(c) => str.trim(c),
    None => "",
  }
}

fn example_expected(e :: Str) -> Str
  examples {
    example_expected("gcd(12, 8) => 4") => "4",
    example_expected("f(1) => Err(\"x\")") => "Err(\"x\")",
    example_expected("no arrow") => ""
  }
{
  str.trim(str.join(list.tail(str.split(e, " => ")), " => "))
}

# ---- layer 2: consistency rules ---------------------------------------
fn any_starts(xs :: List[Str], prefix :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or str.starts_with(x, prefix)
  })
}

# A function returning Result must show both outcomes in its examples, an
# Option both Some and None — otherwise the contract pins one branch only.
fn outcome_errors(u :: plan.PlanUnit) -> List[Str] {
  list.fold(u.api, [], fn (acc :: List[Str], a :: plan.Api) -> List[Str] {
    let ret := return_type(a.signature)
    let expected := list.map(list.filter(u.examples, fn (e :: Str) -> Bool {
      plan.callee(e) == a.name
    }), example_expected)
    let who := str.join(["unit `", u.key, "`: `", a.name, "` "], "")
    if plan.is_effectful(a.signature) or list.is_empty(expected) {
      acc
    } else {
      match generic_args(ret, "Result") {
        Some(_) => if any_starts(expected, "Ok(") and any_starts(expected, "Err(") {
          acc
        } else {
          list.concat(acc, [str.concat(who, "returns a Result, so its examples must show both an `Ok(...)` and an `Err(...)` outcome — the expected value after `=>` must itself start with `Ok(` or `Err(`: write the whole value, e.g. `f(good) => Ok(value)`. Projecting a field or calling a helper on the result (`f(x).field`, `.ok_or(..)`) does not count")])
        },
        None => match generic_args(ret, "Option") {
          Some(_) => if any_starts(expected, "Some(") and any_starts(expected, "None") {
            acc
          } else {
            list.concat(acc, [str.concat(who, "returns an Option, so its examples must show both a `Some(...)` and a `None` outcome — the expected value after `=>` must itself be `Some(...)` or `None`: write the whole value, not a projection of it")])
          },
          None => acc,
        },
      }
    }
  })
}

fn dangling_errors(p :: plan.Plan) -> List[Str] {
  let known := list.concat(builtin_types(), list.map(p.types, fn (t :: plan.TypeDecl) -> Str {
    t.name
  }))
  list.fold(p.units, [], fn (acc :: List[Str], u :: plan.PlanUnit) -> List[Str] {
    list.fold(u.api, acc, fn (acc2 :: List[Str], a :: plan.Api) -> List[Str] {
      list.fold(type_names_in(a.signature), acc2, fn (acc3 :: List[Str], t :: Str) -> List[Str] {
        if plan.has(known, t) {
          acc3
        } else {
          list.concat(acc3, [str.join(["unit `", u.key, "`: `", a.name, "` mentions type `", t, "`, which is neither built in nor declared in the plan's `types` — if a dependency package owns it, write it qualified by a module alias (`conn.ConnDb`, `ctx.Ctx`), otherwise declare it in `types`"], "")])
        }
      })
    })
  })
}

# `type Invoice = Invoice { id :: Int }` is not Lex: a record type is written
# `type Invoice = { id :: Int }`; a constructor takes parentheses.
fn record_ctor_misuse(name :: Str, decl :: Str) -> Bool
  examples {
    record_ctor_misuse("Inv", "type Inv = Inv { id :: Int }") => true,
    record_ctor_misuse("Inv", "type Inv = { id :: Int }") => false,
    record_ctor_misuse("Inv", "type Inv = Inv(Int) | Nope") => false
  }
{
  match str.strip_prefix(str.trim(decl), str.concat("type ", name)) {
    None => false,
    Some(rest) => match str.strip_prefix(str.trim(rest), "=") {
      None => false,
      Some(body) => match str.strip_prefix(str.trim(body), name) {
        None => false,
        Some(after) => str.starts_with(str.trim(after), "{"),
      },
    },
  }
}

fn type_decl_errors(p :: plan.Plan) -> List[Str] {
  let dups := list.map(plan.duplicates(list.map(p.types, fn (t :: plan.TypeDecl) -> Str {
    t.name
  })), fn (n :: Str) -> Str {
    str.join(["type `", n, "` is declared twice"], "")
  })
  let shape := list.fold(p.types, [], fn (acc :: List[Str], t :: plan.TypeDecl) -> List[Str] {
    if str.starts_with(str.trim(t.decl), str.concat("type ", t.name)) {
      acc
    } else {
      list.concat(acc, [str.join(["type `", t.name, "`: decl must start with `type ", t.name, "`"], "")])
    }
  })
  let misuse := list.fold(p.types, [], fn (acc :: List[Str], t :: plan.TypeDecl) -> List[Str] {
    if record_ctor_misuse(t.name, t.decl) {
      list.concat(acc, [str.join(["type `", t.name, "`: a record type is written `type ", t.name, " = { field :: Int, ... }` — without the constructor name before the brace"], "")])
    } else {
      acc
    }
  })
  list.concat(list.concat(dups, shape), misuse)
}

fn policy_errors(p :: plan.Plan) -> List[Str] {
  if str.is_empty(p.policy.error_type) {
    []
  } else {
    list.fold(p.units, [], fn (acc :: List[Str], u :: plan.PlanUnit) -> List[Str] {
      list.fold(u.api, acc, fn (acc2 :: List[Str], a :: plan.Api) -> List[Str] {
        match generic_args(return_type(a.signature), "Result") {
          None => acc2,
          Some(args) => match list.head(list.tail(args)) {
            None => acc2,
            Some(err) => if err == p.policy.error_type {
              acc2
            } else {
              list.concat(acc2, [str.join(["unit `", u.key, "`: `", a.name, "` returns Result[_, ", err, "], but the project policy says every error type is `", p.policy.error_type, "`"], "")])
            },
          },
        }
      })
    })
  }
}

fn layer2_errors(p :: plan.Plan) -> List[Str] {
  let outcomes := list.fold(p.units, [], fn (acc :: List[Str], u :: plan.PlanUnit) -> List[Str] {
    list.concat(acc, outcome_errors(u))
  })
  list.concat(list.concat(list.concat(list.concat(dangling_errors(p), type_decl_errors(p)), policy_errors(p)), outcomes), invariant_errors(p))
}

# Everything that can be decided without running the checker.
fn static_errors(p :: plan.Plan) -> List[Str] {
  let base := plan.validate(p)
  if list.is_empty(base) {
    layer2_errors(p)
  } else {
    base
  }
}

fn check_text(text :: Str) -> Result[plan.Plan, List[Str]]
  examples {
    check_text("nope") => Err(["the plan is not valid JSON"])
  }
{
  match plan.parse_plan(text) {
    Err(e) => Err([e]),
    Ok(p) => {
      let errs := static_errors(p)
      if list.is_empty(errs) {
        Ok(p)
      } else {
        Err(errs)
      }
    },
  }
}

# ---- layer 1: the stub module ------------------------------------------
type Chunk = { label :: Str, text :: Str }

type StubProgram = { source :: Str, labels :: List[(Int, Str)] }

# A stub body of `todo()` (lex-lang#1080) rather than a self-recursive
# call: both compile and both do nothing if never reached, but a build
# task that leaves this one alone gets an immediate, legible
# "todo() reached" panic the moment hardening or another issue's
# examples exercise it — not a step-limit timeout that looks like a
# hang. `todo()` type-checks as `Never`, so it unifies against any
# signature with no per-signature reconstruction needed.
fn stub_fn(a :: plan.Api) -> Str
  examples {
    stub_fn({ name: "f", signature: "(x :: Int, y :: Str) -> Int" }) => "fn f(x :: Int, y :: Str) -> Int {\n  todo()\n}\n\n",
    stub_fn({ name: "serve", signature: "() -> [net] Nil" }) => "fn serve() -> [net] Nil {\n  todo()\n}\n\n"
  }
{
  str.join(["fn ", a.name, a.signature, " {\n  todo()\n}\n\n"], "")
}

fn example_fn(n :: Int, e :: Str) -> Str
  examples {
    example_fn(3, "f(1) => 2") => "fn __example_3() -> Bool {\n  (f(1)) == (2)\n}\n\n"
  }
{
  str.join(["fn __example_", int.to_str(n), "() -> Bool {\n  (", example_call(e), ") == (", example_expected(e), ")\n}\n\n"], "")
}

# Header, shared types and every function with its final signature — the
# module every task starts from.
fn scaffold_chunks(p :: plan.Plan) -> List[Chunk] {
  let header := [{ label: "imports", text: "import \"std.str\" as str\n\nimport \"std.list\" as list\n\nimport \"std.int\" as int\n\n" }]
  let types := list.map(p.types, fn (t :: plan.TypeDecl) -> Chunk {
    { label: str.concat("type ", t.name), text: str.concat(t.decl, "\n\n") }
  })
  let fns := list.fold(p.units, [], fn (acc :: List[Chunk], u :: plan.PlanUnit) -> List[Chunk] {
    list.concat(acc, list.map(u.api, fn (a :: plan.Api) -> Chunk {
      { label: str.join(["unit `", u.key, "` signature of `", a.name, "`"], ""), text: stub_fn(a) }
    }))
  })
  list.concat(list.concat(list.concat(header, types), fns), invariant_chunks(p))
}

fn example_chunks(p :: plan.Plan) -> List[Chunk] {
  let numbered := list.fold(p.units, ([], 0), fn (acc :: (List[Chunk], Int), u :: plan.PlanUnit) -> (List[Chunk], Int) {
    match acc {
      (chunks, n) => {
        let mine := list.map(list.enumerate(u.examples), fn (pair :: (Int, Str)) -> Chunk {
          match pair {
            (i, e) => { label: str.join(["unit `", u.key, "` example `", e, "`"], ""), text: example_fn(n + i, e) },
          }
        })
        (list.concat(chunks, mine), n + list.len(u.examples))
      },
    }
  })
  match numbered {
    (cs, _) => cs,
  }
}

fn stub_chunks(p :: plan.Plan) -> List[Chunk] {
  list.concat(scaffold_chunks(p), example_chunks(p))
}

# The scaffold as a file: no example checkers, nothing that is not final.
fn scaffold_source(p :: plan.Plan) -> Str {
  str.join(list.map(scaffold_chunks(p), fn (c :: Chunk) -> Str {
    c.text
  }), "")
}

# lex.toml with the plan's packages added under [dependencies]. A package
# already listed is left alone, so applying twice changes nothing.
fn toml_with_packages(toml :: Str, pkgs :: List[plan.Pkg]) -> Str
  examples {
    toml_with_packages("[package]\nname = \"x\"\n\n[dependencies]\n# note\n", [{ name: "lex-web", git: "https://g/lex-web" }]) => "[package]\nname = \"x\"\n\n[dependencies]\nlex-web = { git = \"https://g/lex-web\" }\n# note\n",
    toml_with_packages("[dependencies]\nlex-web = { git = \"u\" }\n", [{ name: "lex-web", git: "u" }]) => "[dependencies]\nlex-web = { git = \"u\" }\n",
    toml_with_packages("[package]\n", []) => "[package]\n"
  }
{
  let lines := str.split(toml, "\n")
  let missing := list.filter(pkgs, fn (k :: plan.Pkg) -> Bool {
    not list.fold(lines, false, fn (acc :: Bool, l :: Str) -> Bool {
      acc or str.starts_with(str.trim(l), str.concat(k.name, " "))
    })
  })
  if list.is_empty(missing) {
    toml
  } else {
    let added := list.map(missing, fn (k :: plan.Pkg) -> Str {
      str.join([k.name, " = { git = \"", k.git, "\" }"], "")
    })
    str.join(list.fold(lines, [], fn (acc :: List[Str], l :: Str) -> List[Str] {
      if str.trim(l) == "[dependencies]" {
        list.concat(list.concat(acc, [l]), added)
      } else {
        list.concat(acc, [l])
      }
    }), "\n")
  }
}

# The whole stub module and, for each chunk, the line it starts on — so a
# checker error at a line can be told back as "unit X, example Y".
fn stub_program(p :: plan.Plan) -> StubProgram {
  program_of(stub_chunks(p))
}

fn program_of(chunks :: List[Chunk]) -> StubProgram {
  let r := list.fold(chunks, ("", 1, []), fn (acc :: (Str, Int, List[(Int, Str)]), c :: Chunk) -> (Str, Int, List[(Int, Str)]) {
    match acc {
      (src, line, labels) => (str.concat(src, c.text), line + list.len(str.split(c.text, "\n")) - 1, list.concat(labels, [(line, c.label)])),
    }
  })
  match r {
    (src, _, labels) => { source: src, labels: labels },
  }
}

# Which chunk a checker error at `line` belongs to.
fn label_at(labels :: List[(Int, Str)], line :: Int) -> Str
  examples {
    label_at([(1, "imports"), (5, "unit a"), (9, "unit b")], 6) => "unit a",
    label_at([(1, "imports"), (5, "unit a")], 1) => "imports",
    label_at([], 3) => "the plan"
  }
{
  list.fold(labels, "the plan", fn (acc :: Str, p :: (Int, Str)) -> Str {
    match p {
      (start, label) => if start <= line {
        label
      } else {
        acc
      },
    }
  })
}

# The 1-based line that holds byte offset `n` of `source`.
fn line_of_byte(source :: Str, n :: Int) -> Int
  examples {
    line_of_byte("ab\ncd\n", 0) => 1,
    line_of_byte("ab\ncd\n", 3) => 2,
    line_of_byte("ab\ncd\nef", 6) => 3,
    line_of_byte("aaaa\nbbbbbb\nc\nd", 7) => 2
  }
{
  let r := list.fold(str.split(source, "\n"), (0, 1, false), fn (acc :: (Int, Int, Bool), l :: Str) -> (Int, Int, Bool) {
    match acc {
      (start, line, done) => if done {
        acc
      } else {
        if start + str.len(l) < n {
          (start + str.len(l) + 1, line + 1, false)
        } else {
          (start, line, true)
        }
      },
    }
  })
  match r {
    (_, line, _) => line,
  }
}

# The byte offset a parse error reports ("parse error at byte 1337: ...").
fn parse_error_byte(msg :: Str) -> Option[Int]
  examples {
    parse_error_byte("error: parse x.lex: parse error at byte 1337: expected expression") => Some(1337),
    parse_error_byte("type error") => None
  }
{
  match list.head(list.tail(str.split(msg, "at byte "))) {
    None => None,
    Some(rest) => match list.head(str.split(rest, ":")) {
      None => None,
      Some(d) => str.to_int(str.trim(d)),
    },
  }
}

# The 1-based `n`th line of `source` ("" past the end).
fn nth_line(source :: Str, n :: Int) -> Str
  examples {
    nth_line("a\nb\nc", 2) => "b",
    nth_line("a", 5) => ""
  }
{
  let r := list.fold(str.split(source, "\n"), (1, ""), fn (acc :: (Int, Str), l :: Str) -> (Int, Str) {
    match acc {
      (i, found) => if i == n {
        (i + 1, l)
      } else {
        (i + 1, found)
      },
    }
  })
  match r {
    (_, found) => found,
  }
}

# A parse error told in the plan's terms: which unit's text it is in.
fn describe_parse_error(prog :: StubProgram, msg :: Str) -> Str {
  match parse_error_byte(msg) {
    None => str.concat("lex check failed: ", msg),
    Some(n) => {
      let line := line_of_byte(prog.source, n)
      str.join([label_at(prog.labels, line), ": the stub does not parse at `", str.trim(nth_line(prog.source, line)), "`"], "")
    },
  }
}

# Which chunk (0-based, in stub order) holds `line`.
fn chunk_index_at(labels :: List[(Int, Str)], line :: Int) -> Int
  examples {
    chunk_index_at([(1, "imports"), (5, "unit a"), (9, "unit b")], 6) => 1,
    chunk_index_at([(1, "imports"), (5, "unit a")], 1) => 0,
    chunk_index_at([], 3) => 0
  }
{
  let n := list.fold(labels, 0, fn (acc :: Int, p :: (Int, Str)) -> Int {
    match p {
      (start, _) => if start <= line {
        acc + 1
      } else {
        acc
      },
    }
  })
  if n > 0 {
    n - 1
  } else {
    0
  }
}

fn remove_chunk(chunks :: List[Chunk], i :: Int) -> List[Chunk] {
  list.map(list.filter(list.enumerate(chunks), fn (p :: (Int, Chunk)) -> Bool {
    match p {
      (k, _) => k != i,
    }
  }), fn (p :: (Int, Chunk)) -> Chunk {
    match p {
      (_, c) => c,
    }
  })
}

# ---- corpora for hardening -----------------------------------------------
#
# Fixed and deterministic, so a run is reproducible: the same edge cases every
# time, not a fresh random sample that might miss the case it missed last run.
# Includes exactly the shape that a hyphen-collapsing bug needs to show up
# (a run of separators inside a word) — this is the corpus that would have
# caught it, not just examples the model happened to think of.
fn str_corpus_literal() -> Str {
  "[\"\", \" \", \"a\", \"Hello, World!\", \"--a--\", \"  spaced   out  \", \"ALL CAPS\", \"x_y-z\", \"9 lives\", \"!!!\", \"a b\", \"one two three\", \"Cafe 100%!\", \"hello_world 2.0\"]"
}

fn int_corpus_literal() -> Str {
  "[0, 1, -1, 2, 3, 5, 10, 100, -100, 1000]"
}

fn corpus_literal_for(ty :: Str) -> Str
  examples {
    corpus_literal_for("Str") => str_corpus_literal(),
    corpus_literal_for("Int") => int_corpus_literal(),
    corpus_literal_for("Bool") => "[true, false]"
  }
{
  if ty == "Str" {
    str_corpus_literal()
  } else {
    if ty == "Int" {
      int_corpus_literal()
    } else {
      "[true, false]"
    }
  }
}

# ---- invariants: real functions, validated the same way a signature is ----
fn invariant_signature(name :: Str, params :: List[plan.Param]) -> Str {
  str.join(["(", str.join(list.map(params, fn (p :: plan.Param) -> Str {
    str.join([p.name, " :: ", p.ty], "")
  }), ", "), ") -> Bool"], "")
}

fn invariant_fn_name(unit_key :: Str, inv_name :: Str) -> Str {
  str.join(["inv_", unit_key, "_", inv_name], "")
}

# The invariant as a real (non-stub) function: it is fully specified by the
# plan, so it does not wait to be filled in — only the functions it calls do.
fn render_invariant(unit_key :: Str, inv :: plan.Invariant) -> Str {
  str.join(["fn ", invariant_fn_name(unit_key, inv.name), invariant_signature("", inv.params), " {\n  ", inv.expr, "\n}\n\n"], "")
}

# For layer 1 (stub compile): the same function, so a malformed expression or
# a wrong param type is rejected by the real type checker before anything is
# filed — exactly the treatment a signature gets.
fn render_invariant_check(unit_key :: Str, inv :: plan.Invariant) -> Chunk {
  { label: str.join(["unit `", unit_key, "` invariant `", inv.name, "`"], ""), text: render_invariant(unit_key, inv) }
}

fn invariant_chunks(p :: plan.Plan) -> List[Chunk] {
  list.fold(p.units, [], fn (acc :: List[Chunk], u :: plan.PlanUnit) -> List[Chunk] {
    list.concat(acc, list.map(u.invariants, fn (i :: plan.Invariant) -> Chunk {
      render_invariant_check(u.key, i)
    }))
  })
}

fn invariant_errors(p :: plan.Plan) -> List[Str] {
  list.fold(p.units, [], fn (acc :: List[Str], u :: plan.PlanUnit) -> List[Str] {
    let names := list.map(u.invariants, fn (i :: plan.Invariant) -> Str {
      i.name
    })
    let dups := list.map(plan.duplicates(names), fn (n :: Str) -> Str {
      str.join(["unit `", u.key, "`: invariant `", n, "` is declared twice"], "")
    })
    let shape := list.fold(u.invariants, [], fn (acc2 :: List[Str], i :: plan.Invariant) -> List[Str] {
      if list.is_empty(i.params) or str.is_empty(str.trim(i.expr)) {
        list.concat(acc2, [str.join(["unit `", u.key, "`: invariant `", i.name, "` needs at least one param and a non-empty expr"], "")])
      } else {
        list.fold(i.params, acc2, fn (acc3 :: List[Str], param :: plan.Param) -> List[Str] {
          if param.ty == "Str" or param.ty == "Int" or param.ty == "Bool" {
            acc3
          } else {
            list.concat(acc3, [str.join(["unit `", u.key, "`: invariant `", i.name, "` param `", param.name, "` has type `", param.ty, "` — only Str, Int and Bool have a corpus"], "")])
          }
        })
      }
    })
    let wildcard := list.fold(u.invariants, [], fn (acc2 :: List[Str], i :: plan.Invariant) -> List[Str] {
      if str.contains(i.expr, "(_)") {
        list.concat(acc2, [str.join(["unit `", u.key, "`: invariant `", i.name, "` uses a `_` pattern like `Err(_)` in an expression — that only works inside `match`: write `match f(x) { Err(_) => true, Ok(_) => false }`"], "")])
      } else {
        acc2
      }
    })
    let implication := list.fold(u.invariants, [], fn (acc2 :: List[Str], i :: plan.Invariant) -> List[Str] {
      if str.contains(i.expr, " => ") and not str.contains(i.expr, "match ") {
        list.concat(acc2, [str.join(["unit `", u.key, "`: invariant `", i.name, "` uses `=>` — an invariant is a plain Bool expression with no implication; write \"if A then B\" as `not (A) or (B)`"], "")])
      } else {
        acc2
      }
    })
    list.concat(acc, list.concat(list.concat(dups, shape), list.concat(wildcard, implication)))
  })
}

# ---- the hardening harness, generated, never written by a model ----------
#
# One check per invariant, over the cross product of its params' corpora
# (capped, so two Str params — 14 x 14 — stay fast). Each records the calls
# where the invariant came back false, as literal Lex source for that exact
# call — text a `failing_example` issue can use as its example verbatim.
fn max_combos() -> Int {
  200
}

fn render_arg(ty :: Str, v :: Str) -> Str
  examples {
    render_arg("Str", "a b") => "\"a b\"",
    render_arg("Int", "3") => "3"
  }
{
  if ty == "Str" {
    str.concat("\"", str.concat(v, "\""))
  } else {
    v
  }
}

# `str_corpus_literal`'s entries, unquoted, for building call text. Kept in
# lockstep with it deliberately rather than derived, so both stay literal and
# reviewable.
fn str_corpus_values() -> List[Str] {
  ["", " ", "a", "Hello, World!", "--a--", "  spaced   out  ", "ALL CAPS", "x_y-z", "9 lives", "!!!", "a b", "one two three", "Cafe 100%!", "hello_world 2.0"]
}

fn int_corpus_values() -> List[Str] {
  ["0", "1", "-1", "2", "3", "5", "10", "100", "-100", "1000"]
}

fn corpus_values_for(ty :: Str) -> List[Str] {
  if ty == "Str" {
    str_corpus_values()
  } else {
    if ty == "Int" {
      int_corpus_values()
    } else {
      ["true", "false"]
    }
  }
}

# Every combination of values across `params`, as literal-argument lists,
# capped at `max_combos`.
fn combos(params :: List[plan.Param]) -> List[List[Str]] {
  let per := list.map(params, fn (p :: plan.Param) -> List[Str] {
    corpus_values_for(p.ty)
  })
  let raw := list.fold(per, [[]], fn (acc :: List[List[Str]], vals :: List[Str]) -> List[List[Str]] {
    list.fold(acc, [], fn (acc2 :: List[List[Str]], prefix :: List[Str]) -> List[List[Str]] {
      list.concat(acc2, list.map(vals, fn (v :: Str) -> List[Str] {
        list.concat(prefix, [v])
      }))
    })
  })
  list.fold(list.enumerate(raw), [], fn (acc :: List[List[Str]], pair :: (Int, List[Str])) -> List[List[Str]] {
    match pair {
      (i, combo) => if i < max_combos() {
        list.concat(acc, [combo])
      } else {
        acc
      },
    }
  })
}

# Pair each value with its param's type and render it as a literal.
fn render_args(params :: List[plan.Param], values :: List[Str]) -> List[Str] {
  match list.head(params) {
    None => [],
    Some(p) => match list.head(values) {
      None => [],
      Some(v) => list.cons(render_arg(p.ty, v), render_args(list.tail(params), list.tail(values))),
    },
  }
}

fn call_text(fn_name :: Str, params :: List[plan.Param], values :: List[Str]) -> Str {
  str.join([fn_name, "(", str.join(render_args(params, values), ", "), ")"], "")
}

# For one invariant: a checker function returning the calls (as literal
# source) where it came back false — plain generated code, not a fold, so the
# generated file reads like something a person would write by hand.
# A flat `[r0, r1, ...]` list literal plus a fold, not a chain of nested
# `list.concat` calls: at 200 combos a chained expression exceeds Lex's parser
# nesting limit (max 96) — found by actually running this against a corpus
# that size, not by inspection.
fn invariant_check_fn(u :: plan.PlanUnit, i :: plan.Invariant) -> Str {
  let fname := invariant_fn_name(u.key, i.name)
  let qualified := str.concat("t.", fname)
  let checker := str.concat("__check_", fname)
  let cs := combos(i.params)
  let bindings := list.map(list.enumerate(cs), fn (pair :: (Int, List[Str])) -> Str {
    match pair {
      (n, values) => {
        let call := call_text(qualified, i.params, values)
        let readable := call_text(fname, i.params, values)
        let quoted := str.concat("\"", str.concat(str.replace(str.replace(readable, "\\", "\\\\"), "\"", "\\\""), "\""))
        str.join(["  let r", int.to_str(n), " := if ", call, " { [] } else { [", quoted, "] }\n"], "")
      },
    }
  })
  let names := list.map(list.range(0, list.len(cs)), fn (n :: Int) -> Str {
    str.concat("r", int.to_str(n))
  })
  str.join(["fn ", checker, "() -> [io] List[Str] {\n", str.join(bindings, ""), "  flatten([", str.join(names, ", "), "])\n}\n\n"], "")
}

fn invariant_check_fn_name(u :: plan.PlanUnit, i :: plan.Invariant) -> Str {
  str.concat("__check_", invariant_fn_name(u.key, i.name))
}

# Every invariant checker over every unit, plus a run_all()/failing_calls()
# pair matching `lex test`'s convention (`run_all() -> Int`, non-zero = a
# failing count) and giving the driver the literal calls that came back
# false, ready to become failing_example issues.
fn harden_source(p :: plan.Plan) -> Str {
  let all_invs := list.fold(p.units, [], fn (acc :: List[(plan.PlanUnit, plan.Invariant)], u :: plan.PlanUnit) -> List[(plan.PlanUnit, plan.Invariant)] {
    list.concat(acc, list.map(u.invariants, fn (i :: plan.Invariant) -> (plan.PlanUnit, plan.Invariant) {
      (u, i)
    }))
  })
  let checker_fns := str.join(list.map(all_invs, fn (p2 :: (plan.PlanUnit, plan.Invariant)) -> Str {
    match p2 {
      (u, i) => invariant_check_fn(u, i),
    }
  }), "")
  let checker_names := list.map(all_invs, fn (p2 :: (plan.PlanUnit, plan.Invariant)) -> Str {
    match p2 {
      (u, i) => invariant_check_fn_name(u, i),
    }
  })
  let calls := str.join(list.map(checker_names, fn (n :: Str) -> Str {
    str.concat(n, "()")
  }), ", ")
  let flatten_fn := "fn flatten(xss :: List[List[Str]]) -> List[Str] {\n  list.fold(xss, [], fn (acc :: List[Str], x :: List[Str]) -> List[Str] {\n    list.concat(acc, x)\n  })\n}\n\n"
  str.join(["import \"../src/", p.project, "\" as t\n\n", "import \"std.str\" as str\n\n", "import \"std.list\" as list\n\n", flatten_fn, checker_fns, "fn failing_calls() -> [io] List[Str] {\n  flatten([", calls, "])\n}\n\n", "fn run_all() -> [io] Int {\n  list.len(failing_calls())\n}\n"], "")
}

