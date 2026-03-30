# ============================================================
# ws-launcher – Executable Management (PowerShell 5.1+)
# ============================================================

function Get-ExecutableList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoDir
    )

    $executables = @()
    
    # Try to read from .ws-config.json in the repo
    $configPath = Join-Path $RepoDir $RepoConfigFile
    if (Test-Path -LiteralPath $configPath) {
        try {
            $json = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($json -and $json.executables) {
                foreach ($exe in $json.executables) {
                    $executables += $exe
                }
            }
        }
        catch {
            Write-Host "  [warn] Could not read executables from config: $_" -ForegroundColor DarkYellow
        }
    }
    
    return $executables
}

function Open-Executable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Repo
    )

    try {
        $baseDir = $Repo.Dir
        
        # For bare repos, ask user to select a worktree first
        if ($Repo.IsBare) {
            $wt = Select-Worktree -Srv $Repo
            if (-not $wt) {
                return
            }
            $baseDir = $wt.Path
        }
        
        # Get executables from config
        $executables = Get-ExecutableList -RepoDir $baseDir
        
        if (-not $executables -or $executables.Count -eq 0) {
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
            Write-Host "`nPress any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return
        }
        
        # Show menu to select executable
        $selected = Show-Menu `
            -Title "Select Executable -- $($Repo.Title)" `
            -Items $executables `
            -LabelScript { param($exe) "$($exe.name)  ($($exe.path))" } `
            -MultiSelect $false
        
        if (-not $selected) {
            return
        }
        
        # Resolve the path
        $exePath = $selected.path
        if (-not [System.IO.Path]::IsPathRooted($exePath)) {
            $exePath = Join-Path $baseDir $exePath
        }
        
        if (-not (Test-Path -LiteralPath $exePath)) {
            Clear-Host
            Write-Host "`n=== Executable Not Found ===" -ForegroundColor Red
            Write-Host "  Path: $exePath" -ForegroundColor Yellow
            Write-Host "`nPress any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return
        }
        
        # Launch the executable
        Clear-Host
        Write-Host "=== Launching Executable ===" -ForegroundColor Cyan
        Write-Host "  Name: $($selected.name)" -ForegroundColor Green
        Write-Host "  Path: $exePath" -ForegroundColor Yellow
        Write-Host "`nLaunching..." -ForegroundColor DarkCyan
        
        Start-Process -FilePath $exePath -WorkingDirectory (Split-Path -Parent $exePath)
        
        Start-Sleep -Seconds 1
        Write-Host "Launched successfully!" -ForegroundColor Green
        Start-Sleep -Milliseconds 800
    }
    catch {
        Write-Host "`nError launching executable: $_" -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
