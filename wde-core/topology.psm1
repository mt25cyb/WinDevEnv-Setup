<#
.SYNOPSIS
WinDevEnv-Setup 依赖拓扑排序核心模块
#>

<#
.SYNOPSIS
生成拓扑排序后的执行顺序
.PARAMETER Items
软件/组件列表，每项需包含 id、dependencies（依赖数组）、hardDependencies（硬依赖数组）
.PARAMETER Reverse
是否反向排序（用于卸载）
#>
function Get-TopologicalSort {
    param(
        [array]$Items,
        [switch]$Reverse
    )

    if ($Items.Count -eq 0) {
        return @()
    }

    # 构建入度表与邻接表
    $inDegree = @{}
    $adjacency = @{}
    $itemMap = @{}

    foreach ($item in $Items) {
        $id = $item.id
        $inDegree[$id] = 0
        $adjacency[$id] = @()
        $itemMap[$id] = $item
    }

    # 填充依赖关系（仅硬依赖参与拓扑排序）
    foreach ($item in $Items) {
        $id = $item.id
        $deps = @()
        if ($item.hardDependencies -and $item.hardDependencies -is [array]) {
            $deps = $item.hardDependencies
        }
        elseif ($item.dependencies -and $item.dependencies -is [array]) {
            $deps = $item.dependencies
        }

        foreach ($dep in $deps) {
            if ($adjacency.ContainsKey($dep)) {
                $adjacency[$dep] += $id
                $inDegree[$id]++
            }
        }
    }

    # Kahn 算法
    $queue = @()
    foreach ($id in $inDegree.Keys) {
        if ($inDegree[$id] -eq 0) {
            $queue += $id
        }
    }

    $sortedIds = @()
    while ($queue.Count -gt 0) {
        $current = $queue[0]
        $queue = $queue[1..($queue.Length - 1)]
        $sortedIds += $current

        foreach ($next in $adjacency[$current]) {
            $inDegree[$next]--
            if ($inDegree[$next] -eq 0) {
                $queue += $next
            }
        }
    }

    # 检测环，剩余入度不为0的节点跳过并告警
    foreach ($id in $inDegree.Keys) {
        if ($inDegree[$id] -gt 0) {
            Write-LogWarn -Message ("检测到依赖循环，跳过组件: {0}" -f $id)
        }
    }

    # 反向排序（卸载用）
    if ($Reverse) {
        [array]::Reverse($sortedIds)
    }

    # 映射回完整对象
    $result = @()
    foreach ($id in $sortedIds) {
        $result += $itemMap[$id]
    }

    return $result
}

<#
.SYNOPSIS
过滤出启用的组件，返回可执行的排序列表
#>
function Get-EnabledSortedItems {
    param(
        [array]$AllItems,
        [hashtable]$EnableConfig,
        [switch]$Reverse
    )

    $enabledItems = @()
    foreach ($item in $AllItems) {
        $enableKey = "ENABLE_$($item.id.ToUpper())"
        if ($EnableConfig.ContainsKey($enableKey) -and $EnableConfig[$enableKey] -eq $true) {
            $enabledItems += $item
        }
    }

    return Get-TopologicalSort -Items $enabledItems -Reverse:$Reverse
}

# 导出模块成员
Export-ModuleMember -Function Get-TopologicalSort, Get-EnabledSortedItems
