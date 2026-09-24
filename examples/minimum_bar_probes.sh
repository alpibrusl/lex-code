#!/usr/bin/env bash
# Verifies "Minimum bar mode"'s no-model probes command (README#minimum-bar-mode) —
# also the exact command lex-code's own CI runs against itself.
#
# Usage: bash examples/minimum_bar_probes.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

lex run --allow-effects io,proc src/bar/checks.lex gate '"."' '"src"'
