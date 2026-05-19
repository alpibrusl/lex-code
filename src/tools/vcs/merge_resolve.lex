import "std.proc" as proc
import "std.str"  as str

import "lex-llm/tool"          as t
import "lex-schema/json_value" as jv
import "lex-schema/error"      as e
import "lex-schema/schema"     as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsMergeResolveArgs",
    description: "Submit conflict resolutions for an in-flight merge. resolutions_file must be a path to a JSON array of {conflict_id, resolution} objects.",
    fields: [
      s.required_str("merge_id", []),
      s.required_str("resolutions_file", []),
    ] }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "merge_id") {
    None => Err(e.single("", "missing_field", "merge_id is required")),
    Some(id) =>
      match util.field_str(args, "resolutions_file") {
        None => Err(e.single("", "missing_field", "resolutions_file is required")),
        Some(file) =>
          match proc.spawn("lex", ["merge", "resolve", id, "--file", file, "--output", "json"]) {
            Err(msg) => Err(e.single("", "proc_error", msg)),
            Ok(out)  => Ok(jv.JStr(str.concat(out.stdout, out.stderr))),
          }
      }
  }
}

fn tool() -> t.Tool {
  t.define(
    "vcs_merge_resolve",
    "Submit conflict resolutions for a lex-vcs merge session. Write a JSON resolutions file first (e.g. with write_file), then pass its path here.",
    params(),
    execute)
}
