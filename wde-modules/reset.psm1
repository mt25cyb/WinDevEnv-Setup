<#
.SYNOPSIS
WinDevEnv-Setup 全局重置模块
#>

<#
.SYNOPSIS
执行全局重置
.PARAMETER ConfigOnly
仅清理配置，不卸载软件
#>
function Invoke-GlobalReset {
    param([switch]$ConfigOnly)
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  全局重置警告" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    
    if ($ConfigOnly) {
        Write-Host "  当前模式：仅清理配置" -ForegroundColor Yellow
        Write-Host "  将执行："
        Write-Host "  1. 解除所有软链接"
        Write-Host "  2. 清理 PowerShell 托管配置"
        Write-Host "  3. 删除运行日志与临时文件"
        Write-Host "  4. 还原 .env 为默认模板"
        Write-Host "  * profiles 目录下的用户资产将完整保留"
    }
    else {
        Write-Host "  当前模式：完全重置" -ForegroundColor Red
        Write-Host "  将执行："
        Write-Host "  1. 卸载所有启用的软件组件"
        Write-Host "  2. 解除所有软链接"
        Write-Host "  3. 清理 PowerShell 托管配置"
        Write-Host "  4. 删除运行日志与临时文件"
        Write-Host "  5. 还原 .env 为默认模板"
        Write-Host "  * profiles 目录下的用户资产将完整保留"
    }
    
    Write-Host ""
    $confirm1 = Read-Host "第一次确认：输入「确认重置」继续，输入其他内容取消"
    if ($confirm1 -ne "确认重置") {
        Write-Host "已取消重置操作" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host ""
    $confirm2 = Read-Host "第二次确认：输入「我已知晓风险，确认执行重置」继续，输入其他内容取消"
    if ($confirm2 -ne "我已知晓风险，确认执行重置") {
        Write-Host "已取消重置操作" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host ""
    Write-LogWarn -Message "开始执行全局重置"
    
    try {
        # 1. 解除所有软链接
        Write-LogInfo -Message "步骤1/5：解除所有软链接"
        Remove-EnabledSymlinks
        
        # 2. 清理 PowerShell 托管配置
        Write-LogInfo -Message "步骤2/5：清理 PowerShell 托管配置"
        $profile5 = [System.Environment]::ExpandEnvironmentVariables("%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
        $profile7 = [System.Environment]::ExpandEnvironmentVariables("%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1")
        Remove-ManagedProfileBlock -ProfilePath $profile5
        Remove-ManagedProfileBlock -ProfilePath $profile7
        
        # 3. 卸载软件（非仅配置模式）
        if (-not $ConfigOnly) {
            Write-LogInfo -Message "步骤3/5：卸载所有启用的软件"
            Uninstall-EnabledSoftware
        }
        else {
            Write-LogInfo -Message "步骤3/5：跳过软件卸载（仅配置模式）"
        }
        
        # 4. 删除运行时日志与临时文件
        Write-LogInfo -Message "步骤4/5：清理运行时数据"
        if (Test-Path -Path "./logs") {
            Remove-Item -Path "./logs" -Recurse -Force
            Write-LogInfo -Message "已删除日志目录"
        }
        
        # 5. 还原 .env 配置
        Write-LogInfo -Message "步骤5/5：还原配置文件为默认模板"
        if (Test-Path -Path "./WinDevEnv-Setup.env") {
            $timestamp = Get-Date -Format "yyyyMMddHHmmss"
            $backupPath = "./WinDevEnv-Setup.env.backup_$timestamp"
            Copy-Item -Path "./WinDevEnv-Setup.env" -Destination $backupPath -Force
            Write-LogInfo -Message "已备份原配置文件: $backupPath"
        }
        
        if (Test-Path -Path "./WinDevEnv-Setup.env.example") {
            Copy-Item -Path "./WinDevEnv-Setup.env.example" -Destination "./WinDevEnv-Setup.env" -Force
            Write-LogInfo -Message "已还原为默认配置模板"
        }
        
        Write-LogInfo -Message "全局重置执行完成"
        Write-Host ""
        Write-Host "✅ 全局重置执行完成" -ForegroundColor Green
        Write-Host "用户资产目录 profiles 已完整保留"
        return $true
    }
    catch {
        Write-LogError -Message "全局重置执行失败" -ErrorRecord $_
        Write-Host "❌ 重置过程中出现错误，请查看日志详情" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function Invoke-GlobalReset
