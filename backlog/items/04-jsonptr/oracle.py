#!/usr/bin/env python3
import json, re
def esc(t): return t.replace('~', '~0').replace('/', '~1')
def unesc(t):
    if re.search(r'~(?![01])', t): return None
    return t.replace('~1', '/').replace('~0', '~')
def parse(p):
    if p == '': return []
    if not p.startswith('/'): return None
    out = []
    for t in p[1:].split('/'):
        u = unesc(t)
        if u is None: return None
        out.append(u)
    return out
def fmt(ts): return ''.join('/' + esc(t) for t in ts)
def Ok(x): return {"$variant": "Ok", "args": [x]}
GOOD = ["", "/", "//", "/a", "/a/b", "/a~1b", "/a~0b", "/~01", "/~10", "/a/", "/é/日本", "/ /", "/0/1", "/a~1~1b", "/~0~1"]
BAD = ["a", "a/b", "~", "/~", "/~2", "/a~", "/a~x/b", "/~/a", "x/", " /a"]
T = [[], [""], ["a"], ["a", "b"], ["a/b"], ["a~b"], ["~1"], ["~0"], ["a/b", "c~d", ""], ["é"], ["", ""]]
def main():
    for p in GOOD: print(json.dumps({"fn": "ptr_parse", "args": [p], "expect": Ok(parse(p))}))
    for p in BAD: print(json.dumps({"fn": "ptr_parse", "args": [p], "expect_err": True}))
    for t in T: print(json.dumps({"fn": "ptr_format", "args": [t], "expect": fmt(t)}))
    for p in GOOD:
        for t in ["x", "a/b", "~", "", "é"]:
            print(json.dumps({"fn": "ptr_append", "args": [p, t], "expect": Ok(p + '/' + esc(t))}))
    for p in BAD[:4]: print(json.dumps({"fn": "ptr_append", "args": [p, "x"], "expect_err": True}))
    for p in GOOD:
        if p == '': print(json.dumps({"fn": "ptr_parent", "args": [p], "expect_err": True}))
        else: print(json.dumps({"fn": "ptr_parent", "args": [p], "expect": Ok(p[:p.rindex('/')])}))
    for p in BAD[:4]: print(json.dumps({"fn": "ptr_parent", "args": [p], "expect_err": True}))
main()
