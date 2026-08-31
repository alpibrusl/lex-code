# Tests for the minimum-bar ledger and its probes.
#
# The probes themselves are not exercised here: they shell out to git,
# find and grep, and CI runs `lex test` without the `proc` effect. What
# is tested is everything a wrong edit to the ledger could break
# silently:
#
#   1. IDS ARE UNIQUE — two items claiming one id makes by_id lie.
#   2. TIER AND PROBE AGREE — a Repo item with no probe is an item the
#      walk thinks is automated and never asks about; an Attested item
#      WITH a probe claims to have settled something it cannot.
#   3. THE WIRING HOLDS — every probe the ledger names is one of the
#      canonical ids, and all of them are named. A ledger item pointing
#      at a probe nobody implements would be skipped in silence, which
#      is the exact failure the ledger exists to prevent. (src/bar/checks
#      is deliberately NOT imported here: it declares [proc], and `lex
#      test` runs without it — probe_ids is the pure module both sides
#      share.)
#   4. THE CARDS ARE INTACT — five items from each book. The books call
#      these the five with the worst consequence-to-effort ratio in
#      them; losing one in an edit should be a red build.

import "std.list" as list

import "std.io" as io

import "std.str" as str

import "../src/bar/probe_ids" as pid

import "../src/bar/ledger" as ledger

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn ids() -> List[Str] {
  list.map(ledger.all_items(), fn (i :: ledger.Item) -> Str {
    i.id
  })
}

fn occurrences(xs :: List[Str], want :: Str) -> Int {
  list.len(list.filter(xs, fn (x :: Str) -> Bool {
    x == want
  }))
}

fn contains_all(haystack :: List[Str], needles :: List[Str]) -> Bool {
  list.fold(needles, true, fn (acc :: Bool, n :: Str) -> Bool {
    acc and occurrences(haystack, n) > 0
  })
}

fn test_ids_unique() -> Result[Unit, Str] {
  let all := ids()
  check("every item id appears exactly once", list.fold(all, true, fn (acc :: Bool, id :: Str) -> Bool {
    acc and occurrences(all, id) == 1
  }))
}

fn test_tier_and_probe_agree() -> Result[Unit, Str] {
  check("a probe is named by exactly the Repo-tier items", list.fold(ledger.all_items(), true, fn (acc :: Bool, i :: ledger.Item) -> Bool {
    let has_probe := match i.probe {
      None => false,
      Some(_) => true,
    }
    acc and has_probe == (ledger.tier_label(i.tier) == "repo")
  }))
}

fn test_probe_wiring_holds() -> Result[Unit, Str] {
  let named := ledger.probe_ids()
  let built := pid.all()
  check("ledger probe ids and the canonical probe ids are the same set", list.len(named) == list.len(built) and contains_all(built, named) and contains_all(named, built))
}

fn test_cards_intact() -> Result[Unit, Str] {
  check("five card items from each book, fourteen in total", list.len(ledger.production_card()) == 5 and list.len(ledger.evidence_card()) == 5 and ledger.item_count() == 14)
}

# An unprobed item must render as one the repository cannot answer.
# This string is what stops a walk from quietly treating an unanswered
# attested item as fine.
fn test_unprobed_items_say_so() -> Result[Unit, Str] {
  let unprobed := list.filter(ledger.all_items(), fn (i :: ledger.Item) -> Bool {
    match i.probe {
      None => true,
      Some(_) => false,
    }
  })
  check("every unprobed item renders as unanswerable from the repository", list.len(unprobed) == 8 and list.fold(unprobed, true, fn (acc :: Bool, i :: ledger.Item) -> Bool {
    acc and str.contains(ledger.render_item(i), "cannot be answered from the repository")
  }))
}

fn suite() -> List[Result[Unit, Str]] {
  [test_ids_unique(), test_tier_and_probe_agree(), test_probe_wiring_holds(), test_cards_intact(), test_unprobed_items_say_so()]
}

fn run_all() -> [io] Unit {
  let results := suite()
  let __dbg := list.map(results, fn (r :: Result[Unit, Str]) -> [io] Unit {
    match r {
      Ok(_) => (),
      Err(e) => io.print(str.concat("FAIL: ", e)),
    }
  })
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __force_fail := 1 / 0
    ()
  }
}

