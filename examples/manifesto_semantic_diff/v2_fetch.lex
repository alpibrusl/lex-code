# lex-code — manifesto demo: semantic diff, not line diff (version 2)
#
# Version 2 of `fetch`: it now reaches the network. The signature gains
# a `[net]` effect row. To a line-based diff this is a handful of
# changed characters indistinguishable from a comment edit. To `lex diff`
# it is a structural fact: fetch's effect set gained `net` — the single
# most security-relevant change a review can surface.
#
#   lex ast-diff --json v1_fetch.lex v2_fetch.lex
#     -> .modified[].effect_changes.added == ["net"]

import "std.http" as http

fn fetch(url :: Str) -> [net] Bool {
  match http.get(url) {
    Ok(_) => true,
    Err(_) => false,
  }
}

