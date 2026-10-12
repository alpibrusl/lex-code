#!/usr/bin/env python3
import json, re
def parse(text):
    section, order, vals = "", [], {}
    for raw in text.split("\n"):
        line = raw[:-1] if raw.endswith("\r") else raw
        line = line.strip()
        if not line or line[0] in ";#": continue
        if line[0] == "[":
            if not line.endswith("]"): return None
            name = line[1:-1].strip()
            if not name or any(c in name for c in "[]="): return None
            section = name; continue
        if "=" not in line: return None
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', k): return None
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"': v = v[1:-1]
        full = (section + "." if section else "") + k
        if full not in vals: order.append(full)
        vals[full] = v
    return [f"{k}={vals[k]}" for k in order]
def Ok(x): return {"$variant": "Ok", "args": [x]}
def Opt(x): return {"$variant": "None", "args": []} if x is None else {"$variant": "Some", "args": [x]}
TEXTS = ["", "a=1", "a = 1", "  a  =  1  ", "a=1\nb=2", "[s]\na=1", "[s]\na=1\n[t]\na=2", "a=1\n[s]\nb=2", "; comment\n# other\na=1", "a=1\n\n\nb=2", "a=1\r\nb=2\r\n",
         "a=b=c", "a=", "a=\"quoted value\"", "a=\"  padded  \"", "a=\"half", "a=\"\"", "a=\"\"\"", "a = x ; not a comment", "[ spaced name ]\nk=v", "[a.b]\nc.d=e", "k=1\nk=2", "k=1\nj=2\nk=3", "[s]\nk=1\n[s]\nk=2\nj=3",
         "[s]\n; c\nk=1\n  # indented comment\nj=2", "é=1", "k=é", "[日本]\nキー=値", "a=1\n[s]\n[t]\nb=2", "key-with.dash_1=x", "=novalue", "a b=1", "[unclosed\na=1", "[]\na=1", "[a]b]\nk=1", "[a=b]\nk=1", "just text", "a=1\njust text", "[s] trailing\na=1", "a=1 \n b=2"]
def main():
    for t in TEXTS:
        r = parse(t)
        if r is None: print(json.dumps({"fn": "ini_parse", "args": [t], "expect_err": True}))
        else: print(json.dumps({"fn": "ini_parse", "args": [t], "expect": Ok(r)}))
    G = "a=1\n[s]\nk=v\nj = \"two words\"\n[t]\nk=w\n[a.b]\nc=d"
    for sec, key in [("", "a"), ("s", "k"), ("s", "j"), ("t", "k"), ("s", "x"), ("u", "k"), ("a.b", "c"), ("", "k")]:
        r = parse(G); d = dict(x.split("=", 1) for x in r)
        full = (sec + "." if sec else "") + key
        print(json.dumps({"fn": "ini_get", "args": [G, sec, key], "expect": Ok(Opt(d.get(full)))}))
    print(json.dumps({"fn": "ini_get", "args": ["[bad", "", "a"], "expect_err": True}))
main()
