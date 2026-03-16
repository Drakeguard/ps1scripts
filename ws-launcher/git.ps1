# ============================================================
# ws-launcher – Git-Worktrees (Bare-Repos) (PowerShell 5.1+)
# ============================================================

function Get-WorktreesForBare {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BareDir
    )

    $worktrees = @()

    $raw = & git -C $BareDir worktree list --porcelain -z 2>$null
    if (-not $raw) {
        return @()
    }

    $fields = $raw -split '\0' | Where-Object { $_.Trim() -ne "" }
    $path = $null
    $branch = $null
    $isBareRoot = $false
    $isPrunable = $false

    foreach ($f in $fields) {
        if ($f -match '^worktree (.+)') {
            if ($path -and -not $isBareRoot -and -not $isPrunable) {
                $winPath = $path.Replace('/', '\')
                if (Test-Path $winPath) {
                    $worktrees += [PSCustomObject]@{
                        Path   = $winPath
                        Branch = if ($null -ne $branch) { $branch } else { "(detached)" }
                    }
                }
            }
            $path = $Matches[1].Trim()
            $branch = $null
            $isBareRoot = $false
            $isPrunable = $false
        }
        elseif ($f -match '^branch refs/heads/(.+)') {
            $branch = $Matches[1].Trim()
        }
        elseif ($f -eq "bare") {
            $isBareRoot = $true
        }
        elseif ($f -match '^prunable') {
            $isPrunable = $true
        }
    }

    if ($path -and -not $isBareRoot -and -not $isPrunable) {
        $winPath = $path.Replace('/', '\')
        if (Test-Path $winPath) {
            $worktrees += [PSCustomObject]@{
                Path   = $winPath
                Branch = if ($null -ne $branch) { $branch } else { "(detached)" }
            }
        }
    }

    return $worktrees
}
