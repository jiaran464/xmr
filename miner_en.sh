#!/bin/bash

# XMR Mining Script (English Version)
# Compatible with mainstream Linux distributions and CPU architectures
# Usage: curl -s -L your-domain.com/miner_en.sh | LC_ALL=en_US.UTF-8 bash -s wallet_address pool_address:port cpu_usage

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parameter validation
if [ $# -ne 3 ]; then
    log_error "Usage: $0 <wallet_address> <pool_address:port> <cpu_usage_percentage>"
    log_error "Example: $0 your_wallet_address pool.example.com:4444 70"
    exit 1
fi

WALLET_ADDRESS="$1"
POOL_ADDRESS="$2"
CPU_USAGE="$3"

# Validate parameters
if [ -z "$WALLET_ADDRESS" ] || [ -z "$POOL_ADDRESS" ] || [ -z "$CPU_USAGE" ]; then
    log_error "All parameters are required"
    exit 1
fi

if ! [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] || [ "$CPU_USAGE" -lt 1 ] || [ "$CPU_USAGE" -gt 100 ]; then
    log_error "CPU usage must be a number between 1-100"
    exit 1
fi

# Set environment variables
export HOME=/root
export LC_ALL=en_US.UTF-8

log_info "Starting XMR mining script installation..."
log_info "Wallet Address: $WALLET_ADDRESS"
log_info "Pool Address: $POOL_ADDRESS"
log_info "CPU Usage: $CPU_USAGE%"

# System detection
detect_system() {
    log_info "Detecting system information..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            XMRIG_ARCH="x64"
            ;;
        aarch64|arm64)
            XMRIG_ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    log_info "Operating System: $OS"
    log_info "Architecture: $ARCH -> $XMRIG_ARCH"
}

# Get latest XMRig version
get_latest_version() {
    log_info "Getting latest XMRig version..."
    
    # Try GitHub API first
    VERSION=$(curl -s "https://api.github.com/repos/xmrig/xmrig/releases/latest" | grep -o '"tag_name":"v[^"]*' | head -1 | cut -d'"' -f4 | sed 's/v//')
    
    # Fallback to alternative GitHub API
    if [ -z "$VERSION" ]; then
        log_info "Trying alternative GitHub API..."
        VERSION=$(curl -s "https://github.com/xmrig/xmrig/releases/latest" | grep -o 'tag/v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1 | sed 's/tag\/v//')
    fi
    
    # Fallback to hardcoded stable version
    if [ -z "$VERSION" ]; then
        log_info "Using fallback stable version..."
        VERSION="6.24.0"
    fi
    
    if [ -z "$VERSION" ]; then
        log_error "Failed to get XMRig version"
        exit 1
    fi
    
    log_info "Latest XMRig version: $VERSION"
}

# Get download URL
get_download_url() {
    log_info "Generating download URL..."
    
    # Get distribution info for Linux
    case $OS in
        ubuntu|debian)
            if [ "$OS_VERSION" = "20.04" ] || [ "$OS_VERSION" = "20" ]; then
                DISTRO="focal"
            elif [ "$OS_VERSION" = "22.04" ] || [ "$OS_VERSION" = "22" ]; then
                DISTRO="jammy"
            else
                DISTRO="focal"  # Default fallback
            fi
            ;;
        centos|rhel|rocky|almalinux)
            DISTRO="focal"  # Use focal as fallback for RHEL-based
            ;;
        *)
            DISTRO="focal"  # Default fallback
            ;;
    esac
    
    FILENAME="xmrig-${VERSION}-linux-${DISTRO}-${XMRIG_ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${VERSION}/${FILENAME}"
    
    log_info "Download URL: $DOWNLOAD_URL"
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y wget curl tar
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL 7
        yum install -y wget curl tar
    elif command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL 8+/Fedora
        dnf install -y wget curl tar
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        zypper install -y wget curl tar
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -Sy --noconfirm wget curl tar
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        apk add --no-cache wget curl tar
    else
        log_warn "Cannot identify package manager, please install wget, curl, tar manually"
    fi
}

# Download and install XMRig
download_and_install() {
    log_info "Downloading and installing XMRig..."
    
    # Create working directory
    WORK_DIR="/opt/xmrig"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Download file
    log_info "Downloading $FILENAME ..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME" || {
        log_error "Download failed"
        exit 1
    }
    
    # Extract file
    log_info "Extracting file..."
    tar -xzf "$FILENAME" --strip-components=1 || {
        log_error "Extraction failed"
        exit 1
    }
    
    # Clean up download file
    rm -f "$FILENAME"
    
    # Delete official config file (if exists)
    if [ -f "$WORK_DIR/config.json" ]; then
        log_info "Removing official default config file..."
        rm -f "$WORK_DIR/config.json"
    fi
    
    # Set execute permissions
    chmod +x xmrig
    
    log_info "XMRig installation completed"
}

# Create configuration file
create_config() {
    log_info "Creating configuration file..."
    
    # If official config file exists, remove it completely
    if [ -f "$WORK_DIR/config.json" ]; then
        log_info "Detected official config file, will completely overwrite..."
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
        "max-threads-hint": $CPU_USAGE,
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
    
    log_info "Configuration file created successfully"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
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
    
    systemctl daemon-reload
    systemctl enable xmrig.service
    
    log_info "Systemd service created and enabled"
}

# Create SysV init script
create_sysv_service() {
    log_info "Creating SysV init script..."
    
    cat > /etc/init.d/xmrig << EOF
#!/bin/bash
# xmrig        XMRig Monero Miner
# chkconfig: 35 99 99
# description: XMRig Monero Miner
#

. /etc/rc.d/init.d/functions

USER="root"
DAEMON="xmrig"
ROOT_DIR="$WORK_DIR"

SERVER="\$ROOT_DIR/\$DAEMON"
LOCK_FILE="/var/lock/subsys/xmrig"

do_start() {
    if [ -f \$LOCK_FILE ] ; then
        echo "\$DAEMON is locked."
        return 1
    fi
    
    echo -n "Starting \$DAEMON: "
    runuser -l "\$USER" -c "\$SERVER --config=\$ROOT_DIR/config.json" && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && touch \$LOCK_FILE
    return \$RETVAL
}
do_stop() {
    echo -n "Shutting down \$DAEMON: "
    pid=\$(ps -aefw | grep "\$DAEMON" | grep -v " grep " | awk '{print \$2}')
    kill -9 \$pid > /dev/null 2>&1
    [ \$? -eq 0 ] && echo_success || echo_failure
    RETVAL=\$?
    echo
    [ \$RETVAL -eq 0 ] && rm -f \$LOCK_FILE
    return \$RETVAL
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
    
    chmod +x /etc/init.d/xmrig
    chkconfig --add xmrig
    chkconfig xmrig on
    
    log_info "SysV init script created and enabled"
}

# Setup auto-start
setup_autostart() {
    log_info "Setting up auto-start..."
    
    if command -v systemctl >/dev/null 2>&1; then
        create_systemd_service
    else
        create_sysv_service
    fi
    
    log_info "Auto-start configuration completed"
}

# Start mining
start_mining() {
    log_info "Starting mining service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start xmrig.service
        systemctl status xmrig.service --no-pager
    else
        service xmrig start
    fi
    
    log_info "Mining service started"
}

# Show status information
show_status() {
    echo
    log_info "=== Installation Complete ==="
    log_info "XMRig Version: $VERSION"
    log_info "Installation Directory: $WORK_DIR"
    log_info "Wallet Address: $WALLET_ADDRESS"
    log_info "Pool Address: $POOL_ADDRESS"
    log_info "CPU Usage: $CPU_USAGE%"
    log_info "Donation Setting: 0%"
    echo
    log_info "=== Management Commands ==="
    if command -v systemctl >/dev/null 2>&1; then
        log_info "Check Status: systemctl status xmrig"
        log_info "Stop Mining: systemctl stop xmrig"
        log_info "Start Mining: systemctl start xmrig"
        log_info "Restart Mining: systemctl restart xmrig"
        log_info "View Logs: journalctl -u xmrig -f"
    else
        log_info "Check Status: service xmrig status"
        log_info "Stop Mining: service xmrig stop"
        log_info "Start Mining: service xmrig start"
        log_info "Restart Mining: service xmrig restart"
    fi
    echo
    log_info "Config File: $WORK_DIR/config.json"
    log_info "Manual Run: cd $WORK_DIR && ./xmrig --config=config.json"
}

# Main function
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with root privileges"
        exit 1
    fi
    
    # Execute installation steps
    detect_system
    get_latest_version
    get_download_url
    install_dependencies
    download_and_install
    create_config
    setup_autostart
    start_mining
    show_status
    
    log_info "XMR mining script installation completed!"
}

# Run main function
main "$@"
