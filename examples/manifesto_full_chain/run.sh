#!/usr/bin/env bash
# Manifesto full-chain demo (lex-code): effect typing + hash chain tamper-evidence.
#
# Validates two manifesto claims:
#
#   §VI  — Effect-typed orchestration: the type checker verifies the composed
#           row [env,concurrent,net,io,proc,sql,fs_write,time] for run_parallel,
#           and REJECTS orchestrator_bad.lex which under-declares it.
#
#   §VIII — Hash chain tamper-evidence: verify_chain surfaces a deletion as a
#            structured Err (seq gap), proving the event was removed even though
#            the remaining events' individual content hashes are still valid.
#
#   bash examples/manifesto_full_chain/run.sh
#   LEX=/path/to/lex bash examples/manifesto_full_chain/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEX="${LEX:-lex}"
fail=0

echo "==> §VI  lex check orchestrator.lex (8-effect composition — must pass)"
if "$LEX" check "$HERE/orchestrator.lex"; then
  echo "    OK: effect row [env,concurrent,net,io,proc,sql,fs_write,time] verified"
else
  echo "    FAIL: orchestrator.lex should type-check cleanly"
  fail=1
fi

echo
echo "==> §VI  lex check orchestrator_bad.lex (under-declared row — must be rejected)"
if ! "$LEX" check "$HERE/orchestrator_bad.lex" 2>/dev/null; then
  echo "    OK: lex check rejected the under-declared row (missing proc,sql,fs_write)"
else
  echo "    FAIL: orchestrator_bad.lex should have been rejected"
  fail=1
fi

echo
echo "==> §VIII lex run chain_verify.lex main (hash chain deletion detection)"
out="$("$LEX" run "$HERE/chain_verify.lex" main --allow-effects sql,fs_write,time,io 2>&1)"
echo "$out"

if echo "$out" | grep -q "VALIDATED: deletion detected"; then
  echo "    OK: hash chain detected the deleted event via seq gap"
else
  echo "    FAIL: chain tamper detection did not produce expected output"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "VALIDATED: effect rows enforced by type system; hash chain detects deletion."
else
  echo "FAILED: see output above."
fi
exit "$fail"
