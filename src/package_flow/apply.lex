# lex-code — file a reviewed plan as typed issues
#
# The impure half of `--package-apply`: for each unit, in dependency order,
# `lex issue create` with `--dep` on the ids of the units it needs. Issues
# are content-addressed, so applying the same plan twice files nothing new.

import "std.str" as str

import "std.list" as list

import "std.process" as proc

import "std.io" as io

import "std.int" as int

import "lex-schema/json_value" as jv

import "../issue_contract" as ic

import "./plan" as plan

import "./check" as chk

import "./acceptance" as acc

import "std.time" as time

import "std.env" as env

import "std.regex" as regex

fn id_of(made :: List[(Str, Str)], key :: Str) -> Str
  examples {
    id_of([("a", "1"), ("b", "2")], "b") => "2",
    id_of([("a", "1")], "z") => "",
    id_of([], "a") => ""
  }
{
  list.fold(made, "", fn (acc :: Str, p :: (Str, Str)) -> Str {
    match p {
      (k, id) => if k == key {
        id
      } else {
        acc
      },
    }
  })
}

# Each unit is filed a second after the last: an issue's created_at has
# one-second resolution, so units filed together tie and the board falls back
# to id order, which is arbitrary (and put the hardest unit first). The pause
# keeps the plan's dependency order as the board's order.
fn file_units(units :: List[plan.PlanUnit], project :: Str, made :: List[(Str, Str)]) -> [proc] Result[List[(Str, Str)], Str] {
  match list.head(units) {
    None => Ok(made),
    Some(u) => {
      let dep_ids := list.map(u.deps, fn (d :: Str) -> Str {
        id_of(made, d)
      })
      match proc.run("lex", plan.create_argv(u, project, dep_ids)) {
        Err(e) => Err(e),
        Ok(out) => if out.exit_code != 0 {
          Err(str.join(["filing `", u.key, "` failed: ", str.trim(str.concat(out.stdout, out.stderr))], ""))
        } else {
          let __tick := proc.run("sleep", ["1"])
          file_units(list.tail(units), project, list.concat(made, [(u.key, str.trim(out.stdout))]))
        },
      }
    },
  }
}

# Returns (unit key, issue id) for every unit, in the order filed.
fn apply_plan(p :: plan.Plan) -> [proc] Result[List[(Str, Str)], Str] {
  match plan.ordered(p) {
    Err(e) => Err(e),
    Ok(units) => file_units(units, p.project, []),
  }
}

# ---- layer 1: let the real checker judge the plan ---------------------
fn error_line(j :: jv.Json) -> Int {
  match jv.get_field(j, "position") {
    None => 0,
    Some(pos) => match jv.get_field(pos, "line") {
      None => 0,
      Some(l) => match jv.as_int(l) {
        None => 0,
        Some(n) => n,
      },
    },
  }
}

# One checker error, told in the plan's terms.
fn describe_error(j :: jv.Json, labels :: List[(Int, Str)]) -> Str {
  let kind := ic.field_text(j, "kind")
  let expected := ic.field_text(j, "expected")
  let got := ic.field_text(j, "got")
  let detail := if str.is_empty(expected) {
    ""
  } else {
    str.join([" (expected ", expected, ", got ", got, ")"], "")
  }
  let ctx := str.join(ic.texts(ic.field_list(j, "context")), ", ")
  str.join([chk.label_at(labels, error_line(j)), ": ", kind, detail, if str.is_empty(ctx) {
    ""
  } else {
    str.concat(" in ", ctx)
  }], "")
}

# Every chunk of the stub that does not PARSE, each told in the plan's terms.
# The parser stops at the first bad chunk, so a model fixing one syntax slip
# per round-trip would take one retry per slip: after each hit that chunk is
# dropped and the rest checked again, until the stub parses or `budget` runs
# out. Parse errors are self-contained, so dropping a chunk cannot hide one
# in another.
fn parse_problems(chunks :: List[chk.Chunk], path :: Str, found :: List[Str], budget :: Int) -> [proc, io] List[Str] {
  if budget <= 0 {
    found
  } else {
    let prog := chk.program_of(chunks)
    let __w := io.write(path, prog.source)
    match proc.run("lex", ["check", path]) {
      Err(_) => found,
      Ok(out) => if out.exit_code == 0 {
        found
      } else {
        let msg := str.trim(str.concat(out.stdout, out.stderr))
        match chk.parse_error_byte(msg) {
          None => found,
          Some(n) => {
            let line := chk.line_of_byte(prog.source, n)
            parse_problems(chk.remove_chunk(chunks, chk.chunk_index_at(prog.labels, line)), path, list.concat(found, [chk.describe_parse_error(prog, msg)]), budget - 1)
          },
        }
      },
    }
  }
}

# Write the stub module and run `lex check` on it. Ok([]) = the contracts
# are well-typed and every example fits its signature.
fn compile_check(p :: plan.Plan) -> [proc, io] Result[List[Str], Str] {
  let parse_path := str.join([".lex/plans/", p.project, ".parse.lex"], "")
  let __d := proc.run("mkdir", ["-p", ".lex/plans"])
  let parse_found := parse_problems(chk.stub_chunks(p), parse_path, [], 12)
  if list.is_empty(parse_found) {
    compile_types(p)
  } else {
    Ok(parse_found)
  }
}

fn compile_types(p :: plan.Plan) -> [proc, io] Result[List[Str], Str] {
  let prog := chk.stub_program(p)
  let path := str.join([".lex/plans/", p.project, ".stub.lex"], "")
  let __dir := proc.run("mkdir", ["-p", ".lex/plans"])
  let __w := io.write(path, prog.source)
  match proc.run("lex", ["check", path]) {
    Err(e) => Err(e),
    Ok(out) => if out.exit_code == 0 {
      Ok([])
    } else {
      let lines := str.split(str.concat(out.stdout, out.stderr), "\n")
      let errs := list.fold(lines, [], fn (acc :: List[Str], l :: Str) -> List[Str] {
        if str.starts_with(str.trim(l), "{") {
          match jv.parse(str.trim(l)) {
            Err(_) => acc,
            Ok(j) => list.concat(acc, [describe_error(j, prog.labels)]),
          }
        } else {
          acc
        }
      })
      if list.is_empty(errs) {
        Ok([chk.describe_parse_error(prog, str.trim(str.concat(out.stdout, out.stderr)))])
      } else {
        Ok(errs)
      }
    },
  }
}

# Every check there is, in order: structure, consistency rules, then the
# real checker on the stub module. Err carries all the problems found.
fn full_check(text :: Str) -> [proc, io] Result[plan.Plan, List[Str]] {
  match chk.check_text(text) {
    Err(errs) => Err(errs),
    Ok(p) => match compile_check(p) {
      Err(e) => Err([e]),
      Ok(errs) => {
        let all := list.concat(errs, acceptance_problems(p))
        if list.is_empty(all) {
          Ok(p)
        } else {
          Err(all)
        }
      },
    },
  }
}

# A plan with a network handler describes a program that has to RUN, and no
# unit check shows that it does (see acceptance.lex). So such a plan must come
# with black-box scenarios, and any acceptance file that is there must be sound.
fn declares_net(sig :: Str) -> Bool
  examples {
    declares_net("() -> [sql, net, env] Nil") => true,
    declares_net("(c :: Ctx) -> [net] Response") => true,
    declares_net("(n :: Int) -> [sql] Int") => false,
    declares_net("(n :: Int) -> Int") => false
  }
{
  regex.is_match_str("-> \\[[^]]*\\bnet\\b", sig)
}

fn needs_acceptance(p :: plan.Plan) -> Bool {
  list.fold(p.units, false, fn (acc0 :: Bool, u :: plan.PlanUnit) -> Bool {
    acc0 or list.fold(u.api, false, fn (acc1 :: Bool, a :: plan.Api) -> Bool {
      acc1 or declares_net(a.signature)
    })
  })
}

fn acceptance_problems(p :: plan.Plan) -> [io] List[Str] {
  let path := acc.acceptance_path(p.project)
  match io.read(path) {
    Err(_) => if needs_acceptance(p) {
      [str.join(["this plan has network handlers, so it must say what the finished program is expected to DO: write ", path, " — black-box scenarios taken from the brief's own requirements (see ACCEPTANCE in the instructions)"], "")]
    } else {
      []
    },
    Ok(text) => list.map(acc.check_text(text), fn (e :: Str) -> Str {
      str.join([path, ": ", e], "")
    }),
  }
}

fn write_if_changed(path :: Str, old :: Str, new :: Str) -> [io] Nil {
  if old == new {
    ()
  } else {
    let __w := io.write(path, new)
    ()
  }
}

# The starting point of every task, written by the tool instead of a model:
# lex.toml with the plan's packages (installed), and src/<project>.lex with
# every shared type and every function's final signature over a placeholder
# body, published to the store head. An agent then only replaces bodies — it
# cannot drift from a signature, forget a dependency, or drop a function by
# rewriting the module. Applying twice leaves existing work alone.
fn write_scaffold(p :: plan.Plan) -> [proc, io] Result[Str, Str] {
  let file := str.join(["src/", p.project, ".lex"], "")
  let toml := match io.read("lex.toml") {
    Err(_) => str.join(["[package]\nname = \"", p.project, "\"\nversion = \"0.1.0\"\n"], ""),
    Ok(t) => t,
  }
  let __toml := write_if_changed("lex.toml", toml, chk.toml_with_packages(toml, p.packages))
  let installed := if list.is_empty(p.packages) {
    Ok("")
  } else {
    match proc.run("lex", ["pkg", "install"]) {
      Err(e) => Err(e),
      Ok(o) => if o.exit_code == 0 {
        Ok("")
      } else {
        Err(str.concat("lex pkg install failed: ", str.trim(str.concat(o.stdout, o.stderr))))
      },
    }
  }
  match installed {
    Err(e) => Err(e),
    Ok(_) => match io.read(file) {
      Ok(_) => Ok(str.join(["kept the existing ", file], "")),
      Err(_) => {
        let __d := proc.run("mkdir", ["-p", "src"])
        let __w := io.write(file, chk.scaffold_source(p))
        match proc.run("lex", ["publish", file, "--activate"]) {
          Err(e) => Err(e),
          Ok(o) => if o.exit_code == 0 {
            let __mark := io.write(str.join([".lex/plans/", p.project, ".scaffold"], ""), file)
            Ok(str.join(["wrote and published ", file, " — ", int.to_str(list.len(chk.scaffold_chunks(p))), " chunks (types, signatures)"], ""))
          } else {
            Err(str.concat("publishing the scaffold failed: ", str.trim(str.concat(o.stdout, o.stderr))))
          },
        }
      },
    },
  }
}

type HardenResult = { calls_checked :: Int, failing :: List[Str] }

# Reproduced live (2026-09-30): a package whose plan legitimately declares
# one effectful unit (a file-writing function, say) hardened every OTHER
# unit fine, then failed outright on `hardening unavailable` — not an
# invariant violation, `effect_not_allowed: fs_write`. The harness's own
# grant was hardcoded to exactly "io", regardless of what the package
# under test actually needs; calling ANY unit whose effect row isn't a
# subset of "io" was never going to work, no matter how correct the code
# was. This wasn't exercised before because no plan given to `harden` had
# declared a non-`io` effect on any of its units until now.
#
# `lex check` already computes exactly the answer needed — the union of
# every effect the file in front of it requires — and reports it as
# `required_effects` in its own JSON output (the same field this project
# already reads as a warning elsewhere). Ask it about the harness file
# itself (which imports and calls every unit under test) rather than
# hardcode a guess, and this generalizes to any future effect a plan
# might legitimately declare, not just fs_write.
fn required_effects_of(path :: Str) -> [proc] List[Str] {
  match proc.run("lex", ["--output", "json", "check", path]) {
    Err(_) => [],
    Ok(o) => match jv.parse(str.trim(o.stdout)) {
      Err(_) => [],
      Ok(env) => match jv.get_field(env, "data") {
        None => [],
        Some(data) => list.filter(ic.texts(ic.field_list(data, "required_effects")), fn (e :: Str) -> Bool {
          not str.is_empty(e)
        }),
      },
    },
  }
}

# Write tests/test_<project>.lex from the plan's invariants (nothing a model
# wrote), run it, and return the calls that came back false. Every invariant
# is fully specified by the plan, so there is nothing here to ask a model for.
fn harden(p :: plan.Plan) -> [proc, io] Result[HardenResult, Str] {
  if list.fold(p.units, 0, fn (acc :: Int, u :: plan.PlanUnit) -> Int {
    acc + list.len(u.invariants)
  }) == 0 {
    Ok({ calls_checked: 0, failing: [] })
  } else {
    let path := str.join(["tests/test_", p.project, ".lex"], "")
    let __d := proc.run("mkdir", ["-p", "tests"])
    let __w := io.write(path, chk.harden_source(p))
    let needed := required_effects_of(path)
    let effects := str.join(list.cons("io", list.filter(needed, fn (e :: Str) -> Bool {
      e != "io"
    })), ",")
    match proc.run("lex", ["--output", "json", "run", "--allow-effects", effects, path, "failing_calls"]) {
      Err(e) => Err(e),
      Ok(o) => if o.exit_code != 0 {
        Err(str.concat("running the hardening harness failed: ", str.trim(str.concat(o.stdout, o.stderr))))
      } else {
        match jv.parse(str.trim(o.stdout)) {
          Err(_) => Err(str.concat("hardening harness did not return JSON: ", str.trim(o.stdout))),
          Ok(env) => match jv.get_field(env, "data") {
            None => Err(str.concat("hardening harness returned no data: ", str.trim(o.stdout))),
            Some(data) => match jv.get_field(data, "result") {
              None => Err(str.concat("hardening harness result had no `result` field: ", str.trim(o.stdout))),
              Some(j) => Ok({ calls_checked: combos_total(p), failing: ic.texts(match jv.as_list(j) {
                None => [],
                Some(xs) => xs,
              }) }),
            },
          },
        }
      },
    }
  }
}

fn combos_total(p :: plan.Plan) -> Int {
  list.fold(p.units, 0, fn (acc :: Int, u :: plan.PlanUnit) -> Int {
    list.fold(u.invariants, acc, fn (acc2 :: Int, i :: plan.Invariant) -> Int {
      acc2 + list.len(chk.combos(i.params))
    })
  })
}

# An invariant that fails on EVERY probed input is not a bug in the code, it is
# a contradiction in the plan: the unit's examples are its immutable oracle, so
# the implementation satisfied them, and the invariant asks for the opposite.
# Observed live: `sql_builders` examples said each builder returns `[]` params
# while its invariants said 4, 2, 1 and 2 — hardening filed 52 issues, none of
# which any attempt could ever close. Returns "<unit>: <invariant>" for each.
fn contradicted_invariants(p :: plan.Plan, failing :: List[Str]) -> List[Str]
  examples {
    contradicted_invariants(empty_plan_for_tests(), []) => [],
    contradicted_invariants(one_invariant_plan(), ["inv_u_i(true, true)", "inv_u_i(true, false)", "inv_u_i(false, true)", "inv_u_i(false, false)"]) => ["u: i"],
    contradicted_invariants(one_invariant_plan(), ["inv_u_i(true, true)", "inv_u_i(false, false)"]) => []
  }
{
  list.fold(p.units, [], fn (acc0 :: List[Str], u :: plan.PlanUnit) -> List[Str] {
    list.fold(u.invariants, acc0, fn (acc1 :: List[Str], i :: plan.Invariant) -> List[Str] {
      let prefix := str.concat(chk.invariant_fn_name(u.key, i.name), "(")
      let total := list.len(chk.combos(i.params))
      let bad := list.len(list.filter(failing, fn (call :: Str) -> Bool {
        str.starts_with(call, prefix)
      }))
      if total >= 3 and bad == total {
        list.concat(acc1, [str.join([u.key, ": ", i.name], "")])
      } else {
        acc1
      }
    })
  })
}

fn empty_plan_for_tests() -> plan.Plan {
  { project: "p", types: [], packages: [], policy: { error_type: "" }, units: [] }
}

fn one_invariant_plan() -> plan.Plan {
  { project: "p", types: [], packages: [], policy: { error_type: "" }, units: [{ key: "u", title: "t", body: "", api: [], examples: [], invariants: [{ name: "i", params: [{ name: "a", ty: "Bool" }, { name: "b", ty: "Bool" }], expr: "a" }], deps: [] }] }
}

# What the acceptance run found: the gate word and, when it failed, the lines a
# repair attempt needs (one per scenario that did not hold, or the reason the
# program never started).
type AcceptOutcome = { gate :: Str, problems :: List[Str] }

# The closing gate that runs the assembled program. "none" = the plan wrote no
# acceptance file (a library, say), "pass" = every scenario held, "fail" = the
# program did not start or a scenario did not hold. Prints what it found.
fn acceptance_run(project :: Str) -> [proc, io, net, time, env] AcceptOutcome {
  match io.read(acc.acceptance_path(project)) {
    Err(_) => { gate: "none", problems: [] },
    Ok(text) => match acc.parse_acceptance(text) {
      Err(e) => {
        let __p := io.print(str.join(["[ACCEPTANCE] ", e], ""))
        { gate: "fail", problems: [e] }
      },
      Ok(a) => {
        let errs := acc.acceptance_errors(a)
        if not list.is_empty(errs) {
          let __p := io.print(str.join(["[ACCEPTANCE] the acceptance file is not sound:\n  - ", str.join(errs, "\n  - ")], ""))
          { gate: "fail", problems: errs }
        } else {
          let file := str.join(["src/", project, ".lex"], "")
          let needed := required_effects_of(file)
          if list.is_empty(needed) {
            let msg := str.join(["cannot run ", file, ": `lex check` reports no required effects (does it type-check?)"], "")
            let __p := io.print(str.concat("[ACCEPTANCE] ", msg))
            { gate: "fail", problems: [msg] }
          } else {
            match acc.run_acceptance(file, a, str.join(needed, ",")) {
              Err(e) => {
                let __p := io.print(str.join(["[ACCEPTANCE] 0/", int.to_str(list.len(a.scenarios)), " — ", e], ""))
                { gate: "fail", problems: [e] }
              },
              Ok(r) => {
                let __p := io.print(str.join(["[ACCEPTANCE] ", int.to_str(r.passed), "/", int.to_str(r.total), " scenarios hold", if list.is_empty(r.failures) {
                  ""
                } else {
                  str.concat(":\n  - ", str.join(r.failures, "\n  - "))
                }], ""))
                if list.is_empty(r.failures) {
                  { gate: "pass", problems: [] }
                } else {
                  let how := acc.repro_line(file, a, str.join(needed, ","), r.failures)
                  { gate: "fail", problems: if str.is_empty(how) {
                    r.failures
                  } else {
                    list.concat(r.failures, [how])
                  } }
                }
              },
            }
          }
        }
      },
    },
  }
}

fn acceptance_gate(project :: Str) -> [proc, io, net, time, env] Str {
  acceptance_run(project).gate
}

