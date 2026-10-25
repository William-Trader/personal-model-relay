#!/usr/bin/env bash
# 轮换访问令牌：生成新值 → 原子替换 → 校验 → reload
set -euo pipefail
TOKEN_CONF=/etc/nginx/.relay-token.conf
[[ $EUID -eq 0 ]] || { echo "需要 root" >&2; exit 1; }
NEW="$(openssl rand -hex 24)"
umask 077
printf 'map "$http_authorization|$http_x_api_key" $relay_key_ok {\n    default 0;\n    "~%s" 1;\n}\n' "$NEW" > "${TOKEN_CONF}.new"
mv "${TOKEN_CONF}.new" "$TOKEN_CONF"
nginx -t
systemctl reload nginx
echo "新令牌: $NEW"
echo "（只显示这一次；记得同步所有客户端）"
