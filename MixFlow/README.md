<div align="center">

# 🌊 MixFlow

**多协议代理 + Web 管理面板 · 一键部署**

Trojan · Hysteria2 · SOCKS5 / HTTP　|　直连 / WARP 出站　|　内核终极优化

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue)
![systemd](https://img.shields.io/badge/service-systemd-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

</div>

---

## 🚀 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh)
```

自动识别 CPU 架构下载对应二进制，装到 `/opt/mixflow`，systemd 常驻 + 开机自启。

## ⚡ 一键起飞（新机推荐）

菜单里按 **`g`**，或直接：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh) oneclick
```

一个 `Y` 确认，只干三件事：

> **①** 建一个 `Trojan-[地区]` 节点（随机端口）　**②** 建一个 `Hysteria2-[地区]` 节点（随机端口）　**③** 套用「专用代理 VPS · 终极模式」内核优化（BBR + 缓冲区自适应）

节点名自动带上本机地区，如 `Trojan-HK` / `Hysteria2-HK`，建好即启用。

## 🎛️ 面板

默认地址 `http://服务器IP:12321`，账号 `admin` / `admin123`（**请尽快改**）。

**隐藏入口**：设一个随机路径后，只有访问 `http://IP:12321/你的密路径` 才进得去，其它路径一律 404，扫端口的人看不到面板存在。

## 🧰 常用命令

> 装好后二进制已软链到 `PATH`，可全局使用 `mixflow`。改动重启服务生效。

| 命令 | 作用 |
| :-- | :-- |
| `mixflow.sh` | 打开管理菜单 |
| `mixflow.sh oneclick` | 一键建两个节点 + 终极优化 |
| `mixflow quicknode --tag HK` | 建 Trojan + Hysteria2（随机端口） |
| `mixflow optimize` | 终极代理模式内核优化 |
| `mixflow panel --port <N>` | 改面板端口 |
| `mixflow panel --path /xxx` | 设隐藏入口（`--path off` 关闭） |
| `mixflow panel --pass <密码>` | 改面板密码（忘密码也能改，不用进面板） |

## 🛠️ 自行编译

推荐 musl 静态版，一个二进制跑遍所有发行版：

```bash
cargo build --release --target x86_64-unknown-linux-musl   # amd64
cross build --release --target aarch64-unknown-linux-musl   # arm64
```

产物按 `mixflow-linux-amd64` / `mixflow-linux-arm64` 命名，放进本目录即可。详见 [COMPILE.md](./MixFlow/COMPILE.md)。

---

<div align="center">
<sub>放行提醒：节点端口需在防火墙 / 云安全组开放 —— Trojan 走 <b>TCP</b>，Hysteria2 走 <b>UDP</b>。</sub>
</div>
