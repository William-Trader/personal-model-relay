#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Personal Model Relay · 历史峰值记录器

每秒轮询上游状态接口，累计峰值并持久化；通过 loopback HTTP 提供：
  GET /max        当前记录（JSON）
  GET /panel.js   前端注入脚本
  GET /health     存活探针

环境变量：
  RELAY_UPSTREAM     上游状态接口（默认 http://127.0.0.1:18092/api/summary）
  RELAY_HIST_LISTEN  监听地址（默认 127.0.0.1:18094）
  RELAY_STATE        状态文件（默认 /var/lib/model-relay/history.json）
"""
import json
import os
import signal
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPSTREAM = os.environ.get("RELAY_UPSTREAM", "http://127.0.0.1:18092/api/summary")
LISTEN = os.environ.get("RELAY_HIST_LISTEN", "127.0.0.1:18094")
STATE = os.environ.get("RELAY_STATE", "/var/lib/model-relay/history.json")
INTERVAL = float(os.environ.get("RELAY_INTERVAL", "1"))

_lock = threading.Lock()
state = {
    "since": int(time.time() * 1000),
    "samples": 0,
    "decode": {"v": None, "at": None},
    "prefill": {"v": None, "at": None},
    "roundDecode": {"v": None, "at": None},
    "roundPrefill": {"v": None, "at": None},
    "gpu": {"v": None, "at": None},
    "updated": None,
    "upstream": False,
    "error": None,
    "engineUptimeSec": None,
}


def load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            data = json.load(f)
        for key in ("since", "samples", "decode", "prefill",
                    "roundDecode", "roundPrefill", "gpu"):
            if key in data:
                state[key] = data[key]
    except (OSError, ValueError):
        pass


def save_state():
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
        os.replace(tmp, STATE)
    except OSError:
        pass


def bump(key, value, at):
    if value is None:
        return False
    try:
        value = float(value)
    except (TypeError, ValueError):
        return False
    current = state[key]
    if current["v"] is None or value > current["v"]:
        current["v"] = round(value, 3)
        current["at"] = at
        return True
    return False


def poll_loop():
    ticks = 0
    changed = False
    while True:
        try:
            with urllib.request.urlopen(UPSTREAM, timeout=6) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            now = int(time.time() * 1000)
            engine = payload.get("engine") or {}
            phase = engine.get("phase") or "idle"
            hit = False
            if phase == "decode":
                hit = bump("decode", engine.get("tpsInstant"), now) or hit
            if phase == "prefill":
                hit = bump("prefill", engine.get("prefillTpsInstant"), now) or hit
            last = payload.get("lastRequest") or {}
            last_at = last.get("at") or now
            hit = bump("roundDecode", last.get("predicted_per_second"), last_at) or hit
            hit = bump("roundPrefill", last.get("prompt_per_second"), last_at) or hit
            gpu = payload.get("gpu") or {}
            if isinstance(gpu.get("utilPct"), (int, float)):
                hit = bump("gpu", gpu.get("utilPct"), now) or hit
            with _lock:
                state["samples"] += 1
                state["updated"] = now
                state["upstream"] = True
                state["error"] = None
                uptime = engine.get("uptimeSec")
                if uptime is not None:
                    state["engineUptimeSec"] = round(float(uptime), 1)
            changed = changed or hit
        except Exception as exc:  # noqa: BLE001 - 上游任何异常都不应终止服务
            with _lock:
                state["upstream"] = False
                state["error"] = str(exc)[:160]
        ticks += 1
        if changed or ticks % 30 == 0:
            save_state()
            changed = False
        time.sleep(INTERVAL)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        try:
            if path == "/max":
                with _lock:
                    body = json.dumps(state, ensure_ascii=False).encode("utf-8")
                ctype = "application/json; charset=utf-8"
            elif path == "/panel.js":
                with open(os.path.join(BASE_DIR, "panel.js"), "rb") as f:
                    body = f.read()
                ctype = "application/javascript; charset=utf-8"
            elif path == "/health":
                body, ctype = b"ok", "text/plain; charset=utf-8"
            else:
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except OSError:
            try:
                self.send_response(500)
                self.end_headers()
            except OSError:
                pass

    def log_message(self, *_args):
        pass


def main():
    host, _, port = LISTEN.rpartition(":")
    load_state()
    signal.signal(signal.SIGTERM, lambda *_: (save_state(), os._exit(0)))
    threading.Thread(target=poll_loop, daemon=True).start()
    server = ThreadingHTTPServer((host or "127.0.0.1", int(port or 18094)), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
