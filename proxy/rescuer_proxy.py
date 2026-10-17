#!/usr/bin/env python3
"""Local dev proxy: the game POSTs {system, prompt} and gets {text}.

Runs `claude -p --model haiku` with every tool disabled, no MCP servers,
no settings/CLAUDE.md, no session persistence, in an empty temp directory.
The model is pinned to Haiku on purpose (cheap + fast enough).

    python3 proxy/rescuer_proxy.py            # listens on 127.0.0.1:8765

Every call is appended to proxy/calls.log (gitignored) so usage stays visible.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HOST, PORT = "127.0.0.1", int(os.environ.get("RESCUER_PROXY_PORT", "8765"))
MODEL = "haiku"  # do not change: the jam budget is Haiku-only
TIMEOUT = 60
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "calls.log")
WORKDIR = tempfile.mkdtemp(prefix="rescuer-proxy-")
calls = 0


def ask_claude(system: str, prompt: str) -> str:
    cmd = [
        "claude", "-p",
        "--model", MODEL,
        "--tools", "",
        "--strict-mcp-config",
        "--setting-sources", "",
        "--no-session-persistence",
        "--output-format", "json",
        "--system-prompt", system,
    ]
    out = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                         timeout=TIMEOUT, cwd=WORKDIR)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip()[:500] or f"exit {out.returncode}")
    data = json.loads(out.stdout)
    return data.get("result", "")


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        global calls
        if self.path != "/rescuer":
            self.send_response(404)
            self.end_headers()
            return
        n = int(self.headers.get("Content-Length", "0"))
        try:
            req = json.loads(self.rfile.read(n))
            t0 = time.time()
            text = ask_claude(req["system"], req["prompt"])
            dt = time.time() - t0
            calls += 1
            with open(LOG, "a") as f:
                f.write(json.dumps({"t": time.strftime("%H:%M:%S"), "secs": round(dt, 1),
                                    "prompt_tail": req["prompt"][-300:], "reply": text}) + "\n")
            print(f"[{calls}] {dt:.1f}s  {text[:120]!r}", flush=True)
            body = json.dumps({"text": text}).encode()
            self.send_response(200)
        except Exception as e:  # noqa: BLE001 - report anything to the game
            print("error:", e, file=sys.stderr, flush=True)
            body = json.dumps({"error": str(e)}).encode()
            self.send_response(502)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"rescuer proxy on http://{HOST}:{PORT}/rescuer (model={MODEL}, cwd={WORKDIR})", flush=True)
    HTTPServer((HOST, PORT), Handler).serve_forever()
