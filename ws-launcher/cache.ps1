# ============================================================
# ws-launcher – Repo-Cache lesen/schreiben (PowerShell 5.1+)
# ============================================================

function Read-Cache {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $CacheFile)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $CacheFile -Raw | ConvertFrom-Json
        # PS 5.1: $raw kann Array oder einzelnes Objekt sein
        $items = @($raw)
        $result = @()
        foreach ($obj in $items) {
            $wtList = @()
            if ($obj.Worktrees) {
                foreach ($w in @($obj.Worktrees)) {
                    $wtList += [PSCustomObject]@{
                        Path   = [string]$w.Path
                        Branch = [string]$w.Branch
                    }
                }
            }
            $bareGitDir = $null
            if ($obj.BareGitDir) { $bareGitDir = [string]$obj.BareGitDir }
            elseif ($obj.IsBare -and $obj.Dir) { $bareGitDir = $obj.Dir }
            $result += [PSCustomObject]@{
                Title         = [string]$obj.Title
                Dir           = [string]$obj.Dir
                BareGitDir    = $bareGitDir
                DefaultConfig = $null
                Cmd           = [string]$obj.Cmd
                Exec          = [bool]$obj.Exec
                IsBare        = [bool]$obj.IsBare
                MenuLabel     = [string]$obj.MenuLabel
                Worktrees     = $wtList
            }
        }
        return $result
    }
    catch {
        Write-Host "  [warn] Cache read failed, re-scanning..." -ForegroundColor DarkYellow
        return $null
    }
}

function Write-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Repos
    )

    try {
        $Repos | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CacheFile -Encoding UTF8
    }
    catch {
        Write-Host "  [warn] Could not write cache: $_" -ForegroundColor DarkYellow
    }
}
