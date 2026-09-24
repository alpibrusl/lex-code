#!/usr/bin/env bash
# Verifies the Providers section's OpenCode Go example (README#opencode-go-plan).
# Requires OPENCODE_API_KEY (or ~/.credentials/opencode/key).
#
# Usage: bash examples/providers/opencode_go.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

if [ -z "${OPENCODE_API_KEY:-}" ]; then
  if [ -f "$HOME/.credentials/opencode/key" ]; then
    export OPENCODE_API_KEY="$(cat "$HOME/.credentials/opencode/key" | tr -d '\n')"
  else
    echo "OPENCODE_API_KEY not set and no ~/.credentials/opencode/key found" >&2
    exit 1
  fi
fi

echo "==> lex-code --opencode, one-shot"
./bin/lex-code --opencode "reply with just the word ready, do not write any files"
