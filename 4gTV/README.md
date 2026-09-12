# 📺 4GTV 串流代理 · 公开版

**4GTV 取流代理 + Web 管理面板 · 一键部署**

代理 TS / 转发 M3U8 / 302 重定向 | SOCKS5/HTTP 代理 | EPG · 在线播放器 

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-blue)
![service](https://img.shields.io/badge/service-systemd-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

---

## 🚀 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/4gTV/4gtv.sh)
```

打开管理菜单，选 `1` 安装。装的时候会问两个问题，**全部回车走默认值也行**：

| 问题 | 默认 |
| --- | --- |
| 监听端口 | **随机**高位端口（约 10000–60000） |
| 隐藏路径 | **随机**生成（推荐保留） |

自动识别 CPU 架构（amd64 / arm64 / armv7），装到 `/opt/4gtv`，systemd 常驻 + 开机自启。

> **隐藏路径**：所有接口挂在随机前缀下（例如 `/a1b2c3d4`），不带前缀访问会 404，降低被端口扫描发现的概率。

装完二进制不会覆盖已有配置和频道数据，**更新版本直接再跑一次选 `1`** 即可。

## 🎛️ 面板

装完后脚本会打印地址，形如：

```
http://服务器IP:<端口>/<隐藏路径>/admin?key=<管理密钥>
播放器：http://服务器IP:<端口>/<隐藏路径>/player
订阅：  http://服务器IP:<端口>/<隐藏路径>/4gtv.m3u
```

管理密钥在安装目录下的 `4gtv_admin_key.txt`（首次启动自动生成）。**请妥善保管，不要泄露。**

面板可配：播放模式、代理、登录凭证、EPG、频道更新、缓存清理等。

> 默认监听 `0.0.0.0`。**记得在防火墙 / 云安全组放行对应 TCP 端口。**

## 🧰 常用命令

| 命令 | 作用 |
| --- | --- |
| `bash 4gtv.sh` | 打开管理菜单 |
| `bash 4gtv.sh install` | 安装 / 更新 |
| `bash 4gtv.sh url` | 打印访问地址 |
| `bash 4gtv.sh port <N>` | 改监听端口 |
| `bash 4gtv.sh path </xxx>` | 改隐藏路径（`off` = 关闭） |
| `systemctl restart 4gtv` | 重启服务 |
| `journalctl -u 4gtv -f` | 看运行日志 |
| `bash 4gtv.sh uninstall` | 卸载 |

也可直接用环境变量启动：

```bash
PORT=12345 BASE_PATH=/mysecret /opt/4gtv/4gtv
```

## 📂 文件位置

```
/opt/4gtv/
├── 4gtv                 二进制
├── env                  端口 / 隐藏路径
├── 4gtv_admin_key.txt   管理面板密钥
├── 4gtv_config.json     配置
└── （频道映射、缓存等运行时文件）
```

卸载时会问要不要一起删 `/opt/4gtv`，选 `N` 就只停服务、保留数据，重装即恢复。

## ✨ 功能概览

| 功能 | 说明 |
| --- | --- |
| 模式1 · 代理 TS | 服务端反代切片，兼容性最好 |
| 模式2 · 转发 M3U8 | 改写列表，切片直连 CDN |
| 模式3 · 302 重定向 | 几乎零流量（需客户端能直连 CDN） |
| 代理 | SOCKS5 / SOCKS5h / HTTP，可分别用于 API 与 M3U8 |
| 登录模式 | 面板一键登录，解锁更高清 |
| EPG | 可选开启，定时更新 |
| API 限流 | **内置**，限制并发取流并带排队超时，降低封 IP 风险 |


## ℹ️ 说明

- **请勿将服务裸奔公网**或提供给不信任的第三方；仅供个人学习研究。
- 请勿对大量频道短时间并发刷取流。
- 想换下载源：`FOURGTV_PUBLIC_URL=https://你的地址/4gtv-linux-{arch} bash <(curl -fsSL ...)`

## 免责声明

本项目仅供个人学习与研究。因滥用导致的 IP 封禁、账号风险与法律责任由使用者自行承担。
