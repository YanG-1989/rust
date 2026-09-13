#!/usr/bin/env bash
#
#  4GTV 公开版 · 一键安装 / 管理脚本 (含 Alpine OpenRC 支持)
#  --------------------------------------------------------------------
#  · 自动识别 CPU 架构 (amd64 / arm64 / armv7)，下载预编译二进制
#  · 支持 systemd (Ubuntu/Debian/CentOS) 与 OpenRC (Alpine) 开机自启
#  · 支持自定义端口（PORT）与隐藏路径前缀（BASE_PATH）
#

set -uo pipefail

VERSION="1.1.1"
APP_NAME="4gtv"
APP_DIR="/opt/4gtv"
BIN="$APP_DIR/4gtv"
SERVICE_NAME="4gtv"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_FILE="/etc/init.d/${SERVICE_NAME}"
ENV_FILE="$APP_DIR/env"
MARK="# managed-by: 4gtv.sh"

DOWNLOAD_URL="${FOURGTV_PUBLIC_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/4gTV/4gtv-linux-{arch}}"
SELF_URL="${FOURGTV_PUBLIC_SELF_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/4gTV/4gtv.sh}"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; BLU='\033[0;36m'
DIM='\033[2m'; NC='\033[0m'
[ -t 1 ] || { RED=''; GRN=''; YEL=''; BLU=''; DIM=''; NC=''; }
info() { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YEL}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
step() { echo -e "${BLU}==>${NC} $*"; }

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    command -v sudo >/dev/null 2>&1 || { err "请用 root 运行"; return 1; }
    warn "需要 root 权限，sudo 重新执行 ..."
    exec sudo -E bash "$0" "$@"
}

detect_arch() {
    local m; m="$(uname -m)"
    case "$m" in
        x86_64|amd64)          echo "amd64" ;;
        aarch64|arm64)         echo "arm64" ;;
        armv7l|armv7|armhf)    echo "armv7" ;;
        *) err "不支持的架构: $m（支持 amd64 / arm64 / armv7）"; return 1 ;;
    esac
}

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        err "系统里既没有 curl 也没有 wget"; return 1
    fi
}

looks_like_elf() {
    local magic; magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
    [ "$magic" = "7f454c46" ]
}

public_ip() {
    local ip src
    for src in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ip.sb"; do
        ip="$(curl -fsL --max-time 5 "$src" 2>/dev/null | tr -d ' \r\n')"
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return 0; }
    done
    echo "服务器IP"
}

rand_path() {
    echo "/$(od -An -tx1 -N5 /dev/urandom 2>/dev/null | tr -d ' \n')"
}

rand_port() {
    local n
    n="$(od -An -tu2 -N2 /dev/urandom 2>/dev/null | tr -d ' \n')"
    n=$(( (n % 50001) + 10000 ))
    echo "$n"
}

# ---- 服务抽象层：支持 systemd 与 OpenRC ----
has_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }
has_openrc()  { command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; }

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

load_env() {
    PORT=""
    BASE_PATH=""
    [ -f "$ENV_FILE" ] && . "$ENV_FILE" || true
    PORT="${PORT:-}"
    BASE_PATH="${BASE_PATH:-}"
}

write_env() {
    cat > "$ENV_FILE" <<EOF
# 由 4gtv.sh 管理
PORT=${PORT}
BASE_PATH=${BASE_PATH}
EOF
    chmod 600 "$ENV_FILE"
}

write_service() {
    step "写入 $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
${MARK}
Description=4GTV public stream proxy (Rust)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=-${ENV_FILE}
ExecStart=${BIN}
Restart=always
RestartSec=3
LimitNOFILE=1048576
StandardOutput=null
StandardError=null
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$SERVICE_FILE"
    systemctl daemon-reload
}

write_openrc() {
    step "写入 $OPENRC_FILE"
    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run
${MARK}
description="4GTV public stream proxy"
supervisor="supervise-daemon"
command="${BIN}"
directory="${APP_DIR}"
pidfile="/run/${SERVICE_NAME}.pid"
respawn_delay=3
rc_ulimit="-n 1048576"
output_log="/dev/null"
error_log="/dev/null"

depend() {
    need net
    after firewall
}

start_pre() {
    if [ -f "${ENV_FILE}" ]; then
        set -o allexport
        . "${ENV_FILE}"
        set +o allexport
    fi
}
EOF
    chmod 755 "$OPENRC_FILE"
}

download_binary() {
    local arch url tmp
    arch="$(detect_arch)" || return 1
    url="${DOWNLOAD_URL//\{arch\}/$arch}"
    step "架构 $arch，下载：$url"
    mkdir -p "$APP_DIR"
    tmp="$(mktemp "$APP_DIR/.4gtv.dl.XXXXXX")" || return 1
    if ! fetch "$url" "$tmp"; then
        rm -f "$tmp"; err "下载失败。请设置 FOURGTV_PUBLIC_URL 或检查 Release 资产名"; return 1
    fi
    if ! looks_like_elf "$tmp"; then
        rm -f "$tmp"; err "下载到的不是 ELF 二进制（多半是 404 页面）"; return 1
    fi
    chmod +x "$tmp"
    mv -f "$tmp" "$BIN"
    info "二进制就位：$BIN"
}

show_url() {
    load_env
    local ip path port
    ip="$(public_ip)"
    port="${PORT:-?}"
    path="${BASE_PATH}"
    path="${path%/}"
    echo -e "${BLU}访问地址：${NC}"
    if [ -n "$path" ]; then
        # 首页去掉了末尾多余的 /
        echo -e "  首页      ${GRN}http://${ip}:${port}${path}${NC}"
        echo -e "  播放器    ${GRN}http://${ip}:${port}${path}/player${NC}"
        if [ -f "$APP_DIR/4gtv_admin_key.txt" ]; then
            local admin_key; admin_key="$(cat "$APP_DIR/4gtv_admin_key.txt")"
            echo -e "  管理面板  ${GRN}http://${ip}:${port}${path}/admin?key=${admin_key}${NC}"
        else
            echo -e "  管理面板  ${GRN}http://${ip}:${port}${path}/admin${NC}"
        fi
        echo -e "  ${DIM}（隐藏路径：不带 ${path} 前缀访问会 404）${NC}"
    else
        echo -e "  首页      ${GRN}http://${ip}:${port}/${NC}"
        echo -e "  播放器    ${GRN}http://${ip}:${port}/player${NC}"
        if [ -f "$APP_DIR/4gtv_admin_key.txt" ]; then
            local admin_key; admin_key="$(cat "$APP_DIR/4gtv_admin_key.txt")"
            echo -e "  管理面板  ${GRN}http://${ip}:${port}/admin?key=${admin_key}${NC}"
        else
            echo -e "  管理面板  ${GRN}http://${ip}:${port}/admin${NC}"
        fi
        warn "未设置 BASE_PATH，面板在根路径可被扫到，建议设置隐藏路径"
    fi
    if [ -f "$APP_DIR/4gtv_admin_key.txt" ]; then
        echo -e "  管理密钥  ${YEL}$(cat "$APP_DIR/4gtv_admin_key.txt")${NC}"
    fi
}

cmd_install() {
    need_root "$@"
    download_binary || return 1
    load_env

    echo
    step "初始设置（直接回车用默认值）"
    local port path
    local defport; defport="$(rand_port)"
    [ -f "$ENV_FILE" ] && [ -n "${PORT:-}" ] && defport="$PORT"
    read -r -p "监听端口 [回车=${defport}]: " port
    port="${port:-$defport}"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { warn "端口无效，改用随机端口"; port="$(rand_port)"; }

    local defpath; defpath="$(rand_path)"
    echo -e "  ${DIM}隐藏路径 = 所有路由挂在此前缀下，别人扫端口看不到服务${NC}"
    read -r -p "隐藏路径 [回车=随机 ${defpath}，输 off 关闭]: " path
    path="${path:-$defpath}"
    [ "$path" = "off" ] && path=""
    if [ -n "$path" ] && [[ "$path" != /* ]]; then path="/$path"; fi

    PORT="$port"
    BASE_PATH="$path"
    write_env

    if has_systemd || has_openrc; then
        svc_write_and_enable
        svc_do restart >/dev/null 2>&1
        sleep 1
        if svc_active; then
            info "服务已启动"
        else
            warn "服务未起来，请检查输出"
        fi
    else
        warn "系统既无 systemd 也无 OpenRC，请手动前台运行：PORT=$PORT BASE_PATH=$BASE_PATH $BIN"
    fi

    echo
    info "安装完成"
    show_url
    echo -e "  ${DIM}防火墙请放行 TCP ${PORT}${NC}"
}

cmd_set_port() {
    need_root
    load_env
    echo -e "当前端口：${YEL}${PORT}${NC}"
    local p; read -r -p "新端口: " p
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ] || { err "端口无效"; return 1; }
    PORT="$p"; write_env
    svc_managed && svc_do restart
    info "已更新"; show_url
}

cmd_set_path() {
    need_root
    load_env
    echo -e "当前隐藏路径：${YEL}${BASE_PATH:-<未设置>}${NC}"
    echo "  1) 随机生成  2) 手动输入  3) 关闭"
    local c; read -r -p "选择: " c
    local path
    case "$c" in
        1) path="$(rand_path)" ;;
        2) read -r -p "输入路径（以 / 开头）: " path; [ -z "$path" ] && return 1
           [[ "$path" != /* ]] && path="/$path" ;;
        3) path="" ;;
        *) return 1 ;;
    esac
    BASE_PATH="$path"; write_env
    svc_managed && svc_do restart
    info "已更新"; show_url
}

cmd_uninstall() {
    need_root
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
        rm -f "$SERVICE_FILE"; systemctl daemon-reload
        info "服务已移除"
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" stop 2>/dev/null || true
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
        rm -f "$OPENRC_FILE"
        info "服务已移除"
    fi
    read -r -p "连同 $APP_DIR 一起删掉? [y/N] " c
    if [[ "${c:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"; info "已删除 $APP_DIR"
    else
        warn "已保留 $APP_DIR"
    fi
}

cmd_log() {
    warn "系统层控制台日志已关，请直接查阅 Rust 程序自带生成的日志文件"
}

main_menu() {
    while true; do
        clear 2>/dev/null || true
        load_env
        echo -e "${BLU}=============================================${NC}"
        echo -e "        4GTV 安装 · 管理   ${DIM}v${VERSION}${NC}"
        echo -e "${BLU}=============================================${NC}"
        if [ -x "$BIN" ]; then
            if svc_managed && svc_active; then
                echo -e "  状态: ${GRN}● 运行中${NC}"
            else
                echo -e "  状态: ${YEL}○ 已安装${NC}"
            fi
            echo -e "  端口: ${PORT}    路径: ${BASE_PATH:-/}"
        else
            echo -e "  状态: ${DIM}未安装${NC}"
        fi
        echo -e "${BLU}---------------------------------------------${NC}"
        if [ -x "$BIN" ]; then
            echo "  1) 更新二进制   2) 查看地址"
            echo "  3) 启动  4) 停止  5) 重启  6) 日志说明"
            echo "  7) 改端口  8) 改隐藏路径"
            echo -e "  u) ${RED}卸载${NC}"
        else
            echo "  1) 安装 4GTV"
        fi
        echo "  0) 退出"
        echo -e "${BLU}---------------------------------------------${NC}"
        local opt; read -r -p "请输入: " opt; echo
        case "$opt" in
            1) cmd_install; read -r -p "回车继续..." _ ;;
            2) show_url; read -r -p "回车继续..." _ ;;
            3) need_root; svc_do start; info "已启动" ;;
            4) need_root; svc_do stop; info "已停止" ;;
            5) need_root; svc_do restart; info "已重启" ;;
            6) cmd_log; read -r -p "回车继续..." _ ;;
            7) cmd_set_port; read -r -p "回车继续..." _ ;;
            8) cmd_set_path; read -r -p "回车继续..." _ ;;
            u|U) cmd_uninstall; read -r -p "回车继续..." _ ;;
            0|q|Q) exit 0 ;;
            *) err "无效输入" ;;
        esac
    done
}

case "${1:-}" in
    ""|menu) main_menu ;;
    install) shift; cmd_install "$@" ;;
    url) show_url ;;
    port) shift; [ -n "${1:-}" ] && { need_root; load_env; PORT="$1"; write_env; svc_managed && svc_do restart; show_url; } || cmd_set_port ;;
    path) shift; [ -n "${1:-}" ] && { need_root; load_env; BASE_PATH="$1"; [ "$BASE_PATH" = "off" ] && BASE_PATH=""; write_env; svc_managed && svc_do restart; show_url; } || cmd_set_path ;;
    uninstall) cmd_uninstall ;;
    -h|--help) echo "用法: $0 [install|url|port|path|uninstall]"; exit 0 ;;
    *) err "未知命令: $1"; exit 1 ;;
esac
