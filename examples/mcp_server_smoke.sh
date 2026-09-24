#!/usr/bin/env bash
# Verifies "External tools (MCP)" / "Server Protocols → MCP" (README):
# starts src/server/mcp_main.lex, checks the A2A agent card, tools/list,
# and a real tools/call round-trip through Ollama (no key needed).
#
# Usage: bash examples/mcp_server_smoke.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."

pkill -f "server/mcp_main.lex" 2>/dev/null
sleep 1

LEX_CODE_PROVIDER=ollama lex run --max-steps 20000000000 \
  --allow-effects approval,concurrent,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time \
  src/server/mcp_main.lex main > /tmp/lex-code-mcp-smoke.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT

echo "==> waiting for the server to come up"
for _ in $(seq 1 15); do
  curl -sf http://localhost:7778/.well-known/agent.json >/dev/null 2>&1 && break
  sleep 1
done

echo "==> GET /.well-known/agent.json"
curl -sf http://localhost:7778/.well-known/agent.json | head -c 300
echo
echo
echo "==> tools/list"
curl -sf -X POST http://localhost:7778/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
echo
echo
echo "==> tools/call (real round-trip via Ollama)"
curl -sf -X POST http://localhost:7778/mcp \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code","arguments":{"task":"reply with just the word ready, do not write any files","mode":"explore"}}}'
echo
