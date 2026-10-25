# 交接说明书（给接手的 AI agent）

> 你接手的是「模型远程使用个人中转」。目标：让一台**有 GPU 的电脑**上的模型，被**任意设备**通过 OpenAI 兼容接口安全调用。
> 你只有三台角色机器：**中转服务器**（公网）、**算力电脑**（有 GPU，可能在 NAT 后）、**携带电脑**（发起请求的一方）。
> 全文用占位符，真实值必须由人类提供，不要猜测、不要写进仓库。

---

## 0. 先建立变量表（开工前必须填满）

| 变量 | 含义 | 示例 | 谁知道 |
|---|---|---|---|
| `SERVER_HOST` | 中转服务器公网地址 | `relay.example.com` | 人类 |
| `SERVER_USER` | 服务器 SSH 用户（需 sudo） | `ubuntu` | 人类 |
| `SERVER_KEY` | 服务器 SSH 私钥路径 | `~/.ssh/id_ed25519` | 人类 |
| `TUNNEL_PORT` | 服务器 loopback 隧道端口 | `18092` | 本方案约定 |
| `PUBLIC_PORT` | 对外 HTTP 端口 | `8080` | 本方案约定 |
| `UPSTREAM_PORT` | 算力机本地推理端口 | `8091` | 人类或读算力机配置 |
| `RELAY_TOKEN` | 访问令牌（48 位 hex） | 安装时生成 | 只存密码管理器 |
| `SSH_USER` | 算力机连接服务器用的账号 | `relay` | 人类 |

**缺任何一项就停下来问人类**，不要用「大概」「先默认」推进。

---

## 1. 前置检查（每条都要有输出证据）

```bash
# 1.1 服务器可登录且能 sudo
ssh -T -i "$SERVER_KEY" "$SERVER_USER@$SERVER_HOST" 'hostname; sudo -n true && echo SUDO_OK'

# 1.2 服务器 80/8080 未被别的站点占用
ssh -T ... 'sudo ss -tlnp | grep -E ":(80|8080)\b" || echo FREE'

# 1.3 算力机推理服务本地可用（在算力机上执行）
curl -s -m 5 http://127.0.0.1:$UPSTREAM_PORT/v1/models | head -c 200

# 1.4 算力机能出站 SSH 到服务器
ssh -T -i <key> "$SSH_USER@$SERVER_HOST" 'echo TUNNEL_AUTH_OK'
```

任何一步失败 → 先修这一步，**不要继续**。

---

## 2. 部署顺序（服务器 → 算力机 → 携带机）

### 2.1 服务器

```bash
sudo RELAY_TOKEN="$(openssl rand -hex 24)" bash scripts/install-server.sh
```

验收：

```bash
systemctl is-active model-hist            # active
sudo nginx -t                              # syntax is ok
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/   # 502（隧道没起时的正常值）
```

> 此时 502 是**预期**的：隧道还没建立。

### 2.2 算力机

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File compute\windows\install-task.ps1 `
  -ServerHost $SERVER_HOST -SshUser $SSH_USER -KeyPath $env:USERPROFILE\.ssh\relay_ed25519 `
  -LocalPort $UPSTREAM_PORT
```

Linux：

```bash
sudo cp compute/linux/relay-tunnel.service /etc/systemd/system/
sudo systemctl edit relay-tunnel    # 填 SERVER_HOST / SSH_USER / LOCAL_PORT / KEY
sudo systemctl enable --now relay-tunnel
```

验收（在服务器上）：

```bash
ss -tlnp | grep $TUNNEL_PORT          # 127.0.0.1:18092 users:(("sshd",...))
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$TUNNEL_PORT/v1/models   # 200 或 401
```

### 2.3 携带机

```bash
curl -s http://$SERVER_HOST:$PUBLIC_PORT/v1/models -H "Authorization: Bearer $RELAY_TOKEN"
curl -s http://$SERVER_HOST:$PUBLIC_PORT/v1/chat/completions \
  -H "Authorization: Bearer $RELAY_TOKEN" -H 'Content-Type: application/json' \
  -d '{"model":"<MODEL_ID>","messages":[{"role":"user","content":"ping"}],"max_tokens":16}'
```

验收：返回 `choices[0].message.content` 非空；耗时可接受。

---

## 3. 不变量（违反即返工）

1. **隧道端口只绑 127.0.0.1**：`-R 127.0.0.1:PORT:...`；服务器 `GatewayPorts no`。
2. **token 只出现在**：服务器 `/etc/nginx/.relay-token`（600）、客户端密钥库。**绝不**进 Git、日志、聊天记录、截图。
3. **仓库里不能有真实 IP / 域名 / 用户名 / 密钥 / 主机名**；用 `example.com`、`203.0.113.x` 占位。
4. **不要**把算力机的推理端口通过 `-R 0.0.0.0:` 暴露；不要关防火墙来「先跑通」。
5. 改 nginx 前先备份，改后必须 `nginx -t` 再 `reload`（不要 restart 断流）。
6. 所有「完成」必须有命令输出证据；没有证据就说不确定。

---

## 4. 常见故障的判定顺序

| 现象 | 先查 | 判定 |
|---|---|---|
| 502 | 服务器 `ss -tlnp \| grep 18092` | 无监听 → 隧道没起/已断 → 去算力机 |
| 401 | 客户端 header 与服务器 token 是否一致 | 不一致 → 轮换或重配置 |
| 连上但很慢 | `curl -w '%{time_starttransfer}'` | 首字慢 = 预填充慢；持续慢 = 带宽/并发 |
| 隧道频繁断 | 算力机日志 `relay-tunnel.log` | 网络抖动 → 加 `ServerAliveInterval`；NAT 超时 → 缩短心跳 |
| 服务器重启后 502 | `systemctl is-enabled model-hist` / 隧道自启 | 重新拉起隧道 |

详细见 `docs/troubleshooting.md`。

---

## 5. 交接给下一个人时，你要交付什么

1. 仓库地址 + 本文件。
2. 变量表（**不含 token 明文**，只写「在密码管理器条目 X」）。
3. 三台机器各自「谁负责、怎么登录、坏了找谁」。
4. 一份实测记录：安装时间、验证命令输出、当前模型 ID、已知限制。

---

## 6. 清空服务器（人类明确要求时才做）

```bash
sudo bash scripts/uninstall-server.sh --purge
```

然后核对：

```bash
systemctl status model-hist --no-pager      # 不存在
sudo ss -tlnp | grep -E ':(8080|18092|18094)\b' || echo CLEAN
ls /opt/model-relay 2>/dev/null || echo FILES_GONE
ls /etc/nginx/conf.d/*relay* 2>/dev/null || echo CONF_GONE
```

> 注意：清空后**算力机的隧道会一直重连失败**，请同时停掉算力机侧的计划任务/systemd，
> 否则日志会被重连刷屏。

---

## 7. 你可以自己决定的事

- 端口号、目录、日志路径（保持本文约定即可）。
- 是否启用 TLS、是否加访问频率限制。
- 面板是否保留（`INSTALL_PANEL=0` 可跳过历史面板）。

## 8. 必须先问人类的事

- 是否要把服务暴露到公网 443（涉及证书/域名）。
- 是否允许在服务器上长期存历史统计数据。
- 清空服务器前是否已确认没有其他人在用。
