import "lex-schema/json_value" as jv

import "lex-schema/schema" as s

import "std.list" as list

import "std.str" as str

fn field_str(args :: jv.Json, key :: Str) -> Option[Str] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_str(val),
  }
}

fn field_str_or(args :: jv.Json, key :: Str, default :: Str) -> Str {
  match field_str(args, key) {
    None => default,
    Some(v) => v,
  }
}

fn field_int(args :: jv.Json, key :: Str) -> Option[Int] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_int(val),
  }
}

fn field_bool(args :: jv.Json, key :: Str) -> Option[Bool] {
  match jv.get_field(args, key) {
    None => None,
    Some(val) => jv.as_bool(val),
  }
}

# Does `schema` declare `name` as a boolean field?
#
# The guard for a whole bug class: a tool whose `execute` reads a flag with
# `field_bool` while its schema declares that flag a string. The model
# follows the schema and sends `"dry_run": "true"`; `jv.as_bool` on a JStr
# returns None; the flag is silently dropped. For a preview flag that means
# the real, unpreviewed operation runs — which is how `vcs_op_push`'s
# dry_run behaved until this was checked (#28).
#
# Each affected tool calls this from an `examples {}` block on its own
# `params()`, so the schema and the reader are pinned together at
# `lex check` time rather than diverging silently.
fn declares_bool(schema :: s.ModelSchema, name :: Str) -> Bool
  examples {
    declares_bool({ title: "T", description: "", fields: [s.required_bool("flag")] }, "flag") => true,
    declares_bool({ title: "T", description: "", fields: [s.optional(s.required_bool("flag"))] }, "flag") => true,
    declares_bool({ title: "T", description: "", fields: [s.required_str("flag", [])] }, "flag") => false,
    declares_bool({ title: "T", description: "", fields: [] }, "flag") => false
  }
{
  list.fold(schema.fields, false, fn (acc :: Bool, f :: s.Field) -> Bool {
    if acc {
      true
    } else {
      if f.name == name {
        match f.kind {
          KBool => true,
          _ => false,
        }
      } else {
        false
      }
    }
  })
}

# ---- talking to the `lex` CLI ----------------------------------------
#
# `--output json` is a GLOBAL flag: `lex --output json branch peek main`.
# Eleven tools passed it after the subcommand, where the CLI either
# rejects it outright (`unexpected arg --output`) or — worse — accepts it,
# silently drops it, does the work, and returns human text to a caller
# that asked for JSON (#83).
fn json_cmd(rest :: List[Str]) -> List[Str]
  examples {
    json_cmd(["branch", "list"]) => ["--output", "json", "branch", "list"],
    json_cmd(["branch", "peek", "feat"]) => ["--output", "json", "branch", "peek", "feat"],
    json_cmd([]) => ["--output", "json"]
  }
{
  list.concat(["--output", "json"], rest)
}

# Did the CLI refuse the invocation, as opposed to answering it?
#
# The distinction #74 introduced, generalised. A tool that maps every
# non-zero exit onto a domain verdict tells the model something false
# about the code: `lex_spec_check` reported `spec falsified` — a property
# *disproven* — for a command the checker never ran, and `sigid_lookup`
# reported `sigid not found` for a subcommand that does not exist.
#
# ---- why these six phrases, and not the obvious wider net -------------
#
# The first version matched `error: missing` and `error: --` too, and read
# prose: `lex agent-guidelines` contains the table cell "(Lex error:
# missing return arrow)", so `load_guidelines` — which returns that
# document verbatim — looked like a refused command.
#
# Anchoring to a line that *starts* with `error: ` fixed that and broke
# something else: `e.format` renders an error as "<root>: message [code]",
# so every refusal a tool reports through `Err` is no longer at the start
# of its line. A mutation test caught it — reverting `branch_peek` to the
# broken argument order left the gate green.
#
# So: no anchor, and only phrases that cannot occur in prose about Lex.
# These six are absent from `lex agent-guidelines`, from `lex check`
# diagnostics, and from every JSON payload the tools return. The cost is
# real and worth naming: a refusal phrased outside this vocabulary — the
# `error: missing second run id` that `lex diff` emits — is not caught.
fn refusal_words() -> List[Str] {
  ["unknown flag", "unknown `lex", "subcommand:", "unexpected arg", "unexpected `--", "usage:"]
}

fn is_usage_error(text :: Str) -> Bool
  examples {
    is_usage_error("error: unknown flag `--json` for `lex check`") => true,
    is_usage_error("error: unknown `lex store` subcommand: diff") => true,
    is_usage_error("error: unexpected arg `5`") => true,
    is_usage_error("error: unexpected `--output`") => true,
    is_usage_error("error: usage: lex op {show|log}") => true,
    is_usage_error("<root>: error: unexpected arg `5` [cli_failed]") => true,
    is_usage_error("output\nerror: unexpected `--output`") => true,
    is_usage_error("| `-> T` | return type | `: T` (Lex error: missing return arrow) |") => false,
    is_usage_error("error: unknown stage_id `abc`") => false,
    is_usage_error("type error: expected Str, got Int") => false,
    is_usage_error("2 tests failed") => false,
    is_usage_error("") => false
  }
{
  list.fold(refusal_words(), false, fn (acc :: Bool, needle :: Str) -> Bool {
    if acc {
      true
    } else {
      str.contains(text, needle)
    }
  })
}

fn combined(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Str
  examples {
    combined({ stdout: "a", stderr: "b", exit_code: 0 }) => "ab",
    combined({ stdout: "", stderr: "boom", exit_code: 1 }) => "boom"
  }
{
  str.concat(out.stdout, out.stderr)
}

# The default reading for a tool with no meaningful non-zero exit: zero is
# the answer, anything else is a failure. Six tools returned
# `Ok(stdout ++ stderr)` unconditionally, so `error: unknown \`lex store\`
# subcommand: diff` reached the model as a *successful* tool result (#83).
fn cli_result(out :: { stdout :: Str, stderr :: Str, exit_code :: Int }) -> Result[Str, Str]
  examples {
    cli_result({ stdout: "ok", stderr: "", exit_code: 0 }) => Ok("ok"),
    cli_result({ stdout: "", stderr: "error: unexpected arg", exit_code: 2 }) => Err("error: unexpected arg")
  }
{
  if out.exit_code == 0 {
    Ok(combined(out))
  } else {
    Err(combined(out))
  }
}

# What a tool says when it could not ask the question, as distinct from
# asking it and getting no. `attestation_query` introduced the word in
# #74; the eight tools that conflated the two now share it.
fn unavailable(what :: Str, detail :: Str) -> Str
  examples {
    unavailable("lex spec check", "error: unexpected arg `5`") => "UNAVAILABLE — lex spec check could not be run, so this is not a negative result.\nerror: unexpected arg `5`"
  }
{
  str.join(["UNAVAILABLE — ", what, " could not be run, so this is not a negative result.\n", detail], "")
}

