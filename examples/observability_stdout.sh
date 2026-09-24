#!/usr/bin/env bash
# Verifies "Observability (OpenTelemetry)" (README): LEX_OTEL_STDOUT=1
# prints the turn's otel.traces/otel.metrics envelopes — no collector
# needed for this variant.
#
# Usage: bash examples/observability_stdout.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

OUT=$(LEX_OTEL_STDOUT=1 ./bin/lex-code --ollama "reply with just the word ready, do not write any files" 2>&1)
echo "$OUT"

echo
if echo "$OUT" | grep -q "^otel.traces " && echo "$OUT" | grep -q "^otel.metrics "; then
  echo "PASS: agent.turn trace + turn.duration_ms metric both emitted"
else
  echo "FAIL: expected otel.traces and otel.metrics lines" >&2
  exit 1
fi
