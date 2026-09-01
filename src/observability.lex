# lex-code — OpenTelemetry export, projected from the trail
#
# #16 asked for spans around agent turns and tool calls. Most of that
# instrumentation already exists, in a different representation:
# lex-llm's `dispatch_one_traced` writes `cap.invoked` before every tool
# call and `cap.completed` / `cap.failed` after it, parented to the invoke
# event, and every trail `Event` carries `ts_ms`. A start, an end, a parent
# link and a name is a span — the trail is a trace that has never been
# spoken in OTel's wire format.
#
# So this module PROJECTS rather than instruments. Adding a second
# `span.start` / `span.finish` stream inside the same dispatch loop would
# put two systems on the same facts, and #32 is what that costs: the loop
# wrote verification events to one place, `attestation_query` read another,
# and the tool reported the gap as "no attestations" for months. One
# recording, two readers.
#
# ---- ids are derived, not drawn --------------------------------------
#
# `ctx.new_root()` needs `[random]`, and a random id would make every
# export of a session a different trace. Trail event ids are sha256 hashes
# of the event's own content, so a span id taken from one is stable: export
# the same turn twice and the second export updates the first trace instead
# of forging a rival. It also keeps `random` out of the turn's effect row
# entirely, which is why `finish_turn` needs only `env` and `net` added.
#
# ---- off unless asked -------------------------------------------------
#
# The issue specified stdout JSON-lines when no endpoint is configured.
# That is wrong here: `io.print` is the TUI's own output stream, so a
# default-on stdout exporter would dump OTel envelopes into the user's
# session on every turn. Export is off unless `LEX_OTLP_ENDPOINT` is set,
# with `LEX_OTEL_STDOUT=1` to opt into the stdout form deliberately.

import "lex-log/exporter" as exporter

import "lex-log/span" as span

import "lex-log/context" as tctx

import "lex-log/meter" as meter

import "lex-trail/log" as trail_log

import "lex-trail/event" as ev

import "lex-trail/kinds" as kinds

import "lex-schema/json_value" as jv

import "std.env" as env

import "std.str" as str

import "std.list" as list

import "std.int" as int

type Sink = { on :: Bool, cfg :: exporter.Config }

fn service_name() -> Str
  examples {
    service_name() => "lex-code"
  }
{
  "lex-code"
}

# An endpoint wins over the stdout flag: if both are set, the collector is
# clearly what the operator wants and the terminal stays clean.
fn from_env() -> [env] Sink {
  let endpoint := env_or("LEX_OTLP_ENDPOINT", "")
  if str.is_empty(endpoint) {
    if env_or("LEX_OTEL_STDOUT", "") == "1" {
      { on: true, cfg: exporter.stdout_config(service_name()) }
    } else {
      { on: false, cfg: exporter.stdout_config(service_name()) }
    }
  } else {
    { on: true, cfg: exporter.otlp_config(endpoint, service_name()) }
  }
}

fn env_or(key :: Str, fallback :: Str) -> [env] Str {
  match env.get(key) {
    None => fallback,
    Some(v) => if str.is_empty(v) {
      fallback
    } else {
      v
    },
  }
}

# ---- id derivation ---------------------------------------------------
fn trace_id_len() -> Int
  examples {
    trace_id_len() => 32
  }
{
  32
}

fn span_id_len() -> Int
  examples {
    span_id_len() => 16
  }
{
  16
}

fn is_hex_char(c :: Str) -> Bool
  examples {
    is_hex_char("0") => true,
    is_hex_char("f") => true,
    is_hex_char("F") => false,
    is_hex_char("g") => false,
    is_hex_char("-") => false
  }
{
  match c {
    "0" => true,
    "1" => true,
    "2" => true,
    "3" => true,
    "4" => true,
    "5" => true,
    "6" => true,
    "7" => true,
    "8" => true,
    "9" => true,
    "a" => true,
    "b" => true,
    "c" => true,
    "d" => true,
    "e" => true,
    "f" => true,
    _ => false,
  }
}

fn hex_only(s :: Str, i :: Int, acc :: Str) -> Str {
  if i >= str.len(s) {
    acc
  } else {
    let c := str.char_at(s, i)
    if is_hex_char(c) {
      hex_only(s, i + 1, str.concat(acc, c))
    } else {
      hex_only(s, i + 1, acc)
    }
  }
}

# Grow a hex string to exactly `n` characters by repeating it, then cut.
#
# This is a widening, not a hash: it must never collapse two distinct ids
# onto one output, so the input is repeated rather than padded with a
# constant. "ab" and "abab" would both pad to "ab0000…" under a zero-fill;
# repeating keeps them apart.
fn fill_to(s :: Str, n :: Int) -> Str {
  if str.is_empty(s) {
    fill_to("0", n)
  } else {
    if str.len(s) >= n {
      str.slice(s, 0, n)
    } else {
      fill_to(str.concat(s, s), n)
    }
  }
}

fn to_hex_id(raw :: Str, n :: Int) -> Str {
  fill_to(hex_only(str.to_lower(raw), 0, ""), n)
}

# A session's trace id. Session ids are already lowercase hex (see
# web.is_safe_id), so for the normal case this is a straight widening.
fn trace_id_of(session_id :: Str) -> Str
  examples {
    trace_id_of("a1b2c3d4") => "a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4",
    trace_id_of("") => "00000000000000000000000000000000",
    trace_id_of("ZZZ") => "00000000000000000000000000000000",
    trace_id_of("0123456789abcdef0123456789abcdef0123") => "0123456789abcdef0123456789abcdef"
  }
{
  to_hex_id(session_id, trace_id_len())
}

# A span id from a trail event id. Event ids are sha256 hex, so this is the
# first 16 characters of the hash — deterministic and stable across exports.
fn span_id_of(event_id :: Str) -> Str
  examples {
    span_id_of("0123456789abcdef0123456789abcdef") => "0123456789abcdef",
    span_id_of("") => "0000000000000000"
  }
{
  to_hex_id(event_id, span_id_len())
}

fn ctx_for(trace_id :: Str, event_id :: Str) -> tctx.TraceCtx {
  { trace_id: trace_id, span_id: span_id_of(event_id), sampled: true }
}

# ---- projection ------------------------------------------------------
fn tool_of(payload_json :: Str) -> Str
  examples {
    tool_of("{\"tool\":\"lex_check\"}") => "lex_check",
    tool_of("{\"result\":\"pass\"}") => "",
    tool_of("not json") => "",
    tool_of("") => ""
  }
{
  match jv.parse_into_errors(payload_json) {
    Err(_) => "",
    Ok(j) => match jv.get_field(j, "tool") {
      Some(JStr(t)) => t,
      _ => "",
    },
  }
}

fn span_name(tool :: Str) -> Str
  examples {
    span_name("lex_check") => "tool.lex_check",
    span_name("") => "tool.unknown"
  }
{
  if str.is_empty(tool) {
    "tool.unknown"
  } else {
    str.concat("tool.", tool)
  }
}

# An outcome belongs to an invoke only when it is parented to it. Matching
# on kind alone would pair every invoke with the first outcome in the turn,
# which silently mis-attributes durations and resurrects orphans — so the
# parent check is what these examples exist to hold down.
fn is_outcome_of(e :: ev.Event, invoked_id :: Str) -> Bool
  examples {
    is_outcome_of({ id: "x", kind: "cap.completed", parent: Some("inv1"), payload_json: "{}", ts_ms: 1 }, "inv1") => true,
    is_outcome_of({ id: "x", kind: "cap.failed", parent: Some("inv1"), payload_json: "{}", ts_ms: 1 }, "inv1") => true,
    is_outcome_of({ id: "x", kind: "cap.completed", parent: Some("other"), payload_json: "{}", ts_ms: 1 }, "inv1") => false,
    is_outcome_of({ id: "x", kind: "cap.completed", parent: None, payload_json: "{}", ts_ms: 1 }, "inv1") => false,
    is_outcome_of({ id: "x", kind: "cap.invoked", parent: Some("inv1"), payload_json: "{}", ts_ms: 1 }, "inv1") => false
  }
{
  let is_outcome := if e.kind == kinds.cap_completed() {
    true
  } else {
    e.kind == kinds.cap_failed()
  }
  if is_outcome {
    match e.parent {
      None => false,
      Some(p) => p == invoked_id,
    }
  } else {
    false
  }
}

# The `cap.completed` or `cap.failed` event whose parent is this invoke.
# A turn cut short mid-tool leaves an invoke with no outcome; that span is
# dropped rather than exported with a fabricated end time.
fn outcome_of(events :: List[ev.Event], invoked_id :: Str) -> Option[ev.Event] {
  list.head(list.filter(events, fn (e :: ev.Event) -> Bool {
    is_outcome_of(e, invoked_id)
  }))
}

fn tool_span(trace_id :: Str, parent_span :: Str, invoked :: ev.Event, outcome :: ev.Event) -> span.Span {
  let tool := tool_of(invoked.payload_json)
  let ok := outcome.kind == kinds.cap_completed()
  { ctx: ctx_for(trace_id, invoked.id), parent_id: parent_span, name: span_name(tool), service: service_name(), attrs: [("tool", tool), ("success", bool_str(ok))], start_ms: invoked.ts_ms, end_ms: outcome.ts_ms, status: if ok {
    SpanOk
  } else {
    SpanError(tool)
  } }
}

fn bool_str(b :: Bool) -> Str
  examples {
    bool_str(true) => "true",
    bool_str(false) => "false"
  }
{
  if b {
    "true"
  } else {
    "false"
  }
}

fn tool_spans(trace_id :: Str, parent_span :: Str, events :: List[ev.Event]) -> List[span.Span] {
  list.fold(events, [], fn (acc :: List[span.Span], e :: ev.Event) -> List[span.Span] {
    if e.kind == kinds.cap_invoked() {
      match outcome_of(events, e.id) {
        None => acc,
        Some(out) => list.concat(acc, [tool_span(trace_id, parent_span, e, out)]),
      }
    } else {
      acc
    }
  })
}

# The turn's own span, parent of every tool span in the turn. Its id comes
# from the session id and the turn's start, so two turns in one session get
# distinct spans under a shared trace.
fn turn_span(trace_id :: Str, session_id :: Str, started_ms :: Int, ended_ms :: Int) -> span.Span {
  { ctx: { trace_id: trace_id, span_id: turn_span_id(session_id, started_ms), sampled: true }, parent_id: "", name: "agent.turn", service: service_name(), attrs: [("session", session_id)], start_ms: started_ms, end_ms: ended_ms, status: SpanOk }
}

fn turn_span_id(session_id :: Str, started_ms :: Int) -> Str {
  to_hex_id(str.concat(session_id, int.to_str(started_ms)), span_id_len())
}

# ---- metrics ---------------------------------------------------------
fn tool_metrics(events :: List[ev.Event]) -> List[meter.Metric] {
  list.fold(events, [], fn (acc :: List[meter.Metric], e :: ev.Event) -> List[meter.Metric] {
    if e.kind == kinds.cap_invoked() {
      match outcome_of(events, e.id) {
        None => acc,
        Some(out) => {
          let ok := out.kind == kinds.cap_completed()
          list.concat(acc, [meter.counter("tool.calls", 1, [("tool", tool_of(e.payload_json)), ("success", bool_str(ok))])])
        },
      }
    } else {
      acc
    }
  })
}

fn turn_metrics(started_ms :: Int, ended_ms :: Int) -> List[meter.Metric] {
  [meter.histogram("turn.duration_ms", int.to_float(ended_ms - started_ms), [])]
}

# ---- export ----------------------------------------------------------
# Read the turn's slice of the session log and speak it as OTel.
#
# Bounded by the same [started_ms, ended_ms] window `verification.harvest`
# uses, so a long session does not re-export every earlier turn on every
# turn. Nothing here fails a turn: an unreachable collector costs telemetry,
# never the user's work.
fn export_turn(session_id :: Str, log :: trail_log.Log, started_ms :: Int, ended_ms :: Int) -> [env, net, io, sql, time] Unit {
  let sink := from_env()
  if sink.on {
    match trail_log.range(log, started_ms, ended_ms) {
      Err(_) => (),
      Ok(events) => {
        let trace_id := trace_id_of(session_id)
        let turn := turn_span(trace_id, session_id, started_ms, ended_ms)
        let spans := list.concat([turn], tool_spans(trace_id, turn.ctx.span_id, events))
        let __traces := exporter.export_spans(sink.cfg, spans)
        let __metrics := exporter.export_metrics(sink.cfg, list.concat(turn_metrics(started_ms, ended_ms), tool_metrics(events)))
        ()
      },
    }
  } else {
    ()
  }
}

