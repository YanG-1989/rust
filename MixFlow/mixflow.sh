#!/usr/bin/env bash
#
#  mixflow · 一键安装 / 管理脚本
#  --------------------------------------------------------------------
#  · 自动识别 CPU 架构 (amd64 / arm64)，从 GitHub 下载编译好的二进制
#  · 安装到 /opt/mixflow（不塞进 /root），systemd 常驻 + 开机自启
#  · 内置：改面板端口 / 改隐藏入口路径 / 改面板密码 / 查看面板地址
#

set -uo pipefail

VERSION="1.0.0"

# ============================================================
#  ★ 你的下载地址（已按你的实际布局填好）★
# ============================================================

#   MixFlow/mixflow-linux-amd64
#   MixFlow/mixflow-linux-arm64
# 注意大小写：raw 地址区分大小写
MIXFLOW_URL="${MIXFLOW_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow-linux-{arch}}"

# 脚本自身托管地址（远程一键自举用）。
SELF_URL="${MIXFLOW_SELF_URL:-https://raw.githubusercontent.com/YanG-1989/rust/main/MixFlow/mixflow.sh}"

# —— 备选：如果哪天改用 GitHub Release 发布，把上面 MIXFLOW_URL 留空，再用下面这组 ——
# 留空 MIXFLOW_URL 时才会用到 REPO/TAG/ASSET 去 Release 里找。
MIXFLOW_REPO="${MIXFLOW_REPO:-YanG-1989/rust}"
MIXFLOW_TAG="${MIXFLOW_TAG:-latest}"
MIXFLOW_ASSET="${MIXFLOW_ASSET:-mixflow-linux-{arch}}"
# ============================================================

# ---- 固定路径 ----
APP_DIR="/opt/mixflow"
BIN="$APP_DIR/mixflow"
CONFIG="$APP_DIR/config.toml"
SERVICE_NAME="mixflow"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
OPENRC_FILE="/etc/init.d/${SERVICE_NAME}"
MARK="# managed-by: mixflow.sh"
# 可选：把二进制软链到 PATH，这样能全局 `mixflow panel --port ...`
CLI_LINK="/usr/local/bin/mixflow"

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
    [ "${MF_BOOTSTRAPPED:-}" = "1" ] && return 0

    local tmp
    tmp="$(mktemp /tmp/mixflow.XXXXXX)" || { err "无法创建临时文件"; exit 1; }
    step "远程模式：抓取脚本到 $tmp"
    if ! curl -fsSL "$SELF_URL" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        err "下载脚本失败: $SELF_URL"
        err "换地址：MIXFLOW_SELF_URL=https://... bash <(curl -sL https://...)"
        exit 1
    fi
    head -1 "$tmp" | grep -q '^#!' || {
        rm -f "$tmp"; err "下载到的不是脚本（地址可能返回了错误页）"; exit 1
    }
    chmod +x "$tmp"
    export MF_BOOTSTRAPPED=1
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
# 是否已被任一 init 系统托管
svc_managed() {
    { has_systemd && [ -f "$SERVICE_FILE" ]; } || { has_openrc && [ -f "$OPENRC_FILE" ]; }
}
# 写服务单元并设为开机自启
svc_write_and_enable() {
    if has_systemd; then
        write_service
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    elif has_openrc; then
        write_openrc
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
    fi
}
# start/stop/restart 统一动作
svc_do() { # action
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        systemctl "$1" "$SERVICE_NAME"
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" "$1"
    else
        return 2
    fi
}
# 是否运行中
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

# 下载器：优先 curl，退到 wget
fetch() { # url outfile
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        err "系统里既没有 curl 也没有 wget"; return 1
    fi
}

# 识别架构 → amd64 / arm64
detect_arch() {
    local m; m="$(uname -m)"
    case "$m" in
        x86_64|amd64)          echo "amd64" ;;
        aarch64|arm64)         echo "arm64" ;;
        *) err "不支持的架构: $m（本脚本只支持 amd64 / arm64）"; return 1 ;;
    esac
}

# 拼出最终下载地址
download_url() {
    local arch="$1" url
    if [ -n "$MIXFLOW_URL" ]; then
        url="$MIXFLOW_URL"
    else
        local asset="${MIXFLOW_ASSET//\{arch\}/$arch}"
        if [ "$MIXFLOW_TAG" = "latest" ]; then
            url="https://github.com/${MIXFLOW_REPO}/releases/latest/download/${asset}"
        else
            url="https://github.com/${MIXFLOW_REPO}/releases/download/${MIXFLOW_TAG}/${asset}"
        fi
    fi
    echo "${url//\{arch\}/$arch}"
}

# 下回来的得是个 ELF 可执行文件，不是 404 的 HTML 页
looks_like_elf() {
    local magic; magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
    [ "$magic" = "7f454c46" ]
}

# 随机暗门路径：/ + 10 位十六进制
rand_path() {
    echo "/$(od -An -tx1 -N5 /dev/urandom 2>/dev/null | tr -d ' \n')"
}

# 读 config.toml 里 [panel] 段的某个 key（避开 nodes 里的同名字段）
panel_get() { # key
    [ -f "$CONFIG" ] || return 1
    awk -v k="$1" '
        /^[[:space:]]*\[/ { inpanel = ($0 ~ /^[[:space:]]*\[panel\]/) }
        inpanel && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/^["\x27]|["\x27][[:space:]]*$/, "")
            sub(/[[:space:]]*$/, "")
            print; exit
        }' "$CONFIG"
}

# 取本机公网 IP（多个源兜底），失败退到内网 IP
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

# 探测本机所在地区的两位国家码（如 HK / JP / US），失败返回空
detect_region() {
    local r
    r="$(curl -fsL --max-time 6 https://ipinfo.io/country 2>/dev/null | tr -d ' \r\n')"
    [[ "$r" =~ ^[A-Za-z]{2}$ ]] && { echo "${r^^}"; return; }
    r="$(curl -fsL --max-time 6 'http://ip-api.com/line?fields=countryCode' 2>/dev/null | tr -d ' \r\n')"
    [[ "$r" =~ ^[A-Za-z]{2}$ ]] && { echo "${r^^}"; return; }
    echo ""
}

# ============================================================
#  一键生成节点 + 终极优化
# ============================================================
# 只干三件事：建 Mixed / Trojan / Hysteria2 三个节点（都随机端口）、套用终极代理优化。
cmd_oneclick() {
    need_root "$@"

    echo -e "${BLU}=============================================${NC}"
    echo -e "  ${GRN}全自动部署：装好 mixflow + 建节点 + 优化${NC}"
    echo -e "${BLU}=============================================${NC}"
    if is_installed; then
        echo -e "  ${DIM}检测到已安装，只做优化 + 建节点${NC}"
    else
        echo -e "  ${YEL}检测到未安装，将自动完成全部步骤：${NC}"
        echo -e "    ${GRN}0${NC} 下载二进制并装好面板（端口 12321 · 随机隐藏入口）"
    fi
    echo -e "    ${GRN}①${NC} 内核终极优化（BBR + 缓冲区自适应，持久化）"
    echo -e "    ${GRN}②${NC} 新建 ${GRN}Mixed${NC} 节点    （随机端口 · SOCKS5+HTTP · 自动生成账号密码）"
    echo -e "    ${GRN}③${NC} 新建 ${GRN}Trojan${NC} 节点   （随机端口 · 自签 TLS）"
    echo -e "    ${GRN}④${NC} 新建 ${GRN}Hysteria2${NC} 节点（随机端口）"
    echo -e "  节点名自动带本机地区后缀，例如 ${GRN}Trojan-HK${NC} / ${GRN}Hysteria2-HK${NC}"
    echo -e "${BLU}---------------------------------------------${NC}"
    local c; read -r -p "确认执行? [Y/n] " c
    [[ "${c:-Y}" =~ ^[Nn]$ ]] && { warn "已取消"; return 1; }

    # 0) 没装就先全自动装好（非交互）
    if ! is_installed; then
        printf "  [0/3] 下载并安装 mixflow ... "
        local ilog rc; ilog="$(mktemp /tmp/mixflow.inst.XXXXXX)"
        MF_AUTO=1 cmd_install >"$ilog" 2>&1; rc=$?
        unset MF_AUTO
        if [ "$rc" = 0 ] && is_installed; then
            echo -e "${GRN}完成${NC}"
        else
            echo -e "${RED}失败${NC}"; cat "$ilog"; rm -f "$ilog"
            err "安装失败，请检查下载地址（MIXFLOW_URL）或网络后重试"
            return 1
        fi
        rm -f "$ilog"
    fi

    local region ip
    region="$(detect_region)"
    ip="$(public_ip)"
    echo -e "  地区 ${GRN}${region:-未知}${NC} · 公网IP ${GRN}${ip}${NC}"
    echo

    # ① 先优化：详细报告收进日志，只留一行结果，避免刷屏盖掉后面的链接
    printf "  [1/3] 内核终极优化 ... "
    local olog; olog="$(mktemp /tmp/mixflow.opt.XXXXXX)"
    if "$BIN" optimize >"$olog" 2>&1; then
        local n; n="$(grep -oE '生效 [0-9]+ 项' "$olog" | head -1)"
        echo -e "${GRN}完成${NC} ${DIM}${n}${NC}"
    else
        echo -e "${YEL}部分项未生效（受限环境可忽略）${NC}"
    fi
    rm -f "$olog"

    # ② ③ 建节点
    printf "  [2/3] 创建 Mixed + Trojan + Hysteria2 节点 ... "
    local qlog; qlog="$(mktemp /tmp/mixflow.node.XXXXXX)"
    if ! "$BIN" quicknode --tag "$region" --host "$ip" -c "$CONFIG" >"$qlog" 2>&1; then
        echo -e "${RED}失败${NC}"; cat "$qlog"; rm -f "$qlog"; return 1
    fi
    echo -e "${GRN}OK${NC}"

    printf "  [3/3] 重启服务 ... "
    if svc_managed; then
        svc_do restart >/dev/null 2>&1; sleep 1
        svc_active \
            && echo -e "${GRN}运行中${NC}" || echo -e "${YEL}未起来（菜单→7 看日志）${NC}"
    else
        echo -e "${DIM}未托管${NC}"
    fi

    # 收尾：面板信息 + 节点链接，干净地打印在最后
    local port entry user pass
    port="$(panel_get port)"; entry="$(panel_get entry)"
    user="$(panel_get username)"; pass="$(panel_get password)"
    echo -e "\n${BLU}================  面板信息  ================${NC}"
    echo -e "  地址  ${GRN}http://${ip}:${port:-12321}${entry}${NC}"
    [ -n "$entry" ] && echo -e "        ${DIM}（隐藏入口：不带 ${entry} 访问会是 404）${NC}"
    echo -e "  账号  ${user:-admin}    密码  ${pass:-admin123}"

    echo -e "\n${BLU}================  节点链接  ================${NC}"
    cat "$qlog"; rm -f "$qlog"
    echo -e "${BLU}===========================================${NC}"
    warn "记得放行端口：面板 ${YEL}TCP ${port:-12321}${NC}；Mixed / Trojan 走 ${YEL}TCP${NC}、Hysteria2 走 ${YEL}UDP${NC}（防火墙 / 云安全组）"
    [ "${pass:-admin123}" = "admin123" ] && \
        warn "面板仍是默认密码，建议改掉：${DIM}mixflow panel --pass 新密码 -c $CONFIG${NC}"
}
write_service() {
    step "写入 $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
${MARK}
Description=mixflow multi-protocol proxy + web panel
# network-online 而不是 network：后者只保证网络栈起来了，不保证拿到地址，
# 监听具体 IP 的服务会 bind 失败
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
# WARP 隧道要 CAP_NET_ADMIN，内核参数优化要写 /proc/sys，都需要 root
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${BIN} run -c ${CONFIG}
Restart=always
RestartSec=3
# 文件句柄上限：高并发时 accept 撞默认值会报 EMFILE
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

# OpenRC(Alpine) 版服务单元
write_openrc() {
    step "写入 $OPENRC_FILE"
    cat > "$OPENRC_FILE" <<EOF
#!/sbin/openrc-run
${MARK}
description="mixflow multi-protocol proxy + web panel"
# supervise-daemon 负责挂了自动拉起（对应 systemd 的 Restart=always）
supervisor="supervise-daemon"
command="${BIN}"
command_args="run -c ${CONFIG}"
directory="${APP_DIR}"
pidfile="/run/${SERVICE_NAME}.pid"
respawn_delay=3
# 高并发文件句柄上限（对应 systemd 的 LimitNOFILE）
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

# 下载二进制到位（安装或更新都走这里）
download_binary() {
    local arch url tmp
    arch="$(detect_arch)" || return 1
    url="$(download_url "$arch")"
    step "架构 $arch，下载：$url"
    mkdir -p "$APP_DIR"
    tmp="$(mktemp "$APP_DIR/.mixflow.dl.XXXXXX")" || { err "无法在 $APP_DIR 建临时文件"; return 1; }
    if ! fetch "$url" "$tmp"; then
        rm -f "$tmp"; err "下载失败。检查 MIXFLOW_REPO / 资产名，或用 MIXFLOW_URL 指定完整地址"
        return 1
    fi
    if ! looks_like_elf "$tmp"; then
        rm -f "$tmp"
        err "下载到的不是 ELF 二进制（多半是 404 页面）。请确认 Release 里有：$(basename "$url")"
        return 1
    fi
    chmod +x "$tmp"
    mv -f "$tmp" "$BIN"
    info "二进制就位：$BIN"
    # 方便全局用 CLI（改端口/密码/暗门都靠它）
    ln -sf "$BIN" "$CLI_LINK" 2>/dev/null && info "已软链到 $CLI_LINK（可直接用 mixflow 命令）" || true
}

cmd_install() {
    need_root "$@"
    local fresh=0
    is_installed || fresh=1

    download_binary || return 1

    # 首次安装：生成默认配置，然后按用户输入设端口 / 暗门 / 密码
    if [ ! -f "$CONFIG" ]; then
        step "生成默认配置 $CONFIG"
        "$BIN" init -c "$CONFIG" >/dev/null 2>&1 || {
            err "初始化配置失败"; return 1
        }
    fi

    if [ "$fresh" = 1 ]; then
        if [ "${MF_AUTO:-}" = 1 ]; then
            # 全自动：默认端口 + 随机隐藏入口 + 保持默认密码 admin123（无提问）
            local port=12321 path
            path="$(rand_path)"
            "$BIN" panel --port "$port" --path "$path" -c "$CONFIG" \
                || { err "写入面板设置失败"; return 1; }
        else
            echo
            step "初始设置（直接回车用默认值）"

            local port; read -r -p "面板端口 [回车=12321]: " port; port="${port:-12321}"
            [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] \
                || { warn "端口无效，用 12321"; port=12321; }

            local defpath; defpath="$(rand_path)"
            echo -e "  ${DIM}隐藏入口 = 把登录页藏到一个随机路径后面，别人扫端口看不到面板${NC}"
            local path; read -r -p "隐藏入口路径 [回车=随机 $defpath，输 off 关闭]: " path
            path="${path:-$defpath}"

            local pass; read -r -p "面板密码 [回车=保持默认 admin123]: " pass

            # 落配置：一条 CLI 全搞定
            local args=( panel --port "$port" -c "$CONFIG" )
            if [ "$path" != "off" ]; then args+=( --path "$path" ); else args+=( --path off ); fi
            [ -n "$pass" ] && args+=( --pass "$pass" )
            "$BIN" "${args[@]}" || { err "写入面板设置失败"; return 1; }
        fi
    fi

    # 常驻托管（systemd / OpenRC 自动识别）
    if has_systemd || has_openrc; then
        svc_write_and_enable
        svc_do restart >/dev/null 2>&1
        sleep 1
    else
        warn "系统既无 systemd 也无 OpenRC，跳过服务安装。前台运行：$BIN run -c $CONFIG"
    fi

    # 自动模式下不打完成横幅，交给 oneclick 统一收尾
    [ "${MF_AUTO:-}" = 1 ] && return 0

    echo
    info "安装完成"
    show_panel_url
    [ "$fresh" = 1 ] && [ -z "${pass:-}" ] && \
        warn "面板密码仍是默认 admin123，强烈建议进菜单改掉（或 mixflow panel --pass 新密码 -c $CONFIG）"
    firewall_hint "$(panel_get port)"
}

# ============================================================
#  面板设置
# ============================================================
restart_note() {
    if svc_managed; then
        svc_do restart >/dev/null 2>&1 && info "已重启生效"
    else
        warn "改动已写入配置，请手动重启进程生效"
    fi
}

firewall_hint() { # port
    local p="$1"
    echo -e "  ${DIM}注意：若开了防火墙 / 云安全组，记得放行 TCP ${p}（Hysteria2 节点还要放行对应 UDP）${NC}"
}

show_panel_url() {
    is_installed || { err "还没安装"; return 1; }
    local ip port entry
    ip="$(public_ip)"
    port="$(panel_get port)"; port="${port:-12321}"
    entry="$(panel_get entry)"
    echo -e "${BLU}面板地址：${NC}"
    if [ -n "$entry" ]; then
        echo -e "   ${GRN}http://${ip}:${port}${entry}${NC}"
        echo -e "   ${DIM}（隐藏入口：直接访问 http://${ip}:${port}/ 会是 404，必须带上 ${entry}）${NC}"
    else
        echo -e "   ${GRN}http://${ip}:${port}/${NC}"
        echo -e "   ${DIM}（未设隐藏入口，登录页在根路径直接可见）${NC}"
    fi
    local user; user="$(panel_get username)"
    echo -e "   账号：${user:-admin}"
}

cmd_set_port() {
    need_root "$@"
    local cur; cur="$(panel_get port)"
    echo -e "当前端口：${YEL}${cur:-12321}${NC}"
    local p; read -r -p "新端口: " p
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ] || { err "端口无效"; return 1; }
    "$BIN" panel --port "$p" -c "$CONFIG" || return 1
    restart_note
    firewall_hint "$p"
    show_panel_url
}

cmd_set_path() {
    need_root "$@"
    local cur; cur="$(panel_get entry)"
    echo -e "当前隐藏入口：${YEL}${cur:-<未设置>}${NC}"
    echo "   1) 随机生成一个"
    echo "   2) 手动输入"
    echo "   3) 关闭（面板回到根路径 /）"
    local c; read -r -p "选择: " c
    local p
    case "$c" in
        1) p="$(rand_path)"; info "随机路径：$p" ;;
        2) read -r -p "输入路径（以 / 开头，如 /myfw）: " p
           [ -z "$p" ] && { warn "已取消"; return 1; } ;;
        3) p="off" ;;
        *) warn "已取消"; return 1 ;;
    esac
    "$BIN" panel --path "$p" -c "$CONFIG" || return 1
    restart_note
    show_panel_url
}

cmd_set_pass() {
    need_root "$@"
    local user; user="$(panel_get username)"
    echo -e "当前账号：${YEL}${user:-admin}${NC}"
    local nu; read -r -p "新用户名 [回车=不改]: " nu
    local p1 p2
    read -r -s -p "新密码（至少 4 位）: " p1; echo
    read -r -s -p "再输一次: " p2; echo
    [ "$p1" != "$p2" ] && { err "两次不一致"; return 1; }
    [ "${#p1}" -lt 4 ] && { err "密码太短"; return 1; }
    local args=( panel --pass "$p1" -c "$CONFIG" )
    [ -n "$nu" ] && args+=( --user "$nu" )
    "$BIN" "${args[@]}" || return 1
    restart_note
    info "面板凭据已更新"
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
    if has_systemd && [ -f "$SERVICE_FILE" ]; then
        echo "(Ctrl+C 停止查看)"; sleep 1
        journalctl -u "$SERVICE_NAME" -n 100 -f --no-pager 2>/dev/null || true
    elif has_openrc && [ -f "$OPENRC_FILE" ]; then
        echo "(Ctrl+C 停止查看)"; sleep 1
        tail -n 100 -f "/var/log/${SERVICE_NAME}.log" 2>/dev/null || true
    else
        warn "未托管为系统服务（systemd/OpenRC）"
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
    read -r -p "连同 $APP_DIR (含二进制和配置) 一起删掉? [y/N] " c
    if [[ "${c:-N}" =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"; info "已删除 $APP_DIR"
    else
        warn "已保留 $APP_DIR（配置和流量统计都还在，重装即恢复）"
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
        echo -e "        mixflow 安装 · 管理   ${DIM}v${VERSION}${NC}"
        echo -e "${BLU}=============================================${NC}"
        echo -e "  状态: $(state_line)"
        if is_installed; then
            echo -e "  目录: ${DIM}${APP_DIR}${NC}"
            local port entry; port="$(panel_get port)"; entry="$(panel_get entry)"
            echo -e "  端口: ${port:-?}    隐藏入口: ${entry:-<无>}"
        fi
        echo -e "${BLU}---------------------------------------------${NC}"
        if is_installed; then
            echo -e "   ${GRN}g) ★ 一键生成节点 + 终极优化（新机推荐）${NC}"
            echo -e "${BLU}---------------------------------------------${NC}"
            echo "   1) 更新 / 重装二进制      2) 查看面板地址"
            echo "   3) 启动   4) 停止   5) 重启   6) 状态   7) 日志"
            echo -e "${BLU}--- 面板设置 --------------------------------${NC}"
            echo "   8) 改端口   9) 改隐藏入口   10) 改账号密码"
            echo -e "${BLU}---------------------------------------------${NC}"
            echo -e "   u) ${RED}卸载${NC}"
        else
            echo "   1) 安装 mixflow"
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
            1) cmd_install; pause ;;
            2) show_panel_url; pause ;;
            g|G) cmd_oneclick; pause ;;
            3) cmd_start;   pause ;;
            4) cmd_stop;    pause ;;
            5) cmd_restart; pause ;;
            6) cmd_status;  pause ;;
            7) cmd_log ;;
            8) cmd_set_port; pause ;;
            9) cmd_set_path; pause ;;
            10) cmd_set_pass; pause ;;
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
mixflow 安装 · 管理脚本 v${VERSION}

远程一键：
  bash <(curl -sL ${SELF_URL})

子命令：
  install / update     安装或更新（下载二进制 + 起服务）
  oneclick             ★ 一键：建 Mixed / Trojan / Hysteria2 三个节点（随机端口）并做终极优化
  start|stop|restart|status|log
  url                  打印面板访问地址
  port <N>             改面板端口
  path <P|off>         改隐藏入口路径（off = 关闭）
  pass <密码> [用户名] 改面板密码 / 用户名
  uninstall            卸载

安装位置：${APP_DIR}
配置文件：${CONFIG}

可覆盖的环境变量：
  MIXFLOW_REPO   GitHub 仓库（默认 ${MIXFLOW_REPO}）
  MIXFLOW_TAG    Release tag（默认 latest）
  MIXFLOW_ASSET  资产命名（默认 mixflow-linux-{arch}）
  MIXFLOW_URL    直接给完整下载地址（含 {arch} 占位符也可），设了就忽略上面三个
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
    oneclick|go|quick) cmd_oneclick "$@" ;;
    port)             [ -n "${1:-}" ] && { need_root; "$BIN" panel --port "$1" -c "$CONFIG" && restart_note; } || cmd_set_port ;;
    path)             [ -n "${1:-}" ] && { need_root; "$BIN" panel --path "$1" -c "$CONFIG" && restart_note && show_panel_url; } || cmd_set_path ;;
    pass)             if [ -n "${1:-}" ]; then need_root; a=( panel --pass "$1" -c "$CONFIG" ); [ -n "${2:-}" ] && a+=( --user "$2" ); "$BIN" "${a[@]}" && restart_note; else cmd_set_pass; fi ;;
    uninstall|remove) cmd_uninstall "$@" ;;
    -h|--help|help)   usage ;;
    -v|--version)     echo "v${VERSION}" ;;
    *) err "未知命令: $cmd"; echo; usage; exit 1 ;;
esac
