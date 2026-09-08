# lex_stdlib — authoritative std.* module lookup
#
# A local/reasoning model without lex-lang training data has no way to
# know a stdlib function's real name or return type short of guessing and
# reading `lex check`'s error, or writing throwaway probe files to
# reverse-engineer a signature one function at a time (observed live: a
# from-scratch RLP build against qwen3.8 spent ~10 of its steps rebuilding
# std.bytes/std.crypto's shape this way before writing anything).
#
# This shells out to `lex docs --stdlib-index` (function names, every
# module — always available) and `--stdlib-spec` (typed signatures, only
# for modules migrated onto the declarative builtin catalogue, #778 —
# currently std.str and std.list; more arrive over time with zero change
# needed here). Both are generated straight from the compiler's own
# builtin registry, so the answer can't drift from what `lex check`
# actually accepts the way a hand-maintained prompt table could.

import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "LexStdlibArgs", description: "Look up a std.* module's real function names and (where migrated) exact typed signatures.", fields: [s.with_desc(s.required_str("module", []), "Module name, with or without the \"std.\" prefix (e.g. \"bytes\" or \"std.bytes\"). Pass \"\" to list every module.")] }
}

fn short_name(module :: Str) -> Str {
  match str.strip_prefix(module, "std.") {
    Some(rest) => rest,
    None => module,
  }
}

fn index_line_for(index_text :: Str, name :: Str) -> Option[Str] {
  let needle := str.join(["`std.", name, "`"], "")
  list.fold(str.split(index_text, "\n"), None, fn (acc :: Option[Str], line :: Str) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => if str.contains(line, needle) {
        Some(line)
      } else {
        None
      },
    }
  })
}

fn spec_lines_for(spec_text :: Str, name :: Str) -> List[Str] {
  let needle := str.join(["`", name, "."], "")
  list.filter(str.split(spec_text, "\n"), fn (line :: Str) -> Bool {
    str.contains(line, needle)
  })
}

fn run_docs(flag :: Str) -> [proc] Result[Str, Str] {
  match proc.run("lex", ["docs", flag]) {
    Err(msg) => Err(msg),
    Ok(out) => util.cli_result(out),
  }
}

fn with_signatures(line :: Str, name :: Str) -> [proc] Result[jv.Json, e.Errors] {
  match run_docs("--stdlib-spec") {
    Err(_) => Ok(JStr(line)),
    Ok(spec_text) => {
      let sig_lines := spec_lines_for(spec_text, name)
      if list.is_empty(sig_lines) {
        Ok(JStr(line))
      } else {
        Ok(JStr(str.join([line, "\n\nSignatures:\n", str.join(sig_lines, "\n")], "")))
      }
    },
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "module") {
    None => Err(e.single("", "missing_field", "module is required (pass \"\" to list every module)")),
    Some(raw_module) => match run_docs("--stdlib-index") {
      Err(msg) => Err(e.single("", "proc_error", util.unavailable("lex docs --stdlib-index", msg))),
      Ok(index_text) => if str.is_empty(raw_module) {
        Ok(JStr(index_text))
      } else {
        let name := short_name(raw_module)
        match index_line_for(index_text, name) {
          None => Ok(JStr(str.join(["no stdlib module named \"std.", name, "\". Full index:\n\n", index_text], ""))),
          Some(line) => with_signatures(line, name),
        }
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("lex_stdlib", "Look up a std.* module's real function names and (when available) exact typed signatures, straight from the compiler's own builtin registry — never guesses. module=\"bytes\" for std.bytes, module=\"\" to list every module. Call this before probing a stdlib call with a throwaway file or guessing a return type.", params(), execute)
}

