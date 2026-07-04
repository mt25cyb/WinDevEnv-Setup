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

Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-modules/software.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-modules/terminal.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-modules/mirror.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-modules/diagnose.psm1") -Force
Import-Module (Join-Path -Path $ScriptRoot -ChildPath "wde-modules/reset.psm1") -Force

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

# ========== 子菜单函数 ==========
function Show-SoftwareMenu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  软件管理" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 批量安装启用的软件"
        Write-Host "  2. 批量卸载启用的软件"
        Write-Host "  3. 批量更新所有软件"
        Write-Host "  4. 查看所有软件状态"
        Write-Host "  5. 单个软件操作"
        Write-Host "  0. 返回主菜单"
        Write-Host ""
        $choice = Read-Host "请输入选项编号"

        switch ($choice) {
            "0" { break }
            "1" {
                Write-Host ""
                Install-EnabledSoftware
                Read-Host "`n按回车键返回"
            }
            "2" {
                Write-Host ""
                $confirm = Read-Host "确认批量卸载所有启用的软件？(y/n)"
                if ($confirm -eq "y" -or $confirm -eq "Y") {
                    Uninstall-EnabledSoftware
                }
                Read-Host "`n按回车键返回"
            }
            "3" {
                Write-Host ""
                Update-AllSoftware
                Read-Host "`n按回车键返回"
            }
            "4" {
                Write-Host ""
                $status = Get-AllSoftwareStatus -ForceRefresh
                foreach ($s in $status) {
                    Write-Host "  [$($s.status)] $($s.name) 本地: $($s.localVersion) 最新: $($s.latestVersion)"
                }
                Read-Host "`n按回车键返回"
            }
            "5" {
                Show-SingleSoftwareMenu
            }
            default {
                Write-Host "无效选项" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

function Show-SingleSoftwareMenu {
    $softList = Get-SoftwareList
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  单个软件操作" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        for ($i=0; $i -lt $softList.Count; $i++) {
            Write-Host "  $($i+1). $($softList[$i].name)"
        }
        Write-Host "  0. 返回上一级"
        Write-Host ""
        $num = Read-Host "请选择软件编号"
        
        if ($num -eq "0") { break }
        $idx = [int]$num - 1
        if ($idx -lt 0 -or $idx -ge $softList.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        $soft = $softList[$idx]
        Write-Host ""
        Write-Host "选中: $($soft.name)"
        Write-Host "  1. 安装"
        Write-Host "  2. 卸载"
        Write-Host "  3. 更新"
        Write-Host "  4. 查看状态"
        Write-Host "  0. 返回"
        $op = Read-Host "请选择操作"
        
        switch ($op) {
            "1" { Install-Software -SoftwareId $soft.id; Read-Host "`n按回车键返回" }
            "2" { Uninstall-Software -SoftwareId $soft.id; Read-Host "`n按回车键返回" }
            "3" { Update-Software -SoftwareId $soft.id; Read-Host "`n按回车键返回" }
            "4" { 
                $s = Get-SoftwareStatus -SoftwareId $soft.id
                Write-Host "状态: $($s.status)"
                Write-Host "本地版本: $($s.localVersion)"
                Write-Host "最新版本: $($s.latestVersion)"
                Read-Host "`n按回车键返回"
            }
            "0" { break }
            default { Write-Host "无效选项" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($num -ne "0")
}

function Show-TerminalMenu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  终端美化配置" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 安装字体"
        Write-Host "  2. 下载并应用主题"
        Write-Host "  3. 应用 PowerShell 配置"
        Write-Host "  4. 应用 Windows Terminal 配置"
        Write-Host "  5. 安装 PS 美化模块"
        Write-Host "  6. 一键应用全部美化"
        Write-Host "  0. 返回主菜单"
        Write-Host ""
        $choice = Read-Host "请输入选项编号"

        switch ($choice) {
            "0" { break }
            "1" {
                Write-Host ""
                $envConfig = Get-EnvConfig
                $fontId = $envConfig.OMP_FONT
                Install-OmpFont -FontId $fontId
                Read-Host "`n按回车键返回"
            }
            "2" {
                Show-ThemeSelector
            }
            "3" {
                Write-Host ""
                Apply-PsProfileConfig
                Read-Host "`n按回车键返回"
            }
            "4" {
                Write-Host ""
                Apply-WtConfig
                Read-Host "`n按回车键返回"
            }
            "5" {
                Write-Host ""
                Install-PsModules
                Read-Host "`n按回车键返回"
            }
            "6" {
                Write-Host ""
                $envConfig = Get-EnvConfig
                Install-OmpFont -FontId $envConfig.OMP_FONT
                Install-OmpTheme -ThemeId $envConfig.OMP_DEFAULT_THEME
                Install-PsModules
                Apply-PsProfileConfig
                Apply-WtConfig
                Write-Host "`n✅ 终端美化配置全部应用完成" -ForegroundColor Green
                Read-Host "`n按回车键返回"
            }
            default {
                Write-Host "无效选项" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

function Show-ThemeSelector {
    $themes = (Get-StaticConfig).themes
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  选择 Oh My Posh 主题" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        for ($i=0; $i -lt $themes.Count; $i++) {
            Write-Host "  $($i+1). $($themes[$i].id)"
        }
        Write-Host "  0. 返回上一级"
        Write-Host ""
        $num = Read-Host "请选择主题编号"
        
        if ($num -eq "0") { break }
        $idx = [int]$num - 1
        if ($idx -lt 0 -or $idx -ge $themes.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        $theme = $themes[$idx]
        Write-Host "`n开始下载并应用主题: $($theme.id)"
        $ok = Install-OmpTheme -ThemeId $theme.id
        if ($ok) {
            Set-EnvConfigItem -Key "OMP_DEFAULT_THEME" -Value $theme.id
            Apply-PsProfileConfig
            Write-Host "✅ 主题应用成功，重启终端后生效" -ForegroundColor Green
        }
        Read-Host "`n按回车键返回"
    } while ($num -ne "0")
}

function Show-MirrorMenu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  镜像源管理" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. WinGet 源切换"
        Write-Host "  2. GitHub 镜像切换"
        Write-Host "  3. 配置包管理器镜像"
        Write-Host "  0. 返回主菜单"
        Write-Host ""
        $choice = Read-Host "请输入选项编号"

        switch ($choice) {
            "0" { break }
            "1" {
                Show-WingetMirrorMenu
            }
            "2" {
                Show-GithubMirrorMenu
            }
            "3" {
                Write-Host ""
                Apply-PackageManagerMirrors
                Read-Host "`n按回车键返回"
            }
            default {
                Write-Host "无效选项" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

function Show-WingetMirrorMenu {
    $mirrors = (Get-StaticConfig).mirrors.winget
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  选择 WinGet 镜像源" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        $current = Get-WingetCurrentSource
        Write-Host "当前源: $current"
        Write-Host ""
        for ($i=0; $i -lt $mirrors.Count; $i++) {
            $tag = if ($mirrors[$i].default) { " [默认]" } else { "" }
            Write-Host "  $($i+1). $($mirrors[$i].name)$tag"
        }
        Write-Host "  0. 返回上一级"
        Write-Host ""
        $num = Read-Host "请选择编号"
        
        if ($num -eq "0") { break }
        $idx = [int]$num - 1
        if ($idx -lt 0 -or $idx -ge $mirrors.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        Switch-WingetSource -MirrorId $mirrors[$idx].id
        Read-Host "`n按回车键返回"
    } while ($num -ne "0")
}

function Show-GithubMirrorMenu {
    $mirrors = (Get-StaticConfig).mirrors.github
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  选择 GitHub 镜像" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        $envConfig = Get-EnvConfig
        Write-Host "当前: $($envConfig.GITHUB_MIRROR)"
        Write-Host ""
        for ($i=0; $i -lt $mirrors.Count; $i++) {
            $tag = if ($mirrors[$i].default) { " [默认]" } else { "" }
            Write-Host "  $($i+1). $($mirrors[$i].name)$tag"
        }
        Write-Host "  0. 返回上一级"
        Write-Host ""
        $num = Read-Host "请选择编号"
        
        if ($num -eq "0") { break }
        $idx = [int]$num - 1
        if ($idx -lt 0 -or $idx -ge $mirrors.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        Switch-GithubMirror -MirrorId $mirrors[$idx].id
        Read-Host "`n按回车键返回"
    } while ($num -ne "0")
}

function Show-SymlinkMenu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  便携化软链接管理" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 创建所有已启用的软链接"
        Write-Host "  2. 解除所有已启用的软链接"
        Write-Host "  3. 查看软链接状态"
        Write-Host "  0. 返回主菜单"
        Write-Host ""
        $choice = Read-Host "请输入选项编号"

        switch ($choice) {
            "0" { break }
            "1" {
                Write-Host ""
                New-EnabledSymlinks
                Read-Host "`n按回车键返回"
            }
            "2" {
                Write-Host ""
                Remove-EnabledSymlinks
                Read-Host "`n按回车键返回"
            }
            "3" {
                Write-Host ""
                $status = Get-AllSymlinkStatus
                foreach ($s in $status) {
                    $state = if ($s.isSymlink) { "正常" } elseif ($s.exists) { "异常(真实文件)" } else { "不存在" }
                    Write-Host "  [$state] $($s.id)"
                }
                Read-Host "`n按回车键返回"
            }
            default {
                Write-Host "无效选项" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

function Show-ConfigMenu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  配置管理" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. 可视化编辑配置项"
        Write-Host "  2. 打开配置文件"
        Write-Host "  3. 恢复默认配置"
        Write-Host "  0. 返回主菜单"
        Write-Host ""
        $choice = Read-Host "请输入选项编号"

        switch ($choice) {
            "0" { break }
            "1" {
                Show-ConfigEditor
            }
            "2" {
                Invoke-Item -Path "./WinDevEnv-Setup.env"
                Write-Host "已打开配置文件"
                Read-Host "`n按回车键返回"
            }
            "3" {
                $confirm = Read-Host "确认恢复默认配置？将覆盖当前配置(y/n)"
                if ($confirm -eq "y") {
                    Copy-Item -Path "./WinDevEnv-Setup.env.example" -Destination "./WinDevEnv-Setup.env" -Force
                    Write-Host "已恢复默认配置" -ForegroundColor Green
                }
                Read-Host "`n按回车键返回"
            }
            default {
                Write-Host "无效选项" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($choice -ne "0")
}

function Show-ConfigEditor {
    $envConfig = Get-EnvConfig
    $keys = $envConfig.Keys | Sort-Object
    do {
        Clear-Host
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  编辑配置项" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        for ($i=0; $i -lt $keys.Count; $i++) {
            $key = $keys[$i]
            $value = $envConfig[$key]
            Write-Host "  $($i+1). $key = $value"
        }
        Write-Host "  0. 返回上一级"
        Write-Host ""
        $num = Read-Host "选择要修改的配置编号"
        
        if ($num -eq "0") { break }
        $idx = [int]$num - 1
        if ($idx -lt 0 -or $idx -ge $keys.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
        
        $key = $keys[$idx]
        $currentValue = $envConfig[$key]
        Write-Host "`n当前值: $currentValue"
        
        # 布尔值快速切换
        if ($currentValue -is [bool]) {
            $newVal = -not $currentValue
            Set-EnvConfigItem -Key $key -Value $newVal.ToString().ToLower()
            Write-Host "已切换为: $newVal" -ForegroundColor Green
        }
        else {
            $newVal = Read-Host "请输入新值（留空取消）"
            if (-not [string]::IsNullOrEmpty($newVal)) {
                Set-EnvConfigItem -Key $key -Value $newVal
                Write-Host "已更新为: $newVal" -ForegroundColor Green
            }
        }
        
        # 刷新配置
        $envConfig = Get-EnvConfig
        $keys = $envConfig.Keys | Sort-Object
        Start-Sleep -Seconds 1
    } while ($num -ne "0")
}

function Invoke-OneClickInstall {
    Write-Host ""
    Write-Host "开始一键部署开发环境..." -ForegroundColor Cyan
    Write-Host ""
    
    Write-LogInfo -Message "=== 一键安装开始 ==="
    
    # 1. 安装软件
    Write-Host "[1/4] 安装软件组件..."
    Install-EnabledSoftware
    
    # 2. 终端美化
    Write-Host "`n[2/4] 配置终端美化..."
    $envConfig = Get-EnvConfig
    if ($envConfig.ENABLE_OH_MY_POSH -eq $true) {
        Install-OmpFont -FontId $envConfig.OMP_FONT
        Install-OmpTheme -ThemeId $envConfig.OMP_DEFAULT_THEME
        Install-PsModules
        Apply-PsProfileConfig
        Apply-WtConfig
    }
    
    # 3. 创建软链接
    Write-Host "`n[3/4] 创建便携化软链接..."
    New-EnabledSymlinks
    
    # 4. 包管理器镜像
    Write-Host "`n[4/4] 配置包管理器镜像..."
    Apply-PackageManagerMirrors
    
    Write-LogInfo -Message "=== 一键安装完成 ==="
    Write-Host "`n✅ 开发环境部署完成！" -ForegroundColor Green
    Write-Host "建议重启终端使所有配置生效"
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
            Invoke-OneClickInstall
            Read-Host "`n按回车键返回菜单"
        }
        "2" {
            Show-SoftwareMenu
        }
        "3" {
            Show-TerminalMenu
        }
        "4" {
            Show-MirrorMenu
        }
        "5" {
            Show-SymlinkMenu
        }
        "6" {
            Invoke-EnvironmentDiagnose
            Read-Host "`n按回车键返回菜单"
        }
        "7" {
            Show-ConfigMenu
        }
        "8" {
            Write-Host ""
            Write-Host "  1. 完全重置（卸载软件+清理配置）"
            Write-Host "  2. 仅清理配置"
            Write-Host "  0. 返回"
            $resetChoice = Read-Host "请选择重置模式"
            if ($resetChoice -eq "1") {
                Invoke-GlobalReset
            }
            elseif ($resetChoice -eq "2") {
                Invoke-GlobalReset -ConfigOnly
            }
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
