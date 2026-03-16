# ============================================================
# ws-launcher – Tabs starten und Service-Logik (PowerShell 5.1+)
# ============================================================

function Get-EffectiveCmd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dir,
        [string]$ConfiguredCmd
    )

    $runCmdPath = Join-Path $Dir ".run-cmd"
    if (Test-Path -LiteralPath $runCmdPath) {
        $content = Get-Content -LiteralPath $runCmdPath -Raw
        if ($content -and ($content.Trim().Length -gt 0)) {
            return $content.Trim()
        }
    }
    return $ConfiguredCmd
}


function Start-GitBashTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Dir,
        [string]$Cmd,
        [string]$EnvString = "",
        [bool]$Exec
    )

    $bashCmd = $Cmd
    if (-not [string]::IsNullOrWhiteSpace($EnvString)) {
        $bashCmd = "$EnvString $Cmd"
    }

    if ($Exec) {
        & wt.exe -w 0 new-tab -p $GitBashProfile --title $Title -d $Dir -- $GitBash -li -c "{
$bashCmd
}"
    }
    else {
        $cmdBlock = "exec bash"
        if (-not [string]::IsNullOrWhiteSpace($Cmd)) {
            $cmdBlock = "echo 'Run manually:'`necho '$($bashCmd)'`nexec bash"
        }
        & wt.exe -w 0 new-tab -p $GitBashProfile --title $Title -d $Dir -- $GitBash -li -c "{
$cmdBlock
}"
    }
}

function Get-RepoServices {
    [CmdletBinding()]
    param(
        [string]$BareDir,
        [string]$BareRootDir,
        [Parameter(Mandatory = $true)]
        [string]$WorktreePath,
        [Parameter(Mandatory = $true)]
        [string]$DefaultTitle,
        [string]$DefaultCmd,
        [object]$InheritedConfig
    )

    $services = @()

    if ($InheritedConfig -and $InheritedConfig.services) {
        foreach ($s in $InheritedConfig.services) {
            $services += $s
        }
    }

    # .ws-config.json im Bare-Repo-Root (z. B. ct-angular-ui-bare/.ws-config.json)
    if ($BareRootDir -and (Test-Path (Join-Path $BareRootDir $RepoConfigFile))) {
        try {
            $path = Join-Path $BareRootDir $RepoConfigFile
            $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json -and $json.services) {
                $services = @()
                foreach ($s in $json.services) {
                    $services += $s
                }
            }
        }
        catch {
            # keep previous $services
        }
    }

    # .ws-config.json inside .git (BareGitDir)
    if ($BareDir -and (Test-Path (Join-Path $BareDir $RepoConfigFile))) {
        try {
            $json = Get-Content (Join-Path $BareDir $RepoConfigFile) -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json -and $json.services) {
                $services = @()
                foreach ($s in $json.services) {
                    $services += $s
                }
            }
        }
        catch {
            # keep previous $services
        }
    }

    # Worktree-Config hat Vorrang: .ws-config.json im gewählten Worktree (z. B. development/) ersetzt die Bare-Config
    $worktreeConfigPath = Join-Path $WorktreePath $RepoConfigFile
    if (Test-Path -LiteralPath $worktreeConfigPath) {
        try {
            $json = Get-Content -LiteralPath $worktreeConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json -and $json.services) {
                $services = @()
                foreach ($s in $json.services) {
                    $services += $s
                }
            }
        }
        catch {
            # Fehler beim Lesen: Bare-Config bleibt gültig
        }
    }

    if ($services.Count -eq 0) {
        $services = @(@{ title = $DefaultTitle; dir = "."; cmd = $DefaultCmd })
    }
    return $services
}

function Launch-Service {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Srv
    )

    $queue = @()

    if ($Srv.IsBare) {
        $wt = Select-Worktree -Srv $Srv
        if (-not $wt) {
            return @()
        }
        $baseDir = $wt.Path
    }
    else {
        $baseDir = $Srv.Dir
    }

    $bareDirParam = if ($Srv.IsBare -and $Srv.BareGitDir) { $Srv.BareGitDir } else { $null }
    $bareRootDirParam = if ($Srv.IsBare -and $Srv.Dir) { $Srv.Dir } else { $null }
    $repoServices = @(Get-RepoServices `
        -BareDir $bareDirParam `
        -BareRootDir $bareRootDirParam `
        -WorktreePath $baseDir `
        -DefaultTitle $Srv.Title `
        -DefaultCmd $Srv.Cmd `
        -InheritedConfig $Srv.DefaultConfig)

    if ($repoServices.Count -gt 1) {
        $toLaunch = Show-Menu `
            -Title "Select Services -- $($Srv.Title)" `
            -Items $repoServices `
            -LabelScript { param($rs) $line = $rs.cmd; if ($rs.env) { $line = "$($rs.env) $line" }; "$($rs.title) ($line)" } `
            -MultiSelect $true
    }
    else {
        $toLaunch = @($repoServices)
    }

    if (-not $toLaunch) {
        return @()
    }

    foreach ($svc in $toLaunch) {
        $finalDir = Join-Path $baseDir $svc.dir
        if (-not (Test-Path -LiteralPath $finalDir)) {
            $finalDir = $baseDir
        }
        $finalCmd = Get-EffectiveCmd -Dir $finalDir -ConfiguredCmd $svc.cmd

        if ($Srv.Exec -and [string]::IsNullOrWhiteSpace($finalCmd)) {
            Clear-Host
            Write-Host "=== No Command Found: $($svc.title) ===`n" -ForegroundColor Yellow
            Write-Host "  Dir : $finalDir" -ForegroundColor Green
            Write-Host "Press [Y] to open directory, [N]/[ESC] to skip..." -ForegroundColor DarkCyan
            $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if (($k.Character -eq 'y') -or ($k.Character -eq 'Y')) {
                $queue += [PSCustomObject]@{ Title = $svc.title; Dir = $finalDir; Cmd = $null; Env = ""; Exec = $false }
            }
            continue
        }

        $finalEnv = ""
        if ($svc.env) { $finalEnv = [string]$svc.env }

        $displayCmd = $finalCmd
        if (-not [string]::IsNullOrWhiteSpace($finalEnv)) { $displayCmd = "$finalEnv $finalCmd" }
        if ($Srv.Exec -and $finalCmd -and -not (Confirm-Launch -Title $svc.title -Dir $finalDir -Cmd $displayCmd)) {
            continue
        }
        $queue += [PSCustomObject]@{ Title = $svc.title; Dir = $finalDir; Cmd = $finalCmd; Env = $finalEnv; Exec = $Srv.Exec }
    }
    return $queue
}
