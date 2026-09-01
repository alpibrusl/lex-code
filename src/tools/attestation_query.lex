import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

import "../verification" as verification

import "std.list" as list

import "std.int" as int

fn params() -> s.ModelSchema {
  { title: "AttestationQueryArgs", description: "List attestations on a function", fields: [s.required_str("fn_name", []), s.optional(s.required_str("path", []))] }
}

# Two sources, because there are two kinds of evidence and neither alone
# answers "should I trust this function".
#
#   lex blame --with-evidence   the store's attestation graph, per function,
#                               tied to a SigId — evidence about this exact
#                               body, which survives a rename and dies on an
#                               edit.
#   .lex/verified.jsonl         verification passes harvested from agent
#                               sessions — project-scoped, cross-session, and
#                               the only reason a later review agent finds
#                               anything at all. Since lex-llm#48 each pass
#                               names the path the tool was given, so this is
#                               file-level evidence rather than merely
#                               "something passed somewhere".
#
# This tool used to run `lex store attestations <fn>`. That subcommand does
# not exist: `lex store` rejects it, the error goes to stderr, stdout comes
# back empty — and the old code read an empty stdout as "no attestations".
# So every query answered "<fn> has no attestations", which is the one answer
# a reviewer must never be given wrongly. A broken query and an honest
# negative are now different results.
fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "fn_name") {
    None => Err(e.single("", "missing_field", "fn_name is required")),
    Some(fn_name) => {
      let file := util.field_str_or(args, "path", "")
      let blame := if str.is_empty(file) {
        "store evidence: pass `path` (the .lex file) to query the attestation graph"
      } else {
        blame_section(file, fn_name)
      }
      let passes := session_section(fn_name)
      Ok(JStr(str.join([blame, "\n\n", passes], "")))
    },
  }
}

fn blame_section(file :: Str, fn_name :: Str) -> [proc] Str {
  match proc.run("lex", ["blame", file, "--with-evidence"]) {
    Err(msg) => str.concat("store evidence: UNAVAILABLE — could not run `lex blame`: ", msg),
    Ok(out) => if out.exit_code == 0 {
      let lines := matching_lines(out.stdout, fn_name)
      if str.is_empty(lines) {
        str.join(["store evidence: none for ", fn_name, " in ", file], "")
      } else {
        str.join(["store evidence for ", fn_name, ":\n", lines], "")
      }
    } else {
      str.join(["store evidence: UNAVAILABLE — `lex blame` exited ", int.to_str(out.exit_code), ": ", str.trim(str.concat(out.stdout, out.stderr))], "")
    },
  }
}

# `lex blame` prints a stanza per function; keep the one naming this fn and
# the indented lines under it.
fn matching_lines(output :: Str, fn_name :: Str) -> Str {
  let needle := str.concat(".", fn_name)
  match list.fold(str.split(output, "\n"), (false, []), fn (acc :: (Bool, List[Str]), line :: Str) -> (Bool, List[Str]) {
    match acc {
      (inside, kept) => if str.starts_with(line, "fn ") {
        if str.ends_with(line, needle) {
          (true, list.concat(kept, [line]))
        } else {
          (false, kept)
        }
      } else {
        if inside {
          (true, list.concat(kept, [line]))
        } else {
          (false, kept)
        }
      },
    }
  }) {
    (_, kept) => str.join(kept, "\n"),
  }
}

fn session_section(fn_name :: Str) -> [io] Str {
  let records := verification.all()
  if list.is_empty(records) {
    "verification passes: none recorded for this project yet"
  } else {
    str.join(["verification passes recorded in this project:\n", verification.render(records), "\n\nThese are FILE-level, not function-level: a pass names the path the tool was given, so it says a check covered the file ", fn_name, " lives in, not that it covered ", fn_name, " itself. A pass on \"the whole project\" is a tool called with no path at all. Store evidence is still the stronger signal, because it is tied to a SigId and dies when the body changes."], "")
  }
}

fn tool() -> t.Tool {
  t.define("attestation_query", "Evidence about a function: the store attestation graph via `lex blame --with-evidence` (pass `path` to the .lex file), plus verification passes recorded across this project's agent sessions. Reports an unavailable query as unavailable, never as an absence of evidence.", params(), execute)
}

