<#
.SYNOPSIS
WinDevEnv-Setup 环境诊断模块
#>

<#
.SYNOPSIS
执行完整环境诊断并输出结果
#>
function Invoke-EnvironmentDiagnose {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  环境诊断报告" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # 1. 系统基础信息
    Write-Host ""
    Write-Host "【系统信息】" -ForegroundColor White
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Host "  操作系统: $($os.Caption)"
        Write-Host "  版本号: $($os.Version)"
    }
    catch {
        Write-Host "  操作系统: 获取失败" -ForegroundColor Red
    }
    
    $arch = if ([Environment]::Is64BitOperatingSystem) { "64位" } else { "32位" }
    Write-Host "  系统架构: $arch"
    
    $admin = Test-AdminRights
    if ($admin) {
        Write-Host "  管理员权限: 已获取" -ForegroundColor Green
    }
    else {
        Write-Host "  管理员权限: 未获取" -ForegroundColor Red
    }
    
    Write-Host "  PowerShell 版本: $($PSVersionTable.PSVersion)"
    
    $staticConfig = Get-StaticConfig
    Write-Host "  工具版本: $($staticConfig.project.version)"
    
    # 2. 软件状态
    Write-Host ""
    Write-Host "【软件状态】" -ForegroundColor White
    $softStatus = Get-AllSoftwareStatus -ForceRefresh
    
    foreach ($soft in $softStatus) {
        $statusText = ""
        $statusColor = "White"
        
        switch ($soft.status) {
            "notInstalled" { $statusText = "未安装"; $statusColor = "DarkGray" }
            "latest" { $statusText = "最新"; $statusColor = "Green" }
            "updatable" { $statusText = "可更新"; $statusColor = "Yellow" }
            "error" { $statusText = "异常"; $statusColor = "Red" }
        }
        
        $line = "  [{0}] {1}" -f $statusText, $soft.name
        if ($soft.localVersion) {
            $line += " (本地: $($soft.localVersion)"
            if ($soft.latestVersion -and $soft.status -eq "updatable") {
                $line += " / 最新: $($soft.latestVersion)"
            }
            $line += ")"
        }
        
        Write-Host $line -ForegroundColor $statusColor
    }
    
    # 3. PowerShell 模块
    Write-Host ""
    Write-Host "【PowerShell 模块】" -ForegroundColor White
    $modules = @("Terminal-Icons", "posh-git")
    foreach ($mod in $modules) {
        $installed = Get-InstalledModule -Name $mod -ErrorAction SilentlyContinue
        if ($installed) {
            Write-Host "  [已安装] $mod v$($installed.Version)" -ForegroundColor Green
        }
        else {
            Write-Host "  [未安装] $mod" -ForegroundColor DarkGray
        }
    }
    
    # 4. 软链接状态
    Write-Host ""
    Write-Host "【软链接状态】" -ForegroundColor White
    $symlinks = Get-AllSymlinkStatus
    foreach ($link in $symlinks) {
        $envConfig = Get-EnvConfig
        $enabled = $envConfig[$link.switchKey] -eq $true
        
        if (-not $enabled) {
            Write-Host "  [未启用] $($link.id) (开关关闭)" -ForegroundColor DarkGray
            continue
        }
        
        if ($link.isSymlink) {
            Write-Host "  [正常] $($link.id)" -ForegroundColor Green
        }
        elseif ($link.exists) {
            Write-Host "  [异常] $($link.id) (真实目录/文件，非软链接)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [不存在] $($link.id)" -ForegroundColor Red
        }
    }
    
    # 5. 镜像源状态
    Write-Host ""
    Write-Host "【镜像源状态】" -ForegroundColor White
    $wingetSource = Get-WingetCurrentSource
    Write-Host "  WinGet 当前源: $wingetSource"
    
    $envConfig = Get-EnvConfig
    $ghMirror = $envConfig.GITHUB_MIRROR
    Write-Host "  GitHub 镜像: $ghMirror"
    
    $pkgMirror = $envConfig.ENABLE_PKG_MIRROR
    $pkgText = if ($pkgMirror) { "已启用" } else { "未启用" }
    Write-Host "  包管理器镜像: $pkgText"
    
    # 6. 关键目录检测
    Write-Host ""
    Write-Host "【关键目录】" -ForegroundColor White
    $dirs = @(
        "./profiles/vscode",
        "./profiles/omp-themes",
        "./profiles/windows-terminal",
        "./profiles/pwsh-data",
        "./logs"
    )
    foreach ($dir in $dirs) {
        if (Test-Path -Path $dir) {
            Write-Host "  [存在] $dir" -ForegroundColor Green
        }
        else {
            Write-Host "  [不存在] $dir" -ForegroundColor Yellow
        }
    }
    
    # 7. 最新日志预览
    Write-Host ""
    Write-Host "【最新日志尾部】" -ForegroundColor White
    $logDir = "./logs"
    if (Test-Path -Path $logDir) {
        $latestLog = Get-ChildItem -Path $logDir -Filter "wde-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestLog) {
            Write-Host "  文件: $($latestLog.Name)"
            $lines = Get-Content -Path $latestLog.FullName -Tail 10
            foreach ($line in $lines) {
                Write-Host "    $line"
            }
        }
        else {
            Write-Host "  暂无日志文件" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  日志目录不存在" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

Export-ModuleMember -Function Invoke-EnvironmentDiagnose
