# 📺 IPTV Proxy

**IPTV Proxy + Web Admin Panel · One-Click Deploy**

[简体中文](README.zh-CN.md) | **English**

Proxy / Redirect / Rewrite / DASH four forwarding modes | EPG guide · Logos · Timeshift · Scheduled recording | Token auth + IP blocking

![arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-blue)
![service](https://img.shields.io/badge/service-systemd%20%7C%20OpenRC-green)
![panel](https://img.shields.io/badge/panel-Web%20UI-orange)

---

## 🚀 Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YanG-1989/rust/main/IPTV%20Proxy/iptv-proxy.sh)
```

Open the management menu, choose `1` to install. It asks three questions, **all can be left as defaults**:

| Prompt | Default |
| --- | --- |
| Panel port | `19899` |
| Panel username | `admin` |
| Panel password | `admin` |

Auto-detects CPU arch (amd64 / arm64 / armv7), installs to `/opt/iptv-proxy`, runs as systemd service (OpenRC on Alpine) with autostart.

The binary never overwrites your existing `config.toml`, so **updating is just running it again and choosing `1`** — channels and settings are kept.

## 🎛️ Panel

URL `http://SERVER_IP:19899/panel`, login `admin` / `admin` (**change it ASAP**).

Channels, groups, EPG, cache, and security are all configured in the panel; subscription URLs are generated on the "Groups" page.

> The panel listens on `[::]` (dual-stack) by default. **Remember to open the TCP port in your firewall / cloud security group.**

## 🧰 Commands

> After install the script is symlinked into `PATH` as `iptv-proxy`.

| Command | What it does |
| --- | --- |
| `iptv-proxy` | Open management menu |
| `iptv-proxy update` | Update binary to latest (keeps config) |
| `iptv-proxy reinstall` | Reinstall from scratch (backs up config first) |
| `iptv-proxy port <N>` | Change panel port |
| `iptv-proxy pass <password> [user]` | Change panel password / username (works even if you forgot it) |
| `iptv-proxy restart` | Restart service |
| `iptv-proxy log` | View logs |
| `iptv-proxy url` | Print panel URL |
| `iptv-proxy uninstall` | Uninstall |

Port/password changes edit `config.toml` directly and restart the service; old login sessions are invalidated.

## 📂 File Layout

```
/opt/iptv-proxy/
├── iptv-proxy          binary
├── config.toml         config (everything changed in panel is stored here)
├── iptv-proxy.log      logs
└── cache/              segment cache, logos, EPG data
```

Uninstall asks whether to delete `/opt/iptv-proxy` too — answer `N` to keep data, reinstall restores everything.

## ℹ️ Notes

- **ffmpeg is optional**: only needed for MP4 → HLS transcoding in "Media assets". Proxying works fine without it.
- Panel password is stored as SHA-256, never in plaintext.
- Custom download source: `IPTV_URL=https://your-mirror/iptv-proxy-linux-{arch} bash <(curl -fsSL ...)`

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for recent updates.
