# XMR Mining Script

Automated script for one-click XMRig miner deployment, supporting mainstream Linux distributions and different CPU architectures.

## 🚀 Features

- ✅ **One-Click Deployment**: Complete configuration with a single command
- ✅ **System Compatibility**: Supports Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, openSUSE, Arch, Alpine, etc.
- ✅ **Architecture Support**: Auto-detects x64 and ARM64 architectures
- ✅ **Auto Update**: Fetches latest version from official API
- ✅ **Zero Donation**: donate-level set to 0
- ✅ **System Service**: Auto-configures systemd or SysV init service
- ✅ **Auto Start**: Automatically starts mining after system reboot
- ✅ **Complete Override**: Generated config file completely overrides official default configuration

## 📋 System Requirements

- Linux operating system (supports mainstream distributions)
- Root privileges
- Network connection
- CPU architecture: x86_64 or aarch64/arm64

## 🛠️ Usage

### Basic Usage

```bash
curl -s -L your-domain.com/miner_en.sh | LC_ALL=en_US.UTF-8 bash -s wallet_address pool_address:port cpu_usage
```

### Chinese Version

```bash
curl -s -L your-domain.com/miner.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池地址:端口 CPU利用率
```

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| wallet_address | Your Monero wallet address | `4xxxxx...xxxxx` |
| pool_address:port | Mining pool server address and port | `pool.example.com:4444` |
| cpu_usage | CPU usage percentage (1-100) | `70` |

### Usage Examples

```bash
# English version
curl -s -L example.com/miner_en.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443 70

# Chinese version
curl -s -L example.com/miner.sh | LC_ALL=en_US.UTF-8 bash -s 4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx pool.supportxmr.com:443 70
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

## 🔧 Management Commands

### Systemd Systems (Recommended)

```bash
# Check status
systemctl status xmrig

# Stop mining
systemctl stop xmrig

# Start mining
systemctl start xmrig

# Restart mining
systemctl restart xmrig

# View logs
journalctl -u xmrig -f

# Disable auto-start
systemctl disable xmrig

# Enable auto-start
systemctl enable xmrig
```

### SysV Init Systems

```bash
# Check status
service xmrig status

# Stop mining
service xmrig stop

# Start mining
service xmrig start

# Restart mining
service xmrig restart
```

### Manual Execution

```bash
# Navigate to installation directory
cd /opt/xmrig

# Manual start
./xmrig --config=config.json

# Background execution
nohup ./xmrig --config=config.json > /dev/null 2>&1 &
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

## 🤝 Supported Mining Pools

The script supports all standard Monero mining pools. Recommended pools include:

- SupportXMR: `pool.supportxmr.com:443`
- MineXMR: `pool.minexmr.com:4444`
- MoneroOcean: `gulf.moneroocean.stream:10001`
- Nanopool: `xmr-eu1.nanopool.org:14433`

## 📄 License

This project is licensed under the MIT License. See the LICENSE file for details.

## 🔗 Related Links

- [XMRig Official Website](https://xmrig.com/)
- [XMRig GitHub](https://github.com/xmrig/xmrig)
- [Monero Official Website](https://www.getmonero.org/)

## ⚠️ Disclaimer

- This script is for educational and research purposes only
- Please ensure usage within legal jurisdictions
- Mining may increase power consumption and hardware wear
- Please understand local laws and regulations before use
- The author assumes no responsibility for any losses or legal liabilities arising from the use of this script

---

**Note**: Before using this script, please ensure you fully understand the risks and legal requirements associated with cryptocurrency mining.