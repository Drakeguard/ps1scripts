# ============================================================
# ws-launcher – Executable Management (PowerShell 5.1+)
# ============================================================

function Read-LauncherPause {
    Write-Host "`nPress any key to continue..." -ForegroundColor DarkCyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-ConfiguredExeMenuLabel {
    param([Parameter(Mandatory = $true)] $Entry)
    "$($Entry.name)  ($($Entry.path))"
}

function Get-ProcessArgumentList {
    param([Parameter(Mandatory = $true)] $Entry)
    if (-not ($Entry.PSObject.Properties['arguments'] -and $null -ne $Entry.arguments)) {
        return $null
    }
    if ($Entry.arguments -is [string]) { return $Entry.arguments }
    return @($Entry.arguments)
}

function Resolve-WorkingDirectoryForExe {
    param(
        [Parameter(Mandatory = $true)] $Entry,
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )
    if ($Entry.PSObject.Properties['workingDirectory'] -and $Entry.workingDirectory) {
        return [string]$Entry.workingDirectory
    }
    return Split-Path -Parent $ExePath
}

function Invoke-LauncherStartProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        $ArgumentList
    )

    Clear-Host
    Write-Host "=== Launching ===" -ForegroundColor Cyan
    Write-Host "  Name: $DisplayName" -ForegroundColor Green
    Write-Host "  Path: $FilePath" -ForegroundColor Yellow
    Write-Host "`nLaunching..." -ForegroundColor DarkCyan

    $sp = @{
        FilePath          = $FilePath
        WorkingDirectory  = $WorkingDirectory
    }
    if ($ArgumentList) { $sp['ArgumentList'] = $ArgumentList }
    Start-Process @sp

    Start-Sleep -Seconds 1
    Write-Host "Launched successfully!" -ForegroundColor Green
    Start-Sleep -Milliseconds 800
}

function Get-ExecutableList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoDir
    )

    $configPath = Join-Path $RepoDir $RepoConfigFile
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @()
    }
    try {
        $json = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($json -and $json.executables) {
            return @($json.executables)
        }
    }
    catch {
        Write-Host "  [warn] Could not read executables from config: $_" -ForegroundColor DarkYellow
    }
    return @()
}

function Open-Executable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Repo
    )

    try {
        $baseDir = $Repo.Dir
        if ($Repo.IsBare) {
            $wt = Select-Worktree -Srv $Repo
            if (-not $wt) { return }
            $baseDir = $wt.Path
        }

        $executables = @(Get-ExecutableList -RepoDir $baseDir)
        if ($executables.Count -eq 0) {
            Clear-Host
            Write-Host "`n=== No Executables Configured ===" -ForegroundColor Yellow
            Write-Host "`nNo executables found in .ws-config.json" -ForegroundColor DarkCyan
            Write-Host "Add an 'executables' array to your config file." -ForegroundColor DarkCyan
            Write-Host "`nExample:" -ForegroundColor White
            Write-Host '{' -ForegroundColor Gray
            Write-Host '  "executables": [' -ForegroundColor Gray
            Write-Host '    {' -ForegroundColor Gray
            Write-Host '      "name": "My App",' -ForegroundColor Gray
            Write-Host '      "path": "bin/myapp.exe"' -ForegroundColor Gray
            Write-Host '    }' -ForegroundColor Gray
            Write-Host '  ]' -ForegroundColor Gray
            Write-Host '}' -ForegroundColor Gray
            Read-LauncherPause
            return
        }

        $label = { param($exe) Get-ConfiguredExeMenuLabel -Entry $exe }
        $selected = Show-Menu `
            -Title "Select Executable -- $($Repo.Title)" `
            -Items $executables `
            -LabelScript $label `
            -MultiSelect $false

        if (-not $selected) { return }

        $exePath = $selected.path
        if (-not [System.IO.Path]::IsPathRooted($exePath)) {
            $exePath = Join-Path $baseDir $exePath
        }

        if (-not (Test-Path -LiteralPath $exePath)) {
            Clear-Host
            Write-Host "`n=== Executable Not Found ===" -ForegroundColor Red
            Write-Host "  Path: $exePath" -ForegroundColor Yellow
            Read-LauncherPause
            return
        }

        $workDir = Resolve-WorkingDirectoryForExe -Entry $selected -ExePath $exePath
        $args = Get-ProcessArgumentList -Entry $selected
        Invoke-LauncherStartProcess -DisplayName $selected.name -FilePath $exePath -WorkingDirectory $workDir -ArgumentList $args
    }
    catch {
        Write-Host "`nError launching executable: $_" -ForegroundColor Red
        Read-LauncherPause
    }
}

function Open-GlobalApplications {
    [CmdletBinding()]
    param()

    $apps = @($Config.Applications)
    if ($apps.Count -eq 0) {
        Clear-Host
        Write-Host "`n=== No Global Applications ===" -ForegroundColor Yellow
        Write-Host "`nAdd an `"applications`" array under `"config`" in global.json:" -ForegroundColor DarkCyan
        Write-Host "  $GlobalConfig" -ForegroundColor Gray
        Write-Host "`nExample:" -ForegroundColor White
        Write-Host '  "config": {' -ForegroundColor Gray
        Write-Host '    "applications": [' -ForegroundColor Gray
        Write-Host '      { "name": "KeePass", "path": "C:\\Program Files\\KeePass\\KeePass.exe" },' -ForegroundColor Gray
        Write-Host '      { "name": "VS Code", "path": "C:\\...\\Code.exe" }' -ForegroundColor Gray
        Write-Host '    ]' -ForegroundColor Gray
        Write-Host '  }' -ForegroundColor Gray
        Write-Host "`nOptional per entry: `"arguments`", `"workingDirectory`"." -ForegroundColor DarkCyan
        Read-LauncherPause
        return
    }

    $label = { param($a) Get-ConfiguredExeMenuLabel -Entry $a }
    $selected = Show-Menu `
        -Title "Global Applications" `
        -Items $apps `
        -LabelScript $label `
        -MultiSelect $false

    if (-not $selected) { return }

    $exePath = [string]$selected.path
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        Write-Host "`nInvalid entry: missing path." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if (-not (Test-Path -LiteralPath $exePath)) {
        Clear-Host
        Write-Host "`n=== Application Not Found ===" -ForegroundColor Red
        Write-Host "  Path: $exePath" -ForegroundColor Yellow
        Read-LauncherPause
        return
    }

    try {
        $workDir = Resolve-WorkingDirectoryForExe -Entry $selected -ExePath $exePath
        $args = Get-ProcessArgumentList -Entry $selected
        Invoke-LauncherStartProcess -DisplayName $selected.name -FilePath $exePath -WorkingDirectory $workDir -ArgumentList $args
    }
    catch {
        Write-Host "`nError launching application: $_" -ForegroundColor Red
        Read-LauncherPause
    }
}
