#!/usr/bin/env bash
# Verifies the Bootstrap Script's env-var overrides (README#bootstrap-script):
# LEX_TASK / LEX_PIPELINE / LEX_PROVIDER replace the hardcoded list.zip demo.
#
# Usage: bash examples/bootstrap_custom_task.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

LEX_TASK="reply with just the word ready, do not write any files" \
LEX_PIPELINE=build \
LEX_PROVIDER=ollama \
  lex run --max-steps 20000000000 \
  --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/bootstrap/run.lex main
