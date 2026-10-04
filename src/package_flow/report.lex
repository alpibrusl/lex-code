# report.lex — what happened while nobody was watching.
#
# The dashboard is for someone looking at the run; this is for the person who
# comes back to it. It reads the same things the dashboard does (the plan, the
# issue store, the run's own log) and writes one Markdown page: the verdict,
# what each unit cost, what is still wrong and what was set aside on the way.
# Nothing here writes to the project; it prints.
#
# It reuses the dashboard's log parser on purpose: two readers of one log
# that disagree about what an attempt or a verdict is would be worse than none.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.fs" as fs

import "std.process" as process

import "lex-schema/json_value" as jv

import "./dashboard" as dash

fn lines_of(text :: Str) -> List[Str] {
  str.split(text, "\n")
}

fn starts_any(line :: Str, prefixes :: List[Str]) -> Bool {
  list.fold(prefixes, false, fn (hit :: Bool, p :: Str) -> Bool {
    hit or str.starts_with(line, p)
  })
}

# The log lines that start with one of `prefixes`, in order, trimmed of nothing:
# the report quotes them as the run printed them.
fn lines_starting(text :: Str, prefixes :: List[Str]) -> List[Str]
  examples {
    lines_starting("a\n[X] one\nb\n[Y] two", ["[X]", "[Y]"]) => ["[X] one", "[Y] two"],
    lines_starting("nothing here", ["[X]"]) => [],
    lines_starting("", ["[X]"]) => []
  }
{
  list.filter(lines_of(text), fn (l :: Str) -> Bool {
    starts_any(l, prefixes)
  })
}

type Block = { lines :: List[Str], open :: Bool }

# The LAST line starting with `prefix`, with the `  - …` lines that follow it.
# Earlier ones are rounds that were later repaired.
fn last_block(text :: Str, prefix :: Str) -> List[Str]
  examples {
    last_block("[A] 1/3:\n  - a\n  - b\n\n[A] 2/3:\n  - c\nnext", "[A] ") => ["[A] 2/3:", "  - c"],
    last_block("[A] 3/3 hold\n[A]\tpass\tp", "[A] ") => ["[A] 3/3 hold"],
    last_block("nothing here", "[A] ") => []
  }
{
  let end := list.fold(lines_of(text), { lines: [], open: false }, fn (b :: Block, l :: Str) -> Block {
    if str.starts_with(l, prefix) {
      { lines: [l], open: true }
    } else {
      if b.open and str.starts_with(l, "  - ") {
        { lines: list.concat(b.lines, [l]), open: true }
      } else {
        { lines: b.lines, open: false }
      }
    }
  })
  end.lines
}

# `[PROJECT_VERDICT]<TAB>word<TAB>project` -> word, the last one in the log.
fn verdict_of(text :: Str) -> Str
  examples {
    verdict_of("x\n[PROJECT_VERDICT]\tstuck\tp\ny\n[PROJECT_VERDICT]\tdone\tp") => "done",
    verdict_of("nothing") => "none yet"
  }
{
  let found := list.fold(lines_of(text), "none yet", fn (acc :: Str, l :: Str) -> Str {
    if str.starts_with(l, "[PROJECT_VERDICT]\t") {
      match list.head(list.tail(str.split(l, "\t"))) {
        Some(w) => w,
        None => acc,
      }
    } else {
      acc
    }
  })
  found
}

fn k(n :: Int) -> Str
  examples {
    k(0) => "0",
    k(999) => "999",
    k(1500) => "1.5k",
    k(2400000) => "2.4M"
  }
{
  if n >= 1000000 {
    str.join([int.to_str(n / 1000000), ".", int.to_str(n % 1000000 / 100000), "M"], "")
  } else {
    if n >= 1000 {
      str.join([int.to_str(n / 1000), ".", int.to_str(n % 1000 / 100), "k"], "")
    } else {
      int.to_str(n)
    }
  }
}

fn bullet_list(xs :: List[Str]) -> Str
  examples {
    bullet_list(["a", "  - b"]) => "- a\n  - b",
    bullet_list([]) => ""
  }
{
  str.join(list.map(xs, fn (x :: Str) -> Str {
    if str.starts_with(x, "  - ") {
      x
    } else {
      str.concat("- ", x)
    }
  }), "\n")
}

# How many attempts the run made on one issue, across every round: the log's
# own attempt counter restarts at 1 each time the build is resumed.
fn count_attempts(text :: Str, id :: Str) -> Int
  examples {
    count_attempts("[PROJECT] issue abc — attempt 1 on x\n[PROJECT] issue abc — attempt 2 on x\n[PROJECT] issue zzz — attempt 1 on x\n[PROJECT] issue abc — attempt 1 on x", "abc") => 3,
    count_attempts("nothing", "abc") => 0
  }
{
  list.len(list.filter(lines_of(text), fn (l :: Str) -> Bool {
    str.starts_with(l, str.join(["[PROJECT] issue ", id, " — attempt "], ""))
  }))
}

# (title, state) for every issue of the project, straight from the issue store:
# the authority on what is verified, which a log cannot be once a build has been
# resumed (a resumed run never prints "verified" for what an earlier one did).
# [] when the store cannot be asked, and the report then falls back to the log.
fn store_states(project :: Str) -> [proc] List[(Str, Str)] {
  match process.run("lex", ["--output", "json", "issue", "list", "--project", project]) {
    Err(_) => [],
    Ok(o) => match jv.parse(str.trim(o.stdout)) {
      Err(_) => [],
      Ok(j) => match jv.get_field(j, "data") {
        None => [],
        Some(d) => match jv.get_field(d, "issues") {
          None => [],
          Some(arr) => match jv.as_list(arr) {
            None => [],
            Some(items) => list.map(items, fn (it :: jv.Json) -> (Str, Str) {
              (dash.json_str_field(it, "title"), dash.json_str_field(it, "state"))
            }),
          },
        },
      },
    },
  }
}

fn state_of(states :: List[(Str, Str)], title :: Str) -> Str {
  list.fold(states, "", fn (acc :: Str, p :: (Str, Str)) -> Str {
    match p {
      (t, st) => if t == title {
        st
      } else {
        acc
      },
    }
  })
}

fn unit_row(u :: dash.PlanUnit, t2id :: List[(Str, Str)], st :: dash.LogState, text :: Str, states :: List[(Str, Str)]) -> Str {
  let from_store := state_of(states, u.title)
  let us0 := dash.unit_status(u.title, t2id, st)
  let us := if str.is_empty(from_store) {
    us0
  } else {
    { status: from_store, attempt: us0.attempt }
  }
  let usage := dash.unit_usage(u.title, t2id, st)
  let tries := match dash.assoc_get(t2id, u.title) {
    None => "",
    Some(id) => int.to_str(count_attempts(text, id)),
  }
  str.join(["| `", u.key, "` | ", us.status, " | ", if str.is_empty(tries) or tries == "0" {
    "-"
  } else {
    tries
  }, " | ", k(usage.prompt), " / ", k(usage.completion), " |"], "")
}

fn nth(xs :: List[Str], i :: Int) -> Str
  examples {
    nth(["a", "b"], 1) => "b",
    nth(["a"], 3) => "",
    nth([], 0) => ""
  }
{
  match list.head(xs) {
    None => "",
    Some(x) => if i <= 0 {
      x
    } else {
      nth(list.tail(xs), i - 1)
    },
  }
}

# One row per supervisor round, from `rounds.tsv`:
# round, start, end, verdict, verified, acceptance, thinking, note (tab-separated).
fn rounds_table(tsv :: Str) -> Str
  examples {
    rounds_table("") => "",
    rounds_table("1\t100\t460\tstuck\t3\t-\tfalse\t") => "| round | minutes | verdict | verified | acceptance | thinking | note |\n|---|---|---|---|---|---|---|\n| 1 | 6 | stuck | 3 | - | false |  |"
  }
{
  let rows := list.filter(lines_of(tsv), fn (l :: Str) -> Bool {
    not str.is_empty(str.trim(l))
  })
  if list.is_empty(rows) {
    ""
  } else {
    let body := list.map(rows, fn (l :: Str) -> Str {
      let f := str.split(l, "\t")
      let at := fn (i :: Int) -> Str {
        nth(f, i)
      }
      let mins := match str.to_int(at(2)) {
        Some(e) => match str.to_int(at(1)) {
          Some(s) => int.to_str((e - s) / 60),
          None => "?",
        },
        None => "?",
      }
      str.join(["| ", at(0), " | ", mins, " | ", at(3), " | ", at(4), " | ", at(5), " | ", at(6), " | ", at(7), " |"], "")
    })
    str.join(["| round | minutes | verdict | verified | acceptance | thinking | note |\n|---|---|---|---|---|---|---|\n", str.join(body, "\n")], "")
  }
}

fn section(title :: Str, body :: Str) -> Str {
  if str.is_empty(body) {
    ""
  } else {
    str.join(["\n## ", title, "\n\n", body, "\n"], "")
  }
}

fn read_or_empty(path :: Str) -> [fs_read] Str {
  dash.read_or_empty(path)
}

# The whole page. `log_path` is every round's output concatenated; `rounds_path`
# is the supervisor's own table (either may be missing: the report still says
# what it can).
fn report_md(project :: Str, log_path :: Str, rounds_path :: Str) -> [fs_read, fs_walk, proc] Str {
  let states := store_states(project)
  let text := read_or_empty(log_path)
  let st := dash.parse_log(text, project)
  let units := dash.parse_units(read_or_empty(str.join([".lex/plans/", project, ".json"], "")))
  let t2id := dash.title_to_id(".lex/store/issues")
  let verdict := verdict_of(text)
  let verified := if list.is_empty(states) {
    list.len(list.filter(units, fn (u :: dash.PlanUnit) -> Bool {
      dash.unit_status(u.title, t2id, st).status == "verified"
    }))
  } else {
    list.len(list.filter(units, fn (u :: dash.PlanUnit) -> Bool {
      state_of(states, u.title) == "verified"
    }))
  }
  let acceptance := last_block(text, "[ACCEPTANCE] ")
  let defects := lines_starting(text, ["[PROJECT] ⚠ not retrying"])
  let skipped := last_block(text, "[PLAN] contradiction")
  let warnings := lines_starting(text, ["[PROJECT] ⚠ the assembled", "[PROJECT] ⚠ still stubbed", "[PROJECT] ⚠ STOPPING", "[PROJECT] stuck:", "[PROJECT] the provider"])
  let repairs := lines_starting(text, ["[REPAIR]"])
  let plan_u := dash.find_usage(st.usage, "plan")
  let total_u := dash.usage_total(st.usage)
  let unit_rows := list.map(units, fn (u :: dash.PlanUnit) -> Str {
    unit_row(u, t2id, st, text, states)
  })
  let head := str.join(["# ", project, " — overnight report\n\n**Verdict:** `", if verdict == "none yet" {
    "none — the last round was stopped before it finished"
  } else {
    verdict
  }, "`   **Units verified:** ", int.to_str(verified), " / ", int.to_str(list.len(units)), if str.is_empty(st.gate) {
    ""
  } else {
    str.concat("   **Gate:** `", str.concat(st.gate, "`"))
  }, "\n"], "")
  let needs := list.concat(list.concat(list.concat(warnings, defects), skipped), if str.is_empty(st.stuck) {
    []
  } else {
    [str.concat("stuck — gave up on: ", st.stuck)]
  })
  str.join([head, section("Acceptance (last run)", if list.is_empty(acceptance) {
    ""
  } else {
    str.join(["```\n", str.join(acceptance, "\n"), "\n```"], "")
  }), section("Needs attention", bullet_list(needs)), section("Repair rounds", bullet_list(repairs)), section("Rounds", rounds_table(read_or_empty(rounds_path))), section("Units", if list.is_empty(unit_rows) {
    ""
  } else {
    str.join(["| unit | status | attempts | tokens in / out |\n|---|---|---|---|\n", str.join(unit_rows, "\n")], "")
  }), section("Tokens", str.join(["planner ", k(plan_u.prompt), " in / ", k(plan_u.completion), " out; whole run ", k(total_u.prompt), " in / ", k(total_u.completion), " out"], ""))], "")
}

fn run_report(project :: Str, log_path :: Str, rounds_path :: Str) -> [io, fs_read, fs_walk, proc] Nil {
  io.print(report_md(project, log_path, rounds_path))
}

