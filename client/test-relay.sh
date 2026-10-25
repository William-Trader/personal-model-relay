#!/usr/bin/env bash
# 用法：
#   RELAY_URL=http://relay.example.com:8080 RELAY_TOKEN=... MODEL=qwen-27b ./test-relay.sh
set -euo pipefail

: "${RELAY_URL:?set RELAY_URL, e.g. http://relay.example.com:8080}"
: "${RELAY_TOKEN:?set RELAY_TOKEN}"
MODEL="${MODEL:-$(curl -s "$RELAY_URL/v1/models" -H "Authorization: Bearer $RELAY_TOKEN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])')}"

echo "== auth check (expect 200)"
curl -s -o /dev/null -w '%{http_code}\n' "$RELAY_URL/v1/models" -H "Authorization: Bearer $RELAY_TOKEN"

echo "== chat completion"
curl -s -m 120 "$RELAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $RELAY_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"只回复两个字：在线\"}],\"max_tokens\":32}" \
  | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["choices"][0]["message"].get("content") or d["choices"][0]["message"].get("reasoning_content",""));print("usage:",d.get("usage"))'

echo "== latency"
curl -s -o /dev/null -w 'dns=%{time_namelookup} conn=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total}\n' \
  "$RELAY_URL/v1/models" -H "Authorization: Bearer $RELAY_TOKEN"
