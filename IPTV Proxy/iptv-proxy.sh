#!/usr/bin/env bash
#
#  iptv-proxy · 一键安装 / 管理脚本
#  --------------------------------------------------------------------
#  · 自动识别 CPU 架构 (amd64 / arm64 / armv7)，从 GitHub 下载编译好的二进制
#  · 安装到 /opt/iptv-proxy，systemd / OpenRC 常驻 + 开机自启
#  · 内置：改面板端口 / 改面板账号密码 / 查看面板地址
#
#  iptv-proxy 本体不带命令行子命令（只接受一个配置文件路径），
#  所以端口和账号密码都由本脚本直接改 config.toml：
#      端口 → [server] bind
#      账号 → [panel] username
#      密码 → [panel] password_sha256   (SHA-256 十六进制)
#

set -uo pipefail

VERSION="1.0.0"

# ============================================================
#  ★ 下载地址 ★
# ============================================================
#   IPTV Proxy/iptv-proxy-linux-amd64
#   IPTV Proxy/iptv-proxy-linux-arm64
#   IPTV Proxy/iptv-proxy-linux-armv7
# 注意：目录名里有空格，raw 地址要写成 %20；raw 地址区分大小写
IPTV_URL="${IPTV_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/IPTV%20Proxy/iptv-proxy-linux-{arch}}"

# 脚本自身托管地址（远程一键自举用）
SELF_URL="${IPTV_SELF_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/IPTV%20Proxy/iptv-proxy.sh}"

# —— 备选：哪天改用 GitHub Release 发布，把上面 IPTV_URL 留空，再用下面这组 ——
IPTV_REPO="${IPTV_REPO:-YanG-1989/rust}"
IPTV_TAG="${IPTV_TAG:-latest}"
IPTV_ASSET="${IPTV_ASSET:-iptv-proxy-linux-{arch}}"
# ============================================================

# ---- 固定路径 ----
APP_DIR="/opt/iptv-proxy"
BIN="$APP_DIR/iptv-proxy"
CONFIG="$APP_DIR/config.toml"
APP_LOG="$APP_DIR/iptv-proxy.log"
SERVICE_NAME="iptv-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_FILE="/etc/init.d/${SERVICE_NAME}"
MARK="# managed-by: iptv-proxy.sh"
# 脚本副本 + 软链，装完可以直接敲 iptv-proxy 打开菜单
SELF_COPY="$APP_DIR/iptv-proxy.sh"
CLI_LINK="/usr/local/bin/iptv-proxy"

DEFAULT_PORT=19899
DEFAULT_USER="admin"
DEFAULT_PASS="admin"
# SHA-256("admin")
DEFAULT_HASH="8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; BLU='\033[0;36m'
DIM='\033[2m'; NC='\033[0m'
[ -t 1 ] || { RED=''; GRN=''; YEL=''; BLU=''; DIM=''; NC=''; }
info() { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YEL}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
step() { echo -e "${BLU}==>${NC} $*"; }

# ============================================================
#  远程执行自举
# ============================================================
self_path() {
    local s="${BASH_SOURCE[0]}" d
    while [ -L "$s" ]; do
        d="$(cd -P "$(dirname "$s")" && pwd)"; s="$(readlink "$s")"
        [[ "$s" != /* ]] && s="$d/$s"
    done
    echo "$(cd -P "$(dirname "$s")" && pwd)/$(basename "$s")"
}

bootstrap_if_remote() {
    local src="${BASH_SOURCE[0]}"
    case "$src" in
        /dev/fd/*|/proc/self/fd/*|-|"") ;;
        *) [ -f "$src" ] && return 0 ;;
    esac
    [ "${IP_BOOTSTRAPPED:-}" = "1" ] && return 0

    local tmp
    tmp="$(mktemp /tmp/iptv-proxy.XXXXXX)" || { err "无法创建临时文件"; exit 1; }
    step "远程模式：抓取脚本到 $tmp"
    if ! curl -fsSL "$SELF_URL" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        err "下载脚本失败: $SELF_URL"
        err "换地址：IPTV_SELF_URL=https://... bash <(curl -sL https://...)"
        exit 1
    fi
    head -1 "$tmp" | grep -q '^#!' || {
        rm -f "$tmp"; err "下载到的不是脚本（地址可能返回了错误页）"; exit 1
    }
    chmod +x "$tmp"
    export IP_BOOTSTRAPPED=1
    exec bash "$tmp" "$@"
}
bootstrap_if_remote "$@"

# curl | bash 场景：stdin 是管道，read 会立刻 EOF，抢回终端
if [ ! -t 0 ] && (exec < /dev/tty) 2>/dev/null; then
    exec < /dev/tty
fi

SELF="$(self_path)"

# ============================================================
#  通用工具
# ============================================================
has_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }
has_openrc()  { command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; }
is_installed() { [ -x "$BIN" ]; }

# ---- 服务抽象层：systemd 与 OpenRC(Alpine) 统一入口 ----
svc_managed() {
    { has_systemd && [ -f "$SERVICE_FILE" ]; } || { has_openrc && [ -f "$OPENRC_FILE" ]; }
}
svc_write_and_enable() {
    if has_systemd; then
        write_service
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    elif has_openrc; then
        write_openrc
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
    fi
}
svc_do() { # action
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl "$1" "$SERVICE_NAME"
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" "$1"
    else
        return 2
    fi
}
svc_active() {
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl is-active --quiet "$SERVICE_NAME"
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    else
        return 1
    fi
}

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    command -v sudo >/dev/null 2>&1 || { err "请用 root 运行"; return 1; }
    warn "需要 root 权限，sudo 重新执行 ..."
    exec sudo -E bash "$SELF" "$@"
}

fetch() { # url outfile
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        err "系统里既没有 curl 也没有 wget"; return 1
    fi
}

# 识别架构 → amd64 / arm64 / armv7
detect_arch() {
    local m; m="$(uname -m)"
    case "$m" in
        x86_64|amd64)              echo "amd64" ;;
        aarch64|arm64)             echo "arm64" ;;
        armv7l|armv7|armv8l|armhf) echo "armv7" ;;
        armv6l|armv6)
            err "armv6 太老（无硬浮点 NEON），本项目不提供该架构二进制"; return 1 ;;
        *) err "不支持的架构: $m（只支持 amd64 / arm64 / armv7）"; return 1 ;;
    esac
}

download_url() {
    local arch="$1" url
    if [ -n "$IPTV_URL" ]; then
        url="$IPTV_URL"
    else
        local asset="${IPTV_ASSET//\{arch\}/$arch}"
        if [ "$IPTV_TAG" = "latest" ]; then
            url="https://github.com/${IPTV_REPO}/releases/latest/download/${asset}"
        else
            url="https://github.com/${IPTV_REPO}/releases/download/${IPTV_TAG}/${asset}"
        fi
    fi
    echo "${url//\{arch\}/$arch}"
}

# 下回来的得是个 ELF 可执行文件，不是 404 的 HTML 页
looks_like_elf() {
    local magic; magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
    [ "$magic" = "7f454c46" ]
}

# SHA-256 十六进制（面板密码就存这个）
sha256hex() { # plaintext
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        printf '%s' "$1" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
    else
        err "系统里没有 sha256sum / shasum / openssl，无法计算密码哈希"; return 1
    fi
}

public_ip() {
    local ip src
    for src in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ip.sb"; do
        ip="$(curl -fsL --max-time 5 "$src" 2>/dev/null | tr -d ' \r\n')"
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return 0; }
    done
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)"
    [ -n "$ip" ] && { echo "$ip"; return 0; }
    echo "服务器IP"
}

# ============================================================
#  config.toml 读写（section 感知，避免改到同名字段）
# ============================================================
cfg_get() { # section key
    [ -f "$CONFIG" ] || return 1
    awk -v s="[$1]" -v k="$2" '
        {
            t = $0
            sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t)
            if (t ~ /^\[/) { inx = (t == s); next }
            if (!inx) next
            if (t ~ "^"k"[ \t]*=") {
                sub(/^[^=]*=[ \t]*/, "", t)
                sub(/[ \t]*#.*$/, "", t)
                sub(/[ \t]+$/, "", t)
                gsub(/^"|"$/, "", t)
                print t; exit
            }
        }' "$CONFIG"
}

cfg_set() { # section key value(已按 TOML 语法写好，字符串要自带引号)
    [ -f "$CONFIG" ] || { err "配置文件不存在: $CONFIG"; return 1; }
    local tmp; tmp="$(mktemp "${CONFIG}.XXXXXX")" || return 1
    awk -v s="[$1]" -v k="$2" -v v="$3" '
        # 空行先攒着：新增 key 要插在段落末尾的空行之前，不然会掉到下一段里
        function flush(  i) { for (i = 1; i <= nb; i++) print buf[i]; nb = 0 }
        BEGIN { inx = 0; done = 0; found = 0; nb = 0 }
        {
            t = $0
            sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t)
            if (t == "") { buf[++nb] = $0; next }
            if (t ~ /^\[/) {
                if (inx && !done) { print k" = "v; done = 1 }
                flush()
                inx = (t == s)
                if (inx) found = 1
                print; next
            }
            flush()
            if (inx && !done && t ~ "^"k"[ \t]*=") { print k" = "v; done = 1; next }
            print
        }
        END {
            if (inx && !done) { print k" = "v; done = 1 }
            flush()
            if (!found) { print ""; print s; print k" = "v }
        }' "$CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp"
    mv -f "$tmp" "$CONFIG"
}

# 从 [server] bind 里取端口
get_port() {
    local b; b="$(cfg_get server bind)"
    [ -z "$b" ] && { echo "$DEFAULT_PORT"; return; }
    echo "${b##*:}"
}
# 换端口但保留原来的监听地址前缀（[::] / 0.0.0.0 …）
set_port() { # port
    local b host; b="$(cfg_get server bind)"
    host="[::]"
    [ -n "$b" ] && host="${b%:*}"
    [ -z "$host" ] && host="[::]"
    cfg_set server bind "\"${host}:$1\""
}

# 生成一份最小可用配置：其余项进面板改，保存后后端会自动补全整个文件
write_default_config() { # port user hash
    step "生成配置 $CONFIG"
    cat > "$CONFIG" <<EOF
# iptv-proxy 配置文件（由 iptv-proxy.sh 生成）
# 这里只写最小必要项，其余全部走内置默认值。
# 进面板改任何设置并保存后，后端会把完整配置回写到本文件。

[server]
# 监听地址：[::]:PORT 同时监听 IPv4 + IPv6；只要 IPv4 就写 0.0.0.0:PORT
bind = "[::]:$1"
# 时区偏移（小时），影响回看 / EPG 时间，中国大陆填 8
timezone_offset_hours = 8
# 日志级别：trace / debug / info / warn / error
log_level = "info"

[panel]
enabled         = true
username        = "$2"
password_sha256 = "$3"
session_ttl     = 86400

[cache]
backend             = "disk"
disk_path           = "./cache"
m3u8_max_entries    = 500
segment_max_entries = 2000
disk_max_mb         = 0

[auth]
token_enabled = false
EOF
    chmod 600 "$CONFIG"
}

# ============================================================
#  服务单元
# ============================================================
write_service() {
    step "写入 $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
${MARK}
Description=iptv-proxy · IPTV 代理 + Web 管理面板
# network-online 而不是 network：后者只保证网络栈起来了，不保证拿到地址，
# 监听具体 IP 的服务会 bind 失败
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=root
# 必须指到 APP_DIR：缓存目录 cache/ 和日志 iptv-proxy.log 都是相对路径
WorkingDirectory=${APP_DIR}
ExecStart=${BIN} ${CONFIG}
Restart=always
RestartSec=3
# 文件句柄上限：多人同时看的时候 accept 会撞默认值报 EMFILE
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$SERVICE_FILE"
    has_systemd && systemctl daemon-reload
}

write_openrc() {
    step "写入 $OPENRC_FILE"
    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run
${MARK}
description="iptv-proxy · IPTV 代理 + Web 管理面板"
supervisor="supervise-daemon"
command="${BIN}"
command_args="${CONFIG}"
directory="${APP_DIR}"
pidfile="/run/${SERVICE_NAME}.pid"
respawn_delay=3
rc_ulimit="-n 1048576"
output_log="/var/log/${SERVICE_NAME}.log"
error_log="/var/log/${SERVICE_NAME}.log"

depend() {
    need net
    after firewall
}
EOF
    chmod 755 "$OPENRC_FILE"
}

# ============================================================
#  安装 / 更新
# ============================================================
download_binary() {
    local arch url tmp
    arch="$(detect_arch)" || return 1
    url="$(download_url "$arch")"
    step "架构 $arch，下载：$url"
    mkdir -p "$APP_DIR"
    tmp="$(mktemp "$APP_DIR/.iptv-proxy.dl.XXXXXX")" || { err "无法在 $APP_DIR 建临时文件"; return 1; }
    if ! fetch "$url" "$tmp"; then
        rm -f "$tmp"; err "下载失败。检查地址，或用 IPTV_URL 指定完整下载地址"
        return 1
    fi
    if ! looks_like_elf "$tmp"; then
        rm -f "$tmp"
        err "下载到的不是 ELF 二进制（多半是 404 页面）。请确认仓库里有：$(basename "${url//%20/ }")"
        return 1
    fi
    chmod +x "$tmp"
    mv -f "$tmp" "$BIN"
    info "二进制就位：$BIN"
}

install_cli() {
    mkdir -p "$APP_DIR"
    if [ "$SELF" != "$SELF_COPY" ]; then
        cp -f "$SELF" "$SELF_COPY" 2>/dev/null && chmod +x "$SELF_COPY"
    fi
    [ -f "$SELF_COPY" ] && ln -sf "$SELF_COPY" "$CLI_LINK" 2>/dev/null \
        && info "已软链到 $CLI_LINK（以后直接敲 iptv-proxy 打开菜单）"
}

# 起来之后探一下 /health，确认真的在监听
health_check() { # port
    local i code
    for i in 1 2 3 4 5 6 7 8; do
        code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 3 \
                "http://127.0.0.1:$1/health" 2>/dev/null)"
        [ "$code" = "200" ] && return 0
        sleep 1
    done
    return 1
}

cmd_install() {
    need_root "$@"
    local fresh=0
    is_installed || fresh=1

    download_binary || return 1
    install_cli

    # 首次安装：问端口 / 账号 / 密码，然后落配置
    if [ ! -f "$CONFIG" ]; then
        local port="$DEFAULT_PORT" user="$DEFAULT_USER" pass="$DEFAULT_PASS"
        if [ "${IP_AUTO:-}" != 1 ]; then
            echo
            step "初始设置（直接回车用默认值）"
            read -r -p "面板端口 [回车=${DEFAULT_PORT}]: " port; port="${port:-$DEFAULT_PORT}"
            [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] \
                || { warn "端口无效，用 ${DEFAULT_PORT}"; port="$DEFAULT_PORT"; }

            read -r -p "面板账号 [回车=${DEFAULT_USER}]: " user; user="${user:-$DEFAULT_USER}"

            local p1 p2
            read -r -s -p "面板密码 [回车=${DEFAULT_PASS}]: " p1; echo
            if [ -n "$p1" ]; then
                read -r -s -p "再输一次: " p2; echo
                if [ "$p1" != "$p2" ]; then
                    warn "两次不一致，先用默认密码 ${DEFAULT_PASS}，装完请到菜单 8 改"
                else
                    pass="$p1"
                fi
            fi
        fi
        local hash; hash="$(sha256hex "$pass")" || return 1
        write_default_config "$port" "$user" "$hash"
    else
        info "已有配置，保留不动：$CONFIG"
    fi

    if has_systemd || has_openrc; then
        svc_write_and_enable
        svc_do restart >/dev/null 2>&1
        sleep 1
    else
        warn "系统既无 systemd 也无 OpenRC，跳过服务安装。前台运行：cd $APP_DIR && ./iptv-proxy config.toml"
    fi

    command -v ffmpeg >/dev/null 2>&1 || \
        warn "未装 ffmpeg（只影响面板「视频素材」的转码功能，不装也能正常代理）"

    [ "${IP_AUTO:-}" = 1 ] && return 0

    echo
    local port; port="$(get_port)"
    if svc_managed; then
        if health_check "$port"; then
            info "安装完成，服务已在监听 $port"
        else
            warn "服务已启动但 /health 没通，可能还在初始化或端口被占。菜单 7 看日志"
        fi
    else
        info "安装完成"
    fi
    show_panel_url
    [ "$(cfg_get panel password_sha256)" = "$DEFAULT_HASH" ] && \
        warn "面板密码仍是默认 ${DEFAULT_PASS}，强烈建议进菜单 8 改掉"
    firewall_hint "$port"
}

# ============================================================
#  面板设置
# ============================================================
firewall_hint() { # port
    echo -e "  ${DIM}注意：若开了防火墙 / 云安全组，记得放行 TCP $1${NC}"
}

show_panel_url() {
    is_installed || { err "还没安装"; return 1; }
    local ip port user
    ip="$(public_ip)"; port="$(get_port)"; user="$(cfg_get panel username)"
    echo -e "${BLU}面板地址：${NC}"
    echo -e "   ${GRN}http://${ip}:${port}/panel${NC}"
    echo -e "   账号：${user:-$DEFAULT_USER}"
    echo -e "   ${DIM}订阅 / 播放地址在面板「分组管理」里生成${NC}"
}

# 改配置前先停服务，改完再起 —— 避免和后端自身的热重载 / 回写打架
apply_config_change() { # 描述
    if svc_managed; then
        svc_do restart >/dev/null 2>&1 && info "已重启生效"
    else
        warn "改动已写入配置，请手动重启进程生效"
    fi
}

cmd_set_port() {
    need_root "$@"
    is_installed || { err "还没安装"; return 1; }
    local cur; cur="$(get_port)"
    echo -e "当前端口：${YEL}${cur}${NC}"
    local p; read -r -p "新端口: " p
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ] || { err "端口无效"; return 1; }
    svc_managed && svc_do stop >/dev/null 2>&1
    set_port "$p" || { err "写入失败"; return 1; }
    info "端口已改为 $p"
    apply_config_change
    firewall_hint "$p"
    show_panel_url
}

cmd_set_pass() {
    need_root "$@"
    is_installed || { err "还没安装"; return 1; }
    local user; user="$(cfg_get panel username)"
    echo -e "当前账号：${YEL}${user:-$DEFAULT_USER}${NC}"
    local nu; read -r -p "新账号 [回车=不改]: " nu
    local p1 p2
    read -r -s -p "新密码（至少 4 位，回车=不改）: " p1; echo

    if [ -z "$nu" ] && [ -z "$p1" ]; then warn "什么都没改"; return 0; fi

    svc_managed && svc_do stop >/dev/null 2>&1
    if [ -n "$p1" ]; then
        read -r -s -p "再输一次: " p2; echo
        [ "$p1" != "$p2" ] && { err "两次不一致"; svc_managed && svc_do start >/dev/null 2>&1; return 1; }
        [ "${#p1}" -lt 4 ] && { err "密码太短"; svc_managed && svc_do start >/dev/null 2>&1; return 1; }
        local hash; hash="$(sha256hex "$p1")" || return 1
        cfg_set panel password_sha256 "\"$hash\"" || { err "写入失败"; return 1; }
        info "密码已更新"
    fi
    if [ -n "$nu" ]; then
        cfg_set panel username "\"$nu\"" || { err "写入失败"; return 1; }
        info "账号已改为 $nu"
    fi
    apply_config_change
    warn "改完后旧的登录会话会失效，需要重新登录"
}

# ============================================================
#  服务操作
# ============================================================
svc() { # action
    if svc_managed; then
        need_root; svc_do "$1"
    else
        err "未托管为系统服务（systemd/OpenRC）"; return 1
    fi
}
cmd_start()   { svc start   && info "已启动"; }
cmd_stop()    { svc stop    && info "已停止"; }
cmd_restart() { svc restart && info "已重启"; }
cmd_status()  {
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null || true
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" status 2>/dev/null || true
    else
        warn "未托管为系统服务（systemd/OpenRC）"
    fi
}
cmd_log() {
    echo "(Ctrl+C 停止查看)"; sleep 1
    # 优先看程序自己写的日志，内容比 journal 详细（面板日志页读的也是这个文件）
    if [ -f "$APP_LOG" ]; then
        tail -n 100 -f "$APP_LOG" 2>/dev/null || true
    elif has_systemd && [ -f "$SERVICE_FILE" ]; then
        journalctl -u "$SERVICE_NAME" -n 100 -f --no-pager 2>/dev/null || true
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        tail -n 100 -f "/var/log/${SERVICE_NAME}.log" 2>/dev/null || true
    else
        warn "找不到日志"
    fi
}

cmd_uninstall() {
    need_root "$@"
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$SERVICE_FILE"; systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        info "服务已移除"
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" stop 2>/dev/null || true
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
        rm -f "$OPENRC_FILE"
        info "服务已移除"
    fi
    [ -L "$CLI_LINK" ] && rm -f "$CLI_LINK"
    echo
    read -r -p "连同 $APP_DIR (含配置、缓存、台标、EPG) 一起删掉? [y/N] " c
    if [[ "${c:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"; info "已删除 $APP_DIR"
    else
        warn "已保留 $APP_DIR（频道和配置都还在，重装即恢复）"
    fi
}

# ============================================================
#  菜单
# ============================================================
state_line() {
    if svc_managed; then
        if svc_active; then echo -e "${GRN}● 运行中${NC}"
        else echo -e "${RED}○ 已停止${NC}"; fi
    elif is_installed; then echo -e "${YEL}○ 已安装未托管${NC}"
    else echo -e "${DIM}未安装${NC}"; fi
}

pause() { echo; read -r -p "按回车返回 ..." _; }

main_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BLU}=============================================${NC}"
        echo -e "       iptv-proxy 安装 · 管理   ${DIM}v${VERSION}${NC}"
        echo -e "${BLU}=============================================${NC}"
        echo -e "  状态: $(state_line)"
        if is_installed; then
            echo -e "  目录: ${DIM}${APP_DIR}${NC}"
            echo -e "  端口: $(get_port)    账号: $(cfg_get panel username)"
        fi
        echo -e "${BLU}---------------------------------------------${NC}"
        if is_installed; then
            echo "   1) 更新 / 重装二进制      2) 查看面板地址"
            echo "   3) 启动   4) 停止   5) 重启   6) 状态   7) 日志"
            echo -e "${BLU}--- 面板设置 --------------------------------${NC}"
            echo "   8) 改端口        9) 改账号密码"
            echo -e "${BLU}---------------------------------------------${NC}"
            echo -e "   u) ${RED}卸载${NC}"
        else
            echo "   1) 安装 iptv-proxy"
        fi
        echo "   0) 退出"
        echo -e "${BLU}---------------------------------------------${NC}"
        local opt; read -r -p "请输入: " opt; echo
        if ! is_installed; then
            case "$opt" in
                1) cmd_install; pause ;;
                0|q|Q) exit 0 ;;
                *) err "无效输入"; sleep 1 ;;
            esac
            continue
        fi
        case "$opt" in
            1) cmd_install;  pause ;;
            2) show_panel_url; pause ;;
            3) cmd_start;    pause ;;
            4) cmd_stop;     pause ;;
            5) cmd_restart;  pause ;;
            6) cmd_status;   pause ;;
            7) cmd_log ;;
            8) cmd_set_port; pause ;;
            9) cmd_set_pass; pause ;;
            u|U) read -r -p "确认卸载? [y/N] " c
                 [[ "${c:-N}" =~ ^[Yy]$ ]] && { cmd_uninstall; pause; } || warn "已取消" ;;
            0|q|Q) exit 0 ;;
            *) err "无效输入"; sleep 1 ;;
        esac
    done
}

# ============================================================
#  命令行入口（不带参数 = 菜单）
# ============================================================
usage() {
cat <<EOF
iptv-proxy 安装 · 管理脚本 v${VERSION}

远程一键：
  bash <(curl -fsSL ${SELF_URL})

子命令：
  install / update     安装或更新（下载二进制 + 起服务）
  start|stop|restart|status|log
  url                  打印面板访问地址
  port <N>             改面板端口
  pass <密码> [账号]   改面板密码 / 账号
  uninstall            卸载

安装位置：${APP_DIR}
配置文件：${CONFIG}
面板地址：http://<IP>:$( [ -f "$CONFIG" ] && get_port || echo "$DEFAULT_PORT" )/panel

可覆盖的环境变量：
  IPTV_URL      直接给完整下载地址（可含 {arch} 占位符）
  IPTV_REPO     GitHub 仓库（默认 ${IPTV_REPO}，仅在 IPTV_URL 留空时用）
  IPTV_TAG      Release tag（默认 latest）
  IPTV_ASSET    资产命名（默认 iptv-proxy-linux-{arch}）
EOF
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
    ""|menu)          main_menu ;;
    install|update)   cmd_install "$@" ;;
    start)            cmd_start ;;
    stop)             cmd_stop ;;
    restart|reload)   cmd_restart ;;
    status|st)        cmd_status ;;
    log|logs)         cmd_log ;;
    url)              show_panel_url ;;
    port)             if [ -n "${1:-}" ]; then
                          need_root
                          [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ] \
                              || { err "端口无效"; exit 1; }
                          svc_managed && svc_do stop >/dev/null 2>&1
                          set_port "$1" && apply_config_change && show_panel_url
                      else cmd_set_port; fi ;;
    pass)             if [ -n "${1:-}" ]; then
                          need_root
                          [ "${#1}" -lt 4 ] && { err "密码太短"; exit 1; }
                          h="$(sha256hex "$1")" || exit 1
                          svc_managed && svc_do stop >/dev/null 2>&1
                          cfg_set panel password_sha256 "\"$h\"" || exit 1
                          [ -n "${2:-}" ] && cfg_set panel username "\"$2\""
                          apply_config_change
                      else cmd_set_pass; fi ;;
    uninstall|remove) cmd_uninstall "$@" ;;
    -h|--help|help)   usage ;;
    -v|--version)     echo "v${VERSION}" ;;
    *) err "未知命令: $cmd"; echo; usage; exit 1 ;;
esac
