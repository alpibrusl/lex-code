#!/usr/bin/env bash
# Verifies "Parallel Multi-Agent (std.conc)" (README): --multi spawns two
# actors (Build + Test) concurrently via std.conc.
#
# Usage: bash examples/agent_modes/multi.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

echo "==> lex-code --multi --ollama"
./bin/lex-code --multi --ollama "reply with just the word ready, do not write any files"
