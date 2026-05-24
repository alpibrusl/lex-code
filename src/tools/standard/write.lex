import "std.io" as io

import "std.str" as str

import "std.proc" as proc

import "std.list" as list

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../util" as util

fn params() -> s.ModelSchema {
  { title: "WriteArgs", description: "Arguments for writing a file", fields: [s.required_str("path", []), s.required_str("content", [])] }
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

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  match util.field_str(args, "path") {
    None => Err(e.single("", "missing_field", "path is required")),
    Some(path) => match util.field_str(args, "content") {
      None => Err(e.single("", "missing_field", "content is required")),
      Some(content) => match io.write(path, content) {
        Err(msg) => Err(e.single("", "io_error", msg)),
        Ok(_) => {
          let is_lex := match str.strip_suffix(path, ".lex") {
            Some(_) => true,
            None => false,
          }
          if is_lex {
            let __lex_discard_1 := proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" fmt ", path)])
            match proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" check ", path)]) {
              Err(msg) => Ok(JStr(str.concat("wrote ", str.concat(path, str.concat("\nlex check error: ", msg))))),
              Ok(out) => {
                let check_raw := str.trim(str.concat(out.stdout, out.stderr))
                if out.exit_code == 0 {
                  Ok(JStr(str.concat("wrote ", str.concat(path, "\nlex check: ok"))))
                } else {
                  let hint := translate_error(check_raw)
                  Err(e.single("", "lex_check_failed", str.concat("wrote ", str.concat(path, str.concat(" but lex check failed — fix and rewrite:\n", hint)))))
                }
              },
            }
          } else {
            Ok(JStr(str.concat("wrote ", path)))
          }
        },
      },
    },
  }
}

fn tool() -> t.Tool {
  t.define("write", "Write content to a file, creating or overwriting it entirely. For .lex files, auto-formats and runs lex check automatically — if it fails, the error includes a specific fix hint. Keep calling write until it returns ok.", params(), execute)
}

