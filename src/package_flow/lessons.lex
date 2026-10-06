# lex-code — candidate lessons, mined from a project's own session trails
#
# Every hour-long stall in the from-scratch builds had the same shape: the model
# met an error it could not interpret, tried again, and met it again. The error
# text was in the trail the whole time (each tool call writes a `cap.failed`
# event), and finding it took a person reading SQLite by hand: the bash tool that
# hung on a background `&`, a write that dropped other units' functions, one
# unit's failing examples blocking every later unit's edit.
#
# This reads those trails and groups the failures by what they say. A failure
# that recurs across several sessions (attempts) of one project is a candidate
# lesson: either a trap in a library, a defect in a tool, or a gap in the plan.
#
# It is deliberately mechanical, and deliberately only a CANDIDATE list. Nothing
# here is injected into a prompt: a wrong lesson shown to every later run is worse
# than none, so a person (or a later, reviewed step) decides which become notes.
# Grouping is by normalised text, not by a model's idea of what the error means;
# the sample is a real error from the trail so the reader can judge it.

import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.io" as io

import "std.fs" as fs

import "std.sql" as sql

import "std.regex" as regex

import "std.process" as proc

import "lex-trail/log" as trail_log

import "lex-schema/json_value" as jv

type Failure = { session :: Str, capability :: Str, text :: Str }

type Acc = { key :: Str, capability :: Str, sig :: Str, count :: Int, ids :: List[Str], sample :: Str }

type Group = { key :: Str, capability :: Str, sig :: Str, count :: Int, sessions :: Int, sample :: Str }

fn sub(pat :: Str, text :: Str, with :: Str) -> Str {
  match regex.compile(pat) {
    Ok(r) => regex.replace_all(r, text, with),
    Err(_) => text,
  }
}

fn matches(pat :: Str, text :: Str) -> Bool {
  match regex.compile(pat) {
    Ok(r) => regex.is_match(r, text),
    Err(_) => false,
  }
}

# One line of an error with what varies between occurrences taken out (quoted
# text, file names, numbers), so the same failure on two attempts reads the same.
fn normalize(line :: Str) -> Str
  examples {
    normalize("old_str not found in file. First difference: line 4 of old_str is \"x y\"") => "old_str not found in file. first difference: line N of old_str is \"..\"",
    normalize("error: src/cronexpr.lex: parse error: pos 1340") => "error: FILE: parse error: pos N"
  }
{
  let a := sub("\"[^\"]*\"", str.to_lower(line), "\"..\"")
  let b := sub("`[^`]*`", a, "`..`")
  let c := sub("[A-Za-z0-9_./-]+\\.lex", b, "FILE")
  let d := sub("[0-9]+", c, "N")
  let e := sub("[ \t]+", d, " ")
  sub("^(.{0,110}).*$", str.trim(e), "$1")
}

fn informative(line :: Str) -> Bool
  examples {
    informative("lint[lex check]: FAILED — [example-mismatch] A case inside an examples block") => true,
    informative("<root>: edited src/x.lex") => false,
    informative("tool argument validation failed:") => false,
    informative("  let x := 1") => false
  }
{
  not str.is_empty(str.trim(line)) and not str.starts_with(line, "tool argument validation failed") and not matches("^<root>: (edited|wrote) ", line) and matches("(?i)(error|failed|refused|not found|mismatch|unknown|expected|invalid|cannot|could not|timed out|denied)", line)
}

fn first_informative(lines :: List[Str]) -> Str {
  match list.head(list.filter(lines, informative)) {
    Some(l) => l,
    None => "",
  }
}

# What this failure is about, as a stable key: the tool and the first informative
# line, normalised.
fn signature(capability :: Str, text :: Str) -> Str
  examples {
    signature("edit", "tool argument validation failed:\n<root>: edited src/a.lex\nlint[lex check]: FAILED — [example-mismatch] A case inside an `examples` block") => "edit: lint[lex check]: failed — [example-mismatch] a case inside an `..` block",
    signature("bash", "") => "bash: (no message)"
  }
{
  let line := first_informative(str.split(text, "\n"))
  if str.is_empty(line) {
    let any := match list.head(list.filter(str.split(text, "\n"), fn (l :: Str) -> Bool {
      not str.is_empty(str.trim(l))
    })) {
      Some(l) => normalize(l),
      None => "",
    }
    if str.is_empty(any) {
      str.concat(capability, ": (no message)")
    } else {
      str.join([capability, ": ", any], "")
    }
  } else {
    str.join([capability, ": ", normalize(line)], "")
  }
}

fn has(xs :: List[Str], s :: Str) -> Bool {
  list.fold(xs, false, fn (f :: Bool, x :: Str) -> Bool {
    f or x == s
  })
}

fn add_failure(accs :: List[Acc], f :: Failure) -> List[Acc] {
  let sig := signature(f.capability, f.text)
  let key := sig
  if list.fold(accs, false, fn (found :: Bool, a :: Acc) -> Bool {
    found or a.key == key
  }) {
    list.map(accs, fn (a :: Acc) -> Acc {
      if a.key == key {
        { key: a.key, capability: a.capability, sig: a.sig, count: a.count + 1, ids: if has(a.ids, f.session) {
          a.ids
        } else {
          list.concat(a.ids, [f.session])
        }, sample: a.sample }
      } else {
        a
      }
    })
  } else {
    list.concat(accs, [{ key: key, capability: f.capability, sig: sig, count: 1, ids: [f.session], sample: f.text }])
  }
}

fn insert_sorted(sorted :: List[Group], g :: Group) -> List[Group] {
  match list.head(sorted) {
    None => [g],
    Some(h) => if g.sessions > h.sessions or g.sessions == h.sessions and g.count > h.count {
      list.cons(g, sorted)
    } else {
      list.cons(h, insert_sorted(list.tail(sorted), g))
    },
  }
}

# Failures grouped by signature, most widespread first (distinct sessions, then
# total occurrences). `min_sessions` drops a failure seen in fewer sessions: one
# session's bad luck is not a lesson.
fn group_failures(failures :: List[Failure], min_sessions :: Int) -> List[Group]
  examples {
    group_failures([], 3) => [],
    group_failures([{ session: "a", capability: "bash", text: "error: boom 1" }, { session: "b", capability: "bash", text: "error: boom 2" }], 2) => [{ key: "bash: error: boom N", capability: "bash", sig: "bash: error: boom N", count: 2, sessions: 2, sample: "error: boom 1" }],
    group_failures([{ session: "a", capability: "bash", text: "error: boom 1" }, { session: "a", capability: "bash", text: "error: boom 2" }], 2) => []
  }
{
  let accs := list.fold(failures, [], add_failure)
  let groups := list.map(accs, fn (a :: Acc) -> Group {
    { key: a.key, capability: a.capability, sig: a.sig, count: a.count, sessions: list.len(a.ids), sample: a.sample }
  })
  list.fold(list.filter(groups, fn (g :: Group) -> Bool {
    g.sessions >= min_sessions
  }), [], insert_sorted)
}

fn clip(s :: Str, n :: Int) -> Str {
  sub(str.concat("^(?s)(.{0,", str.concat(int.to_str(n), "}).*$")), str.trim(s), "$1")
}

fn render_md(project :: Str, groups :: List[Group], sessions_read :: Int, failures_read :: Int, min_sessions :: Int) -> Str {
  let head := str.join(["# ", project, " — candidate lessons\n\n", int.to_str(failures_read), " failed tool calls in ", int.to_str(sessions_read), " sessions; shown: failures that recur in at least ", int.to_str(min_sessions), " sessions. These are candidates to read, not facts: nothing here is fed to a prompt.\n"], "")
  if list.is_empty(groups) {
    str.concat(head, "\nNothing recurs that often yet.\n")
  } else {
    let body := list.map(groups, fn (g :: Group) -> Str {
      str.join(["\n## ", g.sig, "\n\n", int.to_str(g.count), " times in ", int.to_str(g.sessions), " sessions.\n\nSample from the trail:\n\n```\n", clip(g.sample, 600), "\n```\n"], "")
    })
    str.concat(head, str.join(body, ""))
  }
}

fn to_jsonl(project :: Str, groups :: List[Group]) -> Str {
  str.join(list.map(groups, fn (g :: Group) -> Str {
    str.concat(jv.stringify(JObj([("kind", JStr("recurring_failure")), ("project", JStr(project)), ("capability", JStr(g.capability)), ("signature", JStr(g.sig)), ("count", JInt(g.count)), ("sessions", JInt(g.sessions)), ("sample", JStr(clip(g.sample, 600)))])), "\n")
  }), "")
}

# ---- reading the trails ------------------------------------------------------
# The trail's own payloads can hold raw newlines inside a string (a tool error
# quoting several lines), which is not valid JSON; read those with patterns.
fn raw_failure(session :: Str, payload :: Str) -> Failure
  examples {
    raw_failure("s", "{\"capability\":\"edit\",\"error\":{\"error\":\"bad\nthing\"}}") => { session: "s", capability: "edit", text: "bad\nthing\"}}" }
  }
{
  let cap := if matches("\"capability\":\"[^\"]*\"", payload) {
    sub("(?s)^.*?\"capability\":\"([^\"]*)\".*$", payload, "$1")
  } else {
    "?"
  }
  let text := sub("(?s)^.*?\"error\":(\\{\"error\":)?\"", payload, "")
  { session: session, capability: cap, text: text }
}

fn failure_of(session :: Str, payload :: Str) -> Failure {
  match jv.parse(payload) {
    Err(_) => raw_failure(session, payload),
    Ok(j) => {
      let cap := match jv.get_field(j, "capability") {
        Some(v) => match jv.as_str(v) {
          Some(s) => s,
          None => "?",
        },
        None => "?",
      }
      let text := match jv.get_field(j, "error") {
        None => "",
        Some(e) => match jv.as_str(e) {
          Some(s) => s,
          None => match jv.get_field(e, "error") {
            Some(inner) => match jv.as_str(inner) {
              Some(s) => s,
              None => jv.stringify(e),
            },
            None => jv.stringify(e),
          },
        },
      }
      { session: session, capability: cap, text: text }
    },
  }
}

fn load_session(path :: Str) -> [sql, fs_write] List[Failure] {
  match trail_log.open(path) {
    Err(_) => [],
    Ok(log) => match trail_log.xquery(log.db, "SELECT payload_json FROM events WHERE kind = 'cap.failed' ORDER BY ts_ms ASC", []) {
      Err(_) => [],
      Ok(rows) => list.map(rows, fn (r :: sql.Row) -> Failure {
        failure_of(path, match sql.get_str(r, "payload_json") {
          Some(s) => s,
          None => "{}",
        })
      }),
    },
  }
}

fn session_files(dir :: Str) -> [proc] List[Str] {
  match proc.run("sh", ["-c", "ls \"$1\"/*.db 2>/dev/null", "sh", dir]) {
    Err(_) => [],
    Ok(o) => list.filter(str.split(o.stdout, "\n"), fn (l :: Str) -> Bool {
      not str.is_empty(str.trim(l))
    }),
  }
}

# `--lessons=P [--min-sessions=N]`: read this project's session trails
# (.lex/sessions/*.db), print the recurring failures, and write them to
# .lex/lessons-candidates.jsonl. Derived data: rerunning replaces the file.
fn run_lessons(project :: Str, min_sessions :: Int) -> [io, sql, fs_write, proc] Nil {
  let files := session_files(".lex/sessions")
  let failures := list.fold(files, [], fn (acc :: List[Failure], f :: Str) -> [sql, fs_write] List[Failure] {
    list.concat(acc, load_session(f))
  })
  let groups := group_failures(failures, min_sessions)
  let __w := fs.write(".lex/lessons-candidates.jsonl", to_jsonl(project, groups))
  io.print(render_md(project, groups, list.len(files), list.len(failures), min_sessions))
}

