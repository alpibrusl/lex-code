#!/usr/bin/env bash
# Manifesto demo (lex-code): semantic diff, not line diff.
#
# Validates §III by asserting that `lex diff` surfaces the effect-row
# change ([] -> [net]) as a structured fact, where a line diff shows
# only text churn. Exit 0 only if the effect change is reported.
#
#   bash examples/manifesto_semantic_diff/run.sh
#   LEX=/path/to/lex bash examples/manifesto_semantic_diff/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEX="${LEX:-lex}"
fail=0

echo "==> lex ast-diff (AST-native): what actually changed about fetch()?"
out="$("$LEX" ast-diff --json "$HERE/v1_fetch.lex" "$HERE/v2_fetch.lex" 2>&1)"
echo "$out" | jq '.modified[]? | {name, signature_changed, effect_changes}' 2>/dev/null || echo "$out"

if echo "$out" | jq -e '[.modified[]?.effect_changes.added[]?] | index("net")' >/dev/null 2>&1; then
  echo "    OK: lex ast-diff reported fetch newly gained the [net] effect"
else
  echo "    FAIL: effect-row change not surfaced by lex ast-diff"
  fail=1
fi

echo
echo "==> contrast: a line-based diff sees only characters, not effects"
if command -v git >/dev/null 2>&1; then
  git --no-pager diff --no-index -- "$HERE/v1_fetch.lex" "$HERE/v2_fetch.lex" 2>/dev/null | sed -n '1,40p' || true
else
  diff -u "$HERE/v1_fetch.lex" "$HERE/v2_fetch.lex" || true
fi

if [ "$fail" -eq 0 ]; then
  echo "VALIDATED: the diff names the effect-row change — meaning, not lines."
else
  echo "FAILED: see output above."
fi
exit "$fail"
