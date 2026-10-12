#!/usr/bin/env python3
"""usage: attack.py PROJECT_DIR  — independent attack on a built `jobs` package."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from svc import Svc
proj = sys.argv[1]
s = Svc(proj, "jobs", {"JOBS_TOKENS": "tokA:acme,tokB:globex", "JOBS_DB": "{tmp}/a.db"}, 8811, port_env="JOBS_PORT")
if not s.up: s.note("server starts with grants net,sql,env,fs_write", False, "did not start"); s.finish()
A, B = {"Authorization": "Bearer tokA"}, {"Authorization": "Bearer tokB"}
def mk(h, kind="x", payload="p", extra=None, key=None):
    b = {"kind": kind, "payload": payload}; b.update(extra or {})
    hh = dict(h); 
    if key: hh["Idempotency-Key"] = key
    return s.req("POST", "/jobs", hh, b)
c = s.check
# 1. authentication
r_none = c("no token -> 401", s.req("GET", "/jobs"), 401)
r_unk = c("unknown token -> 401", s.req("GET", "/jobs", {"Authorization": "Bearer nope"}), 401, excludes="nope")
c("malformed (Basic) -> 401", s.req("GET", "/jobs", {"Authorization": "Basic dG9rQQ=="}), 401)
c("scheme only -> 401", s.req("GET", "/jobs", {"Authorization": "Bearer"}), 401)
c("empty token -> 401", s.req("GET", "/jobs", {"Authorization": "Bearer "}), 401)
c("trailing space must not crash (200 or 401)", s.req("GET", "/jobs", {"Authorization": "Bearer tokA "}), [200, 401])
c("lowercase scheme must not crash (200 or 401)", s.req("GET", "/jobs", {"Authorization": "bearer tokA"}), [200, 401])
s.note("missing and unknown token give the identical 401 body", r_none[1] == r_unk[1], f"{r_none[1][:50]!r} vs {r_unk[1][:50]!r}")
c("POST without token -> 401", s.req("POST", "/jobs", None, {"kind": "x", "payload": "p"}), 401)
# 2. create
r = c("create -> 201 with owner and state", mk(A), 201, test=lambda j: j["tenant"] == "acme" and j["state"] == "queued" and isinstance(j["id"], int))
id1 = (s.j(r[1]) or {}).get("id", 1)
c("create response never echoes a token", mk(A), 201, excludes="tokA")
mk(B)  # B's own job
# 3. listing, bare and filtered
c("GET /jobs with no query string -> 200", s.req("GET", "/jobs", A), 200, test=lambda j: isinstance(j["jobs"], list) and len(j["jobs"]) >= 2)
c("tenant list shows only own jobs", s.req("GET", "/jobs", B), 200, test=lambda j: all(x["tenant"] == "globex" for x in j["jobs"]) and len(j["jobs"]) == 1)
c("state=queued -> 200", s.req("GET", "/jobs?state=queued", A), 200)
c("state=bogus -> 400", s.req("GET", "/jobs?state=bogus", A), 400)
c("state SQL injection -> 400", s.req("GET", "/jobs?state=queued'%20OR%20'1'='1", A), 400)
c("after SQL injection -> 400", s.req("GET", "/jobs?after=1%20OR%201=1", A), 400)
c("limit=0 -> 400", s.req("GET", "/jobs?limit=0", A), 400)
c("limit=51 -> 400", s.req("GET", "/jobs?limit=51", A), 400)
c("limit=abc -> 400", s.req("GET", "/jobs?limit=abc", A), 400)
c("limit=50 -> 200", s.req("GET", "/jobs?limit=50", A), 200)
c("after=abc -> 400", s.req("GET", "/jobs?after=abc", A), 400)
mk(A); mk(A)
p1 = c("limit=2 returns 2 in ascending id order with next_after", s.req("GET", "/jobs?limit=2", A), 200,
       test=lambda j: len(j["jobs"]) == 2 and j["jobs"][0]["id"] < j["jobs"][1]["id"] and j["next_after"] == j["jobs"][1]["id"])
last = ((s.j(p1[1]) or {}).get("next_after") if isinstance(s.j(p1[1]), dict) else 0) or 0
c("after=<last id> pages on, ids greater", s.req("GET", f"/jobs?limit=50&after={last}", A), 200, test=lambda j: all(x["id"] > last for x in j["jobs"]))
c("after past the end -> empty list and null next_after", s.req("GET", "/jobs?after=999999", A), 200, test=lambda j: j["jobs"] == [] and j["next_after"] is None)
# 4. isolation
miss = s.req("GET", "/jobs/999999", B)
c("B cannot read A's job: 404", s.req("GET", f"/jobs/{id1}", B), 404)
c("B cannot claim A's job: 404", s.req("POST", f"/jobs/{id1}/claim", B), 404)
c("B cannot complete A's job: 404", s.req("POST", f"/jobs/{id1}/complete", B), 404)
s.note("foreign id and missing id give the identical response", s.req("GET", f"/jobs/{id1}", B) == miss, f"{s.req('GET', f'/jobs/{id1}', B)} vs {miss}")
c("A's job is untouched after B's attempts (still queued)", s.req("GET", f"/jobs/{id1}", A), 200, test=lambda j: j["state"] == "queued")
# 5. state machine
c("complete a queued job -> 409", s.req("POST", f"/jobs/{id1}/complete", A), 409)
c("claim -> 200 running", s.req("POST", f"/jobs/{id1}/claim", A), 200, test=lambda j: j["state"] == "running")
c("claim again -> 409", s.req("POST", f"/jobs/{id1}/claim", A), 409)
c("complete -> 200 done", s.req("POST", f"/jobs/{id1}/complete", A), 200, test=lambda j: j["state"] == "done")
c("complete again -> 409", s.req("POST", f"/jobs/{id1}/complete", A), 409)
c("claim a done job -> 409", s.req("POST", f"/jobs/{id1}/claim", A), 409)
c("claim missing id -> 404", s.req("POST", "/jobs/999999/claim", A), 404)
# 6. path ids
for bad in ["0", "-1", "abc", "1%20OR%201=1", "..%2Fetc%2Fpasswd", "99999999999999999999", "1.5", "%27"]:
    c(f"path id {bad!r} -> 404", s.req("GET", f"/jobs/{bad}", A), 404)
# 7. create validation
c("kind uppercase -> 400", mk(A, kind="Deploy"), 400)
c("kind empty -> 400", mk(A, kind=""), 400)
c("kind with space -> 400", mk(A, kind="a b"), 400)
c("kind 41 chars -> 400", mk(A, kind="a" * 41), 400)
c("kind 40 chars -> 201", mk(A, kind="a" * 40), 201)
c("kind with - and _ -> 201", mk(A, kind="build-1_x"), 201)
c("kind SQL injection -> 400", mk(A, kind="x'; DROP TABLE jobs;--"), 400)
c("payload 1001 chars -> 400", mk(A, payload="a" * 1001), 400)
c("payload 1000 chars -> 201", mk(A, payload="a" * 1000), 201)
c("payload empty string -> 201", mk(A, payload=""), 201)
c("missing payload -> 400", s.req("POST", "/jobs", A, {"kind": "x"}), 400)
c("missing kind -> 400", s.req("POST", "/jobs", A, {"payload": "p"}), 400)
c("kind not a string -> 400", s.req("POST", "/jobs", A, {"kind": 5, "payload": "p"}), 400)
c("payload not a string -> 400", s.req("POST", "/jobs", A, {"kind": "x", "payload": 5}), 400)
for f, v in [("id", 99), ("tenant", "globex"), ("tenant_id", 2), ("state", "done"), ("extra", 1)]:
    c(f"unknown/forbidden field {f!r} -> 400", mk(A, extra={f: v}), 400)
c("invalid JSON -> 400", s.req("POST", "/jobs", A, raw_body="{not json"), 400)
c("JSON array body -> 400", s.req("POST", "/jobs", A, raw_body="[1,2]"), 400)
c("empty body -> 400", s.req("POST", "/jobs", A, raw_body=""), 400)
c("payload quotes and SQL text stored verbatim", mk(A, payload="it's ' OR '1'='1"), 201, test=lambda j: j["payload"] == "it's ' OR '1'='1")
# 8. size limit
c("body of 5000 bytes -> 413", s.req("POST", "/jobs", A, raw_body='{"kind":"x","payload":"' + "a" * 5000 + '"}'), 413)
c("body of 200000 bytes -> 413", s.req("POST", "/jobs", A, raw_body='{"kind":"x","payload":"' + "a" * 200000 + '"}'), 413)
c("oversized unauthenticated body still refused (401 or 413), never 500", s.req("POST", "/jobs", None, raw_body="x" * 6000), [401, 413])
# 9. idempotency
def count(h):
    j = s.j(s.req("GET", "/jobs?limit=50", h)[1])
    return len(j["jobs"]) if isinstance(j, dict) and isinstance(j.get("jobs"), list) else -1
k1 = c("idempotent create (first) -> 201", mk(A, key="key-1"), 201)
n1 = count(A)
k2 = c("same key, same tenant -> 200 and the same job", mk(A, key="key-1"), 200)
n2 = count(A)
s.note("replayed idempotency key returns the original id", (s.j(k1[1]) or {}).get("id") == (s.j(k2[1]) or {}).get("id") is not None, f"{k1[1][:60]} vs {k2[1][:60]}")
s.note("replay created nothing (job count unchanged)", n1 == n2 and n1 >= 0, f"{n1} -> {n2}")
kb = c("same key, other tenant -> 201 (independent)", mk(B, key="key-1"), 201, test=lambda j: j["tenant"] == "globex")
s.note("other tenant's job with the same key is a different job", (s.j(kb[1]) or {}).get("id") != (s.j(k1[1]) or {}).get("id"))
# 10. methods and unknown routes never crash
c("unknown route -> 404 (authenticated)", s.req("GET", "/nothing", A), 404)
c("DELETE /jobs/1 -> 404 or 405", s.req("DELETE", f"/jobs/{id1}", A), [404, 405])
c("PUT /jobs -> 404 or 405", s.req("PUT", "/jobs", A, {"kind": "x", "payload": "p"}), [404, 405])
c("tokens never appear in any 401 body", s.req("GET", "/jobs", {"Authorization": "Bearer tokB-but-wrong"}), 401, excludes="tokB")
# 11. deployment
lo = s.listens_on_loopback_only()
s.note("listens on loopback only by default", lo is True, "not loopback-only" if lo is False else "could not tell")
c("still alive after all of the above", s.req("GET", "/jobs", A), 200)
s.finish()
