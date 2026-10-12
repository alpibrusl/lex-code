#!/usr/bin/env python3
import json
def dist(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + (ca != cb)))
        prev = cur
    return prev[-1]
def sim(a, b):
    m = max(len(a), len(b))
    return 100 if m == 0 else (100 * (m - dist(a, b))) // m
def closest(q, cs):
    if not cs: return {"$variant": "None", "args": []}
    best = min(range(len(cs)), key=lambda i: (dist(q, cs[i]), i))
    return {"$variant": "Some", "args": [cs[best]]}
P = [("", ""), ("a", ""), ("", "abc"), ("kitten", "sitting"), ("flaw", "lawn"), ("abc", "abc"), ("abc", "abd"), ("abc", "acb"), ("saturday", "sunday"), ("intention", "execution"),
     ("café", "cafe"), ("café", "cafés"), ("日本語", "日本"), ("日本語", "中国語"), ("é", "e"), ("ü", "ue"), ("naïve", "naive"), ("a" * 40, "b" * 40), ("abcdefghij" * 5, "abcdefghij" * 4 + "abcdefghix"), ("x" * 60, "")]
C = [("kitten", ["sitting", "mitten", "bitten", "kitchen"]), ("abc", []), ("abc", ["abd", "abe"]), ("abc", ["xyz"]), ("café", ["cafe", "caff", "cafés"]), ("a", ["b", "a", "a"]), ("", ["x", "", "yy"]), ("日本", ["日本語", "本日", "日"]), ("same", ["same", "same"])]
def main():
    for a, b in P:
        print(json.dumps({"fn": "edit_distance", "args": [a, b], "expect": dist(a, b)}))
        print(json.dumps({"fn": "similarity_pct", "args": [a, b], "expect": sim(a, b)}))
    for q, cs in C: print(json.dumps({"fn": "closest", "args": [q, cs], "expect": closest(q, cs)}))
main()
