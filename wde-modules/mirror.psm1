<#
.SYNOPSIS
WinDevEnv-Setup 镜像源管理模块
#>

<#
.SYNOPSIS
获取当前 WinGet 源地址
#>
function Get-WingetCurrentSource {
    try {
        $output = winget source list 2>&1
        foreach ($line in $output) {
            if ($line -match '^winget\s+(\S+)') {
                return $matches[1]
            }
        }
        return $null
    }
    catch {
        Write-LogError -Message "获取WinGet源失败" -ErrorRecord $_
        return $null
    }
}

<#
.SYNOPSIS
切换 WinGet 源到指定镜像
#>
function Switch-WingetSource {
    param([string]$MirrorId)
    
    $staticConfig = Get-StaticConfig
    $mirror = $staticConfig.mirrors.winget | Where-Object { $_.id -eq $MirrorId }
    
    if (-not $mirror) {
        Write-LogError -Message "WinGet镜像ID不存在: $MirrorId"
        return $false
    }
    
    Write-LogInfo -Message "切换WinGet源到: $($mirror.name)"
    
    try {
        winget source remove winget --accept-source-agreements 2>&1 | Out-Null
        winget source add --name winget --arg $mirror.url --type Microsoft.WinGet.Source --accept-source-agreements 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Clear-SoftwareStatusCache
            Write-LogInfo -Message "WinGet源切换成功: $($mirror.name)"
            return $true
        }
        else {
            throw "退出码: $LASTEXITCODE"
        }
    }
    catch {
        Write-LogError -Message "WinGet源切换失败" -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
重置 WinGet 源为官方源
#>
function Reset-WingetSource {
    return Switch-WingetSource -MirrorId "official"
}

<#
.SYNOPSIS
切换 GitHub 镜像
#>
function Switch-GithubMirror {
    param([string]$MirrorId)
    
    $staticConfig = Get-StaticConfig
    $mirror = $staticConfig.mirrors.github | Where-Object { $_.id -eq $MirrorId }
    
    if (-not $mirror) {
        Write-LogError -Message "GitHub镜像ID不存在: $MirrorId"
        return $false
    }
    
    Set-EnvConfigItem -Key "GITHUB_MIRROR" -Value $MirrorId
    Write-LogInfo -Message "GitHub镜像已切换为: $($mirror.name)"
    return $true
}

<#
.SYNOPSIS
配置 npm 国内镜像
#>
function Enable-NpmMirror {
    $npmStatus = Get-SoftwareStatus -SoftwareId "NODEJS"
    if ($npmStatus.status -eq "notInstalled") {
        Write-LogWarn -Message "Node.js 未安装，跳过npm镜像配置"
        return $false
    }
    
    try {
        npm config set registry https://registry.npmmirror.com
        Write-LogInfo -Message "npm 镜像已配置为淘宝源"
        return $true
    }
    catch {
        Write-LogError -Message "npm镜像配置失败" -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
配置 pip 国内镜像
#>
function Enable-PipMirror {
    $pythonStatus = Get-SoftwareStatus -SoftwareId "PYTHON"
    if ($pythonStatus.status -eq "notInstalled") {
        Write-LogWarn -Message "Python 未安装，跳过pip镜像配置"
        return $false
    }
    
    try {
        pip config set global.index-url https://pypi.mirrors.ustc.edu.cn/simple/
        Write-LogInfo -Message "pip 镜像已配置为中科大源"
        return $true
    }
    catch {
        Write-LogError -Message "pip镜像配置失败" -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
根据配置自动应用包管理器镜像
#>
function Apply-PackageManagerMirrors {
    $envConfig = Get-EnvConfig
    if ($envConfig.ENABLE_PKG_MIRROR -ne $true) {
        return
    }
    
    Write-LogInfo -Message "开始配置包管理器镜像"
    Enable-NpmMirror | Out-Null
    Enable-PipMirror | Out-Null
}

# 导出模块成员
Export-ModuleMember -Function Get-WingetCurrentSource, Switch-WingetSource, Reset-WingetSource, Switch-GithubMirror, Enable-NpmMirror, Enable-PipMirror, Apply-PackageManagerMirrors
