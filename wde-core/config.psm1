<#
.SYNOPSIS
WinDevEnv-Setup 配置解析核心模块
#>

$script:EnvConfig = @{}
$script:StaticConfig = $null
$script:EnvFilePath = "./WinDevEnv-Setup.env"
$script:ExampleEnvPath = "./WinDevEnv-Setup.env.example"
$script:StaticConfigPath = "./WinDevEnv-Setup.json"

<#
.SYNOPSIS
展开字符串中的系统环境变量
#>
function Expand-EnvironmentVariables {
    param([string]$InputString)
    return [System.Environment]::ExpandEnvironmentVariables($InputString)
}

<#
.SYNOPSIS
递归展开对象中的所有环境变量
#>
function Expand-ObjectVariables {
    param($InputObject)

    if ($InputObject -is [string]) {
        return Expand-EnvironmentVariables -InputString $InputString
    }
    elseif ($InputObject -is [PSCustomObject]) {
        $result = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $result[$prop.Name] = Expand-ObjectVariables -InputObject $prop.Value
        }
        return $result
    }
    elseif ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = Expand-ObjectVariables -InputObject $InputObject[$key]
        }
        return $result
    }
    elseif ($InputObject -is [array]) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += Expand-ObjectVariables -InputObject $item
        }
        return $result
    }
    else {
        return $InputObject
    }
}

<#
.SYNOPSIS
加载并解析 .env 配置文件
#>
function Import-EnvConfig {
    # 首次运行无.env则复制模板
    if (-not (Test-Path -Path $script:EnvFilePath)) {
        if (Test-Path -Path $script:ExampleEnvPath) {
            Copy-Item -Path $script:ExampleEnvPath -Destination $script:EnvFilePath -Force
            Write-LogInfo -Message "首次运行，已从模板生成配置文件 WinDevEnv-Setup.env"
        }
        else {
            Write-LogWarn -Message "未找到.env模板文件，使用默认配置"
            return @{}
        }
    }

    $config = @{}
    $lines = Get-Content -Path $script:EnvFilePath -Encoding UTF8

    foreach ($line in $lines) {
        $trimLine = $line.Trim()
        # 跳过注释和空行
        if ($trimLine.StartsWith("#") -or [string]::IsNullOrEmpty($trimLine)) {
            continue
        }
        # 分割键值对
        $splitIndex = $trimLine.IndexOf("=")
        if ($splitIndex -gt 0) {
            $key = $trimLine.Substring(0, $splitIndex).Trim()
            $value = $trimLine.Substring($splitIndex + 1).Trim()
            # 布尔值转换（不区分大小写）
            $valueLower = $value.ToLower()
            if ($valueLower -eq "true") { $config[$key] = $true }
            elseif ($valueLower -eq "false") { $config[$key] = $false }
            else { $config[$key] = $value }
        }
    }

    $script:EnvConfig = $config
    return $config
}

<#
.SYNOPSIS
获取当前 .env 配置（热更新，每次调用重新读取）
#>
function Get-EnvConfig {
    return Import-EnvConfig
}

<#
.SYNOPSIS
加载静态 JSON 配置
#>
function Import-StaticConfig {
    if (-not (Test-Path -Path $script:StaticConfigPath)) {
        Write-LogError -Message "静态配置文件不存在: $script:StaticConfigPath"
        return $null
    }

    try {
        $jsonContent = Get-Content -Path $script:StaticConfigPath -Raw -Encoding UTF8
        $config = $jsonContent | ConvertFrom-Json
        # 递归展开环境变量，PSCustomObject 转哈希表
        $script:StaticConfig = Expand-ObjectVariables -InputObject $config
        Write-LogInfo -Message "静态配置加载完成，版本: $($script:StaticConfig.project.version)"
        return $script:StaticConfig
    }
    catch {
        Write-LogError -Message "静态配置解析失败" -ErrorRecord $_
        return $null
    }
}

<#
.SYNOPSIS
获取已加载的静态配置
#>
function Get-StaticConfig {
    if ($null -eq $script:StaticConfig) {
        return Import-StaticConfig
    }
    return $script:StaticConfig
}

<#
.SYNOPSIS
更新 .env 配置项
#>
function Set-EnvConfigItem {
    param(
        [string]$Key,
        [string]$Value
    )

    if (-not (Test-Path -Path $script:EnvFilePath)) {
        Import-EnvConfig | Out-Null
    }

    $lines = Get-Content -Path $script:EnvFilePath -Encoding UTF8
    $found = $false
    $newLines = @()

    foreach ($line in $lines) {
        $trimLine = $line.Trim()
        if (-not $trimLine.StartsWith("#") -and $trimLine.IndexOf("=") -gt 0) {
            $currentKey = $trimLine.Substring(0, $trimLine.IndexOf("=")).Trim()
            if ($currentKey -eq $Key) {
                $newLines += ("{0}={1}" -f $Key, $Value)
                $found = $true
                continue
            }
        }
        $newLines += $line
    }

    if (-not $found) {
        $newLines += ("{0}={1}" -f $Key, $Value)
    }

    Set-Content -Path $script:EnvFilePath -Value $newLines -Encoding UTF8
    # 刷新内存配置
    Import-EnvConfig | Out-Null
}

# 导出模块成员
Export-ModuleMember -Function Import-EnvConfig, Get-EnvConfig, Import-StaticConfig, Get-StaticConfig, Set-EnvConfigItem, Expand-EnvironmentVariables
