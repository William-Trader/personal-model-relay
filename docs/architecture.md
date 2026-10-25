# 架构与设计说明

## 1. 三台机器的角色

| 角色 | 要求 | 职责 |
|---|---|---|
| 中转服务器 | 公网 IP，1C1G 起，Linux | 唯一公网入口；鉴权；反向代理；可选状态面板 |
| 算力电脑 | 有 GPU，可访问外网（出站 22） | 运行推理服务；主动建立 SSH 反向隧道 |
| 携带电脑 | 任意能上网的设备 | 用 OpenAI 兼容接口发请求 |

关键点：**公网入口与算力解耦**。算力机换网络、换 IP、重启，都不影响客户端地址。

## 2. 数据流

```
client ──HTTP(S)──▶ nginx :8080
                    ├─ /v1/*  ──token 校验──▶ 127.0.0.1:18092
                    └─ /       ─────────────▶ 127.0.0.1:18092（可选注入面板脚本）
                                                   │
                                       sshd（反向隧道会话）
                                                   │
                                    算力机 ssh -R 127.0.0.1:18092:127.0.0.1:8091
                                                   │
                                          推理服务 :8091
```

## 3. 为什么是反向隧道

- 家用宽带通常无公网 IPv4，且运营商封 80/443 入站。
- `ssh -R` 让算力机**主动外连**，NAT 只放行出站，天然穿透。
- 隧道监听在服务器 loopback：公网扫不到，只有 nginx 能访问。
- SSH 自带加密与保活，比自建隧道省事。

替代方案对比：

| 方案 | 穿透 | 鉴权 | 运维成本 | 适用 |
|---|---|---|---|---|
| SSH 反向隧道（本项目） | 出站即可 | SSH key + token | 低 | 个人/小团队 |
| WireGuard | 需一端公网 | 密钥 | 中 | 多设备组网 |
| Cloudflare Tunnel | 出站即可 | CF Access | 低 | 无服务器也可 |
| frp | 需服务端 | token | 中 | 大量端口 |

## 4. 鉴权设计

- 单一静态 token（48 hex），同时接受 `Authorization: Bearer <token>` 与 `x-api-key: <token>`（兼容不同客户端）。
- 用 nginx `map` 做常量时间比较之外的字符串匹配；token 不落 access log（header 不记录）。
- 轮换：`scripts/rotate-token.sh` 生成新值、原子替换、`nginx -t` 后 reload。
- 未加频率限制属于已知取舍：个人使用足够；对外可加 `limit_req`。

## 5. 状态面板（可选）

`hist.py` 每秒轮询上游 `/api/summary`（若推理服务提供），记录：

- 实时生成/预填充速度峰值（按 `engine.phase` 判定阶段）
- 单轮 timings 峰值（`lastRequest.predicted_per_second` / `prompt_per_second`）
- GPU 利用率峰值

数据存 JSON（原子写），通过 loopback HTTP 暴露；nginx 用 `sub_filter` 把 `panel.js` 注入原页面底部。
**上游没有 `/api/summary` 时面板自动显示「不可达」，不影响推理链路。**

## 6. 边界与已知限制

- 单点：服务器挂了就全断（可加第二台做 DNS 轮询，本项目不做）。
- 单隧道：默认一个算力机；多机可复制 `TUNNEL_PORT`（18092/18093…）并加 nginx upstream。
- 明文 HTTP：默认 8080 无 TLS，**必须**自行加 TLS 或限制来源 IP。
- 无多租户：一个 token 一个权限级别。
