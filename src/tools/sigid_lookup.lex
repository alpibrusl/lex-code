# sigid_lookup — find a stage by the SigId of its function
#
# The tool ran `lex store lookup <sigid>`; `lex store` accepts `list` and
# `get` and nothing else, so it had never run. Worse, it mapped every
# non-zero exit onto `sigid not found: <id>` — so "this subcommand does
# not exist" was returned to the model as an honest negative about the
# store (#83, the same shape #74 fixed in attestation_query).
#
# The real lookup is two steps, because a SigId and a StageId are
# different things: `store list` maps each SigId to its active StageId,
# and `store get` takes the StageId. A SigId with no active stage is a
# third outcome, and is reported as itself rather than as absence.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "SigidLookupArgs", description: "Find a function's active stage by its content-addressed SigId", fields: [s.required_str("sigid", [])] }
}

fn str_field(j :: jv.Json, name :: Str) -> Str {
  match jv.get_field(j, name) {
    Some(JStr(v)) => v,
    _ => "",
  }
}

fn sigs_of(body :: Str) -> List[jv.Json] {
  match jv.parse_into_errors(body) {
    Err(_) => [],
    Ok(j) => match jv.get_field(j, "data") {
      None => [],
      Some(d) => match jv.get_field(d, "sigs") {
        Some(JList(items)) => items,
        _ => [],
      },
    },
  }
}

# Three outcomes, and they are not interchangeable: the SigId is unknown
# to the store, it is known but has no active stage, or it resolves.
type Resolved = Missing | NoStage | Stage(Str)

fn resolve(body :: Str, sigid :: Str) -> Resolved
  examples {
    resolve("{\"data\":{\"sigs\":[{\"sig_id\":\"aa\",\"active_stage_id\":\"bb\"}]}}", "aa") => Stage("bb"),
    resolve("{\"data\":{\"sigs\":[{\"sig_id\":\"aa\",\"active_stage_id\":\"\"}]}}", "aa") => NoStage,
    resolve("{\"data\":{\"sigs\":[{\"sig_id\":\"aa\",\"active_stage_id\":\"bb\"}]}}", "zz") => Missing,
    resolve("not json", "aa") => Missing
  }
{
  list.fold(sigs_of(body), Missing, fn (acc :: Resolved, sg :: jv.Json) -> Resolved {
    match acc {
      Missing => if str_field(sg, "sig_id") == sigid {
        let stage := str_field(sg, "active_stage_id")
        if str.is_empty(stage) {
          NoStage
        } else {
          Stage(stage)
        }
      } else {
        Missing
      },
      _ => acc,
    }
  })
}

fn missing_text(sigid :: Str) -> Str
  examples {
    missing_text("aa") => "no SigId 'aa' in the store. `lex store list` ran and returned no match, so this is a real absence, not a failed lookup."
  }
{
  str.join(["no SigId '", sigid, "' in the store. `lex store list` ran and returned no match, so this is a real absence, not a failed lookup."], "")
}

fn no_stage_text(sigid :: Str) -> Str
  examples {
    no_stage_text("aa") => "SigId 'aa' is in the store but has no active stage. The signature is known; no body is currently published against it."
  }
{
  str.join(["SigId '", sigid, "' is in the store but has no active stage. The signature is known; no body is currently published against it."], "")
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "sigid") {
    None => Err(e.single("", "missing_field", "sigid is required")),
    Some(sigid) => match proc.run("lex", util.json_cmd(["store", "list"])) {
      Err(msg) => Err(e.single("", "proc_error", msg)),
      Ok(out) => match util.cli_result(out) {
        Err(detail) => Err(e.single("", "store_unavailable", util.unavailable("lex store list", detail))),
        Ok(body) => match resolve(body, sigid) {
          Missing => Ok(JStr(missing_text(sigid))),
          NoStage => Ok(JStr(no_stage_text(sigid))),
          Stage(stage_id) => get_stage(stage_id),
        },
      },
    },
  }
}

fn get_stage(stage_id :: Str) -> [io, proc] Result[jv.Json, e.Errors] {
  match proc.run("lex", util.json_cmd(["store", "get", stage_id])) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => match util.cli_result(out) {
      Err(detail) => Err(e.single("", "store_unavailable", util.unavailable(str.concat("lex store get ", stage_id), detail))),
      Ok(body) => Ok(JStr(body)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("sigid_lookup", "Look up a function's active stage by its content-addressed SigId. Exact identity, not name-based. Distinguishes an unknown SigId, a known SigId with no active stage, and a resolved stage.", params(), execute)
}

