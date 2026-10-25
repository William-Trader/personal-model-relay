# 模型远程使用个人中转

把一台**有 GPU 的电脑**（家里 / 公司 / 实验室）上的本地模型，安全地接到一台**公网服务器**上，
让笔记本、手机、其他机器通过 **OpenAI 兼容接口**调用。

不需要公网 IP、不需要路由器端口映射、不把推理端口暴露到公网。

```
 携带电脑 / 手机 / 其他 agent
        │  HTTPS + Bearer Token（可选 TLS）
        ▼
 ┌──────────────────────────────┐
 │  中转服务器（公网，1C1G 够用） │
 │  nginx :8080                 │
 │    /v1/*  → 127.0.0.1:18092  │
 │    /      → 状态面板（可选）  │
 └──────────────┬───────────────┘
                │ 只监听 loopback
        SSH 反向隧道（算力机主动外连）
                │
 ┌──────────────▼───────────────┐
 │  算力电脑（有 GPU，可在 NAT 后）│
 │  推理服务 127.0.0.1:8091      │
 │  llama.cpp / vLLM / 任意 OpenAI 兼容服务  │
 └──────────────────────────────┘
```

**核心思想**：连接由算力机**主动发起**（出站 SSH），所以它不需要公网 IP；
服务器上的隧道端口只绑 `127.0.0.1`，公网只能看到带鉴权的 HTTP 端口。

---

## 它解决什么问题

| 场景 | 没有中转 | 用本项目 |
|---|---|---|
| 家里 GPU 机器在 NAT 后 | 外网访问不了 | 算力机主动连服务器，反向转发 |
| 云服务器没 GPU | 只能买 API | 云服务器只做入口，推理在本地 |
| 直接开放模型端口 | 被扫、被盗用、被打爆 | 只暴露一个 token 鉴权的 HTTP 端口 |
| 换网络 / 换 IP | 客户端要改地址 | 客户端只认服务器地址，算力机重连即可 |

---

## 三步上线

### 1. 服务器（公网 Linux）

```bash
git clone https://github.com/<you>/personal-model-relay.git
cd personal-model-relay
sudo RELAY_TOKEN="$(openssl rand -hex 24)" bash scripts/install-server.sh
```

脚本会：装 nginx/python3 → 部署历史面板守护进程 → 渲染 nginx 配置 → `nginx -t` → reload。
结束时打印**只显示一次**的 token，请立刻保存到密码管理器。

### 2. 算力电脑（Windows 或 Linux）

**Windows（推荐计划任务，开机自启 + 断线重连）**

```powershell
powershell -ExecutionPolicy Bypass -File compute\windows\install-task.ps1 `
  -ServerHost relay.example.com -SshUser relay -KeyPath "$HOME\.ssh\relay_ed25519" -LocalPort 8091
```

**Linux**

```bash
sudo cp compute/linux/relay-tunnel.service /etc/systemd/system/
sudo systemctl edit relay-tunnel   # 填 Environment= 里的 SERVER_HOST / LOCAL_PORT
sudo systemctl enable --now relay-tunnel
```

两者都会执行等价于：

```bash
ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -i ~/.ssh/relay_ed25519 \
    -R 127.0.0.1:18092:127.0.0.1:8091 relay@relay.example.com
```

> 注意 `-R 127.0.0.1:...`：显式绑定 loopback，避免隧道端口被公网访问。

### 3. 携带电脑（客户端）

```bash
curl -s http://relay.example.com:8080/v1/models \
  -H "Authorization: Bearer $RELAY_TOKEN"
```

OpenClaw 配置样例见 `client/openclaw.provider.example.json`。

---

## 目录结构

```
server/nginx/llm-relay.conf.template   nginx 站点模板（含 token 鉴权、流式关闭缓冲）
server/systemd/model-hist.service      历史峰值面板守护进程
server/hist/hist.py                    采样器：轮询上游 /api/summary，持久化峰值
server/hist/panel.js                   注入到面板页底部的「历史最高」卡片
compute/windows/*.ps1                  反向隧道 + 计划任务（断线自动重连）
compute/linux/relay-tunnel.service     systemd 版本
client/*                               客户端样例（curl / OpenClaw / Python）
scripts/install-server.sh              一键安装（幂等）
scripts/uninstall-server.sh            一键卸载（默认保留历史数据）
scripts/rotate-token.sh                轮换 token
docs/architecture.md                   设计说明与边界
docs/troubleshooting.md                502 / 401 / 断线 / 卡顿排查
AGENT-HANDOFF.md                       给「另一个人的 agent」的交接说明书
```

---

## 验证清单

| 检查 | 命令 | 期望 |
|---|---|---|
| 隧道在听 | `ss -tlnp \| grep 18092` | `127.0.0.1:18092` 有 sshd |
| 鉴权生效 | `curl -i .../v1/models` | 无 token 401 |
| 端到端 | `curl .../v1/chat/completions` | 200 且有内容 |
| 断线自愈 | 算力机断网 10 秒后恢复 | 30 秒内自动重连 |

---

## 安全模型

- **token 是唯一入口凭据**：48 位随机十六进制，仅存服务器 `/etc/nginx/.relay-token`（600）与客户端密钥库；不进 Git、不进日志。
- **隧道端口不对外**：`-R 127.0.0.1:...` + 服务器 `GatewayPorts no`（默认）。
- **公网明文是默认值，不是推荐值**：生产请在 nginx 前加 TLS（Caddy 自动证书 / 反代 443），或使用 Cloudflare Tunnel/WireGuard。
- **最小权限**：SSH 用户只用于端口转发，`authorized_keys` 里加 `restrict,port-forwarding`。
- **审计**：nginx access log 记录 IP/UA；面板页只读。

---

## 卸载

```bash
sudo bash scripts/uninstall-server.sh            # 保留历史数据
sudo bash scripts/uninstall-server.sh --purge    # 连历史数据一起删
```

算力机侧：`schtasks /Delete /TN "ModelRelayTunnel" /F` 或 `systemctl disable --now relay-tunnel`。

---

## License

MIT。见 `LICENSE`。
