# dashboard.lex — a read-only, live view of one `--package --auto` run.
#
# Pure parsing: plan file + the run's own log text in, a status snapshot
# out. The HTTP server (bottom of the file) is the only effectful part —
# it just serves whatever `status_json` currently says, polled by a
# single static HTML page.
#
# `--auto` prints its progress to stdout; it does not write a log file of
# its own. This watches whatever file the run's own stdout was
# redirected to (the normal way to run a long `--auto` build in the
# background) — point `--log=` at it. Nothing here writes to that file,
# the plan file or the issue store.

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.time" as time

import "std.fs" as fs

import "std.net" as net

import "std.map" as map

import "lex-schema/json_value" as jv

fn json_str_field(j :: jv.Json, key :: Str) -> Str {
  match jv.get_field(j, key) {
    None => "",
    Some(v) => match jv.as_str(v) {
      Some(s) => s,
      None => "",
    },
  }
}

fn json_str_list_field(j :: jv.Json, key :: Str) -> List[Str] {
  match jv.get_field(j, key) {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(items) => list.fold(items, [], fn (acc :: List[Str], it :: jv.Json) -> List[Str] {
        match jv.as_str(it) {
          Some(s) => list.concat(acc, [s]),
          None => acc,
        }
      }),
    },
  }
}

type ApiSig = { name :: Str, signature :: Str }

type InvariantSig = { name :: Str, expr :: Str }

type PlanUnit = { key :: Str, title :: Str, body :: Str, deps :: List[Str], api :: List[ApiSig], examples :: List[Str], invariants :: List[InvariantSig] }

fn json_api_list(j :: jv.Json, key :: Str) -> List[ApiSig] {
  match jv.get_field(j, key) {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(items) => list.map(items, fn (it :: jv.Json) -> ApiSig {
        { name: json_str_field(it, "name"), signature: json_str_field(it, "signature") }
      }),
    },
  }
}

fn json_invariant_list(j :: jv.Json, key :: Str) -> List[InvariantSig] {
  match jv.get_field(j, key) {
    None => [],
    Some(v) => match jv.as_list(v) {
      None => [],
      Some(items) => list.map(items, fn (it :: jv.Json) -> InvariantSig {
        { name: json_str_field(it, "name"), expr: json_str_field(it, "expr") }
      }),
    },
  }
}

fn plan_project_name(plan_text :: Str) -> Str
  examples {
    plan_project_name("{\"project\": \"invoices\", \"units\": []}") => "invoices",
    plan_project_name("not json") => ""
  }
{
  match jv.parse(plan_text) {
    Err(_) => "",
    Ok(j) => json_str_field(j, "project"),
  }
}

fn parse_units(plan_text :: Str) -> List[PlanUnit] {
  match jv.parse(plan_text) {
    Err(_) => [],
    Ok(j) => match jv.get_field(j, "units") {
      None => [],
      Some(uj) => match jv.as_list(uj) {
        None => [],
        Some(units) => list.map(units, fn (u :: jv.Json) -> PlanUnit {
          { key: json_str_field(u, "key"), title: json_str_field(u, "title"), body: json_str_field(u, "body"), deps: json_str_list_field(u, "deps"), api: json_api_list(u, "api"), examples: json_str_list_field(u, "examples"), invariants: json_invariant_list(u, "invariants") }
        }),
      },
    },
  }
}

fn parse_type_names(plan_text :: Str) -> List[Str] {
  match jv.parse(plan_text) {
    Err(_) => [],
    Ok(j) => match jv.get_field(j, "types") {
      None => [],
      Some(tj) => match jv.as_list(tj) {
        None => [],
        Some(types) => list.map(types, fn (t :: jv.Json) -> Str {
          json_str_field(t, "name")
        }),
      },
    },
  }
}

# `after .. before`: the slice strictly between the first `after` and the
# next `before` that follows it, or None if either marker is missing.
fn between(s :: Str, after :: Str, before :: Str) -> Option[Str]
  examples {
    between("issue abc — attempt 3 on ollama", "issue ", " —") => Some("abc"),
    between("no marker here", "issue ", " —") => None
  }
{
  match str.find(s, after, 0) {
    None => None,
    Some(a_at) => {
      let start := a_at + str.len(after)
      match str.find(s, before, start) {
        None => None,
        Some(b_at) => Some(str.slice(s, start, b_at)),
      }
    },
  }
}

fn suffix_after(s :: Str, marker :: Str) -> Option[Str]
  examples {
    suffix_after("invoices  6/13 verified, 4 ready", "invoices  ") => Some("6/13 verified, 4 ready"),
    suffix_after("no marker", "xyz") => None
  }
{
  match str.find(s, marker, 0) {
    None => None,
    Some(i) => Some(str.slice(s, i + str.len(marker), str.len(s))),
  }
}

fn assoc_set(xs :: List[(Str, Str)], k :: Str, v :: Str) -> List[(Str, Str)] {
  let without := list.filter(xs, fn (p :: (Str, Str)) -> Bool {
    match p {
      (k2, _) => k2 != k,
    }
  })
  list.concat(without, [(k, v)])
}

fn assoc_get(xs :: List[(Str, Str)], k :: Str) -> Option[Str] {
  list.fold(xs, None, fn (acc :: Option[Str], p :: (Str, Str)) -> Option[Str] {
    match acc {
      Some(_) => acc,
      None => match p {
        (k2, v) => if k2 == k {
          Some(v)
        } else {
          None
        },
      },
    }
  })
}

# One row per issue id (or the literal label "plan" for the planner's turns):
# tokens summed over every attempt the run printed a [USAGE] line for.
type UsageRow = { id :: Str, prompt :: Int, completion :: Int, turns :: Int }

type LogState = { attempts :: List[(Str, Str)], verdicts :: List[(Str, Str)], agg :: Str, stuck :: Str, gate :: Str, exited :: Str, activity :: List[Str], usage :: List[UsageRow] }

fn empty_state() -> LogState {
  { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] }
}

fn apply_attempt(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PROJECT] issue ") and str.contains(line, " — attempt ") {
    match between(line, "[PROJECT] issue ", " —") {
      None => s,
      Some(id) => match between(line, "attempt ", " on") {
        None => s,
        Some(n) => { attempts: assoc_set(s.attempts, id, n), verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity, usage: s.usage },
      },
    }
  } else {
    s
  }
}

# The verdict word is read by CONTAINS, never by slicing past the arrow:
# `str.find`'s returned index and `str.len`'s count use different units for
# a multi-byte character like `→` (3 UTF-8 bytes), so the previous
# `suffix_after(line, "→ ")` sliced 2 bytes short — turning "verified" into
# "rified", which then failed `v == "verified"` and silently reported
# every verified unit as failed. The only two words `main.lex` ever prints
# here are "verified" and "failed" (confirmed against its own source), so
# checking for each by substring sidesteps the offset entirely rather than
# computing one.
fn apply_verdict(s :: LogState, line :: Str) -> LogState
  examples {
    apply_verdict(empty_state(), "[PROJECT] issue abc123 → verified") => { attempts: [], verdicts: [("abc123", "verified")], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] },
    apply_verdict(empty_state(), "[PROJECT] issue abc123 → failed") => { attempts: [], verdicts: [("abc123", "failed")], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] },
    apply_verdict(empty_state(), "nothing here") => empty_state(),
    apply_verdict(empty_state(), "some other line mentioning → failed in passing") => empty_state(),
    apply_verdict(empty_state(), "[PROJECT] issue abc123 → pending") => empty_state()
  }
{
  if str.contains(line, "[PROJECT] issue ") and str.contains(line, "→ verified") {
    match between(line, "[PROJECT] issue ", " →") {
      None => s,
      Some(id) => { attempts: s.attempts, verdicts: assoc_set(s.verdicts, id, "verified"), agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity, usage: s.usage },
    }
  } else {
    if str.contains(line, "[PROJECT] issue ") and str.contains(line, "→ failed") {
      match between(line, "[PROJECT] issue ", " →") {
        None => s,
        Some(id) => { attempts: s.attempts, verdicts: assoc_set(s.verdicts, id, "failed"), agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity, usage: s.usage },
      }
    } else {
      s
    }
  }
}

fn apply_aggregate(s :: LogState, line :: Str, project_marker :: Str) -> LogState {
  if str.contains(line, project_marker) and str.contains(line, "verified,") {
    match suffix_after(line, str.slice(project_marker, str.len("[PROJECT] "), str.len(project_marker))) {
      None => s,
      Some(rest) => { attempts: s.attempts, verdicts: s.verdicts, agg: str.trim(rest), stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity, usage: s.usage },
    }
  } else {
    s
  }
}

fn apply_stuck(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PROJECT] stuck: gave up") {
    match suffix_after(line, "attempts on: ") {
      None => s,
      Some(titles) => { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: titles, gate: s.gate, exited: s.exited, activity: s.activity, usage: s.usage },
    }
  } else {
    s
  }
}

fn apply_gate(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PACKAGE_GATE]") {
    match between(line, "[PACKAGE_GATE]\t", "\t") {
      None => s,
      Some(g) => { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: g, exited: s.exited, activity: s.activity, usage: s.usage },
    }
  } else {
    s
  }
}

fn apply_exit(s :: LogState, line :: Str) -> LogState {
  if str.starts_with(line, "EXIT ") {
    { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: str.slice(line, 5, str.len(line)), activity: s.activity, usage: s.usage }
  } else {
    s
  }
}

fn is_narration(line :: Str) -> Bool
  examples {
    is_narration("[tool: bash]") => false,
    is_narration("(trail: foo.db)") => false,
    is_narration("") => false,
    is_narration("Let me check the file.") => true
  }
{
  let t := str.trim(line)
  if str.is_empty(t) {
    false
  } else {
    not (str.starts_with(t, "[") or str.starts_with(t, "("))
  }
}

fn apply_activity(s :: LogState, line :: Str) -> LogState {
  if is_narration(line) {
    let kept := if list.len(s.activity) >= 6 {
      list.tail(s.activity)
    } else {
      s.activity
    }
    { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: list.concat(kept, [line]), usage: s.usage }
  } else {
    s
  }
}

# `[USAGE]<TAB>prompt<TAB>completion<TAB>id-or-label`, one per agent turn
# lex-code runs (a build attempt on an issue, or a planner turn labelled
# "plan"). Summed per id: a retried unit shows what ALL its attempts cost.
fn usage_field(parts :: List[Str], idx :: Int) -> Str {
  let r := list.fold(parts, (0, ""), fn (acc :: (Int, Str), p :: Str) -> (Int, Str) {
    match acc {
      (i, found) => if i == idx {
        (i + 1, p)
      } else {
        (i + 1, found)
      },
    }
  })
  match r {
    (_, v) => v,
  }
}

fn add_usage(rows :: List[UsageRow], id :: Str, p :: Int, c :: Int) -> List[UsageRow]
  examples {
    add_usage([], "a", 10, 2) => [{ id: "a", prompt: 10, completion: 2, turns: 1 }],
    add_usage([{ id: "a", prompt: 10, completion: 2, turns: 1 }], "a", 5, 1) => [{ id: "a", prompt: 15, completion: 3, turns: 2 }],
    add_usage([{ id: "a", prompt: 10, completion: 2, turns: 1 }], "b", 5, 1) => [{ id: "a", prompt: 10, completion: 2, turns: 1 }, { id: "b", prompt: 5, completion: 1, turns: 1 }]
  }
{
  let seen := list.fold(rows, false, fn (acc :: Bool, r :: UsageRow) -> Bool {
    if r.id == id {
      true
    } else {
      acc
    }
  })
  if seen {
    list.map(rows, fn (r :: UsageRow) -> UsageRow {
      if r.id == id {
        { id: r.id, prompt: r.prompt + p, completion: r.completion + c, turns: r.turns + 1 }
      } else {
        r
      }
    })
  } else {
    list.concat(rows, [{ id: id, prompt: p, completion: c, turns: 1 }])
  }
}

fn apply_usage(s :: LogState, line :: Str) -> LogState
  examples {
    apply_usage(empty_state(), "[USAGE]\t100\t20\tabc") => { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [{ id: "abc", prompt: 100, completion: 20, turns: 1 }] },
    apply_usage(empty_state(), "[USAGE]\t0\t0\tabc") => { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [{ id: "abc", prompt: 0, completion: 0, turns: 1 }] },
    apply_usage(empty_state(), "not a usage line") => empty_state(),
    apply_usage(empty_state(), "[USAGE]\tbad") => empty_state()
  }
{
  if str.starts_with(line, "[USAGE]\t") {
    let parts := str.split(line, "\t")
    let id := usage_field(parts, 3)
    if str.is_empty(id) {
      s
    } else {
      { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity, usage: add_usage(s.usage, id, parse_int(usage_field(parts, 1)), parse_int(usage_field(parts, 2))) }
    }
  } else {
    s
  }
}

fn process_line(s :: LogState, line :: Str, project_marker :: Str) -> LogState {
  apply_activity(apply_exit(apply_gate(apply_stuck(apply_aggregate(apply_verdict(apply_usage(apply_attempt(s, line), line), line), line, project_marker), line), line), line), line)
}

fn parse_log(text :: Str, project_name :: Str) -> LogState {
  let marker := str.join(["[PROJECT] ", project_name], "")
  list.fold(str.split(text, "\n"), empty_state(), fn (acc :: LogState, line :: Str) -> LogState {
    process_line(acc, line, marker)
  })
}

type UnitStatus = { status :: Str, attempt :: Str }

fn unit_status(title :: Str, t2id :: List[(Str, Str)], st :: LogState) -> UnitStatus
  examples {
    unit_status("t", [], empty_state()) => { status: "not_filed", attempt: "" },
    unit_status("t", [("t", "id1")], { attempts: [], verdicts: [("id1", "verified")], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] }) => { status: "verified", attempt: "" },
    unit_status("t", [("t", "id1")], { attempts: [("id1", "2")], verdicts: [("id1", "failed")], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] }) => { status: "failed", attempt: "2" },
    unit_status("t", [("t", "id1")], { attempts: [("id1", "1")], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] }) => { status: "running", attempt: "1" },
    unit_status("t", [("t", "id1")], { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [], usage: [] }) => { status: "ready", attempt: "" }
  }
{
  match assoc_get(t2id, title) {
    None => { status: "not_filed", attempt: "" },
    Some(id) => match assoc_get(st.verdicts, id) {
      Some(v) => if v == "verified" {
        { status: "verified", attempt: "" }
      } else {
        { status: "failed", attempt: match assoc_get(st.attempts, id) {
          Some(n) => n,
          None => "",
        } }
      },
      None => match assoc_get(st.attempts, id) {
        Some(n) => { status: "running", attempt: n },
        None => { status: "ready", attempt: "" },
      },
    },
  }
}

fn basename_no_ext(path :: Str) -> Str {
  let parts := str.split(path, "/")
  let base := match list.head(list.reverse(parts)) {
    Some(b) => b,
    None => path,
  }
  match str.strip_suffix(base, ".json") {
    Some(s) => s,
    None => base,
  }
}

fn title_to_id(issues_dir :: Str) -> [fs_read, fs_walk] List[(Str, Str)] {
  if not fs.exists(issues_dir) {
    []
  } else {
    match fs.glob(str.concat(issues_dir, "/*.json")) {
      Err(_) => [],
      Ok(paths) => list.fold(paths, [], fn (acc :: List[(Str, Str)], p :: Str) -> [fs_read] List[(Str, Str)] {
        match jv.parse(read_or_empty(p)) {
          Err(_) => acc,
          Ok(j) => {
            let title := json_str_field(j, "title")
            if str.is_empty(title) {
              acc
            } else {
              list.concat(acc, [(title, basename_no_ext(p))])
            }
          },
        }
      }),
    }
  }
}

fn read_or_empty(path :: Str) -> [fs_read] Str {
  match fs.read_to_string(path) {
    Ok(s) => s,
    Err(_) => "",
  }
}

fn digit_value(c :: Str) -> Int {
  if c == "0" {
    0
  } else {
    if c == "1" {
      1
    } else {
      if c == "2" {
        2
      } else {
        if c == "3" {
          3
        } else {
          if c == "4" {
            4
          } else {
            if c == "5" {
              5
            } else {
              if c == "6" {
                6
              } else {
                if c == "7" {
                  7
                } else {
                  if c == "8" {
                    8
                  } else {
                    if c == "9" {
                      9
                    } else {
                      0
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn parse_int(s :: Str) -> Int
  examples {
    parse_int("0") => 0,
    parse_int("1790926798") => 1790926798,
    parse_int("") => 0
  }
{
  list.fold(str.split(s, ""), 0, fn (acc :: Int, c :: Str) -> Int {
    acc * 10 + digit_value(c)
  })
}

fn fmt_elapsed(total_secs :: Int) -> Str
  examples {
    fmt_elapsed(5) => "00m05s",
    fmt_elapsed(65) => "01m05s",
    fmt_elapsed(3661) => "01h01m01s"
  }
{
  let h := total_secs / 3600
  let m := (total_secs - h * 3600) / 60
  let s := total_secs - h * 3600 - m * 60
  let m_s := if m < 10 {
    str.concat("0", int.to_str(m))
  } else {
    int.to_str(m)
  }
  let s_s := if s < 10 {
    str.concat("0", int.to_str(s))
  } else {
    int.to_str(s)
  }
  if h > 0 {
    let h_s := if h < 10 {
      str.concat("0", int.to_str(h))
    } else {
      int.to_str(h)
    }
    str.join([h_s, "h", m_s, "m", s_s, "s"], "")
  } else {
    str.join([m_s, "m", s_s, "s"], "")
  }
}

fn read_ts_or(path :: Str, fallback :: Int) -> [fs_read] Int {
  let raw := str.trim(read_or_empty(path))
  if str.is_empty(raw) {
    fallback
  } else {
    parse_int(raw)
  }
}

type Snapshot = { project_dir :: Str, log_path :: Str }

fn find_usage(rows :: List[UsageRow], id :: Str) -> UsageRow
  examples {
    find_usage([], "a") => { id: "a", prompt: 0, completion: 0, turns: 0 },
    find_usage([{ id: "a", prompt: 7, completion: 2, turns: 1 }], "a") => { id: "a", prompt: 7, completion: 2, turns: 1 }
  }
{
  match list.head(list.filter(rows, fn (r :: UsageRow) -> Bool {
    r.id == id
  })) {
    Some(r) => r,
    None => { id: id, prompt: 0, completion: 0, turns: 0 },
  }
}

fn unit_usage(title :: Str, t2id :: List[(Str, Str)], st :: LogState) -> UsageRow {
  match assoc_get(t2id, title) {
    None => { id: "", prompt: 0, completion: 0, turns: 0 },
    Some(id) => find_usage(st.usage, id),
  }
}

fn usage_total(rows :: List[UsageRow]) -> UsageRow
  examples {
    usage_total([]) => { id: "total", prompt: 0, completion: 0, turns: 0 },
    usage_total([{ id: "a", prompt: 7, completion: 2, turns: 1 }, { id: "plan", prompt: 3, completion: 1, turns: 2 }]) => { id: "total", prompt: 10, completion: 3, turns: 3 }
  }
{
  list.fold(rows, { id: "total", prompt: 0, completion: 0, turns: 0 }, fn (acc :: UsageRow, r :: UsageRow) -> UsageRow {
    { id: "total", prompt: acc.prompt + r.prompt, completion: acc.completion + r.completion, turns: acc.turns + r.turns }
  })
}

fn usage_json(r :: UsageRow) -> jv.Json {
  JObj([("in", JInt(r.prompt)), ("out", JInt(r.completion)), ("turns", JInt(r.turns))])
}

fn unit_to_json(u :: PlanUnit, t2id :: List[(Str, Str)], st :: LogState) -> jv.Json {
  let us := unit_status(u.title, t2id, st)
  JObj([("key", JStr(u.key)), ("title", JStr(u.title)), ("body", JStr(u.body)), ("deps", JList(list.map(u.deps, fn (d :: Str) -> jv.Json {
    JStr(d)
  }))), ("status", JStr(us.status)), ("attempt", JStr(us.attempt)), ("usage", usage_json(unit_usage(u.title, t2id, st))), ("api", JList(list.map(u.api, fn (a :: ApiSig) -> jv.Json {
    JObj([("name", JStr(a.name)), ("signature", JStr(a.signature))])
  }))), ("examples", JList(list.map(u.examples, fn (e :: Str) -> jv.Json {
    JStr(e)
  }))), ("invariants", JList(list.map(u.invariants, fn (iv :: InvariantSig) -> jv.Json {
    JObj([("name", JStr(iv.name)), ("expr", JStr(iv.expr))])
  })))])
}

# Everything the page needs, as one JSON object. Reads the plan file, the
# issue store and the given log file; writes nothing.
fn status_json(project_name :: Str, log_path :: Str) -> [fs_read, fs_walk, time] Str {
  let plan_path := str.join([".lex/plans/", project_name, ".json"], "")
  let issues_dir := ".lex/store/issues"
  let start_path := str.join([".lex/dashboard-", project_name, ".start.ts"], "")
  let plan_text := read_or_empty(plan_path)
  let log_text := read_or_empty(log_path)
  let st := parse_log(log_text, project_name)
  let units := parse_units(plan_text)
  let type_names := parse_type_names(plan_text)
  let t2id := title_to_id(issues_dir)
  let now := time.now()
  let start_ts := read_ts_or(start_path, now)
  let elapsed := fmt_elapsed(now - start_ts)
  let phase := if not str.is_empty(st.exited) {
    "done"
  } else {
    if str.is_empty(plan_text) {
      "planning"
    } else {
      if list.is_empty(t2id) {
        "planning"
      } else {
        "building"
      }
    }
  }
  jv.encode(JObj([("project", JStr(project_name)), ("phase", JStr(phase)), ("elapsed", JStr(elapsed)), ("aggregate", JStr(st.agg)), ("draft_units", JInt(list.len(units))), ("types", JList(list.map(type_names, fn (t :: Str) -> jv.Json {
    JStr(t)
  }))), ("units", JList(list.map(units, fn (u :: PlanUnit) -> jv.Json {
    unit_to_json(u, t2id, st)
  }))), ("stuck", JStr(st.stuck)), ("gate", JStr(st.gate)), ("exited", JStr(st.exited)), ("usage", JObj([("plan", usage_json(find_usage(st.usage, "plan"))), ("total", usage_json(usage_total(st.usage)))])), ("activity", JList(list.map(st.activity, fn (l :: Str) -> jv.Json {
    JStr(l)
  })))]))
}

fn page_html() -> Str {
  "<!doctype html> <html> <head> <meta charset=\"utf-8\"> <title>lex-code dashboard</title> <style> :root{--bg:#0b0e14;--fg:#c9d1d9;--dim:#8b949e;--line:#21262d;--accent:#58a6ff; --verified:#3fb950;--failed:#f85149;--running:#d29922;--ready:#6e7681;} body{background:var(--bg);color:var(--fg);font-family:ui-monospace,Menlo,monospace;margin:2rem;} h1{color:var(--accent);font-size:1.1rem;margin:0 0 .2rem} #meta{color:var(--dim);margin-bottom:1rem} .stepper{display:flex;align-items:center;margin-bottom:1.4rem} .step{display:flex;align-items:center;color:var(--dim)} .step .dot{width:10px;height:10px;border-radius:50%;border:2px solid var(--line); background:var(--bg);margin-right:.5rem;flex:none} .step .label{white-space:nowrap} .step.done .dot{background:var(--verified);border-color:var(--verified)} .step.done .label{color:var(--fg)} .step.current .dot{background:var(--running);border-color:var(--running); box-shadow:0 0 0 3px rgba(210,153,34,.25)} .step.current .label{color:var(--running)} .step.failed .dot{background:var(--failed);border-color:var(--failed)} .step.failed .label{color:var(--failed)} .stepline{flex:1;height:1px;background:var(--line);margin:0 .7rem;min-width:1.2rem} .tabs{margin-bottom:1rem} .tabs button{background:none;border:1px solid var(--line);color:var(--fg);padding:.3rem .8rem; cursor:pointer;font:inherit;border-radius:4px;margin-right:.4rem} .tabs button.active{border-color:var(--accent);color:var(--accent)} table{border-collapse:collapse;width:100%} td,th{padding:.25rem .6rem;text-align:left;border-bottom:1px solid var(--line)} th{color:var(--dim);font-weight:normal} tbody tr{cursor:pointer} tbody tr:hover{background:#111726} .verified{color:var(--verified)} .failed{color:var(--failed)} .running{color:var(--running)} .ready,.not_filed{color:var(--ready)} #activity div{color:var(--dim);margin:.15rem 0} #stuck{color:var(--failed);margin-top:1rem} #graph{display:none} #graph svg{width:100%;height:auto} .node rect{stroke:var(--line);stroke-width:1;cursor:pointer} .node text{fill:var(--fg);font-size:12px;font-family:ui-monospace,Menlo,monospace;pointer-events:none} .node .sub{fill:var(--dim);font-size:10px} .edge{fill:none;stroke:#30363d;stroke-width:1.5} .edge.verified-src{stroke:#2ea043;opacity:.6} #kanban{display:none;gap:1rem} .kcol{flex:1;min-width:0} .kcol h4{color:var(--dim);font-weight:normal;text-transform:uppercase;font-size:.75rem; letter-spacing:.05em;margin:0 0 .5rem;display:flex;justify-content:space-between} .kcol .count{color:var(--fg)} .kcard{background:#111726;border:1px solid var(--line);border-left:3px solid var(--ready); border-radius:4px;padding:.5rem .6rem;margin-bottom:.5rem;cursor:pointer} .kcard:hover{border-color:var(--accent)} .kcard .k{color:var(--fg)} .kcard .t{color:var(--dim);font-size:.8rem;margin-top:.15rem; overflow:hidden;text-overflow:ellipsis;white-space:nowrap} .kcard .a{font-size:.75rem;margin-top:.3rem} .kcol[data-status=\"verified\"] .kcard{border-left-color:var(--verified)} .kcol[data-status=\"running\"] .kcard{border-left-color:var(--running)} .kcol[data-status=\"failed\"] .kcard{border-left-color:var(--failed)} #overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:10} #panel{position:fixed;right:0;top:0;bottom:0;width:min(520px,90vw);background:#0d1117; border-left:1px solid var(--line);padding:1.2rem;overflow-y:auto;z-index:11} #panel h2{color:var(--accent);margin:0 0 .2rem;font-size:1rem} #panel .pstatus{margin-bottom:1rem} #panel h4{color:var(--dim);font-weight:normal;margin:1rem 0 .3rem;font-size:.85rem; text-transform:uppercase;letter-spacing:.04em} #panel pre{background:#161b22;padding:.5rem .7rem;border-radius:4px;overflow-x:auto; white-space:pre-wrap;word-break:break-word;margin:.2rem 0} #panel .sig{color:#79c0ff} #panel .body-text{color:var(--fg);line-height:1.5} #panel .close{float:right;cursor:pointer;color:var(--dim);font-size:1.3rem;line-height:1} #panel .deplist span{display:inline-block;background:#161b22;border-radius:3px; padding:.1rem .5rem;margin:.1rem .2rem .1rem 0;color:var(--dim)} </style> </head> <body> <h1 id=\"title\">lex-code dashboard</h1> <div id=\"meta\"></div> <div class=\"stepper\" id=\"stepper\"></div> <div class=\"tabs\"> <button id=\"tab-table\" class=\"active\">table</button> <button id=\"tab-kanban\">kanban</button> <button id=\"tab-graph\">graph</button> </div> <div id=\"table\"> <table><thead><tr><th>unit</th><th>deps</th><th>status</th><th>tokens</th></tr></thead><tbody id=\"units\"></tbody></table> </div> <div id=\"kanban\"> <div class=\"kcol\" data-status=\"ready\"><h4>ready <span class=\"count\" id=\"count-ready\"></span></h4><div id=\"col-ready\"></div></div> <div class=\"kcol\" data-status=\"running\"><h4>running <span class=\"count\" id=\"count-running\"></span></h4><div id=\"col-running\"></div></div> <div class=\"kcol\" data-status=\"failed\"><h4>failed <span class=\"count\" id=\"count-failed\"></span></h4><div id=\"col-failed\"></div></div> <div class=\"kcol\" data-status=\"verified\"><h4>verified <span class=\"count\" id=\"count-verified\"></span></h4><div id=\"col-verified\"></div></div> </div> <div id=\"graph\"><svg id=\"svg\" xmlns=\"http://www.w3.org/2000/svg\"></svg></div> <div id=\"stuck\"></div> <h3>recent activity</h3> <div id=\"activity\"></div> <div id=\"overlay\"></div> <div id=\"panel\"></div> <script> var SVGNS = 'http://www.w3.org/2000/svg'; var lastData = null; var TABS = ['table', 'kanban', 'graph']; function fmtTok(n){ n = Number(n) || 0; if (n >= 1000000) return (n/1000000).toFixed(2) + 'M'; if (n >= 1000) return (n/1000).toFixed(1) + 'k'; return String(n); } function tokText(t){ if (!t || !t.turns) return ''; if (!t.in && !t.out) return 'not reported'; return fmtTok(t.in) + ' in / ' + fmtTok(t.out) + ' out'; } function tokCell(u){ return tokText(u.usage) || '-'; } function tokLine(u){ var x = tokText(u.usage); return x ? '<div class=\"a\">' + esc(x) + '</div>' : ''; } function tokPanel(u){ var t = u.usage; if (!t || !t.turns) return ''; return '<h4>tokens</h4><div class=\"body-text\">' + esc(tokText(t)) + ' over ' + t.turns + ' attempt' + (t.turns === 1 ? '' : 's') + '</div>'; } function tokenMeta(d){ var u = d.usage; if (!u || !u.total || !u.total.turns) return ''; var s = '  tokens ' + tokText(u.total); if (u.plan && u.plan.turns) s += ' (plan ' + tokText(u.plan) + ')'; return s; } function statusLabel(u){ return u.status + (u.attempt ? ' (attempt ' + u.attempt + ')' : ''); } function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); } function openPanel(u){ var p = document.getElementById('panel'); var html = '<div class=\"close\" id=\"panel-close\">&times;</div>'; html += '<h2>' + esc(u.key) + '</h2>'; html += '<div class=\"pstatus ' + u.status + '\">' + esc(statusLabel(u)) + '</div>'; html += tokPanel(u); if (u.title) html += '<div class=\"body-text\">' + esc(u.title) + '</div>'; if (u.body) { html += '<h4>spec</h4><div class=\"body-text\">' + esc(u.body) + '</div>'; } if (u.deps && u.deps.length) { html += '<h4>depends on</h4><div class=\"deplist\">' + u.deps.map(function(d){ return '<span>' + esc(d) + '</span>'; }).join('') + '</div>'; } if (u.api && u.api.length) { html += '<h4>api</h4>' + u.api.map(function(a){ return '<pre><span class=\"sig\">' + esc(a.name) + '</span> ' + esc(a.signature) + '</pre>'; }).join(''); } if (u.examples && u.examples.length) { html += '<h4>examples</h4>' + u.examples.map(function(e){ return '<pre>' + esc(e) + '</pre>'; }).join(''); } if (u.invariants && u.invariants.length) { html += '<h4>invariants</h4>' + u.invariants.map(function(iv){ return '<pre><span class=\"sig\">' + esc(iv.name) + '</span>: ' + esc(iv.expr) + '</pre>'; }).join(''); } p.innerHTML = html; p.style.display = 'block'; document.getElementById('overlay').style.display = 'block'; document.getElementById('panel-close').onclick = closePanel; } function closePanel(){ document.getElementById('panel').style.display = 'none'; document.getElementById('overlay').style.display = 'none'; } document.getElementById('overlay').onclick = closePanel; function byKey(units){ var m = {}; units.forEach(function(u){ m[u.key] = u; }); return m; } function levelsOf(units){ var m = byKey(units); var level = {}; var visiting = {}; function lvl(k){ if (level[k] !== undefined) return level[k]; if (visiting[k]) return 0; visiting[k] = true; var u = m[k]; var deps = (u && u.deps) ? u.deps.filter(function(d){ return m[d]; }) : []; var l = deps.length ? 1 + Math.max.apply(null, deps.map(lvl)) : 0; level[k] = l; return l; } units.forEach(function(u){ lvl(u.key); }); return level; } function renderGraph(units){ var svg = document.getElementById('svg'); svg.innerHTML = ''; if (!units.length) return; var level = levelsOf(units); var cols = {}; units.forEach(function(u){ var l = level[u.key]; (cols[l] = cols[l] || []).push(u); }); var colW = 210, rowH = 54, nodeW = 150, nodeH = 34, padL = 20, padT = 20; var maxCol = Math.max.apply(null, Object.keys(cols).map(Number)); var maxRows = Math.max.apply(null, Object.values(cols).map(function(a){ return a.length; })); var width = padL * 2 + (maxCol + 1) * colW; var height = padT * 2 + maxRows * rowH; svg.setAttribute('viewBox', '0 0 ' + width + ' ' + Math.max(height, 200)); var pos = {}; Object.keys(cols).forEach(function(l){ var arr = cols[l].sort(function(a,b){ return a.key < b.key ? -1 : 1; }); arr.forEach(function(u, i){ pos[u.key] = { x: padL + Number(l) * colW, y: padT + i * rowH, u: u }; }); }); var m = byKey(units); units.forEach(function(u){ (u.deps || []).forEach(function(d){ if (!pos[d] || !pos[u.key]) return; var a = pos[d], b = pos[u.key]; var x1 = a.x + nodeW, y1 = a.y + nodeH / 2; var x2 = b.x, y2 = b.y + nodeH / 2; var mx = (x1 + x2) / 2; var path = document.createElementNS(SVGNS, 'path'); path.setAttribute('d', 'M ' + x1 + ' ' + y1 + ' C ' + mx + ' ' + y1 + ', ' + mx + ' ' + y2 + ', ' + x2 + ' ' + y2); path.setAttribute('class', 'edge' + (a.u.status === 'verified' ? ' verified-src' : '')); svg.appendChild(path); }); }); var colorOf = { verified: '#1b3a24', failed: '#3a1d1c', running: '#3a2f14', ready: '#161b22', not_filed: '#161b22' }; var strokeOf = { verified: '#3fb950', failed: '#f85149', running: '#d29922', ready: '#30363d', not_filed: '#30363d' }; Object.keys(pos).forEach(function(k){ var p = pos[k], u = p.u; var g = document.createElementNS(SVGNS, 'g'); g.setAttribute('class', 'node'); g.setAttribute('transform', 'translate(' + p.x + ',' + p.y + ')'); var r = document.createElementNS(SVGNS, 'rect'); r.setAttribute('width', nodeW); r.setAttribute('height', nodeH); r.setAttribute('rx', 5); r.setAttribute('fill', colorOf[u.status] || '#161b22'); r.setAttribute('stroke', strokeOf[u.status] || '#30363d'); g.appendChild(r); var t = document.createElementNS(SVGNS, 'text'); t.setAttribute('x', 8); t.setAttribute('y', 15); t.textContent = u.key; g.appendChild(t); var sub = document.createElementNS(SVGNS, 'text'); sub.setAttribute('x', 8); sub.setAttribute('y', 28); sub.setAttribute('class', 'sub'); sub.textContent = statusLabel(u); g.appendChild(sub); g.onclick = function(){ openPanel(u); }; svg.appendChild(g); }); } function renderTable(units){ var rows = units.map(function(u){ return '<tr data-key=\"' + esc(u.key) + '\"><td>' + esc(u.key) + '</td><td>' + esc((u.deps||[]).join(',')) + '</td><td class=\"' + u.status + '\">' + esc(statusLabel(u)) + '</td><td>' + esc(tokCell(u)) + '</td></tr>'; }).join(''); var tbody = document.getElementById('units'); tbody.innerHTML = rows; Array.prototype.forEach.call(tbody.querySelectorAll('tr'), function(tr){ tr.onclick = function(){ var u = lastData.units.filter(function(x){ return x.key === tr.getAttribute('data-key'); })[0]; if (u) openPanel(u); }; }); } var KANBAN_COLS = ['ready', 'running', 'failed', 'verified']; function renderKanban(units){ KANBAN_COLS.forEach(function(status){ var col = units.filter(function(u){ return status === 'ready' ? (u.status === 'ready' || u.status === 'not_filed') : u.status === status; }); document.getElementById('count-' + status).textContent = col.length; var html = col.map(function(u){ return '<div class=\"kcard\" data-key=\"' + esc(u.key) + '\">' + '<div class=\"k\">' + esc(u.key) + '</div>' + (u.title ? '<div class=\"t\">' + esc(u.title) + '</div>' : '') + (u.attempt ? '<div class=\"a ' + u.status + '\">attempt ' + esc(u.attempt) + '</div>' : '') + tokLine(u) + '</div>'; }).join(''); var holder = document.getElementById('col-' + status); holder.innerHTML = html; Array.prototype.forEach.call(holder.querySelectorAll('.kcard'), function(card){ card.onclick = function(){ var u = lastData.units.filter(function(x){ return x.key === card.getAttribute('data-key'); })[0]; if (u) openPanel(u); }; }); }); } function stepState(phase, name, d){ var order = ['plan', 'file', 'build', 'regression', 'gate']; var hasReadyOrRunning = d.units.some(function(u){ return u.status === 'ready' || u.status === 'running' || u.status === 'not_filed'; }); var buildDone = d.phase !== 'planning' && !hasReadyOrRunning; if (name === 'plan') { return d.phase === 'planning' ? 'current' : 'done'; } if (name === 'file') { return d.phase === 'planning' ? 'pending' : 'done'; } if (name === 'build') { if (d.phase === 'planning') return 'pending'; if (d.stuck) return 'failed'; return buildDone ? 'done' : 'current'; } if (name === 'regression') { if (d.phase === 'planning' || !buildDone) return 'pending'; return d.exited ? 'done' : 'current'; } if (name === 'gate') { if (!d.exited) return 'pending'; return d.gate === 'fail' ? 'failed' : 'done'; } return 'pending'; } function renderStepper(d){ var steps = [ ['plan', 'plan'], ['file', 'file'], ['build', 'build'], ['regression', 'regression'], ['gate', 'gate'] ]; var html = steps.map(function(s, i){ var state = stepState(d.phase, s[0], d); var label = s[1]; if (s[0] === 'gate' && d.exited) label = 'gate: ' + (d.gate || d.exited); var html1 = '<span class=\"step ' + state + '\"><span class=\"dot\"></span><span class=\"label\">' + esc(label) + '</span></span>'; if (i < steps.length - 1) html1 += '<span class=\"stepline\"></span>'; return html1; }).join(''); document.getElementById('stepper').innerHTML = html; } function render(d){ lastData = d; document.getElementById('title').textContent = d.project + ' — ' + d.phase; var agg = d.aggregate ? d.aggregate : (d.phase === 'planning' ? ('planning — ' + d.draft_units + ' units drafted (' + (d.types||[]).join(', ') + ')') : ''); document.getElementById('meta').textContent = 'elapsed ' + d.elapsed + (agg ? '  ' + agg : '') + (d.exited ? ('  EXIT ' + d.exited + (d.gate ? ' [' + d.gate + ']' : '')) : '') + tokenMeta(d); renderStepper(d); renderTable(d.units); renderKanban(d.units); renderGraph(d.units); document.getElementById('stuck').textContent = d.stuck ? ('stuck — gave up on: ' + d.stuck) : ''; document.getElementById('activity').innerHTML = d.activity.map(function(a){ return '<div>' + esc(a) + '</div>'; }).join(''); } function showTab(name){ TABS.forEach(function(t){ document.getElementById(t).style.display = (t === name) ? (t === 'kanban' ? 'flex' : 'block') : 'none'; document.getElementById('tab-' + t).classList.toggle('active', t === name); }); } TABS.forEach(function(t){ document.getElementById('tab-' + t).onclick = function(){ showTab(t); }; }); function poll(){ fetch('/status').then(function(r){ return r.json(); }).then(render).catch(function(){}); } if (window.__mock__) { render(window.__mock__); } else { poll(); setInterval(poll, 2000); } </script> </body> </html> "
}

fn handler(req :: Request, project_name :: Str, log_path :: Str) -> [fs_read, fs_walk, time] { status :: Int, body :: ResponseBody, headers :: Map[Str, Str] } {
  if req.path == "/status" {
    { status: 200, body: BodyStr(status_json(project_name, log_path)), headers: map.set(map.new(), "content-type", "application/json") }
  } else {
    { status: 200, body: BodyStr(page_html()), headers: map.set(map.new(), "content-type", "text/html") }
  }
}

# `lex-code --dashboard=NAME [--log=PATH] [--port=N]` serves this at
# http://127.0.0.1:PORT. Read-only: writes nothing but its own start
# timestamp (`.lex/dashboard-NAME.start.ts`, used only to show elapsed
# time — never read by anything else lex-code does).
fn serve_dashboard(project_name :: Str, log_path :: Str, port :: Int) -> [net, fs_read, fs_walk, fs_write, time, io] Nil {
  let start_path := str.join([".lex/dashboard-", project_name, ".start.ts"], "")
  let __w := if fs.exists(start_path) {
    ()
  } else {
    let __mk := fs.write(start_path, int.to_str(time.now()))
    ()
  }
  let __p := io.print(str.join(["dashboard: http://127.0.0.1:", int.to_str(port), "  (watching ", log_path, ")"], ""))
  net.serve_fn(port, fn (req :: Request) -> [fs_read, fs_walk, time] { status :: Int, body :: ResponseBody, headers :: Map[Str, Str] } {
    handler(req, project_name, log_path)
  })
}

