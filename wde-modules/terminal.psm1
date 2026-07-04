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

# 导出模块成员
Export-ModuleMember -Function Install-OmpFont, Install-OmpTheme, Get-ThemeLocalPath
