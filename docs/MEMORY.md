# Memory, search and observability

[README](../README.md) · [All docs](../README.md#documentation)

What lex-code remembers between sessions, how it searches a codebase, and how to watch it.

## Project memory

Facts that outlive a session — a convention, a version pin, a gotcha. Three
stages, and the boundary between them is enforced by the effect system rather
than by policy.

**The agent proposes.** `remember(kind, content, key?, why?)` appends a
candidate. It cannot do more than that: lex-llm fixes the tool row at
`[net, io, proc]`, with no `sql` and no `time`, and record-field rows unify by
equality — so no tool can widen it to what a durable write needs. An agent
*cannot* install a belief.

**Consolidation disposes.** At session start, `src/memory/consolidate.lex`
reconciles each candidate against what the project already knows:

| | |
|---|---|
| unknown kind, empty content | rejected |
| nothing known yet | accepted |
| identical to what is known | skipped |
| contradicts what is known | superseded — the trail keeps the previous value |
| `recent_change` | accepted; it accumulates by design |

Rules are mechanical, not model-judged: a model adjudicating between two
contradictory beliefs is the failure this mechanism exists to contain.

**The trail records why.** Every outcome, including a rejection, becomes a
`memory.recorded` event with a chained `memory.reconciled` attestation in
`.lex/memory_trail.db` — deliberately not the session log, which is in-memory
and gone at exit. So `attest.chain` answers "why does it believe this" with
something better than "it said so once".

**A session opens with a summary, not the store.** At most five entries per
kind, newest first, and the header says how many were left out — a model that
can see its excerpt is partial can ask for the rest; one shown a silently
truncated list cannot.

Everything the prompt sees was attested by consolidation. A candidate that
was refused never leaves `.lex/memory-candidates.jsonl`.

## Semantic search

_Runnable: `examples/semantic_search/build_and_query.sh`_

`grep` and `glob` match names. `semantic_search` matches intent — "validate an
A2A envelope", "retry a failed HTTP call" — by ranking every function's
signature, effects and examples against the query.

It needs an index, and the index needs an embeddings endpoint. LiteLLM is the
one lex-code speaks to, which is how Ollama is reached: the proxy presents
OpenAI's `/v1/embeddings` over `ollama/nomic-embed-text`, so lex-code never
learns Ollama's native embeddings shape. `litellm/config.yaml` ships the entry.

```sh
ollama pull nomic-embed-text        # 768-dim, ~270MB, CPU is fine
cd litellm && docker compose up -d && cd ..

lex run --max-steps 20000000000 --allow-effects env,io,net,proc \
  src/index_build.lex main
```

| Variable | Default | Meaning |
|---|---|---|
| `LITELLM_BASE_URL` | `http://localhost:4000` | proxy (shared with the chat path) |
| `LEX_EMBED_MODEL` | `nomic-embed-text` | must be in the proxy's model list |
| `LEX_EMBED_DIMS` | `128` | components kept per vector — see below |
| `LEX_INDEX_PATH` | `src/` | what to index |

**`--max-steps` is not optional.** The default VM budget is 10M opcode
dispatches and a whole-repo build blows straight through it.

### Why the index stores a prefix

Reading `.lex/index.jsonl` dominates query latency, and the reason is upstream:
`jv.parse_into_errors` is **quadratic in document size**, because
`json_value.char_at` walks the input with `str.slice(src, p, p + 1)` and slicing
is O(p). Doubling a JSON document roughly quadruples parse time — 16K/0.2s,
33K/0.9s, 66K/3.2s, 132K/13.7s, 264K/55.7s. So the index has to stay small, and
on this repo's 674 functions it measures:

| dims | index | read |
|---|---|---|
| 512 | 932K | 34s |
| 128 | ~500K | ~6s |
| 64 | 336K | 3s |

A 34-second search tool is not a search tool, so only the first
`LEX_EMBED_DIMS` components are kept. The same parser cost bounds indexing:
`lex docs` output for the whole tree is 310K and takes ~55s to parse before a
single embedding is requested, which is why `LEX_INDEX_PATH` defaults to a
subtree-sized scope rather than the repo. That is sound rather than merely cheap
for a Matryoshka-trained model like `nomic-embed-text`, which is trained so a
leading slice of the vector is itself a usable embedding; the prefix is
renormalised, since truncating changes the norm. Raise it for better ranking on
a small tree, lower it on a large one.

### Rebuilds are incremental

The reuse key is `sig_id`, not mtime: it hashes the function's own content, so
it answers "did this function change" rather than "was this file touched",
which is true after a comment edit and false after a `git checkout` that
rewinds content. Changing the model, endpoint or dims invalidates the whole
index — vectors are only comparable within one model, and mixing two vector
spaces in one ranking produces plausible nonsense rather than an error.

`semantic_search` is available to the explore, plan and review agents. It never
builds the index itself: a build makes one HTTP call per function, and
`Tool.execute`'s `[net, io, proc]` row cannot read the env it would need.

## Observability (OpenTelemetry)

_Runnable: `examples/observability_stdout.sh`_

Off by default. Point it at a collector and every turn arrives as a trace:

```sh
LEX_OTLP_ENDPOINT=http://localhost:4318 lex-code
```

| Variable | Effect |
|---|---|
| `LEX_OTLP_ENDPOINT` | POST OTLP/JSON to `/v1/traces` and `/v1/metrics` |
| `LEX_OTEL_STDOUT=1` | print the same envelopes to stdout instead |

An endpoint wins over the stdout flag, and with neither set nothing is
emitted — `io.print` is the TUI's own output stream, so a default-on stdout
exporter would dump OTel envelopes into your session on every turn.

**The trace is projected from the trail, not instrumented separately.**
lex-llm already writes `cap.invoked` before every tool call and
`cap.completed` / `cap.failed` after it, parented to the invoke, and every
trail event carries `ts_ms`. A start, an end, a parent link and a name is a
span — the trail was already a trace, just never spoken in OTel's wire
format. `src/observability.lex` reads the turn's slice of the log and
translates. Running a second span stream inside the same dispatch loop would
put two recorders on one set of facts, which is precisely how the
attestation chain broke (#32): the loop wrote one place, the reader read
another.

You get an `agent.turn` root span per turn, one `tool.<name>` child per
completed tool call, a `tool.calls` counter tagged by tool and success, and a
`turn.duration_ms` histogram. An invoke with no outcome — a turn cut short
mid-tool — is dropped rather than exported with a fabricated end time.

**Span ids are derived, not drawn.** Trail event ids are sha256 hashes of the
event's own content, so a span id taken from one is stable: re-exporting a
session reproduces the same trace instead of forging a rival. That also keeps
`random` out of the turn's effect row entirely. An unreachable collector
costs telemetry, never the turn.
