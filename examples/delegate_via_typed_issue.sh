#!/usr/bin/env bash
# Verifies "Delegating to it from another agent" (README) end to end: create
# a typed issue, hand it to lex-code, and check the run ends with a
# machine-readable [ISSUE_VERDICT] line a CALLING agent can branch on
# without trusting the transcript.
#
# Usage: bash examples/delegate_via_typed_issue.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
cd "$REPO_ROOT"

# Runs in a throwaway git worktree, same isolation `make eval` uses (see
# scripts/eval.sh) — lex-code will genuinely write a new src/ file to
# implement the issue, and this keeps that out of your actual working tree.
WORKTREE="$(mktemp -d)"
git worktree add -q --detach "$WORKTREE" HEAD
cleanup() {
  rm -f "$LOG"
  (cd "$REPO_ROOT" && git worktree remove --force "$WORKTREE") 2>/dev/null
}
trap cleanup EXIT
cd "$WORKTREE"

TITLE="digit_sum example $(date +%s)"
echo "==> lex issue create"
ISSUE_ID=$(lex issue create --title "$TITLE" --shape typed_delta \
  --api 'digit_sum:(n :: Int) -> Int:added' \
  --example 'digit_sum(1234) => 10' --example 'digit_sum(-56) => 11')
echo "issue: $ISSUE_ID"

LOG="$(mktemp)"

echo "==> lex-code --issue=$ISSUE_ID --ollama"
./bin/lex-code "--issue=$ISSUE_ID" --ollama 2>&1 | tee "$LOG"

echo
echo "==> what a calling agent actually checks:"
VERDICT_LINE=$(grep '^\[ISSUE_VERDICT\]' "$LOG" || true)
if [ -z "$VERDICT_LINE" ]; then
  echo "FAIL: no [ISSUE_VERDICT] line in the output" >&2
  exit 1
fi
echo "$VERDICT_LINE"

VERDICT=$(echo "$VERDICT_LINE" | cut -f2)
if [ "$VERDICT" = "verified" ]; then
  echo "PASS: issue closed by proof (verified)"
else
  echo "verdict was '$VERDICT', not 'verified' — inspect the trail for why" >&2
fi
