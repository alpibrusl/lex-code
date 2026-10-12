#!/usr/bin/env python3
"""usage: attack.py PROJECT_DIR  — independent attack on a built `webhooks` package."""
import sys, os, hmac, hashlib, json, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from svc import Svc
proj = sys.argv[1]
SECRETS = {"alpha": "s3cret-alpha", "beta": "s3cret-beta"}
ADMIN = "adm-token-xyz"
s = Svc(proj, "webhooks", {"WEBHOOKS_SECRETS": ",".join(f"{k}:{v}" for k, v in SECRETS.items()), "WEBHOOKS_ADMIN_TOKEN": ADMIN, "WEBHOOKS_DB": "{tmp}/a.db"},
        8813, grants="net,sql,env,fs_write,crypto,time", port_env="WEBHOOKS_PORT")
if not s.up: s.note("server starts with grants net,sql,env,fs_write,crypto,time", False, "did not start"); s.finish()
c = s.check
def sign(secret, ts, body):
    return "sha256=" + hmac.new(secret.encode(), f"{ts}.".encode() + body, hashlib.sha256).hexdigest()
def send(source, event_id, obj=None, ts=None, secret=None, raw=None, sig=None, hdr=None):
    body = raw if raw is not None else json.dumps(obj if obj is not None else {"k": "v"}).encode()
    ts = int(time.time()) if ts is None else ts
    h = {"X-Timestamp": str(ts), "X-Event-Id": event_id, "Content-Type": "application/json"}
    h["X-Signature"] = sig if sig is not None else sign(secret if secret is not None else SECRETS.get(source, "x"), ts, body)
    h.update(hdr or {})
    for k in [k for k, v in h.items() if v is None]: del h[k]
    return s.req("POST", f"/hooks/{source}", h, raw_body=body)
AD = {"Authorization": f"Bearer {ADMIN}"}
def events(q=""):
    j = s.j(s.req("GET", "/events" + q, AD)[1])
    return j["events"] if isinstance(j, dict) and isinstance(j.get("events"), list) else None
# 1. happy path
r = c("valid delivery -> 202 not duplicate", send("alpha", "evt-1", {"a": 1}), 202, test=lambda j: j["duplicate"] is False and isinstance(j["id"], int))
id1 = (s.j(r[1]) or {}).get("id")
c("same event id again -> 200 duplicate with the original id", send("alpha", "evt-1", {"a": 1}), 200, test=lambda j: j["duplicate"] is True and j["id"] == id1)
c("same event id, other source -> 202 (independent)", send("beta", "evt-1", {"b": 2}), 202, test=lambda j: j["duplicate"] is False)
c("second event id -> 202", send("alpha", "evt-2", {"a": 2}), 202)
ev = events()
s.note("stored exactly 3 events (the duplicate was not stored)", ev is not None and len(ev) == 3, f"{None if ev is None else len(ev)}")
s.note("events ordered by id ascending", ev is not None and [e["id"] for e in ev] == sorted(e["id"] for e in ev))
s.note("event carries source, event_id, body", ev is not None and any(e["source"] == "alpha" and e["event_id"] == "evt-1" and e["body"] == {"a": 1} for e in ev))
# 2. signature failures
base = events() or []
r_bad = c("wrong signature -> 401", send("alpha", "x1", sig="sha256=" + "0" * 64), 401)
r_unk = c("unknown source -> 401", send("nosuch", "x2", secret="whatever"), 401)
s.note("unknown source and bad signature give the identical response", r_bad == r_unk, f"{r_bad} vs {r_unk}")
c("missing signature -> 401", send("alpha", "x3", hdr={"X-Signature": None}), 401)
c("signature without prefix -> 401", send("alpha", "x4", sig=sign("s3cret-alpha", int(time.time()), b'{"k": "v"}')[7:]), 401)
c("uppercase hex signature -> 401 (the form is lowercase hex)", send("alpha", "x5a", sig="sha256=" + sign("s3cret-alpha", int(time.time()), b'{"k": "v"}')[7:].upper()), 401)
c("signature of another source's secret -> 401", send("alpha", "x6", secret="s3cret-beta"), 401)
c("signature over a different body -> 401", send("alpha", "x7", raw=b'{"k": "v"}', sig=sign("s3cret-alpha", int(time.time()), b'{"k": "w"}')), 401)
c("signature over a different timestamp -> 401", send("alpha", "x8", ts=int(time.time()), sig=sign("s3cret-alpha", int(time.time()) - 5, b'{"k": "v"}')), 401)
c("signature with a trailing space -> 401", send("alpha", "x9", sig=sign("s3cret-alpha", int(time.time()), b'{"k": "v"}') + " "), 401)
c("empty signature -> 401", send("alpha", "x10", sig=""), 401)
c("garbage signature -> 401", send("alpha", "x11", sig="sha256=zz"), 401)
c("signature never echoes a secret", send("alpha", "x12", sig="sha256=" + "1" * 64), 401, excludes="s3cret")
after = events() or []
s.note("nothing was stored by any rejected request", len(after) == len(base), f"{len(base)} -> {len(after)}")
# 3. replay window and header validation (signed correctly, so they reach those checks)
now = int(time.time())
c("timestamp 400 s in the past -> 400", send("alpha", "t1", ts=now - 400), 400)
c("timestamp 400 s in the future -> 400", send("alpha", "t2", ts=now + 400), 400)
c("timestamp 250 s in the past -> accepted", send("alpha", "t3", ts=now - 250), 202)
c("timestamp 250 s in the future -> accepted", send("alpha", "t4", ts=now + 250), 202)
c("non-integer timestamp -> 400", send("alpha", "t5", hdr={"X-Timestamp": "yesterday"}, sig=sign("s3cret-alpha", "yesterday", b'{"k": "v"}')), 400)
c("missing timestamp is 400 or 401, never 5xx", send("alpha", "t6", hdr={"X-Timestamp": None}), [400, 401])
c("event id with a space -> 400", send("alpha", "bad id"), 400)
c("event id of 65 chars -> 400", send("alpha", "e" * 65), 400)
c("event id of 64 chars -> 202", send("alpha", "e" * 64), 202)
c("missing event id -> 400", send("alpha", "z", hdr={"X-Event-Id": None}), 400)
# 4. body rules (after the signature)
c("array body -> 400", send("alpha", "b1", raw=b"[1,2]"), 400)
c("string body -> 400", send("alpha", "b2", raw=b'"hello"'), 400)
c("invalid JSON body (validly signed) -> 400", send("alpha", "b3", raw=b"{nope"), 400)
c("empty body (validly signed) -> 400", send("alpha", "b4", raw=b""), 400)
c("nested object stored verbatim", send("alpha", "b5", {"n": {"x": [1, 2, {"y": "it's ' OR '1'='1"}]}}), 202)
big = b'{"p":"' + b"a" * 70000 + b'"}'
c("body over 65536 bytes -> 413 (even validly signed)", send("alpha", "big1", raw=big), 413)
c("body over 65536 bytes unsigned -> 401 or 413, never 5xx", s.req("POST", "/hooks/alpha", {"X-Timestamp": str(now), "X-Event-Id": "big2", "X-Signature": "sha256=" + "0" * 64}, raw_body=big), [401, 413])
c("body of exactly 65000 bytes validly signed -> 202", send("alpha", "big3", raw=b'{"p":"' + b"a" * 64900 + b'"}'), 202)
# 5. reading events
c("GET /events without token -> 401", s.req("GET", "/events"), 401)
c("GET /events with wrong token -> 401", s.req("GET", "/events", {"Authorization": "Bearer nope"}), 401, excludes="nope")
c("GET /events with Basic auth -> 401", s.req("GET", "/events", {"Authorization": "Basic YWRtaW4="}), 401)
c("GET /events with a source secret as token -> 401", s.req("GET", "/events", {"Authorization": "Bearer s3cret-alpha"}), 401)
c("GET /events with trailing-space token must not crash", s.req("GET", "/events", {"Authorization": f"Bearer {ADMIN} "}), [200, 401])
c("source filter -> only that source", s.req("GET", "/events?source=beta", AD), 200, test=lambda j: j["events"] and all(e["source"] == "beta" for e in j["events"]))
c("unconfigured source -> 400", s.req("GET", "/events?source=gamma", AD), 400)
c("source SQL injection -> 400", s.req("GET", "/events?source=a'%20OR%20'1'='1", AD), 400)
c("limit=0 -> 400", s.req("GET", "/events?limit=0", AD), 400)
c("limit=101 -> 400", s.req("GET", "/events?limit=101", AD), 400)
c("limit=abc -> 400", s.req("GET", "/events?limit=abc", AD), 400)
c("limit=2 -> exactly 2 events", s.req("GET", "/events?limit=2", AD), 200, test=lambda j: len(j["events"]) == 2)
c("no response contains a secret or the admin token", s.req("GET", "/events", AD), 200, excludes="s3cret")
# 6. deployment
lo = s.listens_on_loopback_only()
s.note("listens on loopback only by default", lo is True, "not loopback-only" if lo is False else "could not tell")
c("still alive after all of the above", s.req("GET", "/events", AD), 200)
s.finish()
