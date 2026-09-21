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
  - Hysteria2 专属参数：`hy2_udp`（UDP 转发）、`hy2_up_mbps` / `hy2_down_mbps`（带宽 & Brutal 恒速发送）、`hy2_obfs_password`（Salamander 混淆）、`hy2_masq_type`（伪装成 404 / 静态文本 / 本地目录 / 反代网站）；
  - `[[nodes.rules]]`：按域名 / IP 匹配的分流规则，逐条从上到下匹配，命中即停，落地可选 `direct` / `warp` / 自定义 `proxy`（SOCKS5 或 HTTP）；
  - `[warp]`：WARP 账号文件路径；
  - `[panel]`：面板开关、监听地址、端口、账号密码、隐藏入口 `entry`；
  - `[log]`：日志级别、落盘路径与滚动大小上限。

改完配置重启服务生效。之后随时可以在菜单里按 `g` 一键补建节点 + 跑内核优化。

### 方式二：懒人一条龙（全新机器直接跑）

新机器不想自己配，跑这条命令，装面板、建节点、做优化一气呵成：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh) oneclick
```

一个 `Y` 确认，全程无需其它输入，自动完成：

> **①** 内核终极优化（BBR + 缓冲区自适应，持久化）　**②** 建 `Mixed` 节点（随机端口 · SOCKS5+HTTP · 自动生成账号密码）　**③** 建 `Trojan-[地区]` 节点（随机端口 · 自签 TLS）　**④** 建 `Hysteria2-[地区]` 节点（随机端口）

跑完屏幕直接给出**面板地址 + 账号密码 + 节点链接**，节点名自动带本机地区后缀（如 `Trojan-HK`）。如果机器已经装过 mixflow，这条命令只会执行优化 + 建节点，不会重装。

---

## 🎛️ 面板

默认地址 `http://服务器IP:12321`，账号 `admin` / `admin123`（**请尽快改**）。

**隐藏入口**：设一个随机路径后，只有访问 `http://IP:12321/你的密路径` 才进得去，其它路径一律 404，扫端口的人看不到面板存在。

## 🧰 常用命令

| 命令 | 作用 |
| :-- | :-- |
| `mixflow.sh` | 打开管理菜单 |
| `mixflow.sh oneclick` | 一键建节点 + 终极优化 |
| `mixflow quicknode --tag HK` | 建 Trojan + Hysteria2（随机端口） |
| `mixflow optimize` | 终极代理模式内核优化 |
| `mixflow panel --port <N>` | 改面板端口 |
| `mixflow panel --path /xxx` | 设隐藏入口（`--path off` 关闭） |
| `mixflow panel --pass <密码>` | 改面板密码（忘密码也能改，不用进面板） |

---

## ✨ 功能特性

- **多协议**：Trojan（TLS）、Hysteria2（QUIC）、Mixed（SOCKS5 + HTTP）。
- **多种出站**：直连、远程 SOCKS5/HTTP 代理、WARP；每条分流规则可单独指定出站，支持按域名（含通配符 / `keyword:` 关键词）和 IP/CIDR 匹配，从上到下命中即停。
- **分流可视化**：面板内置流程图与地图，直观查看规则命中路径；分流库可复用常用规则集。
- **Hysteria2 抗封锁**：Salamander 混淆（探测包无有效密码直接丢弃）+ 伪装站点（404 / 固定文本 / 本地静态目录 / 反代真实网站）。
- **订阅链接**：按客户端 UA 自动适配 Clash / sing-box / Base64 通用格式；自签证书自动附带指纹信息，免额外确认。
- **Web 管理面板**：节点增删改、隐藏入口、账号密码可在忘记密码时用命令行直接重置。
- **WARP 集成**：创建节点自动注册并按需拉起隧道，节点全部删除后自动拆除隧道。
- **内核终极优化**：一键 BBR + 缓冲区自适应调优，并持久化到重启后仍生效；TCP Fast Open 自动检测内核支持并按需启用。
- **一键部署**：自动识别 amd64 / arm64，systemd 常驻 + 开机自启，全局 `mixflow` 命令。

---

## 📝 更新日志

| 版本 | 说明 |
| ---- | ---- |
| 0.3.8 | TCP Fast Open 全链路支持：内核检测、自动提升、入站启用、面板状态显示；Trojan 订阅完善（URI 补 `udp=1`/`security=tls`，默认 `udp+tfo`，随机端口上限修正为 65535）；面板/quicknode 随机端口真实 bind 探测；去掉分享链接 `allowInsecure`（兼容新 Xray），自签证书附 `pcs`/`pinSHA256` 指纹；通用订阅按 UA 自动选 Clash / sing-box / Base64 |
| 0.3.0 | Trojan WS 优化：对外显示端口、优选域名；分流库 / 本节点规则交互优化；流程图与地图标签修正；回落地址提示 |
| 0.2.x | GeoIP 多源并行多数决、过滤占位坐标；WARP 随节点自动注册/拆除隧道；分流配置与面板密码交互优化 |
| 0.1.x | Hysteria2 互通性排查：分阶段连接日志、自签证书完善、SNI 回落规则 |
| 0.1.0 | 初版：Trojan / Hysteria2（UDP、带宽、Salamander 混淆、伪装站点）/ Mixed；分流规则与分流库；直连 / 远程代理 / WARP 出站；Web 面板与一键安装 |

> 当前内核版本 `v0.3.8`（对齐 `Cargo.toml`），为最新版本。

---

<div align="center">
<sub>放行提醒：节点端口需在防火墙 / 云安全组开放 —— Trojan 走 <b>TCP</b>，Hysteria2 走 <b>UDP</b>。</sub>
</div>
