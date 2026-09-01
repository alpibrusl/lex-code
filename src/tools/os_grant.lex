# lex-code — trust-grant arithmetic for os_check
#
# Split out of os_check.lex so it can be tested. os_check.lex shells out
# to `lex check` and so carries [net, io, proc]; a test importing it would
# inherit that whole footprint and be refused by the `lex test` grant
# (crypto, fs_read, fs_write, io, random, sql, time) before a single
# assertion ran. Everything here is pure and declares no effects.
#
# This is the security-relevant half: which effects a mode forbids, and
# whether a file's declared effects violate them.

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

# Every effect name the trust lattice classifies as network egress —
# `lex-types::trust::is_network_effect` matches all four, not just `net`.
# Denying only `net` let a file declaring [llm_cloud] or [mcp] pass a
# grant whose net column is `none`.
fn network_effects() -> List[Str] {
  ["net", "http", "mcp", "llm_cloud"]
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
    list.concat(network_effects(), ["proc", "fs_write"])
  } else {
    if mode == "bar" {
      list.concat(network_effects(), ["fs_write"])
    } else {
      if mode == "spec" {
        list.concat(network_effects(), ["proc"])
      } else {
        if mode == "test" or mode == "refactor" {
          network_effects()
        } else {
          []
        }
      }
    }
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

fn malformed(detail :: Str) -> e.Errors {
  e.single("", "malformed_check_output", str.concat(detail, " — cannot verify the grant, refusing to report a pass"))
}

# Fold the JSON array into `List[Str]`, refusing the whole list if any
# element is not a string: an effect we cannot read is an effect we
# cannot check, and dropping it silently would report a false pass.
fn collect_effect_names(items :: List[jv.Json]) -> Result[List[Str], e.Errors] {
  list.fold(items, Ok([]), fn (acc :: Result[List[Str], e.Errors], j :: jv.Json) -> Result[List[Str], e.Errors] {
    match acc {
      Err(errs) => Err(errs),
      Ok(names) => match j {
        JStr(name) => Ok(list.concat(names, [name])),
        _ => Err(malformed("`data.required_effects` holds a non-string element")),
      },
    }
  })
}

# Fails closed on every shape it does not recognise. The previous version
# returned `[]` for a missing or malformed field, which read downstream as
# "no effects required" and so as "grant check passed".
fn extract_effects(check_json :: jv.Json) -> Result[List[Str], e.Errors] {
  match jv.get_field(check_json, "data") {
    None => Err(malformed("lex check output has no `data` field")),
    Some(data) => match jv.get_field(data, "required_effects") {
      None => Err(malformed("lex check output has no `data.required_effects` field")),
      Some(JList(items)) => collect_effect_names(items),
      _ => Err(malformed("`data.required_effects` is not a list")),
    },
  }
}

# The verdict for one file under one mode. `Err` on violation, so the
# agent loop treats it the way it treats a failed `lex check` — a signal
# to fix and retry, not a string to read past.
fn verdict(mode :: Str, required :: List[Str]) -> Result[jv.Json, e.Errors] {
  let violated := violations(required, forbidden_for_mode(mode))
  if list.len(violated) == 0 {
    Ok(JStr(str.join(["grant check passed [mode=", mode, "] effects=", str.join(required, ",")], "")))
  } else {
    Err(e.single("", "grant_violation", str.join(["GRANT VIOLATION [mode=", mode, "]\n", "  forbidden effects used: ", str.join(violated, ", "), "\n", "  all required effects:   ", str.join(required, ", "), "\n", "  grant allows:           ", grant_summary_for_mode(mode)], "")))
  }
}

fn description_for_mode(mode :: Str) -> Str {
  str.join(["Check a Lex file's declared effects against the ", mode, " trust grant (lex-os integration). Run after lex_check to catch grant violations — e.g. a refactor agent must not use net effects. Returns an error naming the forbidden effects if the file exceeds the grant (", grant_summary_for_mode(mode), ")."], "")
}

