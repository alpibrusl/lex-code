#!/usr/bin/env bash
# Verifies "Running under lex-os" (README) end to end: a real lex-code
# session, mediated through `lex-os exec`, actually writes a file and the
# file lands on disk — not just claimed in the transcript.
#
# Prerequisite: lex-os and lex-os-guest built and on PATH (see the README
# section for the build command). Off a KVM host, this uses
# LEX_OS_SIMULATED=1 — lex-os's own in-process perimeter, explicitly NOT a
# security boundary, only the same grant-mediation mechanism.
#
# Usage: bash examples/lex_os/run_mediated.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

command -v lex-os >/dev/null 2>&1 || {
  echo "lex-os not on PATH — see README's 'Running under lex-os' for the build command" >&2
  exit 1
}

TARGET="src/lex_os_example_probe.lex"
rm -f "$TARGET"

echo "==> lex-code --lex-os --ollama (LEX_OS_SIMULATED=1)"
LEX_OS_SIMULATED=1 ./bin/lex-code --lex-os --ollama \
  "write a new file $TARGET with a single comment line '# hello from lex-os'"

echo
if [ -f "$TARGET" ]; then
  echo "PASS: $TARGET actually landed on disk:"
  cat "$TARGET"
  rm -f "$TARGET"
else
  echo "FAIL: $TARGET was not created" >&2
  exit 1
fi
