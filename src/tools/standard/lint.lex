import "std.io" as io

import "std.str" as str

import "std.proc" as proc

import "std.list" as list

import "std.int" as int

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

# Files at or below this many lines have their full on-disk content echoed
# back to the agent even when `lex fmt` made no change. Larger files are only
# echoed when formatting actually rewrote them, to avoid flooding context.
fn readback_limit() -> Int {
  200
}

fn count_lines(content :: Str) -> Int {
  list.len(str.split(content, "\n"))
}

fn is_lex_file(path :: Str) -> Bool {
  match str.strip_suffix(path, ".lex") {
    Some(_) => true,
    None => false,
  }
}

# Translate a raw lex check output line into a human-readable fix hint.
fn translate_error(raw :: Str) -> Str {
  match jv.parse_into_errors(str.trim(raw)) {
    Ok(j) => {
      let kind := match jv.get_field(j, "kind") {
        Some(JStr(s)) => s,
        _ => "",
      }
      let tag := match jv.get_field(j, "rule_tag") {
        Some(JStr(s)) => s,
        _ => "",
      }
      if kind == "unknown_identifier" {
        let name := match jv.get_field(j, "name") {
          Some(JStr(s)) => s,
          _ => "?",
        }
        let stdlib_modules := ["list", "str", "int", "float", "io", "fs", "http", "sql", "env", "conc", "json", "regex"]
        let is_stdlib := match list.head(list.filter(stdlib_modules, fn (m :: Str) -> Bool {
          m == name
        })) {
          Some(_) => true,
          None => false,
        }
        if is_stdlib {
          str.concat("fix: add `import \"std.", str.concat(name, str.concat("\" as ", str.concat(name, "` at the top of the file.\n"))))
        } else {
          str.concat("unknown identifier '", str.concat(name, "' — check for typos or missing import."))
        }
      } else {
        if kind == "unknown_field" {
          let field := match jv.get_field(j, "field") {
            Some(JStr(s)) => s,
            _ => "?",
          }
          if field == "join" {
            "fix: use `str.join(parts, sep)` from `std.str`, not `list.join`."
          } else {
            if field == "find" {
              "fix: `list.find` does not exist. Use `list.filter(xs, pred)` + `list.head(...)`, or `list.fold`."
            } else {
              if field == "any" {
                "fix: `list.any` does not exist. Use `list.fold(xs, false, fn (acc :: Bool, x :: T) -> Bool { if acc { true } else { pred(x) } })`."
              } else {
                if field == "all" {
                  "fix: `list.all` does not exist. Use `list.fold(xs, true, fn (acc :: Bool, x :: T) -> Bool { if acc { pred(x) } else { false } })`."
                } else {
                  str.concat("unknown field '", str.concat(field, "' — check the type definition or stdlib docs."))
                }
              }
            }
          }
        } else {
          if kind == "type_mismatch" {
            let tm_context := match jv.get_field(j, "context") {
              Some(JList(parts)) => match list.head(parts) {
                Some(JStr(s)) => s,
                _ => "",
              },
              _ => "",
            }
            let tm_expected := match jv.get_field(j, "expected") {
              Some(JStr(s)) => s,
              _ => "",
            }
            let tm_got := match jv.get_field(j, "got") {
              Some(JStr(s)) => s,
              _ => "",
            }
            if str.contains(tm_expected, "Option[") {
              "type_mismatch: `list.head(xs)` returns `Option[T]`, not `T`. Unwrap it first: `match list.head(xs) { Some(v) => ..., None => ... }`. Never compare `list.head(xs)` directly with `==`."
            } else {
              if str.contains(tm_got, "Option[") {
                str.concat("type_mismatch: got `Option[T]` where `", str.concat(tm_expected, "` is expected — unwrap with `match ... { Some(v) => v, None => default }`."))
              } else {
                str.concat("[type-mismatch] expected `", str.concat(tm_expected, str.concat("`, got `", str.concat(tm_got, "` — check the types at the indicated position."))))
              }
            }
          } else {
            if kind == "unknown_variant" {
              let variant := match jv.get_field(j, "constructor") {
                Some(JStr(s)) => s,
                _ => "?",
              }
              if variant == "True" {
                "fix: use `true` (lowercase) — Lex booleans are lowercase."
              } else {
                if variant == "False" {
                  "fix: use `false` (lowercase) — Lex booleans are lowercase."
                } else {
                  str.concat("unknown variant '", str.concat(variant, "' — check the type definition."))
                }
              }
            } else {
              let explanation := match jv.get_field(j, "rule_explanation") {
                Some(JStr(s)) => s,
                _ => raw,
              }
              str.concat("[", str.concat(tag, str.concat("] ", explanation)))
            }
          }
        }
      }
    },
    Err(_) => {
      let s := str.trim(raw)
      if str.contains(s, "unrecognized token `&`") {
        "parse error: `&&` is not a Lex operator. Use nested `if`: `if a { b } else { false }` for AND, `if a { true } else { b }` for OR."
      } else {
        if str.contains(s, "unrecognized token `|`") {
          "parse error: `||` is not a Lex operator. Use nested `if`: `if a { true } else { b }` for OR."
        } else {
          if str.contains(s, "expected LBrace before block, got If") {
            "parse error: `else if` is not valid in Lex. Write `else { if cond { ... } else { ... } }` instead."
          } else {
            if str.contains(s, "expected pattern, got Some(LBracket)") {
              "parse error: list pattern matching `[x, y, ...]` is not supported. Use `if list.is_empty(xs)` / `list.head(xs)` / `list.tail(xs)` instead."
            } else {
              if str.contains(s, "expected type expression, got Some(Bar)") {
                "parse error: type definitions cannot start with `|`. Write `type T = A | B`, not `type T = | A | B`."
              } else {
                if str.contains(s, "expected LParen before lambda params") {
                  "parse error: local `fn` definitions inside function bodies are not allowed. Move helpers to the top level."
                } else {
                  if str.contains(s, "expected ColonColon after parameter name") {
                    "parse error: all function and lambda parameters need a type annotation: `param :: Type`. Example: `fn (x :: Int) -> Int { x + 1 }`."
                  } else {
                    if str.contains(s, "expected expression, got Some(Comma)") {
                      "parse error: `let` bindings inside a block need NO trailing comma — just write them on separate lines. Commas only appear between match arms."
                    } else {
                      s
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
  }
}

# Build the success message for a write/edit, appending the canonical on-disk
# content when `lex fmt` changed the file (so it differs from what the agent
# generated) or when the file is small enough to echo wholesale. This grounds
# the agent's next action in the real on-disk content rather than its
# generation buffer.
fn success_message(verb :: Str, path :: Str, written :: Str, on_disk :: Str) -> Str {
  let changed := on_disk != written
  let n := count_lines(on_disk)
  let base := if changed {
    str.concat(verb, str.concat(" ", str.concat(path, "\nlex fmt: auto-formatted — on-disk content differs from what you wrote\nlex check: ok")))
  } else {
    str.concat(verb, str.concat(" ", str.concat(path, "\nlex check: ok")))
  }
  let include := if changed {
    true
  } else {
    if n <= readback_limit() {
      true
    } else {
      false
    }
  }
  if include {
    str.concat(base, str.concat("\n\nactual content (", str.concat(int.to_str(n), str.concat(" lines):\n\n", on_disk))))
  } else {
    base
  }
}

# Run `lex fmt` + `lex check` on a just-written file and produce the tool
# result. For `.lex` files this auto-formats, type-checks, and reads the
# canonical content back; non-lex files are echoed back when small. `written`
# is the content the caller wrote, used to detect whether `lex fmt` rewrote it.
fn finalize(path :: Str, written :: Str, verb :: Str) -> [net, io, proc] Result[jv.Json, e.Errors] {
  if is_lex_file(path) {
    let __lex_discard_1 := proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" fmt ", path)])
    match proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" check ", path)]) {
      Err(msg) => Ok(JStr(str.concat(verb, str.concat(" ", str.concat(path, str.concat("\nlex check error: ", msg)))))),
      Ok(out) => {
        let check_raw := str.trim(str.concat(out.stdout, out.stderr))
        if out.exit_code == 0 {
          match io.read(path) {
            Err(_) => Ok(JStr(str.concat(verb, str.concat(" ", str.concat(path, "\nlex check: ok"))))),
            Ok(on_disk) => Ok(JStr(success_message(verb, path, written, on_disk))),
          }
        } else {
          let hint := translate_error(check_raw)
          Err(e.single("", "lex_check_failed", str.concat(verb, str.concat(" ", str.concat(path, str.concat(" but lex check failed — fix and rewrite:\n", hint))))))
        }
      },
    }
  } else {
    Ok(JStr(str.concat(verb, str.concat(" ", path))))
  }
}

