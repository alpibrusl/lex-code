#!/usr/bin/env bash
# Verifies "Semantic search" (README) end to end: starts the bundled
# LiteLLM proxy, builds a small index, and queries it — checking the top
# hit is actually relevant, not just that the commands didn't error.
#
# Requires: docker, and `ollama pull nomic-embed-text` done once already.
# Indexes src/bar/ (small, fast) rather than the whole tree — see the
# README's own note on why LEX_INDEX_PATH defaults to a subtree.
#
# Usage: bash examples/semantic_search/build_and_query.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

echo "==> starting the bundled LiteLLM proxy"
(cd litellm && docker compose up -d)
trap '(cd litellm && docker compose down) >/dev/null 2>&1' EXIT

echo "==> waiting for the proxy to become healthy"
for _ in $(seq 1 20); do
  if curl -sf http://localhost:4000/health/readiness >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

rm -f .lex/index.jsonl

echo "==> building the index over src/bar"
LEX_INDEX_PATH=src/bar lex run --max-steps 20000000000 --allow-effects env,io,net,proc \
  src/index_build.lex main

echo
echo "==> querying it via the semantic_search tool"
cat > /tmp/lex-code-semantic-search-probe.lex << 'LEXEOF'
import "./src/tools/semantic_search" as ss
import "lex-schema/json_value" as jv

fn main() -> [net, io, proc] Unit {
  let args := JObj([("query", JStr("compute a verdict label for a probe")), ("top_k", JInt(3))])
  match ss.execute(args) {
    Err(_) => io.print("ERR"),
    Ok(v) => io.print(jv.stringify(v)),
  }
}
LEXEOF
cp /tmp/lex-code-semantic-search-probe.lex ./semantic_search_probe_tmp.lex
trap 'rm -f ./semantic_search_probe_tmp.lex; (cd litellm && docker compose down) >/dev/null 2>&1' EXIT

RESULT=$(lex run --allow-effects approval,fs_write,io,net,proc,sql,time ./semantic_search_probe_tmp.lex main)
echo "$RESULT"

if echo "$RESULT" | grep -q "verdict_label"; then
  echo
  echo "PASS: the top-ranked hit for a query about 'a verdict label' is verdict_label itself"
else
  echo
  echo "FAIL: expected verdict_label among the results" >&2
  exit 1
fi

rm -f .lex/index.jsonl
