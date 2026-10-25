#!/usr/bin/env python3
"""最小客户端示例：只用标准库。"""
import json
import os
import urllib.request

BASE = os.environ.get("RELAY_URL", "http://relay.example.com:8080")
TOKEN = os.environ["RELAY_TOKEN"]
MODEL = os.environ.get("MODEL", "")


def call(path, payload=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode() if payload else None,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
        },
        method="POST" if payload else "GET",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode())


models = call("/v1/models")
model_id = MODEL or models["data"][0]["id"]
print("model:", model_id)

out = call("/v1/chat/completions", {
    "model": model_id,
    "messages": [{"role": "user", "content": "ping"}],
    "max_tokens": 32,
})
print(out["choices"][0]["message"].get("content", "").strip())
