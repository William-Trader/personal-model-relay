# 故障排查

## 502 Bad Gateway

**含义**：nginx 连不上 `127.0.0.1:18092`，即隧道断了或算力机服务挂了。

```bash
# 1) 隧道在不在
ss -tlnp | grep 18092
# 2) 谁在监听（应是 sshd）
sudo lsof -iTCP:18092 -sTCP:LISTEN
# 3) nginx 错误日志
sudo tail -20 /var/log/nginx/error.log
```

- 无监听 → 去算力机看隧道进程/计划任务/服务状态。
- 有监听但仍 502 → 算力机本地 `curl 127.0.0.1:8091/v1/models` 是否正常。

## 401 Unauthorized

```bash
# 服务器端 token 指纹（不要打印明文）
sudo sha256sum /etc/nginx/.relay-token
# 客户端发送值比对
printf '%s' "$RELAY_TOKEN" | sha256sum
```

不一致 → 用 `scripts/rotate-token.sh` 轮换并同步客户端。
也检查是否把 token 放进了 `x-api-key` 但中间有代理改写 header。

## 隧道反复断开

```bash
# 算力机日志
tail -50 relay-tunnel.log
```

- `Connection closed by remote host` 频繁 → 中间 NAT 超时：把 `ServerAliveInterval` 降到 15。
- `Permission denied (publickey)` → 公钥没加到服务器对应用户。
- `remote port forwarding failed for listen port 18092` → 服务器上端口已被占用（旧会话未清理）：
  `sudo ss -tlnp | grep 18092`，必要时 `pkill -f 'sshd.*18092'`。

## 首字很慢 / 生成很慢

```bash
curl -o /dev/null -s -w 'dns=%{time_namelookup} conn=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total}\n' \
  http://SERVER:8080/v1/models -H "Authorization: Bearer $TOKEN"
```

- `ttfb` 大：预填充慢（长 prompt、KV 缓存命中差、GPU 弱）。
- 全程慢但稳定：上行带宽不足（家庭宽带上行常见 30–50 Mbps）。

## 面板显示「历史记录服务未启动」

```bash
systemctl status model-hist --no-pager
journalctl -u model-hist -n 30 --no-pager
curl -s http://127.0.0.1:18094/health
```

上游没有 `/api/summary` 时这是**正常降级**；推理不受影响。

## 服务器重启后全部失效

```bash
systemctl is-enabled model-hist nginx
# 隧道由算力机侧自启，检查计划任务/服务
```

## 清空后仍在刷日志

算力机侧隧道还在重连：停掉计划任务或 systemd 单元即可。
