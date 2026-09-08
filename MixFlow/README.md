<div align="center">

# 🌊 MixFlow

**多协议代理 + Web 管理面板 · 一键部署**

Trojan · Hysteria2 · SOCKS5 / HTTP　|　直连 / WARP 出站　|　内核终极优化

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-blue)
![systemd](https://img.shields.io/badge/service-systemd-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

</div>

---

## 🚀 安装

推荐**全自动**一条龙 —— 全新机器直接跑这条，装好面板、建好节点、做完优化：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh) oneclick
```

一个 `Y` 确认，全程无需其它输入。跑完屏幕直接给出**面板地址 + 账号密码 + 两条节点链接**：

> **①** 内核终极优化（BBR + 缓冲区自适应）　**②** 建 `Trojan-[地区]` 节点（随机端口）　**③** 建 `Hysteria2-[地区]` 节点（随机端口）

节点名自动带本机地区（如 `Trojan-HK`），先优化后建节点、优化只显示一行结果，清爽不刷屏。已装过则跳过安装，只做优化 + 建节点。

<details>
<summary>只想装好、自己配置？（不带 <code>oneclick</code>）</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh)
```

打开管理菜单，交互式设置面板端口 / 隐藏入口 / 密码，不自动建节点。之后随时按 `g` 再一键建节点。
</details>

两种方式都会自动识别 CPU 架构（amd64 / arm64），装到 `/opt/mixflow`，systemd 常驻 + 开机自启。

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


---

<div align="center">
<sub>放行提醒：节点端口需在防火墙 / 云安全组开放 —— Trojan 走 <b>TCP</b>，Hysteria2 走 <b>UDP</b>。</sub>
</div>
