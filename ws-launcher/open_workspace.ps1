# ============================================================
# ws-launcher – Einstiegspunkt (PowerShell 5.1+)
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$SearchPath,

    [Parameter(Position = 1)]
    [AllowEmptyString()]
    [ValidateSet("fast", "deep", "")]
    [string]$Reload = "",

    [Parameter(Position = 2)]
    [string]$Profile = "",

    [switch]$Apps
)

if ($PSBoundParameters.ContainsKey('Reload') -and [string]::IsNullOrWhiteSpace($Reload)) {
    $Reload = "fast"
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Module laden (Reihenfolge relevant)
. (Join-Path $ScriptRoot "config.ps1")
. (Join-Path $ScriptRoot "global-config.ps1")
. (Join-Path $ScriptRoot "cache.ps1")
. (Join-Path $ScriptRoot "git.ps1")
. (Join-Path $ScriptRoot "repos.ps1")
. (Join-Path $ScriptRoot "executables.ps1")
. (Join-Path $ScriptRoot "ide.ps1")
. (Join-Path $ScriptRoot "menu.ps1")
. (Join-Path $ScriptRoot "launch.ps1")

# global.json anwenden (Config + Pfad-Defaults)
Initialize-GlobalConfig

if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $GitBashProfile = $Profile
}

# ------------------------------------------------------------
# SearchPath: CLI > ENV > config / global.json
# ------------------------------------------------------------
function Initialize-SearchPath {
    param([string[]]$CliSearchPath)

    if ($CliSearchPath -and $CliSearchPath.Count -gt 0) {
        $Config.TopDirs = @()
        foreach ($p in $CliSearchPath) {
            $Config.TopDirs += [PSCustomObject]@{ path = $p; defaultConfig = $null }
        }
        return
    }
    if ($env:WS_SEARCHPATH) {
        $Config.TopDirs = @()
        foreach ($p in ($env:WS_SEARCHPATH -split ';')) {
            $Config.TopDirs += [PSCustomObject]@{ path = $p; defaultConfig = $null }
        }
        return
    }
    $wrapped = @()
    foreach ($item in $Config.TopDirs) {
        if ($item -is [string]) {
            $wrapped += [PSCustomObject]@{ path = $item; defaultConfig = $null }
        }
        else {
            $wrapped += $item
        }
    }
    $Config.TopDirs = $wrapped
}

Initialize-SearchPath -CliSearchPath $SearchPath

if ($Apps) {
    Open-GlobalApplications
    exit 0
}

# ============================================================
# Hauptablauf
# ============================================================

$Services = Resolve-RepoList

foreach ($r in $Services) {
    $null = Attach-GlobalDefaults -Repo $r
}

if (-not $Services -or $Services.Count -eq 0) {
    Write-Host "No repos found. Check your SearchPath / config." -ForegroundColor Red
    exit 1
}

$toRun = Select-Repos -Services $Services

if (-not $toRun -or $toRun.Count -eq 0) {
    Write-Host "`nNo repos selected. Exiting." -ForegroundColor DarkYellow
    exit 0
}

Write-Host "`nProcessing selections...`n" -ForegroundColor Cyan
$globalQueue = @()

foreach ($s in $toRun) {
    $queueItems = Launch-Service -Srv $s
    if ($queueItems) {
        $globalQueue += $queueItems
    }
}

if ($globalQueue.Count -eq 0) {
    Write-Host "`nNothing to launch." -ForegroundColor DarkYellow
    exit 0
}

Write-Host "`nOpening $($globalQueue.Count) tab(s)...`n" -ForegroundColor Green
foreach ($item in $globalQueue) {
    Start-GitBashTab -Title $item.Title -Dir $item.Dir -Cmd $item.Cmd -EnvString $item.Env -Exec $item.Exec
}
