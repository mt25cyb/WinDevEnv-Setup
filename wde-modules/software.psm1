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
<#
.SYNOPSIS
安装单个 winget 软件
#>
function Install-WingetSoftware {
    param(
        [object]$Software,
        [string]$CustomVersion = ""
    )
    
    $id = $Software.id
    $name = $Software.name
    
    Write-LogInfo -Message ("开始安装 {0}" -f $name)
    
    $cmdArgs = "install --id $($Software.wingetId) --source winget --silent --accept-package-agreements --accept-source-agreements"
    
    if (-not [string]::IsNullOrEmpty($Software.installArgs)) {
        $cmdArgs += " $($Software.installArgs)"
    }
    
    if (-not [string]::IsNullOrEmpty($CustomVersion)) {
        $cmdArgs += " --version $CustomVersion"
        Write-LogInfo -Message ("指定版本: {0}" -f $CustomVersion)
    }
    
    $success = Invoke-WithRetry -ScriptBlock {
        $result = winget $cmdArgs.Split(" ") 2>&1
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            return $true
        }
        throw "安装退出码: $LASTEXITCODE"
    } -MaxRetries 2 -OperationName "安装 $name"
    
    if ($success) {
        # 刷新环境变量
        Update-EnvironmentPath
        Clear-SoftwareStatusCache
        Write-LogInfo -Message ("{0} 安装成功" -f $name)
        return $true
    }
    else {
        Write-LogError -Message ("{0} 安装失败" -f $name)
        return $false
    }
}

<#
.SYNOPSIS
安装 Windows 功能组件（WSL2）
#>
function Install-WindowsFeature {
    param([object]$Software)
    
    $name = $Software.name
    Write-LogInfo -Message ("开始启用 {0} 相关系统功能" -f $name)
    
    $needReboot = $false
    
    foreach ($feature in $Software.features) {
        try {
            $featureInfo = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
            if ($featureInfo.State -eq "Enabled") {
                Write-LogInfo -Message ("功能 {0} 已启用" -f $feature)
                continue
            }
            
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) {
                $needReboot = $true
            }
            Write-LogInfo -Message ("功能 {0} 启用成功" -f $feature)
        }
        catch {
            Write-LogError -Message ("启用功能 {0} 失败" -f $feature) -ErrorRecord $_
            return $false
        }
    }
    
    # 执行后置命令
    if (-not [string]::IsNullOrEmpty($Software.postCommand)) {
        Write-LogInfo -Message "执行后置安装命令"
        try {
            cmd /c $Software.postCommand 2>&1 | Out-Null
        }
        catch {
            Write-LogWarn -Message "后置命令执行可能需要重启系统后生效"
        }
    }
    
    if ($Software.requireReboot -and $needReboot) {
        Write-LogWarn -Message ("{0} 安装完成，系统需要重启后才能完全生效" -f $name)
    }
    
    Clear-SoftwareStatusCache
    Update-EnvironmentPath
    return $true
}

<#
.SYNOPSIS
安装单个软件（统一入口）
#>
function Install-Software {
    param(
        [string]$SoftwareId,
        [string]$CustomVersion = ""
    )
    
    $allSoftware = Get-SoftwareList
    $software = $allSoftware | Where-Object { $_.id -eq $SoftwareId }
    
    if (-not $software) {
        Write-LogError -Message ("软件ID不存在: {0}" -f $SoftwareId)
        return $false
    }
    
    # 仅更新的软件跳过全新安装
    if ($software.isUpdateOnly) {
        Write-LogInfo -Message ("{0} 为仅更新组件，跳过全新安装" -f $software.name)
        return $true
    }
    
    # 检测是否已安装
    $status = Get-SoftwareStatus -SoftwareId $SoftwareId
    if ($status.status -ne "notInstalled") {
        Write-LogInfo -Message ("{0} 已安装，跳过安装步骤" -f $software.name)
        return $true
    }
    
    switch ($software.type) {
        "winget" {
            return Install-WingetSoftware -Software $software -CustomVersion $CustomVersion
        }
        "windowsFeature" {
            return Install-WindowsFeature -Software $software
        }
        default {
            Write-LogError -Message ("不支持的软件类型: {0}" -f $software.type)
            return $false
        }
    }
}

<#
.SYNOPSIS
批量安装所有启用的软件（拓扑排序）
#>
function Install-EnabledSoftware {
    $envConfig = Get-EnvConfig
    $allSoftware = Get-SoftwareList
    
    # 获取排序后的启用列表
    $sortedItems = Get-EnabledSortedItems -AllItems $allSoftware -EnableConfig $envConfig
    
    if ($sortedItems.Count -eq 0) {
        Write-LogWarn -Message "未检测到启用的软件组件，请检查.env配置"
        return
    }
    
    Write-LogInfo -Message ("共 {0} 个组件待安装，开始执行" -f $sortedItems.Count)
    
    $failedItems = @()
    $successItems = @()
    
    foreach ($item in $sortedItems) {
        # 检查硬依赖是否全部成功
        $hardDeps = $item.hardDependencies
        $depFailed = $false
        foreach ($dep in $hardDeps) {
            if ($failedItems -contains $dep) {
                Write-LogWarn -Message ("硬依赖 {0} 安装失败，跳过 {1}" -f $dep, $item.name)
                $failedItems += $item.id
                $depFailed = $true
                break
            }
        }
        if ($depFailed) { continue }
        
        # 获取自定义版本
        $versionKey = "{0}_VERSION" -f $item.id
        $customVer = ""
        if ($envConfig.ContainsKey($versionKey) -and -not [string]::IsNullOrEmpty($envConfig[$versionKey])) {
            $customVer = $envConfig[$versionKey]
        }
        
        # 执行安装
        $ok = Install-Software -SoftwareId $item.id -CustomVersion $customVer
        
        if ($ok) {
            $successItems += $item.id
        }
        else {
            $failedItems += $item.id
        }
    }
    
    Write-LogInfo -Message ("批量安装完成：成功 {0} 个，失败 {1} 个" -f $successItems.Count, $failedItems.Count)
    if ($failedItems.Count -gt 0) {
        Write-LogWarn -Message ("失败组件: {0}" -f ($failedItems -join ", "))
    }
}

<#
.SYNOPSIS
更新单个 winget 软件
#>
function Update-WingetSoftware {
    param([object]$Software)
    
    $name = $Software.name
    Write-LogInfo -Message ("开始更新 {0}" -f $name)
    
    $cmdArgs = "upgrade --id $($Software.wingetId) --source winget --silent --accept-package-agreements --accept-source-agreements"
    
    $success = Invoke-WithRetry -ScriptBlock {
        winget $cmdArgs.Split(" ") 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
            return $true
        }
        throw "更新退出码: $LASTEXITCODE"
    } -MaxRetries 2 -OperationName "更新 $name"
    
    if ($success) {
        Clear-SoftwareStatusCache
        Update-EnvironmentPath
        Write-LogInfo -Message ("{0} 更新成功" -f $name)
        return $true
    }
    else {
        Write-LogError -Message ("{0} 更新失败" -f $name)
        return $false
    }
}

<#
.SYNOPSIS
更新单个软件（统一入口）
#>
function Update-Software {
    param([string]$SoftwareId)
    
    $allSoftware = Get-SoftwareList
    $software = $allSoftware | Where-Object { $_.id -eq $SoftwareId }
    
    if (-not $software) {
        Write-LogError -Message ("软件ID不存在: {0}" -f $SoftwareId)
        return $false
    }
    
    # 检测状态
    $status = Get-SoftwareStatus -SoftwareId $SoftwareId
    if ($status.status -eq "notInstalled") {
        Write-LogWarn -Message ("{0} 未安装，无法更新" -f $software.name)
        return $false
    }
    if ($status.status -eq "latest") {
        Write-LogInfo -Message ("{0} 已是最新版本" -f $software.name)
        return $true
    }
    
    # Windows 功能不支持单独更新
    if ($software.type -eq "windowsFeature") {
        Write-LogInfo -Message ("{0} 为系统功能组件，无需单独更新" -f $software.name)
        return $true
    }
    
    switch ($software.type) {
        "winget" {
            return Update-WingetSoftware -Software $software
        }
        default {
            Write-LogError -Message ("不支持的软件类型: {0}" -f $software.type)
            return $false
        }
    }
}

<#
.SYNOPSIS
批量更新所有已安装且可更新的软件
#>
function Update-AllSoftware {
    $allStatus = Get-AllSoftwareStatus -ForceRefresh
    $updatable = $allStatus | Where-Object { $_.status -eq "updatable" }
    
    if ($updatable.Count -eq 0) {
        Write-LogInfo -Message "所有软件均为最新版本，无需更新"
        return
    }
    
    Write-LogInfo -Message ("共 {0} 个组件可更新，开始执行" -f $updatable.Count)
    
    $failedItems = @()
    $successItems = @()
    
    foreach ($item in $updatable) {
        $ok = Update-Software -SoftwareId $item.id
        
        if ($ok) {
            $successItems += $item.id
        }
        else {
            $failedItems += $item.id
        }
    }
    
    Write-LogInfo -Message ("批量更新完成：成功 {0} 个，失败 {1} 个" -f $successItems.Count, $failedItems.Count)
    if ($failedItems.Count -gt 0) {
        Write-LogWarn -Message ("失败组件: {0}" -f ($failedItems -join ", "))
    }
}

<#
.SYNOPSIS
配置 Docker Desktop WSL2 后端与镜像加速
#>
function Initialize-DockerConfig {
    Write-LogInfo -Message "开始配置 Docker Desktop 运行环境"
    
    $dockerSettingsPath = Join-Path -Path $env:APPDATA -ChildPath "Docker\settings.json"
    $daemonPath = Join-Path -Path $env:USERPROFILE -ChildPath ".docker\daemon.json"
    
    # 1. 开启 WSL2 后端
    try {
        if (Test-Path -Path $dockerSettingsPath) {
            $settings = Get-Content -Path $dockerSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $settings | Add-Member -MemberType NoteProperty -Name "wslEngineEnabled" -Value $true -Force
            $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $dockerSettingsPath -Encoding UTF8
            Write-LogInfo -Message "已启用 Docker WSL2 后端"
        }
        else {
            Write-LogWarn -Message "未找到 Docker 配置文件，将在首次启动后自动生成"
        }
    }
    catch {
        Write-LogError -Message "配置 Docker WSL2 后端失败" -ErrorRecord $_
    }
    
    # 2. 配置镜像加速
    try {
        $daemonDir = Split-Path -Path $daemonPath -Parent
        if (-not (Test-Path -Path $daemonDir)) {
            New-Item -Path $daemonDir -ItemType Directory -Force | Out-Null
        }
        
        $mirrors = @(
            "https://docker.mirrors.ustc.edu.cn",
            "https://hub-mirror.c.163.com"
        )
        
        if (Test-Path -Path $daemonPath) {
            $daemon = Get-Content -Path $daemonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $daemon.registryMirrors) {
                $daemon | Add-Member -MemberType NoteProperty -Name "registryMirrors" -Value @() -Force
            }
            foreach ($m in $mirrors) {
                if ($daemon.registryMirrors -notcontains $m) {
                    $daemon.registryMirrors += $m
                }
            }
        }
        else {
            $daemon = @{
                registryMirrors = $mirrors
            }
        }
        
        $daemon | ConvertTo-Json -Depth 10 | Set-Content -Path $daemonPath -Encoding UTF8
        Write-LogInfo -Message "已配置 Docker 国内镜像加速"
    }
    catch {
        Write-LogError -Message "配置 Docker 镜像加速失败" -ErrorRecord $_
    }
    
    Write-LogWarn -Message "Docker 配置已更新，重启 Docker Desktop 后生效"
}

# 导出模块成员
Export-ModuleMember -Function Get-SoftwareList, Get-SoftwareStatus, Get-AllSoftwareStatus, Clear-SoftwareStatusCache, Test-WingetAvailable
# 追加导出函数
Export-ModuleMember -Function Install-Software, Install-EnabledSoftware
Export-ModuleMember -Function Update-Software, Update-AllSoftware
Export-ModuleMember -Function Initialize-DockerConfig
