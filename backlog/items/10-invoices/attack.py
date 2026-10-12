#!/usr/bin/env python3
"""usage: attack.py PROJECT_DIR  — independent attack on a built `invoices` package."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from svc import Svc
proj = sys.argv[1]
s = Svc(proj, "invoices", {"INVOICES_TOKENS": "tokA:acme,tokB:globex", "INVOICES_DB": "{tmp}/a.db"}, 8812, port_env="INVOICES_PORT")
if not s.up: s.note("server starts with grants net,sql,env,fs_write", False, "did not start"); s.finish()
A, B = {"Authorization": "Bearer tokA"}, {"Authorization": "Bearer tokB"}
def mk(h, customer="acme-co", amount=1000, cur="USD", extra=None):
    b = {"customer": customer, "amount_cents": amount, "currency": cur}; b.update(extra or {})
    return s.req("POST", "/invoices", h, b)
c = s.check
# 1. authentication
r_none = c("no token -> 401", s.req("GET", "/invoices"), 401)
r_unk = c("unknown token -> 401", s.req("GET", "/invoices", {"Authorization": "Bearer nope"}), 401, excludes="nope")
c("malformed (Basic) -> 401", s.req("GET", "/invoices", {"Authorization": "Basic dG9rQQ=="}), 401)
c("scheme only -> 401", s.req("GET", "/invoices", {"Authorization": "Bearer"}), 401)
c("trailing space must not crash (200 or 401)", s.req("GET", "/invoices", {"Authorization": "Bearer tokA "}), [200, 401])
c("POST without token -> 401", s.req("POST", "/invoices", None, {"customer": "x", "amount_cents": 5, "currency": "USD"}), 401)
c("pay without token -> 401", s.req("POST", "/invoices/1/pay"), 401)
s.note("missing and unknown token give the identical 401 body", r_none[1] == r_unk[1], f"{r_none[1][:50]!r} vs {r_unk[1][:50]!r}")
# 2. create and read back
r = c("create -> 201, unpaid, with an id", mk(A, customer="acme-co"), 201, test=lambda j: j["paid"] is False and isinstance(j["id"], int))
id1 = (s.j(r[1]) or {}).get("id", 1)
c("create never echoes a token", mk(A), 201, excludes="tokA")
rb = c("B creates its own invoice (secret customer name)", mk(B, customer="zzq-secret-b"), 201)
idb = (s.j(rb[1]) or {}).get("id", 99)
c("GET own invoice -> 200", s.req("GET", f"/invoices/{id1}", A), 200, contains="acme-co")
# 3. listing
c("bare list -> 200", s.req("GET", "/invoices", A), 200, contains="acme-co", excludes="zzq-secret-b")
c("list shows only the caller's tenant", s.req("GET", "/invoices", B), 200, contains="zzq-secret-b", excludes="acme-co")
c("customer filter exact match", s.req("GET", "/invoices?customer=acme-co", A), 200, contains="acme-co")
c("customer filter is exact (no substring match)", s.req("GET", "/invoices?customer=acme", A), 200, excludes="acme-co")
c("customer filter is case sensitive", s.req("GET", "/invoices?customer=ACME-CO", A), 200, excludes="acme-co")
c("customer SQL injection matches nothing and never errors", s.req("GET", "/invoices?customer=x'%20OR%20'1'='1", A), 200, excludes="acme-co")
c("customer UNION injection returns nothing of B's", s.req("GET", "/invoices?customer=x'%20UNION%20SELECT%20*%20FROM%20invoices--", A), [200, 400], excludes="zzq-secret-b")
c("filter by another tenant's customer name shows nothing", s.req("GET", "/invoices?customer=zzq-secret-b", A), 200, excludes="zzq-secret-b")
# 4. isolation (the original false-success finding lives here)
miss = s.req("GET", "/invoices/999999", B)
c("B cannot read A's invoice: 404", s.req("GET", f"/invoices/{id1}", B), 404)
s.note("foreign id and missing id give the identical response", s.req("GET", f"/invoices/{id1}", B) == miss, f"{s.req('GET', f'/invoices/{id1}', B)} vs {miss}")
c("B cannot pay A's invoice: 404", s.req("POST", f"/invoices/{id1}/pay", B), 404)
c("pay a missing id: 404 (not a false 200)", s.req("POST", "/invoices/999999/pay", A), 404)
c("A's invoice still unpaid after B's attempt", s.req("GET", f"/invoices/{id1}", A), 200, test=lambda j: j["paid"] is False)
# 5. pay
c("pay -> 200 paid", s.req("POST", f"/invoices/{id1}/pay", A), 200, test=lambda j: j["paid"] is True)
c("pay again is idempotent -> 200", s.req("POST", f"/invoices/{id1}/pay", A), 200, test=lambda j: j["paid"] is True)
c("paid state persists on read", s.req("GET", f"/invoices/{id1}", A), 200, test=lambda j: j["paid"] is True)
c("B's invoice is not affected by A's pay", s.req("GET", f"/invoices/{idb}", B), 200, test=lambda j: j["paid"] is False)
# 6. path ids
for bad in ["0", "-1", "abc", "1%20OR%201=1", "..%2Fetc%2Fpasswd", "99999999999999999999", "1.5", "%27"]:
    c(f"GET path id {bad!r} -> 404", s.req("GET", f"/invoices/{bad}", A), 404)
    c(f"pay path id {bad!r} -> 404", s.req("POST", f"/invoices/{bad}/pay", A), 404)
# 7. validation
c("customer empty -> 400", mk(A, customer=""), 400)
c("customer whitespace only -> 400", mk(A, customer="   "), 400)
c("customer 101 chars -> 400", mk(A, customer="a" * 101), 400)
c("customer 100 chars -> 201", mk(A, customer="a" * 100), 201)
c("customer padded to 100 after trim -> 201", mk(A, customer="  " + "b" * 100 + "  "), 201)
c("amount 0 -> 400", mk(A, amount=0), 400)
c("amount -5 -> 400", mk(A, amount=-5), 400)
c("amount 10000001 -> 400", mk(A, amount=10000001), 400)
c("amount 10000000 -> 201", mk(A, amount=10000000), 201)
c("amount 1 -> 201", mk(A, amount=1), 201)
c("amount float -> 400", mk(A, amount=1.5), 400)
c("amount string -> 400", mk(A, amount="5"), 400)
for cur in ["JPY", "usd", "", "EURO"]: c(f"currency {cur!r} -> 400", mk(A, cur=cur), 400)
for cur in ["USD", "EUR", "GBP"]: c(f"currency {cur} -> 201", mk(A, cur=cur), 201)
for f, v in [("id", 5), ("tenant", "globex"), ("tenant_id", 2), ("paid", True), ("extra", 1)]:
    c(f"unknown/forbidden field {f!r} -> 400", mk(A, extra={f: v}), 400)
c("missing field -> 400", s.req("POST", "/invoices", A, {"customer": "x", "amount_cents": 5}), 400)
c("invalid JSON -> 400", s.req("POST", "/invoices", A, raw_body="{not json"), 400)
c("JSON array body -> 400", s.req("POST", "/invoices", A, raw_body="[1]"), 400)
c("empty body -> 400", s.req("POST", "/invoices", A, raw_body=""), 400)
c("customer with quotes stored verbatim", mk(A, customer="O'Brien \"x\" ' OR '1'='1"), 201, test=lambda j: j["customer"] == "O'Brien \"x\" ' OR '1'='1")
# 8. size limit
c("body of 5000 bytes -> 413", s.req("POST", "/invoices", A, raw_body='{"customer":"' + "a" * 5000 + '","amount_cents":5,"currency":"USD"}'), 413)
c("body of 200000 bytes -> 413", s.req("POST", "/invoices", A, raw_body='{"customer":"' + "a" * 200000 + '","amount_cents":5,"currency":"USD"}'), 413)
# 9. robustness
c("unknown route -> 404", s.req("GET", "/nothing", A), 404)
c("DELETE /invoices/1 -> 404 or 405", s.req("DELETE", f"/invoices/{id1}", A), [404, 405])
c("still alive after all of the above", s.req("GET", "/invoices", A), 200)
s.finish()
