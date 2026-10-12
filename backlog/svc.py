"""Harness for independent black-box attacks on a built Lex REST service.

An attack script builds a Svc, calls .check(...) for each thing an attacker (or an
ordinary client) would try, then .finish(). Expected statuses come from the BRIEF,
not from what the package happens to answer. Last line: `[ATTACK] <passed>/<total> hold`.
"""
import atexit, http.client, json, os, re, signal, socket, subprocess, sys, tempfile, time

class Svc:
    def __init__(self, proj, pkg, env, port, grants="net,sql,env,fs_write", port_env=None, entry="main"):
        self.proj, self.port, self.results, self.proc = proj, port, [], None
        self.tmp = tempfile.mkdtemp(prefix="attack-")
        e = dict(os.environ)
        e.update({k: v.replace("{tmp}", self.tmp) for k, v in env.items()})
        if port_env: e[port_env] = str(port)
        self.log = open(os.path.join(self.tmp, "server.log"), "w")
        self.proc = subprocess.Popen(["lex", "run", "--allow-effects", grants, f"src/{pkg}.lex", entry],
                                     cwd=proj, env=e, stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        atexit.register(self.stop)
        for _ in range(100):
            if self.proc.poll() is not None: break
            try:
                socket.create_connection(("127.0.0.1", port), 0.3).close(); self.up = True; return
            except OSError: time.sleep(0.3)
        self.up = False
        print("server did not start:", open(os.path.join(self.tmp, "server.log")).read()[-400:])

    def req(self, method, path, headers=None, body=None, raw_body=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)
        h = dict(headers or {})
        data = raw_body if raw_body is not None else (json.dumps(body) if body is not None else None)
        if isinstance(data, str): data = data.encode()
        if data is not None and "Content-Type" not in h: h["Content-Type"] = "application/json"
        try:
            c.request(method, path, body=data, headers=h)
            r = c.getresponse(); t = r.read().decode("utf-8", "replace")
            return r.status, t
        except Exception as ex:
            return 0, f"<{type(ex).__name__}: {ex}>"
        finally:
            c.close()

    def j(self, text):
        try: return json.loads(text)
        except Exception: return None

    def check(self, name, resp, status, contains=None, excludes=None, test=None):
        st, text = resp
        ok_status = st in status if isinstance(status, (list, tuple, set)) else st == status
        why = []
        if not ok_status: why.append(f"status {st}, expected {status}")
        if ok_status and contains and contains not in text: why.append(f"body lacks {contains!r}")
        if excludes and excludes in text: why.append(f"body contains {excludes!r}")
        if ok_status and test:
            try:
                if not test(self.j(text)): why.append("body check failed")
            except Exception as ex: why.append(f"body check error {ex}")
        self.results.append((name, not why, "; ".join(why) + (f" — {text[:90]}" if why else "")))
        return resp

    def note(self, name, ok, why=""):
        self.results.append((name, ok, why))

    def listens_on_loopback_only(self):
        try:
            out = subprocess.run(["lsof", "-nP", f"-iTCP:{self.port}", "-sTCP:LISTEN"], capture_output=True, text=True).stdout
        except Exception: return None
        lines = [l for l in out.splitlines()[1:] if l.strip()]
        if not lines: return None
        return all("127.0.0.1:" in l or "[::1]:" in l for l in lines)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try: os.killpg(self.proc.pid, signal.SIGTERM)
            except Exception: pass

    def finish(self):
        self.stop()
        bad = [r for r in self.results if not r[1]]
        for n, _, w in bad: print(f"  - {n}: {w}")
        print(f"[ATTACK] {len(self.results)-len(bad)}/{len(self.results)} hold")
        sys.exit(0 if not bad else 1)
