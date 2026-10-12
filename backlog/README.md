# lex-code backlog: briefs with an independent audit

Each item is a brief for `lex-code-overnight` plus an **oracle or attack written before any run**,
so "done" can be checked by something other than the build's own acceptance gate (jobs passed
18/18 acceptance and still answered 500 to a plain `GET /jobs`).

```
items/NN-name/
  brief.txt     the brief given to lex-code (public API pinned: exact names, plain types)
  meta.json     package name, kind (lib|service), held_out, est. units, grants, notes
  oracle.py     libs: prints one JSON test case per line (expected values from a Python reference)
  attack.py     services: black-box attack, expected statuses taken from the brief
```

| item | kind | est. units | held out | notes |
|---|---|---|---|---|
| 01-semver | lib | 6 | no | compare/ranges; numeric vs lexical identifiers |
| 02-glob | lib | 5 | no | pattern compile + match; code points; no exponential backtracking |
| 03-csv | lib | 4 | **yes** | quoting state machine; round trip |
| 04-jsonptr | lib | 4 | no | escape/unescape order |
| 05-duration | lib | 3 | **yes** | ordered units; **oracle validated against a hand-written Lex implementation: 64/64** |
| 06-editdistance | lib | 4 | no | code points (byte-length trap); integer percent |
| 07-tokenbucket | lib | 4 | **yes** | integer math, ceiling division, record return |
| 08-ini | lib | 5 | no | first-`=` split, quote stripping, `Option` inside `Result` |
| 09-jobs | service | 16 | no | already built once: attack finds 10 of 83 checks failing (bare `GET /jobs` 500, unknown field accepted, trailing-space token 500) |
| 10-invoices | service | 18 | no | brief fixed to name `INVOICES_DB` and the real grants |
| 11-webhooks | service | 14 | **yes** | HMAC-SHA256 over `ts.body`, constant-time compare, replay window, dedupe |
| 12-kvstore | service | 12 | **yes** | TTL needs a real clock; per-tenant keys |

## Run

```sh
cd backlog
./run_item.sh 05-duration fast     # one item; appends a row to results.tsv, writes runs/<item>-<profile>-<time>/
./run_all.sh fast                  # every item, one at a time, held-out items last
```

Needs `lex`, `python3`, a local model (`--ollama`; set `LEX_PROVIDER_FLAGS=--vllm` plus `VLLM_BASE_URL` / `VLLM_MODEL` for another server) and, for the services, `lsof`.

`fast` = `--max-attempts=2 --repair-rounds=1 --stall-rounds=1`, one 2 h round: it measures
**first-attempt success** and finds traps cheaply. `full` = supervisor defaults: can it finish at all.
Each run leaves `audit.txt` (the independent check), `lessons.md` (`lex-code --lessons`), and
`.lex/overnight/REPORT.md`. `LEX_CODE_DIR` selects the lex-code checkout under test (default: this one; use a clone nobody is editing during a run, the
commit is recorded in `results.tsv`).

## Protocol

1. Derive lessons only from the **non-held-out** items. Held-out items are run with and without
   those lessons and compared; a lesson tested on the brief that produced it proves nothing.
2. Report fast-profile results as "first-attempt", never as "eventually done".
3. A failed audit is the result, not a defect in the harness, unless the oracle is wrong: when an
   audit disagrees with a brief, read the brief first and fix whichever side is wrong.

## Caveats

- Libraries are audited with **no effect grant**: a pure library that needs one fails.
- Only `05-duration`'s oracle has been run against an independent implementation. The other
  oracles were checked against the brief's worked examples by reading, so expect to find a few
  oracle/brief mismatches on first contact.
- Services listen on ports 8811-8814, never 8000/8100.
- The attack scripts print every failing check with the response, and exit non-zero.

## What the first runs showed (qwen3.8:27b-mlx via Ollama, fast profile, one run per cell)

| item | first pass | repeat | repeat, with error hints (#269) |
|---|---|---|---|
| 03 csv | done, audit 44/50 | stuck, 15/50 | done, 50/50 |
| 05 duration | stuck, 22/64 | done, 64/64 | done, 64/64 |
| 07 tokenbucket | stuck, 46/46 | done, 46/46 | done, 46/46 |
| 11 webhooks | done, 40/54 | stuck, server did not start | stuck 14/14, 50/54 |
| 12 kvstore | stuck, server did not start | no verdict, did not start | no verdict, did not start |
| 01 semver, 02 glob, 04 jsonptr, 06 editdistance, 08 ini, 09 jobs, 10 invoices | stuck 0/492, stuck 0/87, done 129/134, done 49/49, done 49/49, no verdict, done 73/79 | | |

- A verdict of `done` is not correctness: of the six first-pass `done` builds, two passed their audit completely.
- Run-to-run noise is larger than the effects tested: three of four items changed verdict between two identical runs.
  Compare failure counts per model step (`lex-code --lessons`), not verdicts, and repeat each cell.
- Per 100 model steps, failed tool calls were 17.6 without the hints and 17.8 with them; the parse errors the hints
  address did not drop. Nothing here shows the hints help.
- `12-kvstore` never started in three runs for one reason: the expiry unit's plan examples contradict the unit's own
  rule at the boundary (a TTL of 1 second stored at 100 and read at 101; `now > stored + ttl` is false, the example says
  true; in another run `is_expired(5000, 5, 9999) => true` while 5000 + 5000 is 10000). Examples cannot be edited once
  filed, so the unit never verifies (9 to 15 million prompt tokens each time) and the five handlers behind it stay blocked.

## Using the items with another language or assistant

The briefs state behaviour, with exact function names and plain argument and result types, so the same item can be
given to another assistant for another language. What is Lex-specific is the first paragraph of each brief ("Build a
small Lex library package named ...", the standard-library names, the `Result[...]`/`Option[...]` spelling and, for the
services, the lex-web / lex-schema / lex-orm sentence and the grants). The oracles encode results as
`{"$variant": "Ok", "args": [...]}` (what `lex run` prints); `audit_lib.py` is the only place that calls the program, so
porting means changing `run_case` to call the library however the other language exposes a function. The service attacks
need only an HTTP server on the port in the environment variable named in the brief.
