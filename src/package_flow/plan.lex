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

import "std.regex" as regex

import "std.int" as int

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

type Api = { name :: Str, signature :: Str }

type Param = { name :: Str, ty :: Str }

# A property of the unit's own functions, checked over many inputs instead of
# a few hand-picked examples — what would have caught a bug like slugify
# doubling a hyphen, which every hand-picked example missed. `expr` is a Lex
# boolean expression using `params`' names and calling the unit's functions;
# it becomes a real function (`inv_<unit>_<name>`), so it is validated exactly
# like a signature — by compiling it — and, once dependencies are built,
# evaluated for real over a fixed corpus. No model writes or runs it.
type Invariant = { name :: Str, params :: List[Param], expr :: Str }

type PlanUnit = { key :: Str, title :: Str, body :: Str, api :: List[Api], examples :: List[Str], invariants :: List[Invariant], deps :: List[Str] }

# A type every unit shares, declared once: `decl` is the whole Lex declaration.
type TypeDecl = { name :: Str, decl :: Str }

# A package the project depends on — goes into lex.toml, written by the tool.
type Pkg = { name :: Str, git :: Str }

# Rules stated once for the whole project and enforced on every unit.
# error_type: when non-empty, every `Result[T, E]` a unit returns must have E equal to it.
type Policy = { error_type :: Str }

type Plan = { project :: Str, types :: List[TypeDecl], packages :: List[Pkg], policy :: Policy, units :: List[PlanUnit] }

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

fn parse_param(j :: jv.Json) -> Param {
  { name: ic.field_text(j, "name"), ty: ic.field_text(j, "type") }
}

fn parse_invariant(j :: jv.Json) -> Invariant {
  { name: ic.field_text(j, "name"), params: list.map(ic.field_list(j, "params"), parse_param), expr: ic.field_text(j, "expr") }
}

fn parse_unit(j :: jv.Json) -> PlanUnit {
  { key: ic.field_text(j, "key"), title: ic.field_text(j, "title"), body: ic.field_text(j, "body"), api: list.map(ic.field_list(j, "api"), parse_api), examples: ic.texts(ic.field_list(j, "examples")), invariants: list.map(ic.field_list(j, "invariants"), parse_invariant), deps: ic.texts(ic.field_list(j, "deps")) }
}

fn parse_type(j :: jv.Json) -> TypeDecl {
  { name: ic.field_text(j, "name"), decl: ic.field_text(j, "decl") }
}

fn parse_pkg(j :: jv.Json) -> Pkg {
  { name: ic.field_text(j, "name"), git: ic.field_text(j, "git") }
}

fn parse_policy(j :: jv.Json) -> Policy {
  match jv.get_field(j, "policy") {
    None => { error_type: "" },
    Some(p) => { error_type: ic.field_text(p, "error_type") },
  }
}

fn empty_plan(project :: Str) -> Plan {
  { project: project, types: [], packages: [], policy: { error_type: "" }, units: [] }
}

fn parse_plan(text :: Str) -> Result[Plan, Str]
  examples {
    parse_plan("not json") => Err("the plan is not valid JSON"),
    parse_plan("{\"project\": \"p\", \"units\": []}") => Ok(empty_plan("p")),
    parse_plan("{\"project\": \"p\", \"policy\": {\"error_type\": \"Str\"}, \"packages\": [{\"name\": \"lex-web\", \"git\": \"https://x\"}], \"types\": [{\"name\": \"T\", \"decl\": \"type T = Int\"}], \"units\": []}") => Ok({ project: "p", types: [{ name: "T", decl: "type T = Int" }], packages: [{ name: "lex-web", git: "https://x" }], policy: { error_type: "Str" }, units: [] })
  }
{
  match jv.parse(str.trim(text)) {
    Err(_) => Err("the plan is not valid JSON"),
    Ok(j) => Ok({ project: ic.field_text(j, "project"), types: list.map(ic.field_list(j, "types"), parse_type), packages: list.map(ic.field_list(j, "packages"), parse_pkg), policy: parse_policy(j), units: list.map(ic.field_list(j, "units"), parse_unit) }),
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
    valid_name("a/b") => false,
    valid_name("a\"b") => false
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

# Two slips a planner makes from habit in other languages. Both used to
# surface as an unrelated error (a "pure function needs an example" on every
# effectful unit, because `-> T [sql]` does not read as effectful), so each is
# named here, before any other check runs.
fn effect_names() -> List[Str] {
  ["net", "sql", "io", "proc", "env", "fs_read", "fs_write", "fs_walk", "time", "random", "crypto", "llm", "approval", "stream", "concurrent", "mcp", "log"]
}

fn is_effect_row(inner :: Str) -> Bool
  examples {
    is_effect_row("sql") => true,
    is_effect_row("net, sql") => true,
    is_effect_row("Int") => false,
    is_effect_row("") => false
  }
{
  not str.is_empty(str.trim(inner)) and list.fold(str.split(inner, ","), true, fn (ok :: Bool, e :: Str) -> Bool {
    ok and has(effect_names(), str.trim(e))
  })
}

fn signature_syntax_problem(sig :: Str) -> Option[Str]
  examples {
    signature_syntax_problem("(x :: Int) -> Int") => None,
    signature_syntax_problem("() -> [net, sql] Nil") => None,
    signature_syntax_problem("(x :: Map<Str, Int>) -> Int") => Some("write generics with square brackets: `(x :: Map[Str, Int]) -> Int`"),
    signature_syntax_problem("(d :: Db) -> Nil [sql]") => Some("the effect row goes right after the arrow, before the return type: `-> [sql] ...`, not at the end")
  }
{
  if str.contains(str.replace(sig, "->", ""), "<") {
    let fixed := str.replace(str.replace(str.replace(str.replace(sig, "->", "@@"), "<", "["), ">", "]"), "@@", "->")
    Some(str.join(["write generics with square brackets: `", fixed, "`"], ""))
  } else {
    let parts := str.split(str.trim(sig), " [")
    match list.head(list.reverse(parts)) {
      None => None,
      Some(last) => if list.len(parts) > 1 and str.ends_with(last, "]") and is_effect_row(str.slice(last, 0, str.len(last) - 1)) {
        Some(str.join(["the effect row goes right after the arrow, before the return type: `-> [", str.slice(last, 0, str.len(last) - 1), "] ...`, not at the end"], ""))
      } else {
        None
      },
    }
  }
}

fn syntax_errors(units :: List[PlanUnit]) -> List[Str] {
  list.fold(units, [], fn (acc :: List[Str], u :: PlanUnit) -> List[Str] {
    list.fold(u.api, acc, fn (acc2 :: List[Str], a :: Api) -> List[Str] {
      match signature_syntax_problem(a.signature) {
        None => acc2,
        Some(msg) => list.concat(acc2, [str.join(["unit `", u.key, "`: `", a.name, "` signature `", a.signature, "` — ", msg], "")]),
      }
    })
  })
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
    declared_by([{ key: "a", title: "A", body: "", api: [{ name: "f", signature: "() -> Int" }], examples: [], invariants: [], deps: [] }, { key: "b", title: "B", body: "", api: [{ name: "f", signature: "() -> Int" }], examples: [], invariants: [], deps: [] }], "f") => ["a", "b"],
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

# Units of more than a few functions are the one failure mode hand-written
# plans and model-written plans share: a local model asked to plan "HTTP
# handlers" will happily declare five functions in one unit, and a unit that
# size reliably exhausts its turn budget before it type-checks. Below this,
# a unit is small enough that a single `--issue=<id>` run can hold its whole
# contract in view.
fn max_unit_api() -> Int
  examples {
    max_unit_api() => 3
  }
{
  3
}

# The same failure mode one level up: a brief that is really several
# independently-releasable packages ("a bank": accounts, ledger, compliance,
# statements...) still fits the JSON shape of one plan, so nothing stops a
# model from flattening it into one project anyway — rule 7 forces that
# project into ONE file, which a few dozen units turns into an unreviewable
# wall of code no single `--issue=<id>` run can hold in view, the same way
# an oversized unit couldn't. A plan this size is the signal that the brief
# needed to be split into separate packages (each its own `--package` run,
# joined by `lex.toml` deps and `package_api`, the same as any other
# dependency) before planning started, not a reason to plan harder.
fn max_plan_units() -> Int
  examples {
    max_plan_units() => 20
  }
{
  20
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
  let size_err := if list.len(u.api) > max_unit_api() {
    [str.join([who, "declares ", int.to_str(list.len(u.api)), " functions — rule 1 says one unit = one function (helpers may share it); split into separate units"], "")]
  } else {
    []
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
  list.concat(list.concat(list.concat(list.concat(list.concat(key_err, title_err), api_err), size_err), example_err), dep_err)
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
  let size_err := if list.len(plan.units) > max_plan_units() {
    [str.join(["this plan declares ", int.to_str(list.len(plan.units)), " units — more than ", int.to_str(max_plan_units()), " means the brief covers more than one package's worth of work (a single `--package` run builds ONE module). Narrow this plan to one package's worth of the brief (the foundational part other packages will depend on); the rest needs its own separate `--package --name=...` run later, installed as a dependency via lex.toml the same as any other package."], "")]
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
  let base := list.concat(list.concat(list.concat(list.concat(list.concat(project_err, empty_err), size_err), dup_key_err), dup_api_err), per_unit)
  let syntax := syntax_errors(plan.units)
  if not list.is_empty(syntax) {
    syntax
  } else {
    if list.is_empty(base) {
      match ordered(plan) {
        Err(e) => [e],
        Ok(_) => [],
      }
    } else {
      base
    }
  }
}

fn check_plan(text :: Str) -> Result[Plan, List[Str]]
  examples {
    check_plan("nope") => Err(["the plan is not valid JSON"]),
    check_plan("{\"project\": \"p\", \"units\": []}") => Err(["the plan has no units"]),
    check_plan("{\"project\": \"p\", \"units\": [{\"key\": \"h\", \"title\": \"handlers\", \"api\": [{\"name\": \"a\", \"signature\": \"() -> [net] Nil\"}, {\"name\": \"b\", \"signature\": \"() -> [net] Nil\"}, {\"name\": \"c\", \"signature\": \"() -> [net] Nil\"}, {\"name\": \"d\", \"signature\": \"() -> [net] Nil\"}]}]}") => Err(["unit `h`: declares 4 functions — rule 1 says one unit = one function (helpers may share it); split into separate units"]),
    check_plan("{\"project\": \"p\", \"units\": [{\"key\": \"u0\", \"title\": \"t\", \"api\": [{\"name\": \"f0\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u1\", \"title\": \"t\", \"api\": [{\"name\": \"f1\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u2\", \"title\": \"t\", \"api\": [{\"name\": \"f2\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u3\", \"title\": \"t\", \"api\": [{\"name\": \"f3\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u4\", \"title\": \"t\", \"api\": [{\"name\": \"f4\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u5\", \"title\": \"t\", \"api\": [{\"name\": \"f5\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u6\", \"title\": \"t\", \"api\": [{\"name\": \"f6\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u7\", \"title\": \"t\", \"api\": [{\"name\": \"f7\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u8\", \"title\": \"t\", \"api\": [{\"name\": \"f8\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u9\", \"title\": \"t\", \"api\": [{\"name\": \"f9\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u10\", \"title\": \"t\", \"api\": [{\"name\": \"f10\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u11\", \"title\": \"t\", \"api\": [{\"name\": \"f11\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u12\", \"title\": \"t\", \"api\": [{\"name\": \"f12\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u13\", \"title\": \"t\", \"api\": [{\"name\": \"f13\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u14\", \"title\": \"t\", \"api\": [{\"name\": \"f14\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u15\", \"title\": \"t\", \"api\": [{\"name\": \"f15\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u16\", \"title\": \"t\", \"api\": [{\"name\": \"f16\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u17\", \"title\": \"t\", \"api\": [{\"name\": \"f17\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u18\", \"title\": \"t\", \"api\": [{\"name\": \"f18\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u19\", \"title\": \"t\", \"api\": [{\"name\": \"f19\", \"signature\": \"() -> [net] Nil\"}]}, {\"key\": \"u20\", \"title\": \"t\", \"api\": [{\"name\": \"f20\", \"signature\": \"() -> [net] Nil\"}]}]}") => Err(["this plan declares 21 units — more than 20 means the brief covers more than one package's worth of work (a single `--package` run builds ONE module). Narrow this plan to one package's worth of the brief (the foundational part other packages will depend on); the rest needs its own separate `--package --name=...` run later, installed as a dependency via lex.toml the same as any other package."])
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

# The store head records a dependency's type without its module alias
# (`conn.ConnDb` is `ConnDb`, `jv.Json` is `Json`) and `lex issue verify`
# compares signatures as text, so a signature filed with the alias can never
# verify. The source keeps the alias (it needs it to compile); only the
# declared signature loses it.
fn strip_aliases(sig :: Str) -> Str
  examples {
    strip_aliases("(db :: conn.ConnDb, j :: jv.Json) -> [sql] Result[Int, Str]") => "(db :: ConnDb, j :: Json) -> [sql] Result[Int, Str]",
    strip_aliases("(n :: Int) -> Str") => "(n :: Int) -> Str",
    strip_aliases("(a :: List[resp.Response]) -> Nil") => "(a :: List[Response]) -> Nil"
  }
{
  match regex.compile("([^A-Za-z0-9_]|^)[a-z_][a-z0-9_]*\\.([A-Z])") {
    Err(_) => sig,
    Ok(re) => regex.replace_all(re, sig, "$1$2"),
  }
}

# The argv for `lex issue create` for one unit, its dependencies already
# filed (so their ids are known). Effectful api entries are declared without
# an example, as `lex issue create` allows.
fn create_argv(u :: PlanUnit, project :: Str, dep_ids :: List[Str]) -> List[Str]
  examples {
    create_argv({ key: "k", title: "T", body: "B", api: [{ name: "f", signature: "(n :: Int) -> Int" }], examples: ["f(1) => 1"], invariants: [], deps: [] }, "p", ["abc"]) => ["issue", "create", "--title", "T", "--shape", "typed_delta", "--project", "p", "--body", "B", "--api", "f:(n :: Int) -> Int", "--example", "f(1) => 1", "--dep", "abc"]
  }
{
  let head := ["issue", "create", "--title", u.title, "--shape", "typed_delta", "--project", project, "--body", u.body]
  let apis := list.fold(u.api, [], fn (acc :: List[Str], a :: Api) -> List[Str] {
    list.concat(acc, ["--api", str.join([a.name, ":", strip_aliases(a.signature)], "")])
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
  str.join(["Plan a Lex package as a graph of typed issues. Do NOT write the package itself.\n\n", "The package: ", brief, "\n\n", "Write ONE file, ", path, ", containing only JSON of this shape:\n\n", "  { \"project\": \"", project, "\",\n", "    \"types\": [ { \"name\": \"TypeName\", \"decl\": \"type TypeName = { field :: Str }\" } ],\n", "    \"packages\": [ { \"name\": \"lex-web\", \"git\": \"https://github.com/alpibrusl/lex-web\" } ],\n", "    \"policy\": { \"error_type\": \"Str\" },\n", "    \"units\": [\n", "      { \"key\": \"short_snake_name\", \"title\": \"one line\", \"body\": \"what it must do and the edge cases, in prose\",\n", "        \"api\": [ { \"name\": \"fn_name\", \"signature\": \"(x :: Int) -> Str\" } ],\n", "        \"examples\": [ \"fn_name(1) => \\\"one\\\"\" ],\n", "        \"invariants\": [ { \"name\": \"short_snake_name\", \"params\": [ { \"name\": \"x\", \"type\": \"Int\" } ], \"expr\": \"a Lex boolean expression using the param names and calling this unit's functions\" } ],\n", "        \"deps\": [ \"key_of_a_unit_this_needs_first\" ] } ] }\n\n", "`types`, `packages` and `policy` are each optional — omit any you don't need (an empty `[]` or `{}`, or leave the key out entirely). Rules — each one exists because a package built without it went wrong:\n", "1. One unit = one function the size of a screen (helpers may share its unit). If you cannot state its contract in two sentences, split it. A unit may declare at most 3 api entries — a family of similar functions (e.g. one HTTP handler per route) is one unit PER function, not one unit for the family, even though each is individually small.\n", "2. Signatures are the contract. Write them in Lex: `(a :: Int, b :: Str) -> Result[Int, Str]`; an effectful one puts its row after the arrow: `() -> [net] Nil`. Every function that any example calls must be declared as an api entry of some unit.\n", "3. deps are real: a unit lists the units whose functions it calls. Foundations first; no cycles.\n", "4. Give each pure function at least three examples, and make them pin the edges (empty, zero, boundary, the case the obvious implementation gets wrong). Examples run at check time, so an effectful function carries none.\n", "5. Give each pure function 1-2 invariants — a property checked over many inputs, not a few hand-picked ones (this is what catches a bug like a slugifier that doubles a hyphen on a run of separators, which every example happened to miss). `invariants` uses the shape shown above. Only Str, Int and Bool params have a corpus to check against. `expr` is a plain Bool expression (`==`, `and`, `or`, `not`, comparisons, calls): there is no `=>` implication in it — \"if A then B\" is `not (A) or (B)`.\n", "6. If the package composes its functions into ONE entry point, make that the last unit (deps = what it composes) with examples that run the whole thing end to end. If its public functions each stand alone, add no integration unit. Either way every function is declared by exactly ONE unit — never list a function in two units.\n", "7. The package is ONE module, src/", project, ".lex: units split the work, not the files, so never plan a separate file per unit.\n", "8. Before drawing anything, look at what already exists: read lex.toml and use the find_packages tool — depend on an existing package instead of planning to rebuild it; once installed, package_api(package, module) shows its real signatures, so plan against those instead of reading its source.\n", "9. If any signature or invariant mentions a type that isn't a builtin (Int, Str, Bool, List, Option, Result, tuples, records written inline) or one of your own units' functions, declare it in the top-level `types` array first — one entry per type, `decl` holding its FULL, real `type Name = ...` declaration (the field is `decl`, not `definition` or anything else). A record is `type Invoice = { id :: Int, paid :: Bool }` — no constructor name before the brace; a variant type is `type Shape = Circle(Int) | Square(Int)`. A type that a dependency package owns (what package_api shows, e.g. ConnDb or Ctx) is not declared here: write it qualified by a short module alias, `conn.ConnDb`, `ctx.Ctx`, `resp.Response`. A signature that mentions any other undeclared type is rejected before anything is filed.\n\n", "10. Budget: you have a limited number of steps (about 100) and a plan that is not written is worth nothing. Spend at most about 25 on research (find_packages, package_api, lex_stdlib), write the whole plan file ONCE, then spend the rest on plan_check and small `edit` fixes — when unsure of a detail, plan the unit and let the build step discover it.\n\n", "11. A plan may declare at most ", int.to_str(max_plan_units()), " units — a brief this big is more than one package's worth of work. If the brief covers several independently-releasable concerns (e.g. \"a bank\": accounts, ledger, compliance, statements), plan ONLY the foundational one as this package; the rest are separate `--package --name=...` runs later, each depending on this one through lex.toml once it is built. Do not cut corners (merging unrelated functions into one unit, dropping requirements) just to fit under the cap.\n\n", "When the file is written, reply with one line: the number of units. Do not implement anything."], "")
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

# Sent back to the planner when validation rejects its plan. The problems are
# the checker's own, so the fix is mechanical: repair the file, do not redraw it.
fn retry_prompt(original :: Str, errs :: List[Str], path :: Str) -> Str
  examples {
    retry_prompt("TASK", ["a is wrong"], "p.json") => "TASK\n\n--- RETRY ---\nYour plan in p.json was rejected by automatic validation. The file is still on disk: read it, then fix exactly these problems with small `edit` replacements (one line of the file as old_str) — do not rewrite the file and do not redo the research, you already have the plan:\n  - a is wrong\n\nThe rules in the original task still apply. Reply with one line: the number of units.\n\nIf the plan file is missing or empty, the previous attempt spent its whole step budget researching and never wrote it: do at most three more lookups, then write the file."
  }
{
  str.join([original, "\n\n--- RETRY ---\n", repair_prompt(errs, path), "\n\nIf the plan file is missing or empty, the previous attempt spent its whole step budget researching and never wrote it: do at most three more lookups, then write the file."], "")
}

fn repair_prompt(errs :: List[Str], path :: Str) -> Str
  examples {
    repair_prompt(["a is wrong"], "p.json") => "Your plan in p.json was rejected by automatic validation. The file is still on disk: read it, then fix exactly these problems with small `edit` replacements (one line of the file as old_str) — do not rewrite the file and do not redo the research, you already have the plan:\n  - a is wrong\n\nThe rules in the original task still apply. Reply with one line: the number of units."
  }
{
  str.join(["Your plan in ", path, " was rejected by automatic validation. The file is still on disk: read it, then fix exactly these problems with small `edit` replacements (one line of the file as old_str) — do not rewrite the file and do not redo the research, you already have the plan:\n  - ", str.join(errs, "\n  - "), "\n\nThe rules in the original task still apply. Reply with one line: the number of units."], "")
}

