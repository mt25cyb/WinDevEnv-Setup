<#
.SYNOPSIS
WinDevEnv-Setup 主入口脚本
.DESCRIPTION
Windows 开发环境一键部署工具
#>

#Requires -Version 5.1

# ========== 全局初始化 ==========
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 获取脚本所在目录
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $ScriptRoot

# ========== 模块导入 ==========
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-core/common.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-core/logger.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-core/config.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-core/topology.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-core/symlink.psm1") -Force

# ========== 启动前置检查 ==========
# UAC 提权
if (-not (Test-AdminRights)) {
    Write-Host "检测到非管理员权限，正在请求提权..." -ForegroundColor Yellow
    $elevated = Invoke-UacElevation -ScriptPath $MyInvocation.MyCommand.Path
    if (-not $elevated) {
        Read-Host "按回车键退出"
        exit 1
    }
}

# 初始化日志
$envConfig = Import-EnvConfig
$logDays = [int]$envConfig.LOG_RETENTION_DAYS
$logMinKeep = [int]$envConfig.LOG_MIN_KEEP
Initialize-Logger -LogDirectory "./logs" -RetentionDays $logDays -MinKeep $logMinKeep

Write-LogInfo -Message "========================================"
Write-LogInfo -Message "WinDevEnv-Setup 启动"
Write-LogInfo -Message "脚本目录: $ScriptRoot"
Write-LogInfo -Message "管理员权限: 已获取"

# 加载静态配置
$staticConfig = Import-StaticConfig
if ($null -eq $staticConfig) {
    Write-LogError -Message "静态配置加载失败，程序退出"
    Read-Host "按回车键退出"
    exit 1
}

# ========== 主菜单循环 ==========
function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  WinDevEnv-Setup v$($staticConfig.project.version)" -ForegroundColor Cyan
    Write-Host "  Windows 开发环境一键部署工具" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. 一键安装开发环境"
    Write-Host "  2. 软件管理"
    Write-Host "  3. 终端美化配置"
    Write-Host "  4. 镜像源管理"
    Write-Host "  5. 便携化软链接管理"
    Write-Host "  6. 环境诊断"
    Write-Host "  7. 配置管理"
    Write-Host "  8. 全局重置"
    Write-Host "  0. 退出"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

# 主循环
do {
    Show-MainMenu
    $choice = Read-Host "请输入选项编号"

    switch ($choice) {
        "0" {
            Write-LogInfo -Message "用户退出程序"
            break
        }
        "1" {
            Write-Host "`n[开发中] 一键安装功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "2" {
            Write-Host "`n[开发中] 软件管理功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "3" {
            Write-Host "`n[开发中] 终端美化功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "4" {
            Write-Host "`n[开发中] 镜像源管理功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "5" {
            Write-Host "`n[开发中] 软链接管理功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "6" {
            Write-Host "`n[开发中] 环境诊断功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "7" {
            Write-Host "`n[开发中] 配置管理功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        "8" {
            Write-Host "`n[开发中] 全局重置功能将在后续版本实现" -ForegroundColor Yellow
            Read-Host "`n按回车键返回菜单"
        }
        default {
            Write-Host "`n无效选项，请重新输入" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }

} while ($choice -ne "0")

Write-Host "`n感谢使用 WinDevEnv-Setup，再见！" -ForegroundColor Green
Start-Sleep -Seconds 1
