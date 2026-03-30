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

function Remove-GitWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BareDir,
        [Parameter(Mandatory = $true)]
        [string]$WorktreePath
    )

    try {
        Clear-Host
        Write-Host "=== Removing Git Worktree ===" -ForegroundColor Cyan
        Write-Host "  Path: $WorktreePath" -ForegroundColor Yellow
        Write-Host "`nPress [Y] to remove, [N]/[ESC] to cancel..." -ForegroundColor DarkCyan
        
        while ($true) {
            $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if (($k.Character -eq 'y') -or ($k.Character -eq 'Y')) {
                break
            }
            if (($k.Character -eq 'n') -or ($k.Character -eq 'N') -or ($k.VirtualKeyCode -eq 27)) {
                Write-Host "`nCancelled." -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds 800
                return $false
            }
        }

        Write-Host "`nRemoving worktree..." -ForegroundColor Cyan
        $result = & git -C $BareDir worktree remove $WorktreePath --force 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully removed worktree: $WorktreePath" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return $true
        }
        else {
            Write-Host "Failed to remove worktree: $result" -ForegroundColor Red
            Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return $false
        }
    }
    catch {
        Write-Host "Error removing worktree: $_" -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return $false
    }
}

function Add-GitWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BareDir,
        [Parameter(Mandatory = $true)]
        [string]$BareRootDir
    )

    try {
        Clear-Host
        Write-Host "=== Add Git Worktree ===" -ForegroundColor Cyan
        Write-Host "`nEnter branch name (or press ESC to cancel): " -ForegroundColor DarkCyan -NoNewline
        
        $branchName = ""
        while ($true) {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            if ($key.VirtualKeyCode -eq 27) {
                Write-Host "`n`nCancelled." -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds 800
                return $null
            }
            
            if ($key.VirtualKeyCode -eq 13) {
                break
            }
            
            if ($key.VirtualKeyCode -eq 8) {
                if ($branchName.Length -gt 0) {
                    $branchName = $branchName.Substring(0, $branchName.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }
            
            if ($key.Character -match '[a-zA-Z0-9_\-/.]') {
                $branchName += $key.Character
                Write-Host $key.Character -NoNewline
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($branchName)) {
            Write-Host "`n`nBranch name cannot be empty." -ForegroundColor Red
            Start-Sleep -Seconds 1
            return $null
        }
        
        $worktreePath = Join-Path $BareRootDir $branchName.Replace('/', '_')
        
        Write-Host "`n`nWorktree will be created at: $worktreePath" -ForegroundColor Green
        Write-Host "Press [Y] to create, [N]/[ESC] to cancel..." -ForegroundColor DarkCyan
        
        while ($true) {
            $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if (($k.Character -eq 'y') -or ($k.Character -eq 'Y')) {
                break
            }
            if (($k.Character -eq 'n') -or ($k.Character -eq 'N') -or ($k.VirtualKeyCode -eq 27)) {
                Write-Host "`nCancelled." -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds 800
                return $null
            }
        }
        
        Write-Host "`nCreating worktree..." -ForegroundColor Cyan
        
        $branchExists = & git -C $BareDir branch --list $branchName 2>$null
        if ($branchExists) {
            $result = & git -C $BareDir worktree add $worktreePath $branchName 2>&1
        }
        else {
            $result = & git -C $BareDir worktree add -b $branchName $worktreePath 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully created worktree." -ForegroundColor Green
            
            $remoteBranch = & git -C $worktreePath rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
            if (-not $remoteBranch) {
                Write-Host "Setting upstream branch..." -ForegroundColor Cyan
                $remotes = & git -C $BareDir remote 2>$null
                if ($remotes) {
                    $remote = $remotes[0]
                    & git -C $worktreePath branch --set-upstream-to="$remote/$branchName" $branchName 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Upstream set to: $remote/$branchName" -ForegroundColor Green
                    }
                }
            }
            
            Write-Host "`nPress any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return $worktreePath
        }
        else {
            Write-Host "Failed to create worktree: $result" -ForegroundColor Red
            Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return $null
        }
    }
    catch {
        Write-Host "Error creating worktree: $_" -ForegroundColor Red
        Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return $null
    }
}
