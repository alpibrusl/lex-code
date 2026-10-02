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

type PlanUnit = { key :: Str, title :: Str, deps :: List[Str] }

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
          { key: json_str_field(u, "key"), title: json_str_field(u, "title"), deps: json_str_list_field(u, "deps") }
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

type LogState = { attempts :: List[(Str, Str)], verdicts :: List[(Str, Str)], agg :: Str, stuck :: Str, gate :: Str, exited :: Str, activity :: List[Str] }

fn empty_state() -> LogState {
  { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [] }
}

fn apply_attempt(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PROJECT] issue ") and str.contains(line, " — attempt ") {
    match between(line, "[PROJECT] issue ", " —") {
      None => s,
      Some(id) => match between(line, "attempt ", " on") {
        None => s,
        Some(n) => { attempts: assoc_set(s.attempts, id, n), verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity },
      },
    }
  } else {
    s
  }
}

fn apply_verdict(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PROJECT] issue ") and str.contains(line, " → ") {
    match between(line, "[PROJECT] issue ", " →") {
      None => s,
      Some(id) => match suffix_after(line, "→ ") {
        None => s,
        Some(v) => { attempts: s.attempts, verdicts: assoc_set(s.verdicts, id, v), agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity },
      },
    }
  } else {
    s
  }
}

fn apply_aggregate(s :: LogState, line :: Str, project_marker :: Str) -> LogState {
  if str.contains(line, project_marker) and str.contains(line, "verified,") {
    match suffix_after(line, str.slice(project_marker, str.len("[PROJECT] "), str.len(project_marker))) {
      None => s,
      Some(rest) => { attempts: s.attempts, verdicts: s.verdicts, agg: str.trim(rest), stuck: s.stuck, gate: s.gate, exited: s.exited, activity: s.activity },
    }
  } else {
    s
  }
}

fn apply_stuck(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PROJECT] stuck: gave up") {
    match suffix_after(line, "attempts on: ") {
      None => s,
      Some(titles) => { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: titles, gate: s.gate, exited: s.exited, activity: s.activity },
    }
  } else {
    s
  }
}

fn apply_gate(s :: LogState, line :: Str) -> LogState {
  if str.contains(line, "[PACKAGE_GATE]") {
    match between(line, "[PACKAGE_GATE]\t", "\t") {
      None => s,
      Some(g) => { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: g, exited: s.exited, activity: s.activity },
    }
  } else {
    s
  }
}

fn apply_exit(s :: LogState, line :: Str) -> LogState {
  if str.starts_with(line, "EXIT ") {
    { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: str.slice(line, 5, str.len(line)), activity: s.activity }
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
    { attempts: s.attempts, verdicts: s.verdicts, agg: s.agg, stuck: s.stuck, gate: s.gate, exited: s.exited, activity: list.concat(kept, [line]) }
  } else {
    s
  }
}

fn process_line(s :: LogState, line :: Str, project_marker :: Str) -> LogState {
  apply_activity(apply_exit(apply_gate(apply_stuck(apply_aggregate(apply_verdict(apply_attempt(s, line), line), line, project_marker), line), line), line), line)
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
    unit_status("t", [("t", "id1")], { attempts: [], verdicts: [("id1", "verified")], agg: "", stuck: "", gate: "", exited: "", activity: [] }) => { status: "verified", attempt: "" },
    unit_status("t", [("t", "id1")], { attempts: [("id1", "2")], verdicts: [("id1", "failed")], agg: "", stuck: "", gate: "", exited: "", activity: [] }) => { status: "failed", attempt: "2" },
    unit_status("t", [("t", "id1")], { attempts: [("id1", "1")], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [] }) => { status: "running", attempt: "1" },
    unit_status("t", [("t", "id1")], { attempts: [], verdicts: [], agg: "", stuck: "", gate: "", exited: "", activity: [] }) => { status: "ready", attempt: "" }
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

fn unit_to_json(u :: PlanUnit, t2id :: List[(Str, Str)], st :: LogState) -> jv.Json {
  let us := unit_status(u.title, t2id, st)
  JObj([("key", JStr(u.key)), ("deps", JList(list.map(u.deps, fn (d :: Str) -> jv.Json {
    JStr(d)
  }))), ("status", JStr(us.status)), ("attempt", JStr(us.attempt))])
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
  }))), ("stuck", JStr(st.stuck)), ("gate", JStr(st.gate)), ("exited", JStr(st.exited)), ("activity", JList(list.map(st.activity, fn (l :: Str) -> jv.Json {
    JStr(l)
  })))]))
}

fn page_html() -> Str {
  str.join(["<!doctype html><html><head><meta charset=\"utf-8\"><title>lex-code dashboard</title><style>", "body{background:#0b0e14;color:#c9d1d9;font-family:ui-monospace,Menlo,monospace;margin:2rem;}", "h1{color:#58a6ff;font-size:1.1rem;margin:0 0 .2rem}", "#meta{color:#8b949e;margin-bottom:1rem}", "table{border-collapse:collapse;width:100%}", "td,th{padding:.25rem .6rem;text-align:left;border-bottom:1px solid #21262d}", "th{color:#8b949e;font-weight:normal}", ".verified{color:#3fb950}", ".failed{color:#f85149}", ".running{color:#d29922}", ".ready,.not_filed{color:#6e7681}", "#activity div{color:#8b949e;margin:.15rem 0}", "#stuck{color:#f85149;margin-top:1rem}", "</style></head><body>", "<h1 id=\"title\">lex-code dashboard</h1>", "<div id=\"meta\"></div>", "<table><thead><tr><th>unit</th><th>deps</th><th>status</th></tr></thead><tbody id=\"units\"></tbody></table>", "<div id=\"stuck\"></div>", "<h3>recent activity</h3><div id=\"activity\"></div>", "<script>", "function render(d){", "document.getElementById('title').textContent = d.project + ' — ' + d.phase;", "var agg = d.aggregate ? d.aggregate : (d.phase === 'planning' ? ('planning — ' + d.draft_units + ' units drafted (' + d.types.join(', ') + ')') : '');", "document.getElementById('meta').textContent = 'elapsed ' + d.elapsed + (agg ? '    ' + agg : '') + (d.exited ? ('    EXIT ' + d.exited + (d.gate ? ' [' + d.gate + ']' : '')) : '');", "var rows = d.units.map(function(u){", "var s = u.status + (u.attempt ? ' (attempt ' + u.attempt + ')' : '');", "return '<tr><td>' + u.key + '</td><td>' + u.deps.join(',') + '</td><td class=\"' + u.status + '\">' + s + '</td></tr>';", "}).join('');", "document.getElementById('units').innerHTML = rows;", "document.getElementById('stuck').textContent = d.stuck ? ('stuck — gave up on: ' + d.stuck) : '';", "document.getElementById('activity').innerHTML = d.activity.map(function(a){ return '<div>' + a.replace(/</g,'&lt;') + '</div>'; }).join('');", "}", "function poll(){ fetch('/status').then(function(r){return r.json();}).then(render).catch(function(){}); }", "poll(); setInterval(poll, 2000);", "</script></body></html>"], "")
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

