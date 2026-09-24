#!/usr/bin/env bash
# Verifies the Providers section's Ollama example (README#ollama). Fully
# local, no key. Requires `ollama serve` running and OLLAMA_MODEL (default
# qwen3.8:27b-mlx) pulled.
#
# Usage: bash examples/providers/ollama.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/../.."

echo "==> lex-code --ollama, one-shot"
./bin/lex-code --ollama "reply with just the word ready, do not write any files"
