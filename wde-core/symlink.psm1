<#
.SYNOPSIS
WinDevEnv-Setup 软链接管理核心模块
#>

<#
.SYNOPSIS
检测路径是否为软链接/目录联接
#>
function Test-Symlink {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return @{
            Exists = $false
            IsSymlink = $false
            Target = $null
        }
    }

    try {
        $item = Get-Item -Path $Path -Force
        $isSymlink = $false
        $target = $null

        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $isSymlink = $true
            $target = $item.Target
        }

        return @{
            Exists = $true
            IsSymlink = $isSymlink
            Target = $target
            IsDirectory = $item.PSIsContainer
        }
    }
    catch {
        return @{
            Exists = $true
            IsSymlink = $false
            Target = $null
        }
    }
}

<#
.SYNOPSIS
创建备份，格式为 原名称.backup_时间戳
#>
function New-BackupItem {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return $true
    }

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = "{0}.backup_{1}" -f $Path, $timestamp

    try {
        if ((Get-Item -Path $Path -Force).PSIsContainer) {
            Copy-Item -Path $Path -Destination $backupPath -Recurse -Force
        }
        else {
            Copy-Item -Path $Path -Destination $backupPath -Force
        }
        Write-LogInfo -Message ("已备份原有文件/目录: {0} -> {1}" -f $Path, $backupPath)
        return $true
    }
    catch {
        Write-LogError -Message ("备份失败: {0}" -f $Path) -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
创建软链接，自动识别文件/目录类型
#>
function New-Symlink {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [switch]$IsFile
    )

    # 标准化绝对路径
    $SourcePath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $SourcePath))
    $TargetPath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $TargetPath))

    # 确保源存在
    if (-not (Test-Path -Path $SourcePath)) {
        if ($IsFile) {
            New-Item -Path $SourcePath -ItemType File -Force | Out-Null
        }
        else {
            New-Item -Path $SourcePath -ItemType Directory -Force | Out-Null
        }
        Write-LogInfo -Message ("已创建源路径: {0}" -f $SourcePath)
    }

    # 确保目标父目录存在
    $targetParent = Split-Path -Path $TargetPath -Parent
    if (-not (Test-Path -Path $targetParent)) {
        New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
    }

    # 检测目标状态
    $targetState = Test-Symlink -Path $TargetPath

    if ($targetState.Exists) {
        if ($targetState.IsSymlink) {
            # 已是软链接，删除旧链接
            Remove-Item -Path $TargetPath -Force
            Write-LogInfo -Message ("移除旧软链接: {0}" -f $TargetPath)
        }
        else {
            # 真实文件/目录，先备份再删除
            New-BackupItem -Path $TargetPath | Out-Null
            Remove-Item -Path $TargetPath -Recurse -Force
        }
    }

    # 创建软链接
    try {
        if ($IsFile) {
            cmd /c mklink "`"$TargetPath`"" "`"$SourcePath`"" | Out-Null
        }
        else {
            cmd /c mklink /j "`"$TargetPath`"" "`"$SourcePath`"" | Out-Null
        }

        $check = Test-Symlink -Path $TargetPath
        if ($check.IsSymlink) {
            Write-LogInfo -Message ("软链接创建成功: {0} -> {1}" -f $TargetPath, $SourcePath)
            return $true
        }
        else {
            Write-LogError -Message ("软链接创建失败: {0}" -f $TargetPath)
            return $false
        }
    }
    catch {
        Write-LogError -Message "软链接创建异常" -ErrorRecord $_
        return $false
    }
}

<#
.SYNOPSIS
移除软链接，不恢复备份
#>
function Remove-Symlink {
    param([string]$Path)

    $state = Test-Symlink -Path $Path
    if (-not $state.Exists -or -not $state.IsSymlink) {
        Write-LogInfo -Message ("路径不是软链接，无需移除: {0}" -f $Path)
        return $true
    }

    try {
        Remove-Item -Path $Path -Force
        Write-LogInfo -Message ("已移除软链接: {0}" -f $Path)
        return $true
    }
    catch {
        Write-LogError -Message ("移除软链接失败: {0}" -f $Path) -ErrorRecord $_
        return $false
    }
}

# 导出模块成员
Export-ModuleMember -Function Test-Symlink, New-Symlink, Remove-Symlink, New-BackupItem
