import "std.process" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "OsCheckArgs", description: "Check a Lex file's declared effects against the mode's trust grant", fields: [s.required_str("path", []), s.optional(s.required_str("mode", []))] }
}

# Effects the mode forbids, derived from the lex-os grant for that mode.
#   explore / plan / review — ReadOnly FS, No Net, No Exec
#   bar                     — ReadOnly FS, No Net, Sandboxed Exec
#                             (the probes shell out to git / find / grep)
#   spec                    — ReadWrite FS, No Net, No Exec
#   test / refactor         — ReadWrite FS, No Net, Sandboxed Exec
#   build                   — Full FS, Allowlist Net, Full Exec (nothing forbidden)
fn forbidden_for_mode(mode :: Str) -> List[Str] {
  if mode == "explore" or mode == "plan" or mode == "review" {
    ["net", "proc", "fs_write"]
  } else {
    if mode == "bar" {
      ["net", "fs_write"]
    } else {
      if mode == "spec" {
        ["net", "proc"]
      } else {
        if mode == "test" or mode == "refactor" {
          ["net"]
        } else {
          []
        }
      }
    }
  }
}

fn effect_in(effect :: Str, lst :: List[Str]) -> Bool {
  list.fold(lst, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or x == effect
  })
}

fn violations(required :: List[Str], forbidden :: List[Str]) -> List[Str] {
  list.filter(required, fn (eff :: Str) -> Bool {
    effect_in(eff, forbidden)
  })
}

fn extract_effects(check_json :: jv.Json) -> List[Str] {
  match jv.get_field(check_json, "data") {
    None => [],
    Some(data) => match jv.get_field(data, "required_effects") {
      Some(JList(items)) => list.fold(items, [], fn (acc :: List[Str], j :: jv.Json) -> List[Str] {
        match j {
          JStr(s) => list.concat(acc, [s]),
          _ => acc,
        }
      }),
      _ => [],
    },
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let path := util.field_str_or(args, "path", ".")
  let mode := util.field_str_or(args, "mode", "build")
  match proc.run("lex", ["--output", "json", "check", path]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => if out.exit_code != 0 {
      Err(e.single("", "lex_check_failed", str.concat(out.stdout, out.stderr)))
    } else {
      match jv.parse(out.stdout) {
        Err(_) => Err(e.single("", "parse_error", "could not parse lex check output")),
        Ok(parsed) => {
          let required := extract_effects(parsed)
          let forbidden := forbidden_for_mode(mode)
          let violated := violations(required, forbidden)
          if list.len(violated) == 0 {
            Ok(JStr(str.concat("grant check passed [mode=", str.concat(mode, str.concat("] effects=", str.join(required, ","))))))
          } else {
            Ok(JStr(str.join(["GRANT VIOLATION [mode=", mode, "]\n", "  forbidden effects used: ", str.join(violated, ", "), "\n", "  all required effects:   ", str.join(required, ", "), "\n", "  grant allows:           ", grant_summary_for_mode(mode)], "")))
          }
        },
      }
    },
  }
}

fn grant_summary_for_mode(mode :: Str) -> Str {
  if mode == "explore" or mode == "plan" or mode == "review" {
    "fs=read-only net=none exec=none"
  } else {
    if mode == "bar" {
      "fs=read-only net=none exec=sandboxed"
    } else {
      if mode == "spec" {
        "fs=read-write net=none exec=none"
      } else {
        if mode == "test" or mode == "refactor" {
          "fs=read-write net=none exec=sandboxed"
        } else {
          "fs=full net=allowlist exec=full"
        }
      }
    }
  }
}

fn tool() -> t.Tool {
  t.define("os_check", "Check a Lex file's declared effects against the mode's trust grant (lex-os integration). Run after lex_check to catch grant violations — e.g. a refactor agent must not use net effects. Returns GRANT VIOLATION with details if the file exceeds the mode's grant.", params(), execute)
}

