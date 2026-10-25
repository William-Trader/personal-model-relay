# 安全说明

## 凭据

- 访问令牌（`RELAY_TOKEN`）是唯一入口凭据，48 位随机十六进制。
- 存放位置：服务器 `/etc/nginx/.relay-token.conf`（600）；客户端放在系统密钥库或环境变量。
- **不要**提交到 Git、贴进 issue、写进日志或截图。
- 轮换：`sudo bash scripts/rotate-token.sh`。

## 网络暴露面

| 端口 | 绑定 | 说明 |
|---|---|---|
| 8080（可改） | 0.0.0.0 | 唯一的公网入口，带 token 鉴权 |
| 18092（隧道） | 127.0.0.1 | 仅本机，公网不可达 |
| 18094（面板） | 127.0.0.1 | 仅本机，由 nginx 反代 |
| 22 | 0.0.0.0 | SSH；建议限制来源 IP、禁用密码登录 |

## 建议加固

1. 在 nginx 前加 TLS（Caddy 自动证书 / 反代 443），避免 token 明文过网。
2. `authorized_keys` 中给转发账号加限制：
   `restrict,port-forwarding,command="/bin/false" ssh-ed25519 AAAA...`
3. 加访问频率限制：
   `limit_req_zone $binary_remote_addr zone=relay:10m rate=2r/s;`
4. 面板页面不涉及推理权限，但仍建议仅内网或加 basic auth。

## 报告问题

发现安全问题请通过 GitHub Security Advisory 私下报告，不要公开 issue。
