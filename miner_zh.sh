#!/bin/bash

# XMR Mining Script
# Usage: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口

set -e

# 设置环境变量
export HOME=/root
export LC_ALL=en_US.UTF-8

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

# 检查参数
if [ $# -lt 2 ]; then
    log_error "参数不足！"
    echo "使用方法: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池域名:端口"
    echo "示例: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443"
    exit 1
fi

# 参数解析
WALLET_ADDRESS="$1"
POOL_ADDRESS="$2"

log_info "开始XMR挖矿脚本安装..."
log_info "钱包地址: $WALLET_ADDRESS"
log_info "矿池地址: $POOL_ADDRESS"

# 检测系统架构和操作系统
detect_system() {
    log_info "检测系统信息..."
    
    # 检测操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        OS="freebsd"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
    
    # 检测CPU架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="x64"
            ;;
        aarch64|arm64)
            log_error "XMRig不支持Linux系统的ARM64架构"
            log_error "请使用x64系统运行XMRig"
            exit 1
            ;;
        *)
            log_error "不支持的CPU架构: $ARCH"
            exit 1
            ;;
    esac
    
    log_info "检测到系统: $OS-$ARCH"
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
    case $OS in
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
        centos|rhel|rocky|almalinux)
            DISTRO="linux-static"  # RHEL系使用静态构建
            ;;
        freebsd)
            DISTRO="freebsd-static"
            ;;
        *)
            DISTRO="linux-static"  # 默认使用静态构建
            ;;
    esac
    
    # 单独处理macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ "$XMRIG_ARCH" = "arm64" ]; then
            FILENAME="xmrig-${VERSION}-macos-arm64.tar.gz"
        else
            FILENAME="xmrig-${VERSION}-macos-x64.tar.gz"
        fi
    else
        # Linux和其他类Unix系统
        # 注意：XMRig没有提供Linux ARM64版本，所有架构都使用x64静态构建版本
        FILENAME="xmrig-${VERSION}-${DISTRO}-x64.tar.gz"
    fi
    
    DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/xmrig/xmrig/releases/download/v${VERSION}/${FILENAME}"
    
    log_info "下载链接: $DOWNLOAD_URL"
}

# 检查先决条件
check_prerequisites() {
    log_info "检查先决条件..."
    
    # 检查必需的命令
    local missing_commands=""
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_commands="$missing_commands curl"
    fi
    
    if ! command -v wget >/dev/null 2>&1; then
        missing_commands="$missing_commands wget"
    fi
    
    if ! command -v tar >/dev/null 2>&1; then
        missing_commands="$missing_commands tar"
    fi
    
    if [ -n "$missing_commands" ]; then
        log_warn "缺少必需的命令:$missing_commands"
        log_info "尝试安装缺少的依赖..."
        install_missing_dependencies
        
        # 安装后重新检查
        for cmd in $missing_commands; do
            if ! command -v $cmd >/dev/null 2>&1; then
                log_error "安装 $cmd 失败。请手动安装后重新运行脚本。"
                exit 1
            fi
        done
        log_info "所有必需的依赖现在都可用了。"
    else
        log_info "所有必需的依赖都可用。"
    fi
}

# 安装缺少的依赖
install_missing_dependencies() {
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu - 使用类似C3Pool的简单方法
        log_info "更新包列表..."
        if ! apt-get update -qq; then
            log_warn "包更新失败，但继续执行..."
        fi
        
        log_info "安装缺少的包..."
        apt-get install -y wget curl tar || {
            log_error "安装包失败。请运行: sudo apt-get install wget curl tar"
            exit 1
        }
        
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL 7
        yum install -y wget curl tar || {
            log_error "安装包失败。请运行: sudo yum install wget curl tar"
            exit 1
        }
    elif command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL 8+/Fedora
        dnf install -y wget curl tar || {
            log_error "安装包失败。请运行: sudo dnf install wget curl tar"
            exit 1
        }
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        zypper install -y wget curl tar || {
            log_error "安装包失败。请运行: sudo zypper install wget curl tar"
            exit 1
        }
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -Sy --noconfirm wget curl tar || {
            log_error "安装包失败。请运行: sudo pacman -S wget curl tar"
            exit 1
        }
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        apk add --no-cache wget curl tar || {
            log_error "安装包失败。请运行: sudo apk add wget curl tar"
            exit 1
        }
    else
        log_error "无法识别包管理器。请手动安装 wget、curl、tar 后重新运行脚本。"
        exit 1
    fi
}

# 下载和安装XMRig
download_and_install() {
    log_info "下载和安装XMRig..."
    
    # 创建工作目录
    WORK_DIR="/opt/xmrig"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 下载文件
    log_info "下载 $FILENAME ..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME" || {
        log_error "下载失败"
        exit 1
    }
    
    # 解压文件
    log_info "解压文件..."
    tar -xzf "$FILENAME" --strip-components=1 || {
        log_error "解压失败"
        exit 1
    }
    
    # 清理下载文件
    rm -f "$FILENAME"
    
    # 删除官方配置文件（如果存在）
    if [ -f "$WORK_DIR/config.json" ]; then
        log_info "删除官方默认配置文件..."
        rm -f "$WORK_DIR/config.json"
    fi
    
    # 设置执行权限
    chmod +x xmrig
    
    log_info "XMRig安装完成"
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
        "max-threads-hint": null,
        "asm": true,
        "argon2-impl": null,
        "cn/0": false,
        "cn-lite/0": false
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
    
    cat > /etc/systemd/system/xmrig.service << EOF
[Unit]
Description=XMRig Monero Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/xmrig --config=$WORK_DIR/config.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable xmrig.service
    
    log_info "systemd服务创建完成"
}

# 创建SysV init脚本（用于不支持systemd的系统）
create_sysv_service() {
    log_info "创建SysV init脚本..."
    
    cat > /etc/init.d/xmrig << 'EOF'
#!/bin/bash
# xmrig        XMRig Monero Miner
# chkconfig: 35 99 99
# description: XMRig Monero Miner
#

. /etc/rc.d/init.d/functions

USER="root"
DAEMON="xmrig"
ROOT_DIR="/opt/xmrig"

SERVER="$ROOT_DIR/$DAEMON"
LOCK_FILE="/var/lock/subsys/xmrig"

do_start() {
    if [ ! -f "$LOCK_FILE" ] ; then
        echo -n $"Starting $DAEMON: "
        runuser -l "$USER" -c "$SERVER --config=$ROOT_DIR/config.json" && echo_success || echo_failure
        RETVAL=$?
        echo
        [ $RETVAL -eq 0 ] && touch $LOCK_FILE
    else
        echo "$DAEMON is locked."
    fi
}
do_stop() {
    echo -n $"Shutting down $DAEMON: "
    pid=`ps -aefw | grep "$DAEMON" | grep -v " grep " | awk '{print $2}'`
    kill -9 $pid > /dev/null 2>&1
    [ $? -eq 0 ] && echo_success || echo_failure
    RETVAL=$?
    echo
    [ $RETVAL -eq 0 ] && rm -f $LOCK_FILE
}

case "$1" in
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
        echo "Usage: $0 {start|stop|restart}"
        RETVAL=1
esac

exit $RETVAL
EOF
    
    chmod +x /etc/init.d/xmrig
    
    # 添加到启动项
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add xmrig
        chkconfig xmrig on
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d xmrig defaults
    fi
    
    log_info "SysV init脚本创建完成"
}

# 设置自启动
setup_autostart() {
    log_info "设置系统自启动..."
    
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
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start xmrig.service
        systemctl status xmrig.service --no-pager
    else
        service xmrig start
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
    echo
    log_info "=== 管理命令 ==="
    if command -v systemctl >/dev/null 2>&1; then
        log_info "查看状态: systemctl status xmrig"
        log_info "停止挖矿: systemctl stop xmrig"
        log_info "启动挖矿: systemctl start xmrig"
        log_info "重启挖矿: systemctl restart xmrig"
        log_info "查看日志: journalctl -u xmrig -f"
    else
        log_info "查看状态: service xmrig status"
        log_info "停止挖矿: service xmrig stop"
        log_info "启动挖矿: service xmrig start"
        log_info "重启挖矿: service xmrig restart"
    fi
    echo
    log_info "配置文件: $WORK_DIR/config.json"
    log_info "手动运行: cd $WORK_DIR && ./xmrig --config=config.json"
}

# 主函数
main() {
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 执行安装步骤
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
