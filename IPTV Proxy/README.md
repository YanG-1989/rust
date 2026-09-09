# 📺 IPTV Proxy

**IPTV 代理 + Web 管理面板 · 一键部署**

代理 / 重定向 / 改写 / DASH 四种转发模式 | EPG 节目单 · 台标 · 回看 · 定时录制 | Token 鉴权 + IP 封禁

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-blue)
![service](https://img.shields.io/badge/service-systemd%20%7C%20OpenRC-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

---

## 🚀 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/IPTV%20Proxy/iptv-proxy.sh)
```

打开管理菜单，选 `1` 安装。装的时候会问三个问题，**全部回车走默认值也行**：

| 问题 | 默认 |
| --- | --- |
| 面板端口 | `19899` |
| 面板账号 | `admin` |
| 面板密码 | `admin` |

自动识别 CPU 架构（amd64 / arm64 / armv7），装到 `/opt/iptv-proxy`，systemd（Alpine 用 OpenRC）常驻 + 开机自启。

装完二进制不会覆盖已有的 `config.toml`，所以**更新版本直接再跑一次选 `1`**，频道和设置都不会丢。

## 🎛️ 面板

地址 `http://服务器IP:19899/panel`，账号 `admin` / `admin`（**请尽快改**）。

频道、分组、EPG、缓存、安全管控全在面板里配；订阅地址在「分组管理」页生成。

> 面板端口默认监听 `[::]` 双栈。**记得在防火墙 / 云安全组放行对应 TCP 端口。**

## 🧰 常用命令

> 装好后脚本已软链到 `PATH`，可全局使用 `iptv-proxy`。

| 命令 | 作用 |
| --- | --- |
| `iptv-proxy` | 打开管理菜单 |
| `iptv-proxy update` | 更新二进制到最新版 |
| `iptv-proxy port <N>` | 改面板端口 |
| `iptv-proxy pass <密码> [账号]` | 改面板密码 / 账号（**忘密码也能改**，不用进面板） |
| `iptv-proxy restart` | 重启服务 |
| `iptv-proxy log` | 看运行日志 |
| `iptv-proxy url` | 打印面板地址 |
| `iptv-proxy uninstall` | 卸载 |

改端口和改密码都是直接改 `config.toml` 并重启服务，改完旧登录会话失效，需要重新登录。

## 📂 文件位置

```
/opt/iptv-proxy/
├── iptv-proxy          二进制
├── config.toml         配置（面板里改的东西都存这）
├── iptv-proxy.log      运行日志
└── cache/              切片缓存、台标、EPG 数据
```

卸载时会问要不要一起删 `/opt/iptv-proxy`，选 `N` 就只停服务、保留数据，重装即恢复。

## ℹ️ 说明

- **ffmpeg 可选**：只有面板「视频素材」的 MP4 → HLS 转码用得上，不装不影响正常代理。
- 面板密码在配置里存的是 SHA-256，明文不落盘。
- 想换下载源：`IPTV_URL=https://你的地址/iptv-proxy-linux-{arch} bash <(curl -fsSL ...)`
