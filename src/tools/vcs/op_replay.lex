import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "VcsOpReplayArgs", description: "Replay-verify a lex-vcs op: regenerate its change from the recorded intent and check reproducibility.", fields: [s.required_str("op_id", []), s.optional(s.required_str("ollama_model", []))] }
}

# With `ollama_model`, regenerate via the local Ollama daemon and record
# the Replay verdict; without it, print the replay request (target
# signature, recorded intent, parent program) for an external regenerator.
# (Comment kept out of the fn body so `lex fmt` doesn't drop it, lex-lang#755.)
fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "op_id") {
    None => Err(e.single("", "missing_field", "op_id is required")),
    Some(id) => {
      let regen := match util.field_str(args, "ollama_model") {
        None => [],
        Some(m) => ["--ollama", m],
      }
      let cmd := util.json_cmd(list.concat(["op", "replay", id], regen))
      match proc.run("lex", cmd) {
        Err(msg) => Err(e.single("", "proc_error", msg)),
        Ok(out) => match util.cli_result(out) {
          Err(detail) => Err(e.single("", "cli_failed", detail)),
          Ok(body) => Ok(JStr(body)),
        },
      }
    },
  }
}

fn tool() -> t.Tool {
  t.define("vcs_op_replay", "Replay-verify a lex-vcs op by op_id: regenerate the change from its recorded intent and compare the content-addressed stage. Pass ollama_model to regenerate via a local Ollama daemon and record a Replay attestation; omit it to get the replay request for an external regenerator.", params(), execute)
}

