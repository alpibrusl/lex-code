# lex_cli_help — authoritative `lex` CLI subcommand lookup
#
# `lex` implements ACLI (github.com/alpibrusl/acli): `lex introspect
# --output json` emits the full command tree — every subcommand's
# arguments, options, examples, and idempotency, generated from the
# binary's own registration, not hand-maintained prose. `lex_cli.lex`
# (the generic "run any lex command" escape hatch) already ships a
# hand-written summary of a handful of subcommands in its own tool
# description, which goes stale as subcommands are added; this tool
# answers the same "how do I invoke lex X" question by asking the binary
# itself, the same "atomic, authoritative, on demand" move `lex_stdlib`
# makes for stdlib signatures and `lex_guide` makes for the language
# guide — so a CLI usage error (`is_usage_error` in `./util`) is
# something to ask about first, not find out by trial and error.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexCliHelpArgs", description: "Look up a lex CLI subcommand's real arguments, options, and examples.", fields: [s.with_desc(s.required_str("command", []), "Subcommand name, e.g. \"check\", \"run\", \"doc-sync\". Pass \"\" to list every subcommand name.")] }
}

fn run_introspect() -> [proc] Result[jv.Json, Str] {
  match proc.run("lex", util.json_cmd(["introspect"])) {
    Err(msg) => Err(msg),
    Ok(out) => if out.exit_code == 0 {
      match jv.parse(out.stdout) {
        Err(perr) => Err(str.join(["failed to parse `lex introspect` output: ", perr.message], "")),
        Ok(envelope) => match jv.get_field(envelope, "data") {
          None => Err("`lex introspect` JSON envelope had no \"data\" field"),
          Some(root) => Ok(root),
        },
      }
    } else {
      Err(util.combined(out))
    },
  }
}

fn commands_of(root :: jv.Json) -> List[jv.Json] {
  match jv.get_field(root, "commands") {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(items) => items,
    },
  }
}

fn str_field(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    None => "",
    Some(v) => match jv.as_str(v) {
      None => "",
      Some(s) => s,
    },
  }
}

fn bool_field(j :: jv.Json, key :: Str) -> Bool {
  match jv.get_field(j, key) {
    None => false,
    Some(v) => match jv.as_bool(v) {
      None => false,
      Some(b) => b,
    },
  }
}

fn list_field(j :: jv.Json, key :: Str) -> List[jv.Json] {
  match jv.get_field(j, key) {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(l) => l,
    },
  }
}

fn as_str_or_empty(j :: jv.Json) -> Str {
  match jv.as_str(j) {
    None => "",
    Some(s) => s,
  }
}

fn command_names(root :: jv.Json) -> List[Str] {
  list.map(commands_of(root), fn (c :: jv.Json) -> Str {
    str_field(c, "name")
  })
}

fn find_command(root :: jv.Json, name :: Str) -> Option[jv.Json] {
  list.fold(commands_of(root), None, fn (acc :: Option[jv.Json], c :: jv.Json) -> Option[jv.Json] {
    match acc {
      Some(_) => acc,
      None => if str_field(c, "name") == name {
        Some(c)
      } else {
        None
      },
    }
  })
}

fn render_argument(a :: jv.Json) -> Str {
  let tag := if bool_field(a, "required") {
    "required"
  } else {
    "optional"
  }
  str.join(["  ", str_field(a, "name"), " :: ", str_field(a, "type"), " (", tag, ") — ", str_field(a, "description")], "")
}

fn render_option(o :: jv.Json) -> Str {
  str.join(["  ", str_field(o, "name"), " :: ", str_field(o, "type"), " — ", str_field(o, "description")], "")
}

fn render_example(x :: jv.Json) -> Str {
  str.join(["  ", str_field(x, "invocation"), "    # ", str_field(x, "description")], "")
}

fn render_lines(items :: List[jv.Json], render_one :: (jv.Json) -> Str) -> Str {
  if list.is_empty(items) {
    "  (none)"
  } else {
    str.join(list.map(items, render_one), "\n")
  }
}

fn render_command(cmd :: jv.Json) -> Str {
  let see_also := list.map(list_field(cmd, "see_also"), as_str_or_empty)
  let see_also_line := if list.is_empty(see_also) {
    ""
  } else {
    str.join(["\nSee also: ", str.join(see_also, ", ")], "")
  }
  str.join([str.join(["lex ", str_field(cmd, "name"), " — ", str_field(cmd, "description")], ""), "\nArguments:\n", render_lines(list_field(cmd, "arguments"), render_argument), "\nOptions:\n", render_lines(list_field(cmd, "options"), render_option), "\nExamples:\n", render_lines(list_field(cmd, "examples"), render_example), see_also_line], "")
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "command") {
    None => Err(e.single("", "missing_field", "command is required (pass \"\" to list every subcommand)")),
    Some(raw) => match run_introspect() {
      Err(msg) => Err(e.single("", "proc_error", util.unavailable("lex introspect --output json", msg))),
      Ok(root) => if str.is_empty(raw) {
        Ok(JStr(str.join(command_names(root), ", ")))
      } else {
        match find_command(root, raw) {
          None => Ok(JStr(str.join(["no lex subcommand named \"", raw, "\". Available: ", str.join(command_names(root), ", ")], ""))),
          Some(cmd) => Ok(JStr(render_command(cmd))),
        }
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_cli_help", "Look up a `lex` CLI subcommand's real arguments, options, and examples, straight from the binary's own ACLI introspection (`lex introspect`) — never guessed or hand-maintained. command=\"check\" for `lex check`, command=\"\" to list every subcommand. Call this before guessing a lex CLI flag or finding out by trial and error.", params(), execute)
}

