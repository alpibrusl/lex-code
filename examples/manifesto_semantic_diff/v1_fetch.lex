# lex-code — manifesto demo: semantic diff, not line diff (version 1)
#
# Manifesto §III:
#   "A diff that says 'the type of fn execute changed from [io] -> R to
#    [io, net] -> R' tells an agent something. A diff that says 'line 47
#    changed' tells a human something. We give them the second."
#
# This is version 1 of `fetch`: a PURE function (no effect row). Compare
# it against v2_fetch.lex with `lex diff` — see run.sh.

fn fetch(url :: Str) -> Bool {
  url != ""
}

