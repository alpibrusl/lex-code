# lex-code — the minimum-bar ledger
#
# The canon for BAR mode: every item lex-code will walk a project
# against, where it comes from, and — the load-bearing part — whether a
# machine can answer it at all.
#
# Source: the two "short version" cards, which each book presents as the
# five items with the worst consequence-to-effort ratio in it:
#   - *Prompt to Production*, ch. 16 "The Minimum Bar"
#   - *Prompt to Evidence*,   ch. 15 "The Minimum Bar"
# Plus four items from *Prompt to Production*'s full checklist that a
# repository can answer about itself without leaving the repository.
#
# Why a Lex module and not a `bar.yaml`: the books' own gate reads a
# YAML ledger (`glossary.yaml`) because its authors write prose, not
# code. Here the ledger's readers are the type checker and CI, which
# already run over `src/**.lex` — so a typed module gets arity and
# variant checking for free, the `examples {}` blocks below are the
# ledger's own regression tests, and there is no parse-failure path to
# design. The cost is that adding an item needs `lex fmt`.
#
# Tiers are the honest part. `Repo` items a probe in ./checks can
# decide. `Attested` items no coding agent can verify — "a restore has
# actually been performed" is a claim about the world — so the only
# truthful move is to record a dated human assertion, never a green
# tick. `Judgement` items need a person to think, and the prompt asks
# for the reasoning rather than a verdict.

import "./probe_ids" as pid

import "std.int" as int

import "std.list" as list

import "std.str" as str

type Book = Production | Evidence

type Tier = Repo | Attested | Judgement

type Item = { id :: Str, book :: Book, tier :: Tier, teaches :: Int, title :: Str, why :: Str, probe :: Option[Str] }

fn book_label(b :: Book) -> Str
  examples {
    book_label(Production) => "prompt-to-production",
    book_label(Evidence) => "prompt-to-evidence"
  }
{
  match b {
    Production => "prompt-to-production",
    Evidence => "prompt-to-evidence",
  }
}

fn tier_label(t :: Tier) -> Str
  examples {
    tier_label(Repo) => "repo",
    tier_label(Attested) => "attested",
    tier_label(Judgement) => "judgement"
  }
{
  match t {
    Repo => "repo",
    Attested => "attested",
    Judgement => "judgement",
  }
}

# ── The cards ───────────────────────────────────────────────────────────
# Five items each, verbatim in intent from the two books' "short version"
# sections. Four of the ten are the reason BAR mode exists at all: they
# are about backups, money and rehearsals, and nothing in a repository
# can settle them.
fn production_card() -> List[Item] {
  [{ id: "prod.backups-restored", book: Production, tier: Attested, teaches: 7, title: "Backups, with one restore actually performed", why: "A backup nobody has restored is an untested belief. The book's word is performed, not configured — so the record has to say who restored it, when, and how long it took.", probe: None }, { id: "prod.no-secrets", book: Production, tier: Repo, teaches: 5, title: "No secrets in the repository, ever, checked through the history", why: "Deleting a key in the current commit leaves it in the history. This is the one card item a scan can genuinely decide, within the bound it names.", probe: Some(pid.secret_scan()) }, { id: "prod.budget-alert", book: Production, tier: Attested, teaches: 13, title: "A budget alert on the cloud account", why: "The cheapest item in the book — four minutes — and invisible from inside the repository.", probe: None }, { id: "prod.errors-reported", book: Production, tier: Attested, teaches: 10, title: "Errors reported somewhere you will see them", why: "A dependency in a manifest proves a library is installed, never that anyone reads what it sends.", probe: None }, { id: "prod.rollback-rehearsed", book: Production, tier: Attested, teaches: 9, title: "A rollback you have rehearsed", why: "Same shape as the restore: a documented rollback and a performed one differ exactly on the day it matters.", probe: None }]
}

fn evidence_card() -> List[Item] {
  [{ id: "ev.computed-not-narrated", book: Evidence, tier: Judgement, teaches: 4, title: "Computed with real code, run and shown — not narrated", why: "In a Lex project the effect row is unusually good evidence here: a number that came from execution has a trace behind it, and a narrated one has nothing. Judgement until a probe can read the trace.", probe: None }, { id: "ev.known-answer", book: Evidence, tier: Repo, teaches: 7, title: "Tested against a case with a known answer before being trusted", why: "This is what an `examples {}` block is. AGENTS.md asks for one on every pure fn for regression reasons; the book asks for the same thing for correctness reasons, and it is the same block.", probe: Some(pid.examples_coverage()) }, { id: "ev.consistency-check", book: Evidence, tier: Judgement, teaches: 7, title: "Passed a consistency check against something already known", why: "The scalable form of suspicion. An extreme result fails this loudly; an ordinary-looking wrong one fails it quietly, which is why it runs on every result and not only the surprising ones.", probe: None }, { id: "ev.range-not-point", book: Evidence, tier: Judgement, teaches: 10, title: "A range, not just a headline number — narrow enough to decide with", why: "No Lex stdlib module produces an interval today (arrow gives mean and group-by; there is no inferential statistics module), so this cannot be probed and should not pretend to be.", probe: None }, { id: "ev.data-profiled", book: Evidence, tier: Judgement, teaches: 13, title: "The data has actually been looked at, not assumed to be fine", why: "Missing values counted, category spellings checked, ranges sanity-checked — cheap, and the source of most wrong numbers.", probe: None }]
}

# ── Repository-answerable items from the full checklist ─────────────────
# Not on either card, included because a repository can settle them
# about itself and a walk that only ever answers two of ten questions
# reads as theatre.
fn repo_extras() -> List[Item] {
  [{ id: "prod.remote-copy", book: Production, tier: Repo, teaches: 4, title: "In version control, with a remote copy that is not your laptop", why: "First item of the full checklist, and the cheapest to verify: a configured remote is either there or it is not.", probe: Some(pid.git_remote()) }, { id: "prod.tests-exist", book: Production, tier: Repo, teaches: 6, title: "Tests exist for the paths that must not break", why: "A probe can see that tests exist, never that they cover the paths that matter — so it reports what it found and leaves the coverage question to the walk.", probe: Some(pid.tests_present()) }, { id: "prod.ci-on-pr", book: Production, tier: Repo, teaches: 9, title: "Tests run automatically on every pull request and block the merge when red", why: "The first half is in the workflow file. The second half is branch protection, which lives in the forge and not in the repository — the probe says so rather than passing the whole item.", probe: Some(pid.ci_on_pr()) }, { id: "prod.pins-honest", book: Production, tier: Repo, teaches: 5, title: "What is pinned is pinned consistently", why: "The book's item is a committed lockfile. This ecosystem deliberately floats the lex-* packages while they move fast and pins only the lex-lang toolchain, so the checkable rule is the one that survives that choice: the pin that exists must agree everywhere it is written down.", probe: Some(pid.toolchain_pin()) }]
}

fn all_items() -> List[Item] {
  list.concat(production_card(), list.concat(evidence_card(), repo_extras()))
}

fn item_count() -> Int
  examples {
    item_count() => 14
  }
{
  list.len(all_items())
}

fn by_id(id :: Str) -> Option[Item] {
  list.head(list.filter(all_items(), fn (i :: Item) -> Bool {
    i.id == id
  }))
}

fn items_in_tier(t :: Tier) -> List[Item] {
  list.filter(all_items(), fn (i :: Item) -> Bool {
    tier_label(i.tier) == tier_label(t)
  })
}

# The number that decides whether this whole mode is worth having: how
# much of the bar a machine can actually settle. Six of fourteen. The
# other eight are why the walk exists.
fn probe_count() -> Int
  examples {
    probe_count() => 6
  }
{
  list.len(items_in_tier(Repo))
}

fn probe_ids() -> List[Str]
  examples {
    probe_ids() => ["secret_scan", "examples_coverage", "git_remote", "tests_present", "ci_on_pr", "toolchain_pin"]
  }
{
  list.fold(all_items(), [], fn (acc :: List[Str], i :: Item) -> List[Str] {
    match i.probe {
      None => acc,
      Some(p) => list.concat(acc, [p]),
    }
  })
}

# Rendered into the BAR system prompt, so the model walks the ledger
# rather than a checklist it half-remembers from training.
fn render_item(i :: Item) -> Str {
  str.join(["- ", i.id, " [", tier_label(i.tier), "] ", i.title, "\n  source: ", book_label(i.book), " ch. ", int.to_str(i.teaches), "\n  why: ", i.why, "\n  probe: ", match i.probe {
    None => "none — this item cannot be answered from the repository",
    Some(p) => p,
  }, "\n"], "")
}

fn render_all() -> Str {
  str.join(list.map(all_items(), render_item), "\n")
}

