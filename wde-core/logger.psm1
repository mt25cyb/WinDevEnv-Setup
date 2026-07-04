<#
.SYNOPSIS
WinDevEnv-Setup 日志系统核心模块
#>

# 全局日志变量
$script:LogPath = $null
$script:LogRetentionDays = 30
$script:LogMinKeep = 3

<#
.SYNOPSIS
初始化日志系统
#>
function Initialize-Logger {
    param(
        [string]$LogDirectory = "./logs",
        [int]$RetentionDays = 30,
        [int]$MinKeep = 3
    )

    # 创建日志目录
    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $script:LogPath = Join-Path -Path $LogDirectory -ChildPath ("wde-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
    $script:LogRetentionDays = $RetentionDays
    $script:LogMinKeep = $MinKeep

    # 写入启动标记
    $logMsg = "[{0}] [INFO] 日志系统初始化完成" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $script:LogPath -Value $logMsg -Encoding UTF8

    # 清理过期日志
    Clear-ExpiredLogs
}

<#
.SYNOPSIS
写入 INFO 级别日志
#>
function Write-LogInfo {
    param([string]$Message)
    $logMsg = "[{0}] [INFO] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $script:LogPath -Value $logMsg -Encoding UTF8
    Write-Host $logMsg -ForegroundColor White
}

<#
.SYNOPSIS
写入 WARN 级别日志
#>
function Write-LogWarn {
    param([string]$Message)
    $logMsg = "[{0}] [WARN] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $script:LogPath -Value $logMsg -Encoding UTF8
    Write-Host $logMsg -ForegroundColor Yellow
}

<#
.SYNOPSIS
写入 ERROR 级别日志，捕获异常堆栈
#>
function Write-LogError {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )
    
    $logMsg = "[{0}] [ERROR] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $script:LogPath -Value $logMsg -Encoding UTF8
    Write-Host $logMsg -ForegroundColor Red

    if ($ErrorRecord) {
        $stackMsg = "[{0}] [ERROR] 异常堆栈: {1}`n行号: {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $ErrorRecord.ScriptStackTrace, $ErrorRecord.InvocationInfo.ScriptLineNumber
        Add-Content -Path $script:LogPath -Value $stackMsg -Encoding UTF8
        Write-Host $stackMsg -ForegroundColor DarkRed
    }
}

<#
.SYNOPSIS
清理过期日志文件，强制保留最近N个
#>
function Clear-ExpiredLogs {
    try {
        $logDir = Split-Path -Path $script:LogPath -Parent
        $logFiles = Get-ChildItem -Path $logDir -Filter "wde-*.log" | Sort-Object LastWriteTime -Descending

        if ($logFiles.Count -le $script:LogMinKeep) {
            return
        }

        $cutoffDate = (Get-Date).AddDays(-$script:LogRetentionDays)
        $removedCount = 0

        for ($i = $script:LogMinKeep; $i -lt $logFiles.Count; $i++) {
            $file = $logFiles[$i]
            if ($file.LastWriteTime -lt $cutoffDate) {
                Remove-Item -Path $file.FullName -Force
                $removedCount++
            }
        }

        if ($removedCount -gt 0) {
            Write-LogInfo -Message ("清理过期日志文件 {0} 个" -f $removedCount)
        }
    }
    catch {
        # 日志清理失败不影响主流程
    }
}

# 导出模块成员
Export-ModuleMember -Function Initialize-Logger, Write-LogInfo, Write-LogWarn, Write-LogError, Clear-ExpiredLogs
