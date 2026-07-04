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

<#
.SYNOPSIS
获取 Windows Terminal 配置文件路径
#>
function Get-WtConfigPath {
    return [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json")
}

<#
.SYNOPSIS
配置 Windows Terminal 字体
#>
function Set-WtFontConfig {
    param([string]$FontName = "JetBrainsMono NF")
    
    $configPath = Get-WtConfigPath
    
    if (-not (Test-Path -Path $configPath)) {
        Write-LogWarn -Message "未找到 Windows Terminal 配置文件，将在首次启动后生成"
        return $false
    }
    
    try {
        # 备份原配置
        New-BackupItem -Path $configPath | Out-Null
        
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # 写入默认字体
        if (-not $config.profiles) {
            $config | Add-Member -MemberType NoteProperty -Name "profiles" -Value @{} -Force
        }
        if (-not $config.profiles.defaults) {
            $config.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value @{} -Force
        }
        if (-not $config.profiles.defaults.font) {
            $config.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value @{} -Force
        }
        
        $config.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value $FontName -Force
        
        $config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding UTF8
        Write-LogInfo -Message ("Windows Terminal 字体已设置为: {0}" -f $FontName)
        return $true
    }
    catch {
        Write-LogError -Message "Windows Terminal 配置修改失败" -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
迁移 WT 配置到便携源目录（软链接模式启用时执行）
#>
function Migrate-WtConfigToPortable {
    $sourceDir = "./profiles/windows-terminal"
    $systemDir = [System.Environment]::ExpandEnvironmentVariables("%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState")
    
    if (-not (Test-Path -Path $sourceDir)) {
        New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
    }
    
    # 系统侧有配置且源目录为空时，迁移过去
    if ((Test-Path -Path $systemDir) -and (Get-ChildItem -Path $sourceDir | Measure-Object).Count -eq 0) {
        Write-LogInfo -Message "迁移现有 Windows Terminal 配置到便携目录"
        Copy-Item -Path (Join-Path -Path $systemDir -ChildPath "*") -Destination $sourceDir -Recurse -Force
    }
}

<#
.SYNOPSIS
应用 Windows Terminal 完整配置（自动判断模式）
#>
function Apply-WtConfig {
    $envConfig = Get-EnvConfig
    $fontId = $envConfig.OMP_FONT
    
    $staticConfig = Get-StaticConfig
    $font = $staticConfig.fonts | Where-Object { $_.id -eq $fontId }
    if (-not $font) {
        $font = $staticConfig.fonts[0]
    }
    
    if ($envConfig.ENABLE_WT_PORTABLE -eq $true) {
        Migrate-WtConfigToPortable
        Write-LogInfo -Message "便携化模式：WT 配置已同步到源目录，软链接生效"
    }
    else {
        Set-WtFontConfig -FontName $font.name
    }
}

<#
.SYNOPSIS
检测 VSCode 是否正在运行
#>
function Test-VscodeRunning {
    $processes = Get-Process -Name Code -ErrorAction SilentlyContinue
    return $null -ne $processes
}

<#
.SYNOPSIS
初始化源目录/文件
#>
function Initialize-SymlinkSources {
    $staticConfig = Get-StaticConfig
    $envConfig = Get-EnvConfig
    
    foreach ($link in $staticConfig.symlinks) {
        $enabled = $envConfig[$link.switchKey] -eq $true
        if (-not $enabled) { continue }
        
        $source = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $link.source))
        
        if (-not (Test-Path -Path $source)) {
            if ($link.isFile) {
                $dir = Split-Path -Path $source -Parent
                if (-not (Test-Path -Path $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }
                New-Item -Path $source -ItemType File -Force | Out-Null
                Write-LogInfo -Message ("已创建源文件: {0}" -f $source)
            }
            else {
                New-Item -Path $source -ItemType Directory -Force | Out-Null
                Write-LogInfo -Message ("已创建源目录: {0}" -f $source)
            }
        }
    }
}

<#
.SYNOPSIS
创建所有已开启开关的软链接
#>
function New-EnabledSymlinks {
    $staticConfig = Get-StaticConfig
    $envConfig = Get-EnvConfig
    
    # VSCode 软链接前置检测
    if ($envConfig.ENABLE_VSCODE_PORTABLE -eq $true -and (Test-VscodeRunning)) {
        Write-LogWarn -Message "检测到 VSCode 正在运行，请关闭后再创建软链接，否则可能失败"
        return $false
    }
    
    Initialize-SymlinkSources
    
    $successCount = 0
    $failCount = 0
    
    foreach ($link in $staticConfig.symlinks) {
        $enabled = $envConfig[$link.switchKey] -eq $true
        if (-not $enabled) { continue }
        
        $target = [System.Environment]::ExpandEnvironmentVariables($link.target)
        $ok = New-Symlink -SourcePath $link.source -TargetPath $target -IsFile:$link.isFile
        
        if ($ok) {
            $successCount++
        }
        else {
            $failCount++
        }
    }
    
    Write-LogInfo -Message ("软链接批量创建完成：成功 {0} 个，失败 {1} 个" -f $successCount, $failCount)
    return $failCount -eq 0
}

<#
.SYNOPSIS
移除所有已开启开关的软链接，保留备份
#>
function Remove-EnabledSymlinks {
    $staticConfig = Get-StaticConfig
    $envConfig = Get-EnvConfig
    
    foreach ($link in $staticConfig.symlinks) {
        $enabled = $envConfig[$link.switchKey] -eq $true
        if (-not $enabled) { continue }
        
        $target = [System.Environment]::ExpandEnvironmentVariables($link.target)
        Remove-Symlink -Path $target
    }
    
    Write-LogInfo -Message "已解除所有启用的软链接"
}

<#
.SYNOPSIS
获取所有软链接状态
#>
function Get-AllSymlinkStatus {
    $staticConfig = Get-StaticConfig
    $result = @()
    
    foreach ($link in $staticConfig.symlinks) {
        $target = [System.Environment]::ExpandEnvironmentVariables($link.target)
        $state = Test-Symlink -Path $target
        $result += @{
            id = $link.id
            target = $target
            source = $link.source
            isFile = $link.isFile
            switchKey = $link.switchKey
            exists = $state.Exists
            isSymlink = $state.IsSymlink
            linkTarget = $state.Target
        }
    }
    
    return $result
}

# 导出模块成员
Export-ModuleMember -Function Install-OmpFont, Install-OmpTheme, Get-ThemeLocalPath
Export-ModuleMember -Function Install-PsModules, Apply-PsProfileConfig, Remove-ManagedProfileBlock
Export-ModuleMember -Function Apply-WtConfig, Set-WtFontConfig, Get-WtConfigPath
Export-ModuleMember -Function New-EnabledSymlinks, Remove-EnabledSymlinks, Get-AllSymlinkStatus, Initialize-SymlinkSources
