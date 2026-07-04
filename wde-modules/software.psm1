<#
.SYNOPSIS
WinDevEnv-Setup 软件全生命周期管理模块
#>

# 状态缓存
$script:StatusCache = $null
$script:CacheValid = $false

<#
.SYNOPSIS
获取所有软件配置列表
#>
function Get-SoftwareList {
    $config = Get-StaticConfig
    return $config.software
}

<#
.SYNOPSIS
解析版本号字符串，提取纯数字版本
#>
function Extract-VersionNumber {
    param([string]$RawOutput)
    
    if ([string]::IsNullOrEmpty($RawOutput)) {
        return $null
    }
    
    # 匹配 x.y.z 格式的版本号
    if ($RawOutput -match '(\d+\.\d+(\.\d+)*)') {
        return $matches[1]
    }
    return $null
}

<#
.SYNOPSIS
检测 winget 是否可用
#>
function Test-WingetAvailable {
    try {
        winget --version | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
获取单个软件的本地版本
#>
function Get-LocalSoftwareVersion {
    param([object]$Software)
    
    try {
        if ($Software.type -eq "winget" -or $Software.type -eq "windowsFeature") {
            if (-not [string]::IsNullOrEmpty($Software.versionCmd)) {
                $output = & cmd /c $Software.versionCmd 2`>`&1
                return Extract-VersionNumber -RawOutput ($output -join " ")
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
获取源上最新版本号
#>
function Get-LatestSoftwareVersion {
    param([object]$Software)
    
    try {
        if ($Software.type -ne "winget") {
            return $null
        }
        
        $output = winget show --id $Software.wingetId --source winget 2>&1
        $version = Extract-VersionNumber -RawOutput ($output -join " ")
        return $version
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
获取单个软件的完整状态
返回状态：notInstalled / latest / updatable / error
#>
function Get-SoftwareStatus {
    param([string]$SoftwareId)
    
    $allSoftware = Get-SoftwareList
    $software = $allSoftware | Where-Object { $_.id -eq $SoftwareId }
    if (-not $software) {
        return @{
            id = $SoftwareId
            status = "error"
            localVersion = $null
            latestVersion = $null
            message = "软件ID不存在"
        }
    }
    
    $localVer = Get-LocalSoftwareVersion -Software $software
    
    # 未安装
    if (-not $localVer) {
        return @{
            id = $SoftwareId
            name = $software.name
            status = "notInstalled"
            localVersion = $null
            latestVersion = $null
            isUpdateOnly = $software.isUpdateOnly
        }
    }
    
    # 已安装，查询最新版本
    $latestVer = Get-LatestSoftwareVersion -Software $software
    
    if (-not $latestVer) {
        return @{
            id = $SoftwareId
            name = $software.name
            status = "latest"
            localVersion = $localVer
            latestVersion = $localVer
            isUpdateOnly = $software.isUpdateOnly
            message = "无法获取最新版本"
        }
    }
    
    $compare = Compare-Version -VersionA $localVer -VersionB $latestVer
    
    if ($compare -ge 0) {
        $status = "latest"
    }
    else {
        $status = "updatable"
    }
    
    return @{
        id = $SoftwareId
        name = $software.name
        status = $status
        localVersion = $localVer
        latestVersion = $latestVer
        isUpdateOnly = $software.isUpdateOnly
    }
}

<#
.SYNOPSIS
获取所有软件状态，带缓存机制
#>
function Get-AllSoftwareStatus {
    param([switch]$ForceRefresh)
    
    if ($script:CacheValid -and -not $ForceRefresh -and $script:StatusCache) {
        return $script:StatusCache
    }
    
    if (-not (Test-WingetAvailable)) {
        Write-LogWarn -Message "winget 不可用，软件状态检测受限"
    }
    
    $allSoftware = Get-SoftwareList
    $result = @()
    
    foreach ($soft in $allSoftware) {
        $status = Get-SoftwareStatus -SoftwareId $soft.id
        $result += $status
    }
    
    $script:StatusCache = $result
    $script:CacheValid = $true
    return $result
}

<#
.SYNOPSIS
清空状态缓存
#>
function Clear-SoftwareStatusCache {
    $script:CacheValid = $false
    $script:StatusCache = $null
}

# 导出模块成员
Export-ModuleMember -Function Get-SoftwareList, Get-SoftwareStatus, Get-AllSoftwareStatus, Clear-SoftwareStatusCache, Test-WingetAvailable
