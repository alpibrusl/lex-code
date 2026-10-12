#!/usr/bin/env python3
import json, re
def translate(p):
    out, i, n = [], 0, len(p)
    while i < n:
        c = p[i]
        if c == '\\':
            if i + 1 >= n: return None
            out.append(re.escape(p[i+1])); i += 2
        elif c == '*':
            if i + 1 < n and p[i+1] == '*': out.append('.*'); i += 2
            else: out.append('[^/]*'); i += 1
        elif c == '?': out.append('[^/]'); i += 1
        elif c == '[':
            j = i + 1; neg = False
            if j < n and p[j] == '!': neg = True; j += 1
            k = p.find(']', j)
            if k == -1 or k == j: return None
            content = p[j:k]; items = []; a = 0
            while a < len(content):
                if a + 2 < len(content) and content[a+1] == '-':
                    lo, hi = content[a], content[a+2]
                    if lo > hi: return None
                    items.append(re.escape(lo) + '-' + re.escape(hi)); a += 3
                else:
                    items.append(re.escape(content[a])); a += 1
            body = ''.join(items)
            out.append(('[^' + body + '/]') if neg else ('(?!/)[' + body + ']')); i = k + 1
        else: out.append(re.escape(c)); i += 1
    return ''.join(out)
def valid(p): return translate(p) is not None
def match(p, t):
    r = translate(p)
    return r is not None and re.fullmatch(r, t, re.S) is not None
PAIRS = [("*.txt","a.txt"),("*.txt",".txt"),("*.txt","a/b.txt"),("**.txt","a/b.txt"),("a/**/b","a/x/y/b"),("a/**/b","a/b"),("a/**","a/b/c"),("**","a/b"),("*","a/b"),("*",""),
 ("","") ,("","a"),("?","a"),("?","/"),("?",""),("??","ab"),("a?c","abc"),("a?c","a/c"),("[abc]","b"),("[abc]","d"),("[a-c]","b"),("[a-c]x","dx"),("[!a-c]","d"),("[!a-c]","b"),("[!a]","/"),
 ("[a-]","-"),("[a-]","a"),("[a-]","b"),("[-a]","-"),("[]]","]"),("a\\*b","a*b"),("a\\*b","axb"),("\\?","?"),("\\\\","\\"),("file[0-9].log","file7.log"),("file[0-9].log","filex.log"),
 ("*.[ch]","main.c"),("*.[ch]","main.h"),("*.[ch]","main.o"),("src/*/lib.rs","src/core/lib.rs"),("src/*/lib.rs","src/a/b/lib.rs"),("src/**/lib.rs","src/a/b/lib.rs"),
 ("é?","éa"),("é?","éaa"),("?","é"),("??","é"),("[é]","é"),("*é","caffé"),("a*b*c","aXXbYYc"),("a*b*c","acb"),("a*a*a*a*b","aaaaaaaaaaaaaaaaaaaaaaaaa"),("a*a*a*a*b","aaaaaaaaaaaaaaaaaab"),
 ("**/*.lex","x.lex"),("**/*.lex","a/b/x.lex"),("*/**","a/"),("[a-c]*","bcd"),("[!/]","x"),("[/]","/"),("x[!]","x!"),("[z-a]","m"),("a\\","a\\"),("[abc","a"),("[","["),("[!","a")]
BAD = ["[abc","[","[!","[]","[!]","a\\","[z-a]","[a-c","\\",""]
GOOD = ["*","**","?","[a]","[!a]","[a-z]","\\*","a/**/b","[-a]","[a-]","[]]","é*","[]a]"]
def main():
    for p, t in PAIRS: print(json.dumps({"fn": "glob_match", "args": [p, t], "expect": match(p, t)}))
    for p in BAD + GOOD: print(json.dumps({"fn": "glob_valid", "args": [p], "expect": valid(p)}))
main()
