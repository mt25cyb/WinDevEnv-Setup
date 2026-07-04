<#
.SYNOPSIS
WinDevEnv-Setup 通用工具核心模块
#>

<#
.SYNOPSIS
检测当前是否为管理员权限
#>
function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
UAC 自动提权，非管理员则拉起高权限窗口
#>
function Invoke-UacElevation {
    param([string]$ScriptPath)

    if (Test-AdminRights) {
        return $true
    }

    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        # 优先尝试 PowerShell 7
        $pwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshPath) {
            Start-Process -FilePath pwsh.exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
            exit
        }
        
        # 降级使用 PowerShell 5.1
        Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
        exit
    }
    catch {
        Write-Host "提权失败，请右键选择「以管理员身份运行」此脚本" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
从注册表刷新当前会话的 PATH 环境变量
#>
function Update-EnvironmentPath {
    $machineKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Session Manager\Environment")
    $machinePath = $machineKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    
    $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment")
    $userPath = $userKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    
    $env:PATH = "$machinePath;$userPath"
    Write-LogInfo -Message "已刷新系统 PATH 环境变量"
}

<#
.SYNOPSIS
通用重试函数
#>
function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 2,
        [int]$RetryIntervalSeconds = 2,
        [string]$OperationName = "操作"
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $attempt++
            Write-LogInfo -Message ("执行{0}，第 {1} 次尝试" -f $OperationName, $attempt)
            & $ScriptBlock
            return $true
        }
        catch {
            Write-LogWarn -Message ("{0} 第 {1} 次失败: {2}" -f $OperationName, $attempt, $_.Exception.Message)
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryIntervalSeconds
            }
        }
    }

    Write-LogError -Message ("{0} 累计失败 {1} 次，已放弃" -f $OperationName, $MaxRetries)
    return $false
}

<#
.SYNOPSIS
版本号比对，返回 -1/0/1
#>
function Compare-Version {
    param(
        [string]$VersionA,
        [string]$VersionB
    )

    try {
        $verA = [version]$VersionA
        $verB = [version]$VersionB
        return $verA.CompareTo($verB)
    }
    catch {
        Write-LogWarn -Message ("版本号解析失败: {0} / {1}" -f $VersionA, $VersionB)
        return 0
    }
}

# 导出模块成员
Export-ModuleMember -Function Test-AdminRights, Invoke-UacElevation, Update-EnvironmentPath, Invoke-WithRetry, Compare-Version
