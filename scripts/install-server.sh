#!/usr/bin/env bash
# 模型远程使用个人中转 · 服务器一键安装（幂等）
# 用法：sudo RELAY_TOKEN=... bash scripts/install-server.sh
set -euo pipefail

PUBLIC_PORT="${RELAY_PUBLIC_PORT:-8080}"
TUNNEL_PORT="${RELAY_TUNNEL_PORT:-18092}"
HIST_PORT="${RELAY_HIST_PORT:-18094}"
INSTALL_PANEL="${INSTALL_PANEL:-1}"
CONF=/etc/nginx/conf.d/llm-relay.conf
TOKEN_CONF=/etc/nginx/.relay-token.conf
APP=/opt/model-relay

if [[ $EUID -ne 0 ]]; then echo "需要 root：sudo bash $0" >&2; exit 1; fi
command -v python3 >/dev/null || { echo "缺少 python3" >&2; exit 1; }

# 依赖
if command -v apt-get >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx python3 >/dev/null
elif command -v yum >/dev/null; then
  yum install -y -q nginx python3 >/dev/null
else
  echo "不支持的包管理器，请手动安装 nginx 与 python3" >&2
fi

# token（只生成一次）
TOKEN="${RELAY_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then TOKEN="$(openssl rand -hex 24)"; NEW_TOKEN=1; else NEW_TOKEN=0; fi

# 应用文件
install -d -m 755 "$APP"
install -m 755 "$(dirname "$0")/../server/hist/hist.py" "$APP/hist.py"
install -m 644 "$(dirname "$0")/../server/hist/panel.js" "$APP/panel.js"

# systemd
sed -e "s|RELAY_UPSTREAM=.*|RELAY_UPSTREAM=http://127.0.0.1:${TUNNEL_PORT}/api/summary|" \
    -e "s|RELAY_HIST_LISTEN=.*|RELAY_HIST_LISTEN=127.0.0.1:${HIST_PORT}|" \
    "$(dirname "$0")/../server/systemd/model-hist.service" > /etc/systemd/system/model-hist.service
systemctl daemon-reload
systemctl enable model-hist >/dev/null 2>&1 || true

# token 映射
umask 077
printf 'map "$http_authorization|$http_x_api_key" $relay_key_ok {\n    default 0;\n    "~%s" 1;\n}\n' "$TOKEN" > "$TOKEN_CONF"
chmod 600 "$TOKEN_CONF"

# nginx 站点（先备份已有同名配置）
[[ -f "$CONF" ]] && cp -a "$CONF" "${CONF}.bak-$(date +%Y%m%d-%H%M%S)"
python3 - "$CONF" "$PUBLIC_PORT" "$TUNNEL_PORT" "$HIST_PORT" "$INSTALL_PANEL" "$(dirname "$0")/../server/nginx/llm-relay.conf.template" <<'PY'
import re, sys
out, public, tunnel, hist, panel, tpl = sys.argv[1:7]
src = open(tpl, encoding="utf-8").read()
src = src.replace("${RELAY_PUBLIC_PORT}", public).replace("${RELAY_TUNNEL_PORT}", tunnel).replace("${RELAY_HIST_PORT}", hist)
if panel == "0":
    src = re.sub(r"\n    # BEGIN panel.*?# END panel\n", "\n", src, flags=re.S)
open(out, "w", encoding="utf-8").write(src)
PY

nginx -t
systemctl reload nginx

if [[ "$INSTALL_PANEL" == "1" ]]; then systemctl restart model-hist; else systemctl disable --now model-hist >/dev/null 2>&1 || true; fi

cat <<INFO

========================================
 安装完成
 入口        : http://<服务器地址>:${PUBLIC_PORT}/v1
 隧道端口    : 127.0.0.1:${TUNNEL_PORT}（需算力机 -R 建立）
 面板端口    : 127.0.0.1:${HIST_PORT}（INSTALL_PANEL=${INSTALL_PANEL}）
 令牌文件    : ${TOKEN_CONF}（600）
$( [[ "$NEW_TOKEN" == "1" ]] && printf ' 新令牌      : %s\n（只显示这一次，请立即保存到密码管理器）\n' "$TOKEN" || printf ' 令牌        : 使用你提供的 RELAY_TOKEN（未回显）\n' )
========================================
下一步：在算力机建立反向隧道，然后
  curl http://<服务器地址>:${PUBLIC_PORT}/v1/models -H "Authorization: Bearer <token>"
INFO
