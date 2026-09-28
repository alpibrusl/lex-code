# lex-code — file a reviewed plan as typed issues
#
# The impure half of `--package-apply`: for each unit, in dependency order,
# `lex issue create` with `--dep` on the ids of the units it needs. Issues
# are content-addressed, so applying the same plan twice files nothing new.

import "std.str" as str

import "std.list" as list

import "std.process" as proc

import "./plan" as plan

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

