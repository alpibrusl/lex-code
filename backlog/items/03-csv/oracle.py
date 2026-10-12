#!/usr/bin/env python3
import json
def parse(s):
    fields, i, n = [], 0, len(s)
    while True:
        if i < n and s[i] == '"':
            i += 1; buf = []
            while True:
                if i >= n: return None
                if s[i] == '"':
                    if i + 1 < n and s[i+1] == '"': buf.append('"'); i += 2; continue
                    i += 1; break
                buf.append(s[i]); i += 1
            fields.append(''.join(buf))
            if i < n and s[i] != ',': return None
        else:
            j = i
            while j < n and s[j] != ',':
                if s[j] in '"\r\n': return None
                j += 1
            fields.append(s[i:j]); i = j
        if i >= n: return fields
        i += 1  # skip comma
        if i >= n: fields.append(''); return fields
def fmt(fs):
    out = []
    for f in fs:
        if any(c in f for c in ',"\r\n'): out.append('"' + f.replace('"', '""') + '"')
        else: out.append(f)
    return ','.join(out)
def Ok(x): return {"$variant": "Ok", "args": [x]}
LINES = ["", "a", "a,b,c", "a,,b", "a,", ",", ",,", " a , b ", '"a"', '"a,b",c', '"a""b",c', '""', '"",x', '"a\nb",c', 'a,"b,c",d', '"a"""', '""""', '"x","y"', 'é,ü', '"é,ü"', "日本,語", '"line1\r\nline2",z']
BAD = ['  "a"', '"a" ,b', '"a', 'a"b', 'a,"b', '"a"b', '"a" ,b ', 'a\nb', 'a\rb', '"a"x,b', 'a,b"c"', '"""', 'a,"b"c']
F = [["a"], ["a", "b"], [""], ["", ""], ["a,b"], ['a"b'], ["a\nb", "c"], [" a ", "b"], ['"'], ['a', '', 'b'], ["é", "日本"], ['x,"y"', 'z'], ["a\r\nb"], ["", "a", ""], []]
def main():
    for l in LINES:
        r = parse(l); assert r is not None, l
        print(json.dumps({"fn": "csv_parse_line", "args": [l], "expect": Ok(r)}))
    for l in BAD:
        assert parse(l) is None, l
        print(json.dumps({"fn": "csv_parse_line", "args": [l], "expect_err": True}))
    for f in F: print(json.dumps({"fn": "csv_format_line", "args": [f], "expect": fmt(f)}))
main()
