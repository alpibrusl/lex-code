#!/usr/bin/env python3
import json, re
U = [('w', 604800), ('d', 86400), ('h', 3600), ('m', 60), ('s', 1)]
def parse(s):
    if not re.fullmatch(r'(?:[0-9]{1,9}[wdhms])+', s): return None
    parts = re.findall(r'([0-9]{1,9})([wdhms])', s)
    order = [u for u, _ in U]; last = -1; total = 0
    for n, u in parts:
        idx = order.index(u)
        if idx <= last: return None
        last = idx; total += int(n) * dict(U)[u]
    return total
def fmt(n):
    if n < 0: return None
    if n == 0: return "0s"
    out = ''
    for u, k in U:
        q, n = divmod(n, k)
        if q: out += f"{q}{u}"
    return out
def Ok(x): return {"$variant": "Ok", "args": [x]}
GOOD = ["0s", "1s", "59s", "60s", "90s", "1m", "90m", "1h", "1h30m", "2d4h", "1w", "1w1d1h1m1s", "10w", "999999999s", "5m30s", "00s", "007m", "1d12h", "3h45s", "2w3m"]
BAD = ["", "s", "1", "1x", "1 s", " 1s", "1s ", "-1s", "+1s", "1.5h", "1h1h", "30m1h", "1s1m", "1h 30m", "1H", "1ms", "1000000000s", "h1", "1hh", "1h30", "0", "٣s"]
N = [0, 1, 59, 60, 61, 3599, 3600, 3661, 86399, 86400, 90061, 604800, 604801, 1209600, 1814399, 999999999, 1000000000, 31536000, 123456789]
def main():
    for g in GOOD: print(json.dumps({"fn": "duration_parse", "args": [g], "expect": Ok(parse(g))}))
    for b in BAD:
        assert parse(b) is None, b
        print(json.dumps({"fn": "duration_parse", "args": [b], "expect_err": True}))
    for n in N: print(json.dumps({"fn": "duration_format", "args": [n], "expect": Ok(fmt(n))}))
    for n in [-1, -60, -999999]: print(json.dumps({"fn": "duration_format", "args": [n], "expect_err": True}))
main()
