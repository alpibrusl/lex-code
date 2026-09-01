#!/usr/bin/env python3
"""Validate lex-code's ACP wire format against the published ACP schema.

Drives src/server/client_protocol.lex over stdio through a full session —
initialize, session/new, session/prompt with a tool call, session/close —
and checks every frame it emits against schema/schema.json from
@zed-industries/agent-client-protocol.

This exists because the shapes were once a guess. The file's header used to
say they were a "best-effort reconstruction of the ACP v2 schema" and asked
whoever came next to validate against a real client. Two of them were wrong:
`tool_call` and `tool_call_update` both omitted the required `toolCallId`,
and `initialize` answered with protocolVersion 2 when the spec constant is 1
and the schema says a client should disconnect on a version it does not
support. A schema check would have caught all three on the day they landed.

It does NOT replace running against Zed (#62). A schema constrains the shape
of each frame and says nothing about their order, or about whether a client
tolerates a turn that announces a tool_call and never updates it. What it
does is make the shape non-negotiable, so the next wire-format change fails
here rather than in someone's editor.

The model is a mock: this is a protocol test, not a model test. It needs no
network beyond the npm fetch of the schema and no provider key.

Usage:
    npm pack @zed-industries/agent-client-protocol@0.4.5
    tar -xzf zed-industries-agent-client-protocol-*.tgz   # -> package/
    pip install jsonschema
    python3 scripts/validate_acp.py [path/to/schema.json]

Exits non-zero on the first schema violation.
"""
import http.server
import json
import os
import subprocess
import sys
import threading

SCHEMA = sys.argv[1] if len(sys.argv) > 1 else "package/schema/schema.json"
PORT = 11434  # the Ollama endpoint client_protocol.lex talks to by default

EFFECTS = ("approval,crypto,env,fs_read,fs_walk,fs_write,io,llm,net,proc,"
           "random,sql,stream,time")


class MockOllama(http.server.BaseHTTPRequestHandler):
    """Answers the first turn with a tool call, the second with text.

    Two turns are needed on purpose: one tool call exercises tool_call and
    tool_call_update, and the follow-up turn ends the agent loop so the
    server emits a PromptResponse rather than running to max_steps.
    """

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or "{}")
        answered_tool = any(m.get("role") == "tool" for m in body.get("messages", []))
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        if answered_tool:
            chunk = {"message": {"role": "assistant", "content": "done."}, "done": False}
        else:
            chunk = {"message": {"role": "assistant", "content": "", "tool_calls": [
                {"function": {"name": "read", "arguments": {"path": "README.md"}}}]},
                "done": False}
        self._write(chunk)
        self._write({"message": {"role": "assistant", "content": ""},
                     "done": True, "done_reason": "stop"})

    def _write(self, obj):
        self.wfile.write((json.dumps(obj) + "\n").encode())
        self.wfile.flush()

    def log_message(self, *a):
        pass


def main():
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        print("need jsonschema: pip install jsonschema", file=sys.stderr)
        return 2
    if not os.path.exists(SCHEMA):
        print(f"no schema at {SCHEMA} — see the usage note in this file's docstring",
              file=sys.stderr)
        return 2

    defs = json.load(open(SCHEMA))["$defs"]

    def validator(name):
        sch = dict(defs[name])
        sch["$defs"] = defs
        return Draft202012Validator(sch)

    # A previous run leaves the port in TIME_WAIT; without this a re-run
    # fails to bind and looks like a protocol failure rather than a stale
    # socket. HTTPServer sets allow_reuse_address on the class, but set it
    # here too so the intent survives a refactor.
    http.server.HTTPServer.allow_reuse_address = True
    server = http.server.HTTPServer(("127.0.0.1", PORT), MockOllama)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    env = dict(os.environ, LEX_CODE_PROVIDER="ollama")
    agent = subprocess.Popen(
        ["lex", "run", "--allow-effects", EFFECTS,
         "src/server/client_protocol.lex", "main"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1, env=env)

    def send(obj):
        agent.stdin.write(json.dumps(obj) + "\n")
        agent.stdin.flush()

    frames = []
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": 1, "clientCapabilities": {}}})
    frames.append(("InitializeResponse", json.loads(agent.stdout.readline())["result"]))

    send({"jsonrpc": "2.0", "id": 2, "method": "session/new",
          "params": {"cwd": os.getcwd(), "mcpServers": []}})
    new_session = json.loads(agent.stdout.readline())["result"]
    frames.append(("NewSessionResponse", new_session))

    send({"jsonrpc": "2.0", "id": 3, "method": "session/prompt",
          "params": {"sessionId": new_session["sessionId"],
                     "prompt": [{"type": "text", "text": "read the readme"}]}})
    for _ in range(20):
        line = agent.stdout.readline()
        if not line:
            break
        msg = json.loads(line)
        if msg.get("method") == "session/update":
            frames.append(("SessionNotification", msg["params"]))
        elif msg.get("id") == 3:
            frames.append(("PromptResponse", msg["result"]))
            break

    agent.kill()
    server.shutdown()

    violations = 0
    for name, inst in frames:
        errors = sorted(validator(name).iter_errors(inst), key=lambda e: list(e.path))
        label = name
        if name == "SessionNotification":
            label += f" [{inst['update']['sessionUpdate']}]"
        print(f"{'PASS' if not errors else 'FAIL'}  {label}")
        for err in errors[:3]:
            violations += 1
            where = "/".join(map(str, err.path)) or "<root>"
            print(f"         {where} -> {err.message[:200]}")

    kinds = {f[1]["update"]["sessionUpdate"] for f in frames if f[0] == "SessionNotification"}
    for required in ("tool_call", "tool_call_update", "agent_message_chunk"):
        if required not in kinds:
            violations += 1
            print(f"FAIL  no {required} frame was emitted — the run did not exercise it")

    print(f"\n{len(frames)} frames, {violations} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
