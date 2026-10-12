#!/usr/bin/env python3
"""Independent audit of a built pure Lex library against an oracle.

usage: audit_lib.py ITEM_DIR PROJECT_DIR

ITEM_DIR/oracle.py prints one JSON case per line:
  {"fn": "name", "args": [...], "expect": <json>}      exact match on `lex run` output
  {"fn": "name", "args": [...], "expect_err": true}    any Err variant
The library is run WITHOUT any effect grant: a pure library must not need one.
Exit 0 only if every case passes. Last line is machine-readable:
  [AUDIT] <passed>/<total> cases hold
"""
import json, subprocess, sys, os

def run_case(proj, pkg, c):
    cmd = ["lex", "run", f"src/{pkg}.lex", c["fn"]] + [json.dumps(a) for a in c["args"]]
    try:
        p = subprocess.run(cmd, cwd=proj, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    out = p.stdout.strip()
    if p.returncode != 0:
        return False, "error: " + (p.stderr.strip() or out)[:160]
    try:
        got = json.loads(out)
    except Exception:
        return False, "unparseable output: " + out[:100]
    if c.get("expect_err"):
        ok = isinstance(got, dict) and got.get("$variant") == "Err"
        return ok, f"got {json.dumps(got)[:100]}"
    return got == c["expect"], f"got {json.dumps(got)[:100]}"

def main():
    item, proj = sys.argv[1], sys.argv[2]
    pkg = json.load(open(os.path.join(item, "meta.json")))["package"]
    cases = [json.loads(l) for l in subprocess.run(
        [sys.executable, os.path.join(item, "oracle.py")], capture_output=True, text=True, check=True
    ).stdout.splitlines() if l.strip()]
    bad = []
    for c in cases:
        ok, why = run_case(proj, pkg, c)
        if not ok:
            bad.append(f"  - {c['fn']}({', '.join(json.dumps(a) for a in c['args'])}): expected "
                       f"{'Err' if c.get('expect_err') else json.dumps(c['expect'])}, {why}")
    for b in bad[:25]:
        print(b)
    print(f"[AUDIT] {len(cases)-len(bad)}/{len(cases)} cases hold")
    sys.exit(0 if not bad else 1)

main()
