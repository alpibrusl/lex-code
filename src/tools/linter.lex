import "std.proc" as proc

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

type LintOutcome = LintOk(Str) | LintChanged(Str) | LintWarn((Str, Str)) | LintFail((Str, Str))

type RunResult = { summary :: Str, failed :: Bool }

# Translate raw lex check JSON output into a human-readable fix hint.
fn translate_lex_error(raw :: Str) -> Str {
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
          str.concat("fix: add `import \"std.", str.concat(name, str.concat("\" as ", str.concat(name, "` at the top of the file."))))
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
            let tm_expected := match jv.get_field(j, "expected") {
              Some(JStr(s)) => s,
              _ => "",
            }
            let tm_got := match jv.get_field(j, "got") {
              Some(JStr(s)) => s,
              _ => "",
            }
            if str.contains(tm_expected, "Option[") {
              "type_mismatch: `list.head(xs)` returns `Option[T]`, not `T`. Unwrap it first: `match list.head(xs) { Some(v) => ..., None => ... }`. Never compare directly with `==`."
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

fn run_lex_fmt(path :: Str) -> [proc] LintOutcome {
  match proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" fmt ", path)]) {
    Err(msg) => LintWarn("lex fmt", str.concat("could not run: ", msg)),
    Ok(out) => if out.exit_code == 0 {
      if str.contains(str.trim(out.stdout), "reformatted") {
        LintChanged("lex fmt")
      } else {
        LintOk("lex fmt")
      }
    } else {
      LintWarn("lex fmt", str.trim(str.concat(out.stdout, out.stderr)))
    },
  }
}

fn run_lex_check(path :: Str) -> [proc] LintOutcome {
  match proc.spawn("bash", ["-c", str.concat("\"${LEX:-lex}\" check ", path)]) {
    Err(msg) => LintFail("lex check", str.concat("could not run: ", msg)),
    Ok(out) => if out.exit_code == 0 {
      LintOk("lex check")
    } else {
      let raw := str.trim(str.concat(out.stdout, out.stderr))
      LintFail("lex check", translate_lex_error(raw))
    },
  }
}

fn format_outcome(outcome :: LintOutcome) -> Str {
  match outcome {
    LintOk(name) => str.concat("lint[", str.concat(name, "]: ok")),
    LintChanged(name) => str.concat("lint[", str.concat(name, "]: auto-formatted — file on disk differs from what you wrote")),
    LintWarn(name, msg) => str.concat("lint[", str.concat(name, str.concat("]: warning — ", msg))),
    LintFail(name, msg) => str.concat("lint[", str.concat(name, str.concat("]: FAILED — ", msg))),
  }
}

fn has_failure(outcomes :: List[LintOutcome]) -> Bool {
  match list.head(list.filter(outcomes, fn (o :: LintOutcome) -> Bool {
    match o {
      LintFail(_, _) => true,
      _ => false,
    }
  })) {
    Some(_) => true,
    None => false,
  }
}

fn join_lines(lines :: List[Str]) -> Str {
  list.fold(lines, "", fn (acc :: Str, line :: Str) -> Str {
    if str.is_empty(acc) {
      line
    } else {
      str.concat(acc, str.concat("\n", line))
    }
  })
}

fn run_for_lex(path :: Str) -> [proc] RunResult {
  let fmt := run_lex_fmt(path)
  let check := run_lex_check(path)
  let outcomes := [fmt, check]
  let lines := list.map(outcomes, format_outcome)
  { summary: join_lines(lines), failed: has_failure(outcomes) }
}

# Run all linters appropriate for the given file path, keyed by extension.
# Returns a summary string and whether any blocking failure occurred.
# Add new extension branches here to extend coverage.
fn run(path :: Str) -> [proc] RunResult {
  match str.strip_suffix(path, ".lex") {
    Some(_) => run_for_lex(path),
    None => { summary: "", failed: false },
  }
}

