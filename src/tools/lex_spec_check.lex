# lex_spec_check — random property-check a lex-spec Spec
#
# Two things were wrong (#83). The command took `--count N`, which does
# not exist, so every call died with `unexpected arg`. And any non-zero
# exit was rendered **"spec falsified"** — so a rejected invocation
# reached the model as the claim that a property had been *disproven*.
# That is worse than a broken tool: it is a broken tool that testifies.
#
# The real command is `lex spec check <spec> --source <file>`, and both
# halves are required: a `.spec` file states the property, a `.lex` file
# supplies the code it quantifies over.

import "std.process" as proc

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexSpecCheckArgs", description: "Random property-check a lex-spec Spec against its source", fields: [s.required_str("spec", []), s.required_str("source", [])] }
}

# The two outcomes a run can have, and the third that is not an outcome.
# `falsified` is a claim about the code and is only ever printed when the
# checker actually reached a verdict.
fn verdict(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Result[Str, Str]
  examples {
    verdict({ stdout: "100 samples", stderr: "", exit_code: 0 }) => Ok("spec passed\n100 samples"),
    verdict({ stdout: "counterexample: x = 0", stderr: "", exit_code: 1 }) => Ok("spec falsified\ncounterexample: x = 0"),
    verdict({ stdout: "", stderr: "error: unexpected arg `5`", exit_code: 2 }) => Err("error: unexpected arg `5`")
  }
{
  if out.exit_code == 0 {
    Ok(str.concat("spec passed\n", util.combined(out)))
  } else {
    if util.is_usage_error(util.combined(out)) {
      Err(util.combined(out))
    } else {
      Ok(str.concat("spec falsified\n", util.combined(out)))
    }
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "spec") {
    None => Err(e.single("", "missing_field", "spec is required — the path to a .spec file")),
    Some(spec_file) => match util.field_str(args, "source") {
      None => Err(e.single("", "missing_field", "source is required — the .lex file the spec quantifies over")),
      Some(source) => run(spec_file, source),
    },
  }
}

fn run(spec_file :: Str, source :: Str) -> [io, proc] Result[jv.Json, e.Errors] {
  match proc.run("lex", ["spec", "check", spec_file, "--source", source]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => match verdict(out) {
      Err(detail) => Err(e.single("", "spec_check_failed", util.unavailable("lex spec check", detail))),
      Ok(text) => Ok(JStr(text)),
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_spec_check", "Random property-check a lex-spec Spec with `lex spec check <spec> --source <file>`. Returns 'spec passed' or 'spec falsified' with a counterexample; a spec that could not be run says UNAVAILABLE rather than reporting a falsification.", params(), execute)
}

