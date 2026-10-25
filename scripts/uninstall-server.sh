#!/usr/bin/env bash
# 卸载：默认保留历史数据；--purge 一并删除
set -euo pipefail
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1
[[ $EUID -eq 0 ]] || { echo "需要 root" >&2; exit 1; }

systemctl disable --now model-hist >/dev/null 2>&1 || true
rm -f /etc/systemd/system/model-hist.service
systemctl daemon-reload

rm -rf /opt/model-relay
rm -f /etc/nginx/conf.d/llm-relay.conf
rm -f /etc/nginx/.relay-token.conf
[[ "$PURGE" == "1" ]] && rm -rf /var/lib/model-relay

if command -v nginx >/dev/null; then nginx -t && systemctl reload nginx || true; fi
echo "已卸载。$( [[ "$PURGE" == "1" ]] && echo '历史数据已删除。' || echo '历史数据保留在 /var/lib/model-relay。' )"
echo "别忘了在算力机停掉隧道计划任务/systemd。"
