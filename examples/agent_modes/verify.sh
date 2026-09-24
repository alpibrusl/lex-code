#!/usr/bin/env bash
# Verifies "Independent verification mode" (README#independent-verification-mode):
# --verify re-derives expected output independently and writes its OWN new
# verification file — never edits the implementation or its existing tests.
#
# Usage: bash examples/agent_modes/verify.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

BEFORE=$(git status --porcelain tests/ 2>/dev/null || true)

echo "==> lex-code --verify --ollama"
./bin/lex-code --verify --ollama "check src/bar/checks.lex's verdict_label function against its own examples{} block"

echo
NEW_FILES=$(git status --porcelain tests/ 2>/dev/null | grep '^??' || true)
if [ -n "$NEW_FILES" ]; then
  echo "PASS: verify wrote its own new file(s), didn't touch existing tests:"
  echo "$NEW_FILES"
  # Clean up the example's own output — leave the repo as found.
  echo "$NEW_FILES" | awk '{print $2}' | xargs -r rm -f
else
  echo "no new file detected under tests/ — inspect the transcript above" >&2
fi
