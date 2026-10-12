#!/usr/bin/env python3
import json
def refill(tok, last, now, cap, per):
    el = max(0, now - last)
    return min(cap * 1000, tok + el * per)
def take(tok, cost):
    if cost < 1: return None
    return tok - cost * 1000 if tok >= cost * 1000 else None
def retry(tok, cost, per, cap=None):
    if cost < 1: return -1
    if cap is not None and cost > cap: return -1
    if tok >= cost * 1000: return 0
    if per <= 0: return -1
    need = cost * 1000 - tok
    return (need + per - 1) // per
def allow(tok, last, now, cap, per, cost):
    t = refill(tok, last, now, cap, per)
    if cost < 1 or cost > cap: return {"allowed": False, "tokens_milli": t, "retry_ms": -1}
    r = take(t, cost)
    if r is not None: return {"allowed": True, "tokens_milli": r, "retry_ms": 0}
    return {"allowed": False, "tokens_milli": t, "retry_ms": retry(t, cost, per)}
def opt(x): return {"$variant": "None", "args": []} if x is None else {"$variant": "Some", "args": [x]}
R = [(0, 0, 0, 10, 1), (0, 0, 1000, 10, 1), (0, 0, 1000, 10, 5), (9500, 0, 1000, 10, 1), (500, 100, 50, 10, 1), (0, 0, 10000, 10, 1), (0, 0, 20000, 10, 1), (3000, 1000, 1001, 5, 10), (0, 5, 5, 3, 7), (2999, 0, 1, 3, 1), (0, 0, 3000, 3, 1000), (12345, 10, 12, 20, 3)]
T = [(5000, 1), (5000, 5), (4999, 5), (999, 1), (1000, 1), (0, 1), (5000, 0), (5000, -3), (10000, 10), (9999, 10)]
RA = [(0, 1, 1, 10), (0, 1, 2, 10), (500, 1, 1, 10), (999, 1, 1, 10), (1000, 1, 1, 10), (0, 5, 3, 10), (1, 1, 3, 10), (2500, 3, 7, 10), (0, 1, 0, 10), (0, 11, 5, 10), (0, 0, 5, 10), (0, 10, 1000, 10)]
A = [(10000, 0, 0, 10, 1, 1), (0, 0, 0, 10, 1, 1), (0, 0, 500, 10, 2, 1), (0, 0, 1000, 10, 2, 1), (500, 0, 600, 10, 10, 1), (0, 0, 0, 10, 1, 11), (0, 0, 100000, 10, 1, 10), (9500, 0, 100, 10, 5, 2), (3000, 50, 40, 5, 1, 3), (0, 0, 0, 3, 7, 3), (0, 0, 428, 3, 7, 3), (0, 0, 429, 3, 7, 3)]
def main():
    for a in R: print(json.dumps({"fn": "bucket_refill", "args": list(a), "expect": refill(*a)}))
    for a in T: print(json.dumps({"fn": "bucket_take", "args": list(a), "expect": opt(take(*a))}))
    for t, c, p, cap in RA: print(json.dumps({"fn": "retry_after_ms", "args": [t, c, p, cap], "expect": retry(t, c, p, cap)}))
    for a in A: print(json.dumps({"fn": "bucket_allow", "args": list(a), "expect": allow(*a)}))
main()
