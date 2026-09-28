# lex-code — plan a whole package as a graph of typed issues
#
# A package is not one function. It is a project of typed issues with
# dependency edges: each unit is one cohesive function (plus its helpers)
# small enough for a model to close alone, each with its own signatures and
# examples, and the edges say what must exist first. This module is the
# pure half of `--package`: the prompt that asks an agent to draw the graph,
# and the checks that decide whether the graph it drew is fit to file.
#
# The agent writes the plan as JSON; a human reads it; only then does
# `--package-apply` file the issues. Filing is deterministic on purpose —
# an LLM should not be the thing that decides what "done" means unreviewed.
#
# Plan file shape:
#   { "project": "asn1",
#     "units": [
#       { "key": "len_to_hex", "title": "...", "body": "...",
#         "api": [ { "name": "len_to_hex", "signature": "(n :: Int) -> Str" } ],
#         "examples": [ "len_to_hex(5) => \"05\"" ],
#         "deps": [ "other_unit_key" ] } ] }

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

type Api = { name :: Str, signature :: Str }

type PlanUnit = { key :: Str, title :: Str, body :: Str, api :: List[Api], examples :: List[Str], deps :: List[Str] }

type Plan = { project :: Str, units :: List[PlanUnit] }

fn has(xs :: List[Str], s :: Str) -> Bool
  examples {
    has(["a", "b"], "b") => true,
    has(["a"], "z") => false,
    has([], "a") => false
  }
{
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or x == s
  })
}

fn all_in(needles :: List[Str], hay :: List[Str]) -> Bool
  examples {
    all_in([], ["a"]) => true,
    all_in(["a"], ["a", "b"]) => true,
    all_in(["a", "c"], ["a", "b"]) => false
  }
{
  list.fold(needles, true, fn (acc :: Bool, n :: Str) -> Bool {
    acc and has(hay, n)
  })
}

fn parse_api(j :: jv.Json) -> Api {
  { name: ic.field_text(j, "name"), signature: ic.field_text(j, "signature") }
}

fn parse_unit(j :: jv.Json) -> PlanUnit {
  { key: ic.field_text(j, "key"), title: ic.field_text(j, "title"), body: ic.field_text(j, "body"), api: list.map(ic.field_list(j, "api"), parse_api), examples: ic.texts(ic.field_list(j, "examples")), deps: ic.texts(ic.field_list(j, "deps")) }
}

fn parse_plan(text :: Str) -> Result[Plan, Str]
  examples {
    parse_plan("not json") => Err("the plan is not valid JSON"),
    parse_plan("{\"project\": \"p\", \"units\": []}") => Ok({ project: "p", units: [] })
  }
{
  match jv.parse(str.trim(text)) {
    Err(_) => Err("the plan is not valid JSON"),
    Ok(j) => Ok({ project: ic.field_text(j, "project"), units: list.map(ic.field_list(j, "units"), parse_unit) }),
  }
}

# A name that is safe to use as a project name and as a unit key: it ends up
# on a command line and in a file name, so no spaces, slashes or quotes.
fn valid_name(s :: Str) -> Bool
  examples {
    valid_name("asn1") => true,
    valid_name("len_to_hex") => true,
    valid_name("") => false,
    valid_name("two words") => false,
    valid_name("a/b") => false
  }
{
  if str.is_empty(s) {
    false
  } else {
    if str.contains(s, " ") {
      false
    } else {
      if str.contains(s, "/") {
        false
      } else {
        if str.contains(s, "\"") {
          false
        } else {
          true
        }
      }
    }
  }
}

# The function an example calls: everything before the first `(`.
fn callee(example :: Str) -> Str
  examples {
    callee("gcd(12, 8) => 4") => "gcd",
    callee("  f(1) => 2") => "f",
    callee("nothing") => "nothing"
  }
{
  match list.head(str.split(example, "(")) {
    None => "",
    Some(c) => str.trim(c),
  }
}

# A signature is `(params) -> Type`, with an optional `[effects]` row right
# after the arrow. Anything else cannot be compared against a declaration.
fn signature_shape_ok(sig :: Str) -> Bool
  examples {
    signature_shape_ok("(a :: Int) -> Int") => true,
    signature_shape_ok("() -> [net] Nil") => true,
    signature_shape_ok("Int") => false,
    signature_shape_ok("(a :: Int)") => false
  }
{
  str.starts_with(str.trim(sig), "(") and str.contains(sig, "->")
}

# An effectful signature (`-> [net] Nil`) cannot carry an `examples {}` case
# — examples run at check time, where no effect is granted.
fn is_effectful(sig :: Str) -> Bool
  examples {
    is_effectful("() -> [net] Nil") => true,
    is_effectful("(n :: Int) -> Int") => false,
    is_effectful("(xs :: List[Int]) -> List[Int]") => false
  }
{
  str.contains(sig, "-> [")
}

# The keys of the units that declare a function of this name.
fn declared_by(units :: List[PlanUnit], name :: Str) -> List[Str]
  examples {
    declared_by([{ key: "a", title: "A", body: "", api: [{ name: "f", signature: "() -> Int" }], examples: [], deps: [] }, { key: "b", title: "B", body: "", api: [{ name: "f", signature: "() -> Int" }], examples: [], deps: [] }], "f") => ["a", "b"],
    declared_by([], "f") => []
  }
{
  list.map(list.filter(units, fn (u :: PlanUnit) -> Bool {
    has(list.map(u.api, fn (a :: Api) -> Str {
      a.name
    }), name)
  }), fn (u :: PlanUnit) -> Str {
    u.key
  })
}

fn unit_keys(units :: List[PlanUnit]) -> List[Str] {
  list.map(units, fn (u :: PlanUnit) -> Str {
    u.key
  })
}

fn api_names(units :: List[PlanUnit]) -> List[Str] {
  list.fold(units, [], fn (acc :: List[Str], u :: PlanUnit) -> List[Str] {
    list.concat(acc, list.map(u.api, fn (a :: Api) -> Str {
      a.name
    }))
  })
}

fn duplicates(xs :: List[Str]) -> List[Str]
  examples {
    duplicates(["a", "b", "a"]) => ["a"],
    duplicates(["a", "b"]) => [],
    duplicates([]) => []
  }
{
  let seen_and_dups := list.fold(xs, ([], []), fn (acc :: (List[Str], List[Str]), x :: Str) -> (List[Str], List[Str]) {
    match acc {
      (seen, dups) => if has(seen, x) {
        if has(dups, x) {
          (seen, dups)
        } else {
          (seen, list.concat(dups, [x]))
        }
      } else {
        (list.concat(seen, [x]), dups)
      },
    }
  })
  match seen_and_dups {
    (_, dups) => dups,
  }
}

fn unit_errors(u :: PlanUnit, all_keys :: List[Str], all_api :: List[Str]) -> List[Str] {
  let who := str.join(["unit `", u.key, "`: "], "")
  let key_err := if valid_name(u.key) {
    []
  } else {
    [str.concat(who, "key must be non-empty with no spaces, slashes or quotes")]
  }
  let title_err := if str.is_empty(str.trim(u.title)) {
    [str.concat(who, "needs a title")]
  } else {
    []
  }
  let api_err := if list.is_empty(u.api) {
    [str.concat(who, "declares no api entry — a unit with no signature has nothing to verify")]
  } else {
    list.fold(u.api, [], fn (acc :: List[Str], a :: Api) -> List[Str] {
      if str.is_empty(a.name) {
        list.concat(acc, [str.concat(who, "an api entry has no name")])
      } else {
        if signature_shape_ok(a.signature) {
          acc
        } else {
          list.concat(acc, [str.join([who, "signature of `", a.name, "` must look like `(x :: T) -> U`, got `", a.signature, "`"], "")])
        }
      }
    })
  }
  let pure_api := list.filter(u.api, fn (a :: Api) -> Bool {
    not is_effectful(a.signature)
  })
  let example_err := if list.is_empty(u.examples) {
    if list.is_empty(pure_api) {
      []
    } else {
      [str.concat(who, "a pure function needs at least one example — that is the oracle")]
    }
  } else {
    list.fold(u.examples, [], fn (acc :: List[Str], e :: Str) -> List[Str] {
      if has(all_api, callee(e)) {
        acc
      } else {
        list.concat(acc, [str.join([who, "example `", e, "` calls `", callee(e), "`, which no unit declares"], "")])
      }
    })
  }
  let dep_err := list.fold(u.deps, [], fn (acc :: List[Str], d :: Str) -> List[Str] {
    if d == u.key {
      list.concat(acc, [str.concat(who, "depends on itself")])
    } else {
      if has(all_keys, d) {
        acc
      } else {
        list.concat(acc, [str.join([who, "depends on `", d, "`, which is not a unit"], "")])
      }
    }
  })
  list.concat(list.concat(list.concat(list.concat(key_err, title_err), api_err), example_err), dep_err)
}

# Dependency order: a unit comes after everything it depends on. Units that
# can be built at the same time land in the same layer; a layer that cannot
# be formed means a cycle.
fn topo(rest :: List[PlanUnit], placed :: List[Str], out :: List[PlanUnit]) -> Result[List[PlanUnit], Str] {
  if list.is_empty(rest) {
    Ok(out)
  } else {
    let ready := list.filter(rest, fn (u :: PlanUnit) -> Bool {
      all_in(u.deps, placed)
    })
    if list.is_empty(ready) {
      Err(str.concat("dependency cycle among: ", str.join(unit_keys(rest), ", ")))
    } else {
      let waiting := list.filter(rest, fn (u :: PlanUnit) -> Bool {
        not all_in(u.deps, placed)
      })
      topo(waiting, list.concat(placed, unit_keys(ready)), list.concat(out, ready))
    }
  }
}

fn ordered(plan :: Plan) -> Result[List[PlanUnit], Str] {
  topo(plan.units, [], [])
}

# Every problem at once, not the first: an agent repairing a plan fixes them
# in one pass instead of one round trip each.
fn validate(plan :: Plan) -> List[Str] {
  let keys := unit_keys(plan.units)
  let names := api_names(plan.units)
  let project_err := if valid_name(plan.project) {
    []
  } else {
    ["project must be non-empty with no spaces, slashes or quotes"]
  }
  let empty_err := if list.is_empty(plan.units) {
    ["the plan has no units"]
  } else {
    []
  }
  let dup_key_err := list.map(duplicates(keys), fn (k :: Str) -> Str {
    str.join(["two units share the key `", k, "`"], "")
  })
  let dup_api_err := list.map(duplicates(names), fn (n :: Str) -> Str {
    str.join(["`", n, "` is declared by more than one unit (", str.join(declared_by(plan.units, n), ", "), ") — declare it in exactly one"], "")
  })
  let per_unit := list.fold(plan.units, [], fn (acc :: List[Str], u :: PlanUnit) -> List[Str] {
    list.concat(acc, unit_errors(u, keys, names))
  })
  let base := list.concat(list.concat(list.concat(list.concat(project_err, empty_err), dup_key_err), dup_api_err), per_unit)
  if list.is_empty(base) {
    match ordered(plan) {
      Err(e) => [e],
      Ok(_) => [],
    }
  } else {
    base
  }
}

fn check_plan(text :: Str) -> Result[Plan, List[Str]]
  examples {
    check_plan("nope") => Err(["the plan is not valid JSON"]),
    check_plan("{\"project\": \"p\", \"units\": []}") => Err(["the plan has no units"])
  }
{
  match parse_plan(text) {
    Err(e) => Err([e]),
    Ok(plan) => {
      let errs := validate(plan)
      if list.is_empty(errs) {
        Ok(plan)
      } else {
        Err(errs)
      }
    },
  }
}

# The argv for `lex issue create` for one unit, its dependencies already
# filed (so their ids are known). Effectful api entries are declared without
# an example, as `lex issue create` allows.
fn create_argv(u :: PlanUnit, project :: Str, dep_ids :: List[Str]) -> List[Str]
  examples {
    create_argv({ key: "k", title: "T", body: "B", api: [{ name: "f", signature: "(n :: Int) -> Int" }], examples: ["f(1) => 1"], deps: [] }, "p", ["abc"]) => ["issue", "create", "--title", "T", "--shape", "typed_delta", "--project", "p", "--body", "B", "--api", "f:(n :: Int) -> Int", "--example", "f(1) => 1", "--dep", "abc"]
  }
{
  let head := ["issue", "create", "--title", u.title, "--shape", "typed_delta", "--project", project, "--body", u.body]
  let apis := list.fold(u.api, [], fn (acc :: List[Str], a :: Api) -> List[Str] {
    list.concat(acc, ["--api", str.join([a.name, ":", a.signature], "")])
  })
  let exs := list.fold(u.examples, [], fn (acc :: List[Str], e :: Str) -> List[Str] {
    list.concat(acc, ["--example", e])
  })
  let deps := list.fold(dep_ids, [], fn (acc :: List[Str], d :: Str) -> List[Str] {
    list.concat(acc, ["--dep", d])
  })
  list.concat(list.concat(list.concat(head, apis), exs), deps)
}

# The task that asks an agent to draw the graph. It carries what filing
# packages by hand taught: contracts written before code, small units, the
# edge cases pinned by examples (an example list is finite, so a model can
# satisfy it with a lookup table — the properties go in tests/, later), and
# an integration unit that exercises the composed public function.
fn plan_prompt(brief :: Str, project :: Str, path :: Str) -> Str {
  str.join(["Plan a Lex package as a graph of typed issues. Do NOT write the package itself.\n\nThe package: ", brief, "\n\nWrite ONE file, ", path, ", containing only JSON of this shape:\n\n  { \"project\": \"", project, "\",\n    \"units\": [\n      { \"key\": \"short_snake_name\", \"title\": \"one line\", \"body\": \"what it must do and the edge cases, in prose\",\n        \"api\": [ { \"name\": \"fn_name\", \"signature\": \"(x :: Int) -> Str\" } ],\n        \"examples\": [ \"fn_name(1) => \\\"one\\\"\" ],\n        \"deps\": [ \"key_of_a_unit_this_needs_first\" ] } ] }\n\nRules — each one exists because a package built without it went wrong:\n", "1. One unit = one function the size of a screen (helpers may share its unit). If you cannot state its contract in two sentences, split it.\n", "2. Signatures are the contract. Write them in Lex: `(a :: Int, b :: Str) -> Result[Int, Str]`; an effectful one puts its row after the arrow: `() -> [net] Nil`. Every function that any example calls must be declared as an api entry of some unit.\n", "3. deps are real: a unit lists the units whose functions it calls. Foundations first; no cycles.\n", "4. Give each pure function at least three examples, and make them pin the edges (empty, zero, boundary, the case the obvious implementation gets wrong). Examples run at check time, so an effectful function carries none.\n", "5. If the package composes its functions into ONE entry point, make that the last unit (deps = what it composes) with examples that run the whole thing end to end. If its public functions each stand alone, add no integration unit. Either way every function is declared by exactly ONE unit — never list a function in two units.\n", "6. Before drawing anything, look at what already exists: read lex.toml and use the find_packages tool — depend on an existing package instead of planning to rebuild it.\n\nWhen the file is written, reply with one line: the number of units. Do not implement anything."], "")
}

# One line per unit, in dependency order, for a human to review before
# anything is filed.
fn render_plan(plan :: Plan) -> Str {
  match ordered(plan) {
    Err(e) => e,
    Ok(units) => str.join(list.map(units, fn (u :: PlanUnit) -> Str {
      let needs := if list.is_empty(u.deps) {
        ""
      } else {
        str.join(["   <- ", str.join(u.deps, ", ")], "")
      }
      str.join(["  ", u.key, needs, "\n      ", u.title, "  [", str.join(list.map(u.api, fn (a :: Api) -> Str {
        a.name
      }), ", "), "]"], "")
    }), "\n"),
  }
}

