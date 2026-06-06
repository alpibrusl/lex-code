import "std.proc" as proc

import "std.str" as str

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "OsCheckArgs", description: "Check a Lex file's declared effects against the refactor-mode trust grant", fields: [s.required_str("path", [])] }
}

# Effects the mode forbids, derived from the lex-os grant for that mode.
#   explore / plan / review — ReadOnly FS, No Net, No Exec
#   spec                    — ReadWrite FS, No Net, No Exec
#   test / refactor         — ReadWrite FS, No Net, Sandboxed Exec
#   build                   — Full FS, Allowlist Net, Full Exec (nothing forbidden)
fn forbidden_for_mode(mode :: Str) -> List[Str] {
  if mode == "explore" or mode == "plan" or mode == "review" {
    ["net", "proc", "fs_write"]
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

fn extract_effects(check_json :: jv.Json) -> Result[List[Str], e.Errors] {
  match jv.get_field(check_json, "data") {
    None => Err(e.single("", "missing_field", "lex check JSON missing data.required_effects")),
    Some(data) => match jv.get_field(data, "required_effects") {
      Some(JList(items)) => Ok(list.fold(items, [], fn (acc :: List[Str], j :: jv.Json) -> List[Str] {
        match j {
          JStr(s) => list.concat(acc, [s]),
          _ => acc,
        }
      })),
      Some(_) => Err(e.single("", "invalid_field", "lex check JSON data.required_effects must be a list")),
      None => Err(e.single("", "missing_field", "lex check JSON missing data.required_effects")),
    },
  }
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let path := util.field_str_or(args, "path", ".")
  let mode := "refactor"
  match proc.spawn("lex", ["--output", "json", "check", path]) {
    Err(msg) => Err(e.single("", "proc_error", msg)),
    Ok(out) => if out.exit_code != 0 {
      Err(e.single("", "lex_check_failed", str.concat(out.stdout, out.stderr)))
    } else {
      match jv.parse(out.stdout) {
        Err(_) => Err(e.single("", "parse_error", "could not parse lex check output")),
        Ok(parsed) => {
          match extract_effects(parsed) {
            Err(errs) => Err(errs),
            Ok(required) => {
              let forbidden := forbidden_for_mode(mode)
              let violated := violations(required, forbidden)
              if list.len(violated) == 0 {
                Ok(JStr(str.concat("grant check passed [mode=", str.concat(mode, str.concat("] effects=", str.join(required, ","))))))
              } else {
                Err(e.single("", "grant_violation", str.join([
                  "GRANT VIOLATION [mode=", mode, "]\n",
                  "  forbidden effects used: ", str.join(violated, ", "), "\n",
                  "  all required effects:   ", str.join(required, ", "), "\n",
                  "  grant allows:           ", grant_summary_for_mode(mode)
                ], "")))
              }
            },
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

fn tool() -> t.Tool {
  t.define("os_check", "Check a Lex file's declared effects against the refactor-mode trust grant (lex-os integration). Run after lex_check to catch grant violations — e.g. a refactor agent must not use net effects. The grant mode is fixed by the tool and cannot be overridden by model input. Returns GRANT VIOLATION with details if the file exceeds the refactor grant.", params(), execute)
}
