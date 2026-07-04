<#
.SYNOPSIS
WinDevEnv-Setup 终端美化与配置管理模块
#>

$script:ThemeBasePath = "JanDeDobbeleer/oh-my-posh/main/themes/"

<#
.SYNOPSIS
获取当前选中的 GitHub 镜像前缀
#>
function Get-GithubMirrorPrefix {
    $envConfig = Get-EnvConfig
    $staticConfig = Get-StaticConfig
    $mirrorId = $envConfig.GITHUB_MIRROR
    
    $mirror = $staticConfig.mirrors.github | Where-Object { $_.id -eq $mirrorId }
    if (-not $mirror) {
        $mirror = $staticConfig.mirrors.github | Where-Object { $_.default -eq $true }
    }
    return $mirror.prefix
}

<#
.SYNOPSIS
安装指定 Nerd Font 字体
#>
function Install-OmpFont {
    param([string]$FontId = "JetBrainsMono")
    
    $staticConfig = Get-StaticConfig
    $font = $staticConfig.fonts | Where-Object { $_.id -eq $FontId }
    
    if (-not $font) {
        Write-LogError -Message ("字体ID不存在: {0}" -f $FontId)
        return $false
    }
    
    Write-LogInfo -Message ("开始安装字体: {0}" -f $font.name)
    
    $success = Invoke-WithRetry -ScriptBlock {
        oh-my-posh font install $font.installName --yes 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        throw "字体安装退出码: $LASTEXITCODE"
    } -MaxRetries 2 -OperationName "安装字体 $($font.name)"
    
    if ($success) {
        Write-LogInfo -Message ("字体 {0} 安装成功" -f $font.name)
        return $true
    }
    else {
        Write-LogError -Message ("字体 {0} 安装失败" -f $font.name)
        return $false
    }
}

<#
.SYNOPSIS
下载单个主题文件，镜像优先，失败降级原生地址
#>
function Download-ThemeFile {
    param(
        [string]$FileName,
        [string]$SavePath
    )
    
    $mirrorPrefix = Get-GithubMirrorPrefix
    $rawUrl = "https://raw.githubusercontent.com/" + $script:ThemeBasePath + $FileName
    $mirrorUrl = $mirrorPrefix + $script:ThemeBasePath + $FileName
    
    $saveDir = Split-Path -Path $SavePath -Parent
    if (-not (Test-Path -Path $saveDir)) {
        New-Item -Path $saveDir -ItemType Directory -Force | Out-Null
    }
    
    # 优先镜像下载
    $success = Invoke-WithRetry -ScriptBlock {
        Invoke-WebRequest -Uri $mirrorUrl -OutFile $SavePath -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        return $true
    } -MaxRetries 1 -OperationName "镜像下载主题 $FileName"
    
    if ($success) {
        Write-LogInfo -Message ("主题 {0} 下载成功（镜像源）" -f $FileName)
        return $true
    }
    
    # 降级原生地址
    Write-LogWarn -Message "镜像下载失败，降级使用原生 GitHub 地址"
    $success = Invoke-WithRetry -ScriptBlock {
        Invoke-WebRequest -Uri $rawUrl -OutFile $SavePath -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        return $true
    } -MaxRetries 1 -OperationName "原生下载主题 $FileName"
    
    if ($success) {
        Write-LogInfo -Message ("主题 {0} 下载成功（原生源）" -f $FileName)
        return $true
    }
    else {
        Write-LogError -Message ("主题 {0} 下载失败，已跳过" -f $FileName)
        return $false
    }
}

<#
.SYNOPSIS
按需下载主题：本地不存在才下载
#>
function Install-OmpTheme {
    param([string]$ThemeId)
    
    $staticConfig = Get-StaticConfig
    $theme = $staticConfig.themes | Where-Object { $_.id -eq $ThemeId }
    
    if (-not $theme) {
        Write-LogError -Message ("主题ID不存在: {0}" -f $ThemeId)
        return $false
    }
    
    $envConfig = Get-EnvConfig
    $themeDir = "./profiles/omp-themes"
    $savePath = Join-Path -Path $themeDir -ChildPath $theme.fileName
    
    if (Test-Path -Path $savePath) {
        Write-LogInfo -Message ("主题 {0} 已存在，跳过下载" -f $ThemeId)
        return $true
    }
    
    return Download-ThemeFile -FileName $theme.fileName -SavePath $savePath
}

<#
.SYNOPSIS
获取主题本地路径
#>
function Get-ThemeLocalPath {
    param([string]$ThemeId)
    
    $staticConfig = Get-StaticConfig
    $theme = $staticConfig.themes | Where-Object { $_.id -eq $ThemeId }
    if (-not $theme) { return $null }
    
    return [System.IO.Path]::GetFullPath((Join-Path -Path "./profiles/omp-themes" -ChildPath $theme.fileName))
}

<#
.SYNOPSIS
安装 PowerShell 美化模块
#>
function Install-PsModules {
    $envConfig = Get-EnvConfig
    
    # 信任 PSGallery
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Scope CurrentUser -ErrorAction Stop
    }
    catch {
        Write-LogWarn -Message "PSGallery 信任设置失败，安装模块可能需要手动确认"
    }
    
    # Terminal-Icons 与 oh-my-posh 绑定
    if ($envConfig.ENABLE_TERMINAL_ICONS -eq $true) {
        Write-LogInfo -Message "安装 Terminal-Icons 模块"
        try {
            Install-Module Terminal-Icons -Scope CurrentUser -Force -ErrorAction Stop
            Write-LogInfo -Message "Terminal-Icons 安装成功"
        }
        catch {
            Write-LogError -Message "Terminal-Icons 安装失败" -ErrorRecord $_
        }
    }
    
    # posh-git 依赖 Git + oh-my-posh
    if ($envConfig.ENABLE_POSH_GIT -eq $true) {
        $gitStatus = Get-SoftwareStatus -SoftwareId "GIT"
        $ompStatus = Get-SoftwareStatus -SoftwareId "OH_MY_POSH"
        
        if ($gitStatus.status -ne "notInstalled" -and $ompStatus.status -ne "notInstalled") {
            Write-LogInfo -Message "安装 posh-git 模块"
            try {
                Install-Module posh-git -Scope CurrentUser -Force -ErrorAction Stop
                Write-LogInfo -Message "posh-git 安装成功"
            }
            catch {
                Write-LogError -Message "posh-git 安装失败" -ErrorRecord $_
            }
        }
        else {
            Write-LogWarn -Message "Git 或 Oh My Posh 未安装，跳过 posh-git 安装"
        }
    }
}

<#
.SYNOPSIS
生成标准化 PS 配置内容（区分版本）
#>
function Get-StandardPsProfile {
    param([int]$PsVersion = 5)
    
    $themeId = (Get-EnvConfig).OMP_DEFAULT_THEME
    $themePath = Get-ThemeLocalPath -ThemeId $themeId
    
    $lines = @()
    $lines += "# ========== WinDevEnv-Setup 托管配置 =========="
    $lines += ""
    $lines += "# 1. Oh My Posh 初始化"
    $lines += "oh-my-posh init pwsh --config `"$themePath`" | Invoke-Expression"
    $lines += ""
    $lines += "# 2. PSReadLine 历史与补全"
    $lines += "Import-Module PSReadLine"
    $lines += "Set-PSReadLineOption -HistorySearchCursorMovesToEnd"
    $lines += "Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward"
    $lines += "Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward"
    $lines += "Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete"
    
    if ($PsVersion -ge 7) {
        $lines += "Set-PSReadLineOption -PredictionSource History"
        $lines += "Set-PSReadLineOption -PredictionViewStyle ListView"
    }
    else {
        $lines += "Set-PSReadLineOption -PredictionSource History"
    }
    
    $lines += ""
    $lines += "# 3. 终端图标与 Git 集成"
    $lines += "Import-Module Terminal-Icons -ErrorAction SilentlyContinue"
    $lines += "Import-Module posh-git -ErrorAction SilentlyContinue"
    $lines += ""
    $lines += "# 4. 常用别名"
    $lines += "Set-Alias ll Get-ChildItem"
    $lines += "Set-Alias which Get-Command"
    $lines += "Set-Alias grep Select-String"
    $lines += ""
    $lines += "# ========== 用户自定义区域开始 =========="
    $lines += "# 在此处添加您的自定义配置，更新工具不会覆盖此区域"
    $lines += "# ========== 用户自定义区域结束 =========="
    
    return $lines -join "`r`n"
}

<#
.SYNOPSIS
写入托管标记块（非软链接模式使用）
#>
function Set-ManagedProfileBlock {
    param(
        [string]$ProfilePath,
        [int]$PsVersion = 5
    )
    
    $startMarker = "# >>> WinDevEnv-Setup Managed Start >>>"
    $endMarker = "# <<< WinDevEnv-Setup Managed End <<<"
    $content = Get-StandardPsProfile -PsVersion $PsVersion
    
    # 确保目录存在
    $profileDir = Split-Path -Path $ProfilePath -Parent
    if (-not (Test-Path -Path $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    
    if (Test-Path -Path $ProfilePath) {
        $existing = Get-Content -Path $ProfilePath -Raw -Encoding UTF8
    }
    else {
        $existing = ""
    }
    
    # 移除旧的托管块
    $regex = [regex]::new([regex]::Escape($startMarker) + "[\s\S]*?" + [regex]::Escape($endMarker), [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $existing = $regex.Replace($existing, "")
    $existing = $existing.Trim()
    
    # 追加新托管块
    $newContent = @(
        $startMarker,
        $content,
        $endMarker,
        "",
        $existing
    ) -join "`r`n"
    
    Set-Content -Path $ProfilePath -Value $newContent -Encoding UTF8
    Write-LogInfo -Message ("已更新配置文件: {0}" -f $ProfilePath)
}

<#
.SYNOPSIS
移除托管标记块
#>
function Remove-ManagedProfileBlock {
    param([string]$ProfilePath)
    
    if (-not (Test-Path -Path $ProfilePath)) {
        return
    }
    
    $startMarker = "# >>> WinDevEnv-Setup Managed Start >>>"
    $endMarker = "# <<< WinDevEnv-Setup Managed End <<<"
    
    $content = Get-Content -Path $ProfilePath -Raw -Encoding UTF8
    $regex = [regex]::new([regex]::Escape($startMarker) + "[\s\S]*?" + [regex]::Escape($endMarker) + "`r?`n?", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $content = $regex.Replace($content, "").Trim()
    
    Set-Content -Path $ProfilePath -Value $content -Encoding UTF8
    Write-LogInfo -Message ("已移除托管配置: {0}" -f $ProfilePath)
}

<#
.SYNOPSIS
应用 PowerShell 双版本配置（自动判断软链接模式）
#>
function Apply-PsProfileConfig {
    $envConfig = Get-EnvConfig
    $usePortable = $envConfig.ENABLE_PWSH_PROFILE_PORTABLE -eq $true
    
    $profile5 = [System.Environment]::ExpandEnvironmentVariables("%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    $profile7 = [System.Environment]::ExpandEnvironmentVariables("%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1")
    $source5 = "./profiles/pwsh-data/Microsoft.PowerShell_profile_5.ps1"
    $source7 = "./profiles/pwsh-data/Microsoft.PowerShell_profile_7.ps1"
    
    if ($usePortable) {
        Write-LogInfo -Message "便携化模式：写入源配置文件"
        # 确保源目录存在
        $sourceDir = Split-Path -Path $source5 -Parent
        if (-not (Test-Path -Path $sourceDir)) {
            New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
        }
        # 写入源文件
        Set-Content -Path $source5 -Value (Get-StandardPsProfile -PsVersion 5) -Encoding UTF8
        Set-Content -Path $source7 -Value (Get-StandardPsProfile -PsVersion 7) -Encoding UTF8
    }
    else {
        Write-LogInfo -Message "传统模式：写入系统侧托管块"
        Set-ManagedProfileBlock -ProfilePath $profile5 -PsVersion 5
        Set-ManagedProfileBlock -ProfilePath $profile7 -PsVersion 7
    }
    
    Write-LogInfo -Message "PowerShell 双版本配置已应用"
}

# 导出模块成员
Export-ModuleMember -Function Install-OmpFont, Install-OmpTheme, Get-ThemeLocalPath
Export-ModuleMember -Function Install-PsModules, Apply-PsProfileConfig, Remove-ManagedProfileBlock
