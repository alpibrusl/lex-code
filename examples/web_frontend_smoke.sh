#!/usr/bin/env bash
# Verifies "Web Frontend" (README): one process serves both the static UI
# and POST /a2a, plus the Trail/Memory tabs' routes.
#
# Usage: bash examples/web_frontend_smoke.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

pkill -f "server/web.lex" 2>/dev/null
sleep 1

PORT=7799 lex run --max-steps 20000000000 \
  --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/web.lex serve_web > /tmp/lex-code-web-smoke.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
sleep 2

fail=0
check() {
  code=$(curl -s -o /dev/null -w "%{http_code}" "$1")
  if [ "$code" != "$2" ]; then
    echo "FAIL: $1 -> $code (expected $2)" >&2
    fail=1
  else
    echo "ok: $1 -> $code"
  fi
}

check "http://localhost:7799/" 200
check "http://localhost:7799/events?session=none&after=0" 200
check "http://localhost:7799/sessions" 200
check "http://localhost:7799/memory" 200

exit $fail
