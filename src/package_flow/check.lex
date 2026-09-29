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
#                          function's body just calls itself — well-typed for
#                          any signature — plus one checker function per
#                          example, and the real `lex check` judges it. That
#                          catches malformed signatures and examples whose
#                          arguments or expected value do not fit the
#                          signature, with the checker's own error and position.
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
  ["Int", "Float", "Str", "Bool", "Nil", "Unit", "Bytes", "List", "Map", "Set", "Option", "Result", "Iter", "Stream", "Request", "Response"]
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
# `(a :: Int, b :: Str) -> R` → ["a", "b"]
fn param_names(sig :: Str) -> List[Str]
  examples {
    param_names("(a :: Int, b :: Map[Str, Int]) -> Int") => ["a", "b"],
    param_names("() -> Int") => [],
    param_names("(x :: (Int, Str)) -> Int") => ["x"]
  }
{
  match str.strip_prefix(str.trim(sig), "(") {
    None => [],
    Some(rest) => match until_close(rest, ")") {
      None => [],
      Some(body) => list.map(list.filter(top_split(body), fn (p :: Str) -> Bool {
        not str.is_empty(p)
      }), fn (p :: Str) -> Str {
        match list.head(str.split(p, "::")) {
          Some(n) => str.trim(n),
          None => "",
        }
      }),
    },
  }
}

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
          list.concat(acc, [str.concat(who, "returns a Result, so its examples must show both an `Ok(...)` and an `Err(...)` outcome")])
        },
        None => match generic_args(ret, "Option") {
          Some(_) => if any_starts(expected, "Some(") and any_starts(expected, "None") {
            acc
          } else {
            list.concat(acc, [str.concat(who, "returns an Option, so its examples must show both a `Some(...)` and a `None` outcome")])
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
          list.concat(acc3, [str.join(["unit `", u.key, "`: `", a.name, "` mentions type `", t, "`, which is neither built in nor declared in the plan's `types`"], "")])
        }
      })
    })
  })
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
  list.concat(dups, shape)
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
  list.concat(list.concat(list.concat(dangling_errors(p), type_decl_errors(p)), policy_errors(p)), outcomes)
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

fn stub_fn(a :: plan.Api) -> Str
  examples {
    stub_fn({ name: "f", signature: "(x :: Int, y :: Str) -> Int" }) => "fn f(x :: Int, y :: Str) -> Int {\n  f(x, y)\n}\n\n",
    stub_fn({ name: "serve", signature: "() -> [net] Nil" }) => "fn serve() -> [net] Nil {\n  serve()\n}\n\n"
  }
{
  str.join(["fn ", a.name, a.signature, " {\n  ", a.name, "(", str.join(param_names(a.signature), ", "), ")\n}\n\n"], "")
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
  list.concat(list.concat(header, types), fns)
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
  let r := list.fold(stub_chunks(p), ("", 1, []), fn (acc :: (Str, Int, List[(Int, Str)]), c :: Chunk) -> (Str, Int, List[(Int, Str)]) {
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

