# ============================================================
# ws-launcher – Open repo folder in IDE (PowerShell 5.1+)
# Default: VS Code CLI "code"; override via global.json → config.ide
# ============================================================

function Open-RepoInIde {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Repo
    )

    try {
        $projectDir = $Repo.Dir
        if ($Repo.IsBare) {
            $wt = Select-Worktree -Srv $Repo
            if (-not $wt) { return }
            $projectDir = $wt.Path
        }

        if (-not (Test-Path -LiteralPath $projectDir)) {
            Clear-Host
            Write-Host "`n=== IDE: path not found ===" -ForegroundColor Red
            Write-Host "  $projectDir" -ForegroundColor Yellow
            Read-LauncherPause
            return
        }

        $projectDir = (Resolve-Path -LiteralPath $projectDir).Path
        $cmd = [string]$Config.IdeCommand
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            Clear-Host
            Write-Host "`n=== IDE not configured ===" -ForegroundColor Yellow
            Write-Host "Add under config in global.json, e.g.:" -ForegroundColor DarkCyan
            Write-Host '  "ide": { "command": "code", "arguments": [] }' -ForegroundColor Gray
            Write-Host 'or shorthand: "ide": "code"' -ForegroundColor Gray
            Read-LauncherPause
            return
        }

        $extra = @($Config.IdeArguments)
        $argList = @($extra + $projectDir)

        Clear-Host
        Write-Host "=== IDE ===" -ForegroundColor Cyan
        Write-Host "  Command: $cmd" -ForegroundColor Green
        Write-Host "  Folder : $projectDir" -ForegroundColor Yellow
        if ($extra.Count -gt 0) {
            Write-Host "  Args   : $($extra -join ' ')" -ForegroundColor DarkGray
        }
        Write-Host "`nStarting..." -ForegroundColor DarkCyan

        Start-Process -FilePath $cmd -ArgumentList $argList -WorkingDirectory $projectDir

        Start-Sleep -Seconds 1
        Write-Host "Done." -ForegroundColor Green
        Start-Sleep -Milliseconds 600
    }
    catch {
        Write-Host "`nError starting IDE: $_" -ForegroundColor Red
        Read-LauncherPause
    }
}
