# 🚀 XMRig One-Click Mining Script - Monero Automated Mining Deployment Tool

**Easy Mining, One-Click Deploy!** Professional XMRig automated installation script that lets you quickly start your Monero (XMR) mining journey. Supports all mainstream Linux systems with zero configuration, zero donation, and high-performance mining solution.

## 🌟 Core Advantages

- 🎯 **One-Click Deployment**: Complete all configurations with a single command, beginner-friendly
- 🔥 **Zero Donation Mining**: donate-level set to 0, all profits go to you
- ⚡ **High-Performance Optimization**: Automatic CPU thread optimization, huge pages support
- 🛡️ **System Compatibility**: Supports Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, openSUSE, Arch, Alpine, etc.
- 🔄 **Auto Update**: Real-time fetching of latest XMRig version
- 🚀 **Auto Start**: Automatically resume mining after system reboot
- 📊 **Complete Monitoring**: systemd service management, log monitoring

## 🏷️ Keywords Tags

`XMRig` `Monero Mining` `XMR Mining` `One-Click Mining Script` `Linux Mining` `Automated Mining` `Mining Script` `Cryptocurrency Mining` `CPU Mining` `Zero Donation Mining` `Mining Tool` `Blockchain Mining` `Digital Currency` `Mining Deployment` `Ubuntu Mining` `CentOS Mining` `Debian Mining`

## 📋 System Requirements

- 🐧 **Operating System**: Linux (Ubuntu 18.04+, Debian 9+, CentOS 7+, RHEL 7+, etc.)
- 👑 **Privileges**: Root access required
- 🌐 **Network**: Stable internet connection
- 💾 **Memory**: At least 2GB RAM recommended
- 💿 **Storage**: 100MB+ free space
- 🏗️ **Architecture**: x86_64 (64-bit) - **ARM64 currently not supported**

## 🚀 Quick Start

### 🎯 Method 1: Direct Deployment (Recommended)

```bash
# English version - One command to start mining
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_en.sh | LC_ALL=en_US.UTF-8 bash -s wallet_address pool_address:port cpu_usage
```

### 🎯 Method 2: Download and Execute

```bash
# Download script first
wget https://github.com/jiaran464/xmr/raw/main/miner_en.sh
chmod +x miner_en.sh

# Execute with parameters
./miner_en.sh wallet_address pool_address:port cpu_usage
```

### 📝 Parameter Description

| Parameter | Description | Example | Note |
|-----------|-------------|---------|------|
| `wallet_address` | Your Monero wallet address | `4xxxxx...xxxxx` | 95 characters long |
| `pool_address:port` | Mining pool server and port | `pool.supportxmr.com:443` | Include port number |
| `cpu_usage` | CPU usage percentage | `70` | Range: 1-100 |

### 🔥 Popular Mining Pools Examples

```bash
# SupportXMR Pool (SSL)
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_en.sh | bash -s 4xxxxxxx pool.supportxmr.com:443 70

# MineXMR Pool
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_en.sh | bash -s 4xxxxxxx pool.minexmr.com:4444 80

# NanoPool
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_en.sh | bash -s 4xxxxxxx xmr-us-east1.nanopool.org:14444 60
```

## 📁 File Structure

```
/opt/xmrig/
├── xmrig              # XMRig executable
├── config.json        # Configuration file (fully customized)
└── SHA256SUMS         # Checksum file
```

## ⚙️ Configuration Features

### Core Configuration
- **Donation Setting**: `donate-level: 0` (zero donation)
- **Environment Variable**: `HOME=/root`
- **CPU Optimization**: Auto-configures thread count based on specified percentage
- **Memory Optimization**: Enables huge pages support
- **Network Configuration**: Uses latest IP version configuration format

### Differences from Official Configuration
- Completely removes official default configuration file
- Uses custom configuration template
- Ensures all parameters are set according to user requirements
- Compatible with XMRig 6.24.0+ versions

## 🔧 Mining Management Commands

### 🖥️ Systemd Systems (Recommended)

```bash
# 📊 Check mining status
systemctl status xmrig

# ⏹️ Stop mining
systemctl stop xmrig

# ▶️ Start mining
systemctl start xmrig

# 🔄 Restart mining
systemctl restart xmrig

# 📋 View real-time logs
journalctl -u xmrig -f

# 📜 View recent logs
journalctl -u xmrig --since "1 hour ago"

# 🚫 Disable auto-start
systemctl disable xmrig

# ✅ Enable auto-start
systemctl enable xmrig
```

### 🔧 SysV Init Systems

```bash
# 📊 Check status
service xmrig status

# ⏹️ Stop mining
service xmrig stop

# ▶️ Start mining
service xmrig start

# 🔄 Restart mining
service xmrig restart
```

### 🛠️ Manual Execution

```bash
# Navigate to installation directory
cd /opt/xmrig

# 🚀 Manual start
./xmrig --config=config.json

# 🌙 Background execution
nohup ./xmrig --config=config.json > /dev/null 2>&1 &

# 🔍 Check mining process
ps aux | grep xmrig
```

## 📊 Monitoring and Logs

### View Mining Status
```bash
# Real-time logs
journalctl -u xmrig -f

# Recent logs
journalctl -u xmrig -n 50

# System resource usage
htop
```

### Performance Monitoring
```bash
# CPU usage
top -p $(pgrep xmrig)

# Memory usage
ps aux | grep xmrig
```

## 🛡️ Security Features

- **Permission Control**: Only root users can execute
- **Parameter Validation**: Strict validation of all input parameters
- **Error Handling**: Comprehensive error detection and handling mechanisms
- **Logging**: Detailed operation logs
- **Configuration Isolation**: Independent configuration file, doesn't affect other system services

## 🔍 Troubleshooting

### Common Issues

1. **Download Failed**
   ```bash
   # Check network connection
   ping github.com
   
   # Manual download test
   wget https://github.com/xmrig/xmrig/releases/latest
   ```

2. **Permission Error**
   ```bash
   # Ensure root privileges
   sudo su -
   ```

3. **Service Start Failed**
   ```bash
   # View detailed errors
   systemctl status xmrig -l
   
   # View logs
   journalctl -u xmrig --no-pager
   ```

4. **Configuration File Issues**
   ```bash
   # Validate configuration file format
   cat /opt/xmrig/config.json | python -m json.tool
   
   # Regenerate configuration
   rm /opt/xmrig/config.json
   # Re-run the script
   ```

### Uninstallation

```bash
# Stop service
systemctl stop xmrig
systemctl disable xmrig

# Remove service file
rm -f /etc/systemd/system/xmrig.service
systemctl daemon-reload

# Remove installation directory
rm -rf /opt/xmrig

# Remove SysV script (if exists)
rm -f /etc/init.d/xmrig
```

## 📈 Performance Optimization Tips

### CPU Optimization
- Recommend setting CPU usage to 70-80%
- Reserve some CPU resources for system use
- Monitor system temperature to avoid overheating

### Memory Optimization
- Ensure system has sufficient available memory
- Enabling huge pages can improve performance
- Regularly monitor memory usage

### Network Optimization
- Choose mining pools with lower latency
- Use stable network connections
- Consider using backup mining pools

## ⚠️ Important Reminders & Disclaimer

### 📖 Must Read Before Use
- 🔍 **Legal Compliance**: Ensure mining activities comply with local laws and regulations
- ⚡ **Power Consumption**: Mining consumes significant electricity, calculate costs beforehand
- 🌡️ **Hardware Protection**: Monitor CPU temperature to prevent overheating damage
- 🔒 **Security Awareness**: Only download scripts from trusted sources
- 💰 **Investment Risk**: Cryptocurrency mining involves market risks, invest wisely

### 🛠️ Technical Support
- 📚 **Documentation**: Read this guide thoroughly before use
- 🐛 **Issue Reporting**: Report bugs via GitHub Issues
- 💬 **Community**: Join Monero community for mining discussions
- 🔄 **Updates**: Regularly check for script updates

### 👥 Target Users
- 🎯 **Linux Users**: Familiar with basic Linux command operations
- 💻 **Mining Enthusiasts**: Interested in cryptocurrency mining
- 🚀 **Efficiency Seekers**: Want quick deployment solutions
- 📊 **Performance Optimizers**: Pursue high-efficiency mining

## 🔗 Useful Resource Links

### 📚 Official Resources
- 🏠 **XMRig Official**: [https://xmrig.com](https://xmrig.com)
- 📖 **Monero Official**: [https://getmonero.org](https://getmonero.org)
- 💰 **Mining Calculator**: [https://www.cryptocompare.com/mining/calculator/xmr](https://www.cryptocompare.com/mining/calculator/xmr)
- 📊 **Network Stats**: [https://moneroblocks.info](https://moneroblocks.info)

### 🛠️ Useful Tools
- 💼 **Wallet Generator**: [https://moneroaddress.org](https://moneroaddress.org)
- 📈 **Pool Statistics**: [https://miningpoolstats.stream/monero](https://miningpoolstats.stream/monero)
- 🔍 **Block Explorer**: [https://xmrchain.net](https://xmrchain.net)
- 📱 **Mobile Wallet**: Official Monero mobile apps

### 📖 Learning Resources
- 📚 **Mining Guide**: [Monero Mining Guide](https://web.getmonero.org/get-started/mining/)
- 🎓 **Community Forum**: [r/MoneroMining](https://reddit.com/r/MoneroMining)
- 💡 **Best Practices**: [XMRig Documentation](https://xmrig.com/docs)

---

## 🎉 Start Your Mining Journey Now!

**Ready to mine?** Copy the command below and start your profitable Monero mining journey:

```bash
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_en.sh | bash -s YOUR_WALLET_ADDRESS POOL_ADDRESS:PORT CPU_USAGE
```

---

## 💝 Support Our Development

If this script has been helpful to you, please consider supporting our development work through the following ways:

### 🪙 Cryptocurrency Donations

**XMR (Monero)**
```
87WaukyjSWMJxupbYMxUXDCLGCiQpnSmxSVyKN3eLMJj4nNdyrsBz9NYD7UNpVowq93v9rL5oWjzwScL1Z3K2fzBTCik55g
```

**USDT (TRC20)**
```
TMBLk2jaYX3Bx62vHRWW9b6yD8YdsG9MFa
```

**TRX (TRC20)**
```
TMBLk2jaYX3Bx62vHRWW9b6yD8YdsG9MFa
```

Your support helps us continue to improve and maintain this project! 🙏

---

**Happy Mining! 🚀💎**

*© 2024 XMRig One-Click Mining Script. Built with ❤️ for the Monero community.*
