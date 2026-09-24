#!/usr/bin/env python3
# Verifies "Server Protocols → Agent Client Protocol (ACP, Zed)" (README):
# NDJSON JSON-RPC over stdio — initialize, session/new, session/prompt
# (streaming session/update notifications), session/close. Uses Ollama
# (no key needed).
#
# Usage: python3 examples/acp_server_smoke.py
import json
import os
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)


def send(p, msg):
    p.stdin.write(json.dumps(msg) + "\n")
    p.stdin.flush()


def recv(p, timeout=20):
    r, _, _ = select.select([p.stdout], [], [], timeout)
    if not r:
        return None
    return p.stdout.readline()


def main():
    env = dict(os.environ)
    env["LEX_CODE_PROVIDER"] = "ollama"

    p = subprocess.Popen(
        ["lex", "run", "--max-steps", "20000000000",
         "--allow-effects", "approval,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,random,sql,stream,time",
         "src/server/client_protocol.lex", "main"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1, env=env, cwd=REPO_ROOT,
    )

    try:
        send(p, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": {"protocolVersion": "1", "clientCapabilities": {}}})
        print("initialize ->", recv(p))

        send(p, {"jsonrpc": "2.0", "id": 2, "method": "session/new",
                  "params": {"cwd": REPO_ROOT}})
        line = recv(p)
        print("session/new ->", line)
        session_id = json.loads(line)["result"]["sessionId"]

        send(p, {"jsonrpc": "2.0", "id": 3, "method": "session/prompt",
                  "params": {"sessionId": session_id,
                             "prompt": [{"type": "text", "text": "reply with just the word ready, do not write any files"}]}})
        deadline = time.time() + 60
        saw_chunk = False
        while time.time() < deadline:
            line = recv(p, 5)
            if line is None:
                continue
            obj = json.loads(line)
            if obj.get("method") == "session/update":
                saw_chunk = True
            if obj.get("id") == 3:
                print("session/prompt final ->", line.strip())
                break

        send(p, {"jsonrpc": "2.0", "id": 4, "method": "session/close",
                  "params": {"sessionId": session_id}})
        print("session/close ->", recv(p, 10))

        if not saw_chunk:
            print("FAIL: no streaming session/update notifications observed", file=sys.stderr)
            sys.exit(1)
        print("PASS: initialize, session/new, streaming session/prompt, session/close all responded correctly")
    finally:
        p.stdin.close()
        time.sleep(1)
        p.terminate()


if __name__ == "__main__":
    main()
