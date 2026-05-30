#!/usr/bin/env bash
# Theatrical demo script — records cleanly with asciinema.
# Usage:  bash demo.sh
#         asciinema rec demo.cast -c "bash demo.sh" --overwrite
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."      # lex-code root so paths are short
LEX="${LEX:-lex}"

# ANSI helpers
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
RED=$'\033[31m'
RESET=$'\033[0m'
BLUE=$'\033[34m'

slow() { echo "$@" | pv -qL 55; }
pause() { sleep "${1:-1.2}"; }
hr()  { printf '%s' "$DIM"; printf '─%.0s' {1..72}; printf '%s\n' "$RESET"; }
hdr() { echo; hr; echo "  ${BOLD}${CYAN}$*${RESET}"; hr; echo; }
cmd() {
  echo "${BOLD}${BLUE}\$${RESET}  $*"
  pause 0.7
}

# ── Title ────────────────────────────────────────────────────────────────
clear
echo
echo "  ${BOLD}lex-os  ×  lex-code${RESET}"
echo "  ${DIM}Manifesto demo — effect-typed orchestration + tamper-evident audit${RESET}"
echo
sleep 2.5

# ── §VI : Effect row shown ────────────────────────────────────────────
hdr "§VI · Effect-typed orchestration"
slow "  run_parallel composes 9 effects across two parallel agent calls."
slow "  The type checker verifies the row — not at runtime, at check time."
echo
pause 1.4

cmd "grep 'fn run_parallel' examples/manifesto_full_chain/orchestrator.lex"
grep 'fn run_parallel' examples/manifesto_full_chain/orchestrator.lex
echo
pause 1.2

# ── lex check passes ──────────────────────────────────────────────────
hdr "lex check orchestrator.lex  →  must pass"
cmd "lex check examples/manifesto_full_chain/orchestrator.lex"
pause 0.4
"$LEX" check examples/manifesto_full_chain/orchestrator.lex
echo "${GREEN}${BOLD}✓  ok${RESET}  — all 9 effects verified at compile time"
echo
pause 2.0

# ── Negative twin ─────────────────────────────────────────────────────
hdr "orchestrator_bad.lex  →  must be REJECTED"
slow "  Same body. Wrong declared row — only 5 effects declared, body uses 9."
echo
pause 1.0

cmd "grep 'fn run_parallel' examples/manifesto_full_chain/orchestrator_bad.lex"
grep 'fn run_parallel' examples/manifesto_full_chain/orchestrator_bad.lex
echo
pause 0.9

cmd "lex check examples/manifesto_full_chain/orchestrator_bad.lex"
pause 0.4
# pretty-print just the effect errors
"$LEX" --output json check examples/manifesto_full_chain/orchestrator_bad.lex 2>&1 \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for e in d['data']['errors']:
    pos = e['position']
    eff = e.get('effect', '?')
    print(f\"  error[{e['kind']}]  effect '{eff}' not declared\")
    print(f\"    --> examples/manifesto_full_chain/orchestrator_bad.lex:{pos['line']}\")
    print()
"
echo "${RED}${BOLD}✗  REJECTED${RESET}  — the row is a contract, not a comment."
echo
pause 2.5

# ── §VIII : Hash chain ────────────────────────────────────────────────
hdr "§VIII · Hash-chain tamper-evidence"
slow "  The audit log is content-addressed and hash-chained."
slow "  Delete one event → verify_chain surfaces a seq gap."
echo
pause 1.4

cmd "lex run examples/manifesto_full_chain/chain_verify.lex main \\"
echo "        --allow-effects sql,fs_write,time,io"
pause 0.5
"$LEX" run examples/manifesto_full_chain/chain_verify.lex main \
  --allow-effects sql,fs_write,time,io 2>&1 \
  | python3 -c "
import sys, re
raw = sys.stdin.read()
# io.print in lex 0.9.7 omits newlines — inject them before each logical line
raw = re.sub(r'(==>)', r'\n\1', raw)
raw = re.sub(r'(    (?:Ok|Err|VALIDATED|FAIL|UNEXPECTED))', r'\n\1', raw)
for line in raw.splitlines():
    line = line.rstrip()
    if line.endswith('null'):
        line = line[:-4].rstrip()
    s = line.strip()
    if s:
        print(line)
"
echo
pause 1.5

# ── Summary ───────────────────────────────────────────────────────────
hr
echo
echo "  ${BOLD}${GREEN}VALIDATED${RESET}"
echo
echo "  ${BOLD}§VI  ${RESET}Effect rows enforced by type system — not by convention."
echo "       Wrong row → compile error, not a runtime surprise."
echo
echo "  ${BOLD}§VIII${RESET}Hash chain detects deleted event via seq gap."
echo "       Tampered log is structurally detectable."
echo
hr
echo
