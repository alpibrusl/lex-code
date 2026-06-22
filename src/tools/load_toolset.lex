import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "std.str" as str

import "./util" as util

# load_toolset — dynamic tool loading for small/local models.
#
# Local models choke on large tool catalogs (the full set is ~38 tools). The
# build agent starts with a curated minimal set plus this meta-tool. When the
# model genuinely needs an extra capability group it calls load_toolset, which
# emits a "LOADED_TOOLSET:<group>" marker into the tool result. lex-llm's
# bindings_from_conv detects that marker and flips the matching `loaded_*`
# binding, so the gated tools in that group become available on the next step
# (see tools/index.lex `gate_*` preconditions).
fn params() -> s.ModelSchema {
  { title: "LoadToolsetArgs", description: "Load an extra group of tools so they become callable next step.", fields: [s.required_str("group", [])] }
}

fn known(group :: Str) -> Bool {
  str.contains(",vcs,spec,store,", str.concat(",", str.concat(group, ",")))
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "group") {
    None => Err(e.single("", "missing_field", "group is required (one of: vcs, spec, store)")),
    Some(g) => if known(g) {
      Ok(JStr(str.concat("LOADED_TOOLSET:", str.concat(g, str.concat(" — the '", str.concat(g, "' tools are now available; call them directly on the next step."))))))
    } else {
      Err(e.single("", "unknown_group", str.concat("unknown toolset group: ", str.concat(g, " (expected vcs, spec, or store)"))))
    },
  }
}

fn tool() -> t.Tool {
  t.define("load_toolset", "Load an extra group of tools on demand when the curated default set is not enough. group = \"vcs\" (version-control: branches, diffs, merges), \"spec\" (lex-spec checking + SMT), or \"store\" (code-store diff/apply/merge). The requested tools appear on your NEXT step. Only load what you actually need.", params(), execute)
}
