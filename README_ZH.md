# 🚀 XMRig一键挖矿脚本 - 门罗币自动化挖矿部署工具

**轻松挖矿，一键部署！** 专业的XMRig自动化安装脚本，让您快速开启门罗币(XMR)挖矿之旅。支持所有主流Linux系统，零配置、零抽水、高性能挖矿解决方案。

## 🌟 核心优势

- 🎯 **一键部署**：单条命令完成所有配置，新手友好
- 🔥 **零抽水挖矿**：donate-level设为0，收益全归您
- ⚡ **高性能优化**：自动CPU线程优化，大页内存支持
- 🛡️ **系统兼容**：支持Ubuntu、Debian、CentOS、RHEL、Rocky、AlmaLinux、openSUSE、Arch、Alpine等
- 🔄 **自动更新**：实时获取最新XMRig版本
- 🚀 **开机自启**：系统重启后自动恢复挖矿
- 📊 **完整监控**：systemd服务管理，日志监控

## 🏷️ 关键词标签

`XMRig` `门罗币挖矿` `XMR挖矿` `一键挖矿脚本` `Linux挖矿` `自动化挖矿` `挖矿脚本` `加密货币挖矿` `CPU挖矿` `零抽水挖矿` `挖矿工具` `区块链挖矿` `数字货币` `挖矿部署` `Ubuntu挖矿` `CentOS挖矿` `Debian挖矿`

## 📋 系统要求

- 🐧 **操作系统**：Linux（Ubuntu 18.04+、Debian 9+、CentOS 7+、RHEL 7+等）
- 👑 **权限要求**：需要Root权限
- 🌐 **网络连接**：稳定的互联网连接
- 💾 **内存要求**：建议至少2GB内存
- 💿 **存储空间**：100MB+可用空间
- 🏗️ **架构支持**：x86_64（64位）- **ARM64暂不支持**

## 🚀 快速开始

### 🎯 方法一：直接部署（推荐）

```bash
# 中文版 - 一条命令开始挖矿
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_zh.sh | LC_ALL=en_US.UTF-8 bash -s 钱包地址 矿池地址:端口 CPU利用率
```

### 🎯 方法二：下载后执行

```bash
# 先下载脚本
wget https://github.com/jiaran464/xmr/raw/main/miner_zh.sh
chmod +x miner_zh.sh

# 执行脚本
./miner_zh.sh 钱包地址 矿池地址:端口 CPU利用率
```

### 📝 参数说明

| 参数 | 说明 | 示例 | 备注 |
|------|------|------|------|
| `钱包地址` | 您的门罗币钱包地址 | `4xxxxx...xxxxx` | 95位字符长度 |
| `矿池地址:端口` | 矿池服务器地址和端口 | `pool.supportxmr.com:443` | 需包含端口号 |
| `CPU利用率` | CPU使用百分比 | `70` | 范围：1-100 |

### 🔥 热门矿池示例

```bash
# SupportXMR矿池（SSL）
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_zh.sh | bash -s 4xxxxxxx pool.supportxmr.com:443 70

# MineXMR矿池
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_zh.sh | bash -s 4xxxxxxx pool.minexmr.com:4444 80

# NanoPool矿池
curl -s -L https://github.com/jiaran464/xmr/raw/main/miner_zh.sh | bash -s 4xxxxxxx xmr-us-east1.nanopool.org:14444 60
```

## 📁 文件结构

```
/opt/xmrig/
├── xmrig              # XMRig 可执行文件
├── config.json        # 配置文件（完全自定义）
└── SHA256SUMS         # 校验文件
```

## ⚙️ 配置特点

### 核心配置
- **捐赠设置**：`donate-level: 0`（零捐赠）
- **环境变量**：`HOME=/root`
- **CPU 优化**：根据指定百分比自动配置线程数
- **内存优化**：启用大页内存支持
- **网络配置**：使用最新的 IP 版本配置格式

### 与官方配置的区别
- 完全删除官方默认配置文件
- 使用自定义配置模板
- 确保所有参数按用户需求设置
- 兼容 XMRig 6.24.0+ 版本

## 🔧 挖矿管理命令

### 🎮 Systemd 系统管理（推荐）

```bash
# 📊 查看挖矿状态
systemctl status xmrig

# ⏹️ 停止挖矿
systemctl stop xmrig

# ▶️ 启动挖矿
systemctl start xmrig

# 🔄 重启挖矿
systemctl restart xmrig

# 📋 实时查看挖矿日志
journalctl -u xmrig -f

# 📜 查看历史日志
journalctl -u xmrig -n 100

# 🚫 禁用开机自启
systemctl disable xmrig

# ✅ 启用开机自启
systemctl enable xmrig
```

### 🛠️ SysV Init 系统管理

```bash
# 查看状态
service xmrig status

# 停止挖矿
service xmrig stop

# 启动挖矿
service xmrig start

# 重启挖矿
service xmrig restart
```

### 🖥️ 手动运行模式

```bash
# 进入安装目录
cd /opt/xmrig

# 前台运行（可看到实时输出）
./xmrig --config=config.json

# 后台运行
nohup ./xmrig --config=config.json > /dev/null 2>&1 &

# 查看进程
ps aux | grep xmrig
```

## 📊 监控和日志

### 查看挖矿状态
```bash
# 实时日志
journalctl -u xmrig -f

# 最近日志
journalctl -u xmrig -n 50

# 系统资源使用
htop
```

### 性能监控
```bash
# CPU 使用率
top -p $(pgrep xmrig)

# 内存使用
ps aux | grep xmrig
```

## 🛡️ 安全特性

- **权限控制**：仅 root 用户可执行
- **参数验证**：严格验证所有输入参数
- **错误处理**：完善的错误检测和处理机制
- **日志记录**：详细的操作日志
- **配置隔离**：独立的配置文件，不影响系统其他服务

## 🔍 故障排除

### 常见问题

1. **下载失败**
   ```bash
   # 检查网络连接
   ping github.com
   
   # 手动下载测试
   wget https://github.com/xmrig/xmrig/releases/latest
   ```

2. **权限错误**
   ```bash
   # 确保使用 root 权限
   sudo su -
   ```

3. **服务启动失败**
   ```bash
   # 查看详细错误
   systemctl status xmrig -l
   
   # 查看日志
   journalctl -u xmrig --no-pager
   ```

4. **配置文件问题**
   ```bash
   # 验证配置文件格式
   cat /opt/xmrig/config.json | python -m json.tool
   
   # 重新生成配置
   rm /opt/xmrig/config.json
   # 重新运行脚本
   ```

### 卸载方法

```bash
# 停止服务
systemctl stop xmrig
systemctl disable xmrig

# 删除服务文件
rm -f /etc/systemd/system/xmrig.service
systemctl daemon-reload

# 删除安装目录
rm -rf /opt/xmrig

# 删除 SysV 脚本（如果存在）
rm -f /etc/init.d/xmrig
```

## 📈 性能优化建议

### CPU 优化
- 建议 CPU 使用率设置为 70-80%
- 保留部分 CPU 资源给系统使用
- 监控系统温度，避免过热

### 内存优化
- 确保系统有足够的可用内存
- 启用大页内存可提升性能
- 定期监控内存使用情况

### 网络优化
- 选择延迟较低的矿池
- 使用稳定的网络连接
- 考虑使用备用矿池

## ⚠️ 重要提醒与免责声明

### 🚨 使用前必读

- 📚 **学习目的**：本脚本仅供学习和技术研究使用
- ⚖️ **法律合规**：请确保在合法的司法管辖区内使用，遵守当地法律法规
- 💡 **风险提示**：加密货币挖矿存在市场风险，收益不保证
- 🔌 **硬件影响**：挖矿会增加电力消耗和硬件磨损，请合理评估成本
- 🛡️ **安全责任**：使用者需自行承担安全风险，建议在隔离环境中测试

### 📞 技术支持

- 🐛 **问题反馈**：遇到技术问题请提交 Issue
- 💬 **社区讨论**：加入 Monero 中文社区交流
- 📖 **文档更新**：定期查看最新版本和更新日志
- 🔄 **版本升级**：建议使用最新版本脚本

### 🎯 适用人群

- 🔰 **挖矿新手**：想要快速体验 Monero 挖矿
- 🖥️ **Linux 用户**：熟悉 Linux 系统操作
- ⚡ **效率追求者**：需要快速部署挖矿环境
- 🔧 **技术爱好者**：对区块链技术感兴趣

---

## 🔗 相关资源链接

### 📚 官方资源
- [XMRig 官方网站](https://xmrig.com/) - 官方挖矿软件
- [XMRig GitHub](https://github.com/xmrig/xmrig) - 源代码仓库
- [Monero 官方网站](https://www.getmonero.org/) - 门罗币官网
- [Monero GUI 钱包](https://www.getmonero.org/downloads/) - 官方钱包下载

### 🛠️ 实用工具
- [XMR 算力计算器](https://www.cryptocompare.com/mining/calculator/xmr) - 收益计算
- [Monero 区块浏览器](https://xmrchain.net/) - 交易查询
- [矿池统计](https://miningpoolstats.stream/monero) - 矿池对比

### 📖 学习资源
- [Monero 白皮书](https://www.getmonero.org/resources/research-lab/) - 技术文档
- [挖矿入门指南](https://www.getmonero.org/get-started/mining/) - 官方教程

---

## 💝 支持我们的开发

如果这个脚本对您有帮助，欢迎通过以下方式支持我们的开发工作：

### 🪙 加密货币捐赠

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

您的支持将帮助我们持续改进和维护这个项目！ 🙏

---

**🎉 开始您的 Monero 挖矿之旅！** 

使用本脚本，您只需要一条命令就能开始挖矿。记住，挖矿不仅是获得收益的方式，更是支持去中心化网络安全的重要贡献！

**💎 Happy Mining! 祝您挖矿愉快！**