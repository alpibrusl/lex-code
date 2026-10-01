# plan_check — run the plan validator on the plan file the planner just wrote.
#
# The same check the build applies before it files anything (structure,
# consistency rules, then `lex check` on the stub module). Without this tool a
# planner learns that a Result example has no Err case only after it replies,
# and the fix is a whole new planning session that rewrites the file and
# tends to break something else. Here the same problems come back in
# seconds, and the plan is repaired in place.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.io" as io

import "std.process" as proc

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../package_flow/apply" as papply

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "PlanCheckArgs", description: "Validate a plan file against the rules the build enforces.", fields: [s.with_desc(s.required_str("path", []), "Path of the plan JSON file you wrote, as given in the task.")] }
}

fn report(problems :: List[Str]) -> Str {
  str.join(["the plan does not pass — fix these in the file and call plan_check again:\n  - ", str.join(problems, "\n  - ")], "")
}

fn execute(args :: jv.Json) -> [io, net, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match io.read(str.trim(path)) {
      Err(msg) => Err(e.single("", "read_error", str.concat("cannot read the plan file: ", msg))),
      Ok(text) => match papply.full_check(text) {
        Ok(p) => Ok(JStr(str.join(["the plan passes: ", int.to_str(list.len(p.units)), " units. Reply with that number."], ""))),
        Err(problems) => Ok(JStr(report(problems))),
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("plan_check", "Check the plan file you wrote against the build's own validator — structure, signatures, examples, types, and a real `lex check` of the stub. Call it right after writing the plan and again after every fix, until it says the plan passes. Do not reply before it does.", params(), execute)
}

