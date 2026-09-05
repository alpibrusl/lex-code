# bar_check — run the repository-answerable part of the minimum bar
#
# The tool deliberately returns BOTH halves of the ledger: the probe
# results, and the items no probe can settle. Returning only what it
# could check would let a walk quietly end at six of fourteen items and
# read as a pass.

import "std.int" as int

import "std.list" as list

import "std.str" as str

import "lex-llm/tool" as t

import "lex-schema/json_value" as jv

import "lex-schema/error" as e

import "lex-schema/schema" as s

import "../bar/checks" as checks

import "../bar/ledger" as ledger

import "./effect_minimality" as effmin

import "./util" as util

fn params() -> s.ModelSchema {
  { title: "BarCheckArgs", description: "Arguments for the minimum-bar probes", fields: [s.optional(s.required_str("root", [])), s.optional(s.required_str("path", [])), s.optional(s.required_str("item", []))] }
}

fn open_items() -> Str {
  let unprobed := list.filter(ledger.all_items(), fn (i :: ledger.Item) -> Bool {
    match i.probe {
      None => true,
      Some(_) => false,
    }
  })
  str.join(["\nITEMS NO PROBE CAN SETTLE — ", int.to_str(list.len(unprobed)), " of ", int.to_str(ledger.item_count()), ". Each one still needs an answer: an attested claim (who, when, what evidence) for the `attested` tier, or reasoning for the `judgement` tier. Do not report a walk as complete until every one of these has been put to the user.\n\n", str.join(list.map(unprobed, ledger.render_item), "\n")], "")
}

fn run_one(root :: Str, path :: Str, id :: Str) -> [io, proc] Result[jv.Json, e.Errors] {
  match ledger.by_id(id) {
    None => Err(e.single("", "unknown_item", str.join(["no bar item with id '", id, "'. Known ids: ", str.join(list.map(ledger.all_items(), fn (i :: ledger.Item) -> Str {
      i.id
    }), ", ")], ""))),
    Some(item) => match item.probe {
      None => Ok(JStr(str.join([ledger.render_item(item), "\nThis item has no probe. Ask the user for it directly and record the answer verbatim — a missing answer is 'not done', never 'assumed fine'."], ""))),
      Some(_) => Ok(JStr(str.join([ledger.render_item(item), "\n", str.join(list.map(list.filter(checks.run_all(root, path), fn (p :: checks.Probe) -> Bool {
        match item.probe {
          None => false,
          Some(want) => p.id == want,
        }
      }), checks.render), "\n")], ""))),
    },
  }
}

# Lex-native evidence the ledger's two source books have no way to ask
# for — they were written for prose checklists, not a typed effect
# system — so this is deliberately a separate section, not a 15th
# ledger item pretending to be sourced from either book (#121). #119's
# effect_minimality probe is the first signal here: a declared effect
# row wider than the body needs, something no general-purpose review
# tool could check at all.
fn lex_native_signals(path :: Str) -> [io, proc] Str {
  str.join(["\nLEX-NATIVE SIGNALS — not from either source book; specific to what a typed effect system can prove about itself.\n\n", effmin.report(path)], "")
}

fn run_walk(root :: Str, path :: Str) -> [io, proc] Result[jv.Json, e.Errors] {
  let probes := checks.run_all(root, path)
  Ok(JStr(str.join(["MINIMUM BAR — repository probes over ", root, "\n\n", str.join(list.map(probes, checks.render), "\n\n"), "\n", lex_native_signals(path), "\n", open_items()], "")))
}

fn execute(args :: jv.Json) -> [net, io, proc] Result[jv.Json, e.Errors] {
  let root := util.field_str_or(args, "root", ".")
  let path := util.field_str_or(args, "path", "src")
  match util.field_str(args, "item") {
    None => run_walk(root, path),
    Some(id) => run_one(root, path, id),
  }
}

fn tool() -> t.Tool {
  t.define("bar_check", "Walk the minimum-bar ledger over a repository. With no `item`, runs every repository-answerable probe (secrets in history, git remote, tests, CI on PRs, toolchain pin drift, examples {} coverage) and then lists the bar items no probe can settle. With `item`, reports just that ledger item. `root` defaults to '.', `path` (for examples coverage) to 'src'.", params(), execute)
}

