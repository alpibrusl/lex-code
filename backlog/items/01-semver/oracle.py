#!/usr/bin/env python3
import json, re
IDENT = re.compile(r'^[0-9A-Za-z-]+$')
def parse(s):
    m = re.match(r'^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(?:-([^+]*))?(?:\+(.*))?$', s)
    if not m: return None
    pre = m.group(4)
    if pre is not None:
        ids = pre.split('.')
        for i in ids:
            if not i or not IDENT.match(i): return None
            if i.isdigit() and len(i) > 1 and i[0] == '0': return None
    if m.group(5) is not None:
        for i in m.group(5).split('.'):
            if not i or not IDENT.match(i): return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), pre.split('.') if pre is not None else None)
def cmp_ids(a, b):
    for x, y in zip(a, b):
        if x == y: continue
        xn, yn = x.isdigit(), y.isdigit()
        if xn and yn: return -1 if int(x) < int(y) else 1
        if xn: return -1
        if yn: return 1
        return -1 if x < y else 1
    return (len(a) > len(b)) - (len(a) < len(b))
def compare(a, b):
    pa, pb = parse(a), parse(b)
    if pa is None or pb is None: return None
    for x, y in zip(pa[:3], pb[:3]):
        if x != y: return -1 if x < y else 1
    if pa[3] is None and pb[3] is None: return 0
    if pa[3] is None: return 1
    if pb[3] is None: return -1
    return cmp_ids(pa[3], pb[3])
def comparators(rng):
    out = []
    for tok in rng.split(' '):
        m = re.match(r'^(>=|<=|>|<|=|\^|~)?(.+)$', tok)
        op, v = m.group(1) or '=', m.group(2)
        p = parse(v)
        if p is None: return None
        M, m_, pa = p[0], p[1], p[2]
        if op == '^':
            if M > 0: hi = f"{M+1}.0.0"
            elif m_ > 0: hi = f"0.{m_+1}.0"
            else: hi = f"0.0.{pa+1}"
            out += [('>=', v), ('<', hi)]
        elif op == '~':
            out += [('>=', v), ('<', f"{M}.{m_+1}.0")]
        else:
            out.append((op, v))
    return out
def satisfies(ver, rng):
    if parse(ver) is None or not rng or rng != rng.strip() or '  ' in rng: return None
    cs = comparators(rng)
    if cs is None: return None
    ok = True
    for op, v in cs:
        c = compare(ver, v)
        ok = ok and {'=': c == 0, '>': c > 0, '>=': c >= 0, '<': c < 0, '<=': c <= 0}[op]
    return ok
def Ok(x): return {"$variant": "Ok", "args": [x]}
V = ["1.0.0", "1.0.1", "1.1.0", "2.0.0", "0.0.0", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0+build5", "1.0.0-alpha+exp.sha", "10.20.30", "1.0.0-0", "1.0.0-a-b", "0.1.0", "0.0.3", "123456789.0.0"]
BAD = ["", "1", "1.2", "1.2.3.4", "v1.2.3", "01.2.3", "1.02.3", "1.2.03", "1.2.3-", "1.2.3-01", "1.2.3-a..b", "1.2.3+", "1.2.3-a_b", "a.b.c", "1.2.-3", "1.2.3 ", " 1.2.3", "1234567890.0.0", "1.2.3+a..b", "1.2.3-+x"]
def main():
    for v in V: print(json.dumps({"fn": "semver_valid", "args": [v], "expect": True}))
    for v in BAD: print(json.dumps({"fn": "semver_valid", "args": [v], "expect": False}))
    for a in V[:12]:
        for b in V[:12]:
            print(json.dumps({"fn": "semver_compare", "args": [a, b], "expect": Ok(compare(a, b))}))
    for a, b in [("1.0.0+a", "1.0.0+b"), ("1.0.0-alpha.1", "1.0.0-alpha.beta"), ("1.0.0-beta.2", "1.0.0-beta.11"), ("1.0.0-1", "1.0.0-a"), ("1.0.0-alpha", "1.0.0-alpha.1")]:
        print(json.dumps({"fn": "semver_compare", "args": [a, b], "expect": Ok(compare(a, b))}))
    for a, b in [("1.2", "1.2.3"), ("1.2.3", "x"), ("", "1.0.0")]:
        print(json.dumps({"fn": "semver_compare", "args": [a, b], "expect_err": True}))
    R = ["1.2.3", "=1.2.3", ">1.2.3", ">=1.2.3", "<1.2.3", "<=1.2.3", "^1.2.3", "~1.2.3", "^0.2.3", "^0.0.3", "~0.2.3", ">=1.0.0 <2.0.0", ">1.0.0 <=1.1.0", "^1.0.0 <1.5.0", ">=1.0.0-alpha <1.0.0", "^1.0.0-beta", "~1.2.3-alpha"]
    T = ["1.2.3", "1.2.4", "1.3.0", "2.0.0", "1.2.2", "0.2.3", "0.2.9", "0.3.0", "0.0.3", "0.0.4", "1.0.0", "1.0.0-alpha", "1.0.0-beta.2", "1.1.0", "1.9.9", "1.4.99", "1.5.0"]
    for r in R:
        for t in T:
            print(json.dumps({"fn": "semver_satisfies", "args": [t, r], "expect": Ok(satisfies(t, r))}))
    for t, r in [("1.2.3", ""), ("1.2.3", " >=1.0.0"), ("1.2.3", ">=1.0.0 "), ("1.2.3", ">=1.0.0  <2.0.0"), ("1.2.3", "^1.2"), ("1.2.3", "^"), ("1.2.3", "~x"), ("1.2", ">=1.0.0"), ("x", "1.0.0"), ("1.2.3", "!=1.0.0"), ("1.2.3", ">= 1.0.0")]:
        print(json.dumps({"fn": "semver_satisfies", "args": [t, r], "expect_err": True}))
main()
