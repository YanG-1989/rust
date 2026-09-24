<div align="center">

# 🌊 MixFlow

**多协议代理 + Web 管理面板 · 一键部署**

Trojan · Hysteria2 · SOCKS5 / HTTP　|　直连 / 远程代理 / WARP 出站　|　分流规则　|　内核终极优化

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue)
![systemd](https://img.shields.io/badge/service-systemd-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

</div>

---

## 🚀 安装

无论哪种方式，都会自动识别 CPU 架构（amd64 / arm64），装到 `/opt/mixflow`，systemd 常驻 + 开机自启，二进制软链到 `PATH`，全局可用 `mixflow` 命令。

### 方式一：装好后自己配置（推荐熟悉的人）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh)
```

打开交互式管理菜单，自己设置面板端口 / 隐藏入口 / 密码，**不自动建节点**。装好后可以：

- 在面板里手动添加节点，逐项填写协议、端口、密码等参数；
- 或者直接编辑 `config.toml`（示例见 `config.example.toml`），支持：
  - `[[nodes]]`：Mixed（SOCKS5+HTTP）/ Trojan / Hysteria2 节点，监听地址、端口、出站方式（`direct` / `warp`）等全部手写；
  - Hysteria2 专属参数：`hy2_udp`、`hy2_up_mbps` / `hy2_down_mbps`（带宽 & Brutal）、`hy2_obfs_password`（Salamander 混淆）、`hy2_masq_type`（伪装）、`hy2_hop_ports`（端口跳跃，留空默认开，`off` 关闭）；
  - `[[nodes.rules]]`：按域名 / IP 匹配的分流规则，从上到下命中即停，落地可选 `direct` / `warp` / 自定义 `proxy`；
  - `[warp]`：WARP 账号文件路径；
  - `[panel]`：面板开关、监听地址、端口、账号密码、隐藏入口 `entry`；Cloudflare API 令牌与默认根域名；面板绑定域名 / 证书（Origin CA 或 Let's Encrypt DNS-01）与 HTTPS；
  - `[log]`：日志级别、落盘路径与滚动大小上限（默认约 1MB）。

改完配置重启服务生效。之后随时可以在菜单里按 `g` 一键补建节点 + 跑内核优化。

### 方式二：懒人一条龙（全新机器直接跑）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh) oneclick
```

一个 `Y` 确认，自动完成：

> **①** 内核终极优化（BBR + 缓冲区自适应，持久化）　**②** 建 `Mixed` 节点　**③** 建 `Trojan-[地区]` 节点　**④** 建 `Hysteria2-[地区]` 节点

跑完屏幕直接给出**面板地址 + 账号密码 + 节点链接**。若机器已装过 mixflow，只会执行优化 + 建节点，不重装。

---

## 🎛️ 面板

默认地址 `http://服务器IP:12321`，账号 `admin` / `admin123`（**请尽快改**）。

**隐藏入口**：设随机路径后，只有访问 `http://IP:12321/你的密路径` 才进得去，其它路径一律 404。

页签：**概览** / **节点** / **分流** / **订阅** / **设置**。

---

## 🧰 常用命令

| 命令 | 作用 |
| :-- | :-- |
| `mixflow.sh` | 打开管理菜单 |
| `mixflow.sh oneclick` | 一键建节点 + 终极优化 |
| `mixflow quicknode --tag HK` | 建 Trojan + Hysteria2（随机端口） |
| `mixflow optimize` | 终极代理模式内核优化 |
| `mixflow panel --port <N>` | 改面板端口 |
| `mixflow panel --path /xxx` | 设隐藏入口（`--path off` 关闭） |
| `mixflow panel --pass <密码>` | 改面板密码（忘密码也能改） |

---

## ✨ 功能特性

- **多协议**：Trojan（TLS / WS）、Hysteria2（QUIC）、Mixed（SOCKS5 + HTTP）。
- **多种出站**：直连、远程 SOCKS5/HTTP、WARP；每条分流规则可单独指定出站。
- **分流可视化**：流程图与地图；分流库可复用常用规则集。
- **Hysteria2 抗封锁**：Salamander 混淆、伪装站点；**端口跳跃**默认开启（主端口只监听一个，区间 REDIRECT；宽约 500~1000；无权限自动跳过，类似 TFO；订阅按需带 `mport` / `ports`）。
- **Cloudflare 部署**：设置中保存 API 令牌（需**读取和写入**；面板 Origin CA 另需 **SSL and Certificates → Edit**）；Trojan WebSocket 可「CF部署」——自动写 DNS 小黄云 + Origin 回源 + **Origin CA 证书**（同 Zone 通配复用）；删节点时同步清理 DNS / Origin Rule。
- **面板域名与证书**：设置页绑定域名、DNS 小黄云、对外固定 443 回源；证书可选 **Cloudflare Origin CA（约 15 年，仅橙云）** 或 **Let's Encrypt（内置 DNS-01，公有信任）**。
  - **LE 可与小黄云同时开启**：走的是 DNS-01（写 `_acme-challenge` TXT），不依赖 HTTP-01，A 记录是否橙云不影响签发。
  - **LE 自动续期**：进程内每 6 小时检查，距到期 ≤30 天则再签；条件：`cert_mode=letsencrypt` 且已启用 HTTPS、有域名与 CF Token。**解绑 DNS**（会关 HTTPS）或改为 Origin CA / 关 HTTPS 即停止续期。
  - Origin CA 按 Zone 签 `*.根域`，面板域名与节点 CDN **同主域共用**；申请成功后开启面板 HTTPS（证书热加载），并自动勾选「仅 HTTPS / 仅允许本域名」。
- **订阅与导出**：按 UA 自动适配 Clash / sing-box / Base64；自签附 `pcs` / `pinSHA256`；WS 套 CF 时订阅不强制 skip-cert-verify；一次性导出与订阅链接支持**二维码**。
- **可观测**：概览页（版本 / 负载 / 流量 / 运行状态）；排障环形记录（中文摘要）；文件日志大小上限。
- **Web 面板**：节点增删改、回落地址探测、忘记密码可用命令行重置。
- **WARP**：创建节点自动注册并按 family 拉起隧道，节点删光后自动拆除。
- **内核优化**：一键 BBR + 缓冲区调优并持久化；TCP Fast Open 内核检测与自动启用。
- **一键部署**：amd64 / arm64，systemd 常驻，全局 `mixflow` 命令。

---

## 📝 更新日志

| 版本 | 说明 |
| ---- | ---- |
| 0.3.36–0.3.39 | **面板域名与证书**：绑定 DNS / 解绑；Origin CA（Zone 通配约 15 年）与 Let's Encrypt（DNS-01，可开小黄云）；面板 HTTPS 热加载；Host 校验；CF 一键回源写入 Origin CA |
| 0.3.27–0.3.35 | **Cloudflare / 订阅**：CF部署（DNS 橙云 + Origin 回源）；删节点清理 CF；WS+CF 显式 insecure=0 / skip-cert-verify: false；导出与订阅二维码；令牌文案 |
| 0.3.25–0.3.26 | **排障与日志**：排障环形记录（中文）；日志上限；概览分页与文案精简；回落地址探测 |
| 0.3.22–0.3.24 | **Hy2 端口跳跃**：nft/iptables REDIRECT；默认开启；无权限自动跳过；订阅 `mport`/`ports` |
| 0.3.17–0.3.21 | **概览与界面**：概览页签；页签精简；SVG 图标；失败徽章可点 |
| 0.3.11–0.3.16 | **节点与订阅**：Hy2 Brutal；TLS/CDN 联动；订阅导出/链接拆分；WS/CDN 软检查 |
| 0.3.1–0.3.10 | **TFO 与基础**：TFO 全链路；版本统一 0.3.x；自签指纹；UA 自适应订阅 |
| 0.3.0 | Trojan WS 对外端口/优选域名；分流库 UI；地图香港投影 |
| 0.2.x | GeoIP 多源多数决；WARP 随节点自动注册/拆除 |
| 0.1.x | 初版：Trojan / Hy2 / Mixed；分流；WARP；Web 面板 |

> 当前 **`0.3.39`**，与 `Cargo.toml` / `VERSION` 对齐。

---

<div align="center">
<sub>放行提醒：节点端口需在防火墙 / 云安全组开放 —— Trojan 走 <b>TCP</b>，Hysteria2 走 <b>UDP</b>（含端口跳跃区间）。套 Cloudflare 时外网走 CF 端口（如 443 / 2053），本机监听端口由 Origin Rule 回源。</sub>
</div>
