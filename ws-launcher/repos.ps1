# ============================================================
# ws-launcher – Repo-Erkennung und -Auflistung (PowerShell 5.1+)
# ============================================================

function Test-BareRepo {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dir
    )

    $configInRoot = Join-Path $Dir "config"
    if (Test-Path -LiteralPath $configInRoot) {
        $content = Get-Content -LiteralPath $configInRoot -Raw
        if ($content -match "bare\s*=\s*true") {
            return $Dir
        }
    }

    $gitDir = Join-Path $Dir ".git"
    $configInGit = Join-Path $gitDir "config"
    if ((Test-Path -LiteralPath $gitDir -PathType Container) -and (Test-Path -LiteralPath $configInGit)) {
        $content = Get-Content -LiteralPath $configInGit -Raw
        if ($content -match "bare\s*=\s*true") {
            return $gitDir
        }
    }

    return $null
}

function New-RepoEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dir
    )

    $bareGitDir = Test-BareRepo -Dir $Dir
    $isBare = ($bareGitDir -ne $null)
    $repo = [PSCustomObject]@{
        Title         = Split-Path -Path $Dir -Leaf
        Dir           = $Dir
        BareGitDir    = $bareGitDir
        IsBare        = $isBare
        DefaultConfig = $null
        Worktrees     = @()
        Exec          = $true
        MenuLabel     = ""
    }
    return Attach-GlobalDefaults -Repo $repo
}

function Attach-GlobalDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Repo
    )

    foreach ($def in $GlobalDefaults) {
        $resolved = Resolve-GlobalPath -RawPath $def.path -TopDirObjects $Config.TopDirs
        if ($resolved -and $Repo.Dir.StartsWith($resolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $Repo.DefaultConfig = @{ services = $def.services }
            break
        }
    }
    return $Repo
}

function Resolve-RepoList {
    [CmdletBinding()]
    param()

    if ($Reload -eq "") {
        $cached = Read-Cache
        if ($cached) {
            return $cached
        }
    }

    Write-Host "Scanning repositories..." -ForegroundColor Cyan
    $list = @()

    foreach ($topObj in $Config.TopDirs) {
        $list += Find-GitRepos -PathObj $topObj
    }

    foreach ($srv in $Config.Services) {
        $list += New-RepoEntry -Dir $srv.Dir
    }

    if ($Reload -eq "deep") {
        foreach ($r in $list) {
            if ($r.IsBare -and $r.BareGitDir) {
                $r.Worktrees = Get-WorktreesForBare -BareDir $r.BareGitDir
            }
        }
    }

    foreach ($r in $list) {
        $mode = if ($r.Exec) { "[RUN]" } else { "[OPEN]" }
        $type = if ($r.IsBare) { "(Bare)" } else { "" }
        $r.MenuLabel = "{0,-7} {1,-7} {2}" -f $mode, $type, $r.Title
    }

    Write-Cache -Repos $list
    return $list
}

function Find-GitRepos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PathObj
    )

    $topDir = $PathObj.path
    if (-not (Test-Path -LiteralPath $topDir)) {
        return @()
    }

    $dirs = Get-ChildItem -Path $topDir -Directory -ErrorAction SilentlyContinue
    $repos = @()
    foreach ($d in $dirs) {
        $p = $d.FullName
        $hasGit = (Test-Path (Join-Path $p ".git") -PathType Container)
        $bareGitDir = Test-BareRepo -Dir $p
        $hasBare = $bareGitDir -ne $null
        if (-not $hasGit -and -not $hasBare) {
            continue
        }
        $repo = New-RepoEntry -Dir $p
        if ($PathObj.defaultConfig) {
            $repo.DefaultConfig = $PathObj.defaultConfig
        }
        $repo = Attach-GlobalDefaults -Repo $repo
        $repos += $repo
    }
    return $repos
}
