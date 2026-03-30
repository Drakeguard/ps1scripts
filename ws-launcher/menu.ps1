# ============================================================
# ws-launcher – Interaktive Menüs (PowerShell 5.1+)
# ============================================================

function Show-Menu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [array]$Items,
        [Parameter(Mandatory = $true)]
        [scriptblock]$LabelScript,
        [bool]$MultiSelect = $false,
        [scriptblock]$KeyHandler = $null
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return $null
    }

    $idx = 0
    $selected = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $selected += $false
    }

    while ($true) {
        $labels = @()
        foreach ($item in $Items) {
            $labels += & $LabelScript $item
        }

        while ($true) {
            Clear-Host
            Write-Host "=== $Title ===" -ForegroundColor Cyan
            if ($MultiSelect) {
                $hint = "[UP/DOWN] Move  [SPACE] Toggle  [A] All  [T] Mode  [R] Rescan  [W] Worktrees  [V] IDE  [E] Repo exes  [G] Global apps  [ENTER] Confirm  [ESC]/[Ctrl+D] Cancel"
            }
            else {
                $hint = "[UP/DOWN] Move  [ENTER] Confirm  [ESC]/[Ctrl+D] Cancel"
            }
            Write-Host "$hint`n" -ForegroundColor DarkCyan

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $isActive = ($i -eq $idx)
                $ptr = if ($isActive) { ">" } else { " " }
                $color = if ($isActive) { "Yellow" } else { "White" }
                $lines = $labels[$i] -split "`n"

                if ($MultiSelect) {
                    $chk = if ($selected[$i]) { "[X]" } else { "[ ]" }
                    Write-Host "$ptr $chk $($lines[0])" -ForegroundColor $color
                }
                else {
                    Write-Host "$ptr  $($lines[0])" -ForegroundColor $color
                }

                for ($j = 1; $j -lt $lines.Count; $j++) {
                    Write-Host "       $($lines[$j])" -ForegroundColor DarkGray
                }
            }

            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

            if ($key.Character -eq [char]4) { return $null }

            if ($KeyHandler) {
                $action = & $KeyHandler $key $Items[$idx]
                if ($action -eq "Refresh") { break }
                if ($action -eq "Exit") { return $null }
            }

            switch ($key.VirtualKeyCode) {
                38 { if ($idx -gt 0) { $idx-- } }
                40 { if ($idx -lt $Items.Count - 1) { $idx++ } }
                32 { if ($MultiSelect) { $selected[$idx] = -not $selected[$idx] } }
                65 {
                    if ($MultiSelect) {
                        $allOn = $true
                        foreach ($s in $selected) { if (-not $s) { $allOn = $false; break } }
                        for ($j = 0; $j -lt $selected.Count; $j++) {
                            $selected[$j] = -not $allOn
                        }
                    }
                }
                13 {
                    if ($MultiSelect) {
                        $chosen = @()
                        for ($k = 0; $k -lt $Items.Count; $k++) {
                            if ($selected[$k]) { $chosen += $Items[$k] }
                        }
                        return $chosen
                    }
                    return $Items[$idx]
                }
                27 { return $null }
            }
        }
    }
}

function Select-Repos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Services
    )

    $keyHandler = {
        param($key, $item)
        if (($key.Character -eq 'r') -or ($key.Character -eq 'R')) {
            if ($item.IsBare) {
                Clear-Host
                Write-Host "`n  Rescanning worktrees for '$($item.Title)'...`n" -ForegroundColor Cyan
                $item.Worktrees = Get-WorktreesForBare -BareDir $item.BareGitDir
                Write-Cache -Repos $Services
                Start-Sleep -Milliseconds 600
                return "Refresh"
            }
        }
        if (($key.Character -eq 't') -or ($key.Character -eq 'T')) {
            $item.Exec = -not $item.Exec
            $modeTag = if ($item.Exec) { "[RUN]" } else { "[OPEN]" }
            $bareTag = if ($item.IsBare) { " (Bare)" } else { "" }
            $item.MenuLabel = "$modeTag$bareTag  $($item.Title)  ($($item.Dir))"
            Write-Cache -Repos $Services
            return "Refresh"
        }
        if (($key.Character -eq 'w') -or ($key.Character -eq 'W')) {
            if ($item.IsBare) {
                Show-WorktreeMenu -Repo $item
                $item.Worktrees = Get-WorktreesForBare -BareDir $item.BareGitDir
                Write-Cache -Repos $Services
                return "Refresh"
            }
        }
        if (($key.Character -eq 'e') -or ($key.Character -eq 'E')) {
            Open-Executable -Repo $item
            return "Refresh"
        }
        if (($key.Character -eq 'g') -or ($key.Character -eq 'G')) {
            Open-GlobalApplications
            return "Refresh"
        }
        if (($key.Character -eq 'v') -or ($key.Character -eq 'V')) {
            Open-RepoInIde -Repo $item
            return "Refresh"
        }
        return "Continue"
    }

    $labelScript = {
        param($s)
        $base = $s.MenuLabel
        if (-not $s.IsBare) {
            return $base
        }
        $wtList = @($s.Worktrees)
        if ($wtList.Count -gt 0) {
            $lines = @()
            foreach ($wt in $wtList) {
                if ($wt -and -not [string]::IsNullOrWhiteSpace($wt.Path)) {
                    $dirName = Split-Path -Path $wt.Path -Leaf
                    if ($dirName -eq $wt.Branch) {
                        $lines += "  [$dirName]"
                    }
                    else {
                        $lines += "  [$dirName] $($wt.Branch)"
                    }
                }
            }
            if ($lines.Count -gt 0) {
                return "$base`n$($lines -join "`n")"
            }
        }
        return "$base`n  (Worktrees: press R to rescan)"
    }

    return Show-Menu `
        -Title "Select Repos to Launch" `
        -Items $Services `
        -LabelScript $labelScript `
        -MultiSelect $true `
        -KeyHandler $keyHandler
}

function Select-Worktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Srv
    )

    if ($Srv.Worktrees.Count -eq 0) {
        Clear-Host
        Write-Host "`n  Fetching worktrees for '$($Srv.Title)'...`n" -ForegroundColor Cyan
        $Srv.Worktrees = Get-WorktreesForBare -BareDir $Srv.BareGitDir
    }

    $valid = @()
    foreach ($wt in $Srv.Worktrees) {
        if (-not [string]::IsNullOrWhiteSpace($wt.Path)) {
            $valid += $wt
        }
    }

    if ($valid.Count -eq 0) {
        Write-Host "  No valid worktrees found for: $($Srv.Dir)" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return $null
    }

    return Show-Menu `
        -Title "Select Worktree -- $($Srv.Title)" `
        -Items $valid `
        -LabelScript { param($wt) "[$($wt.Branch)]  $($wt.Path)" } `
        -MultiSelect $false
}

function Confirm-Launch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Dir,
        [Parameter(Mandatory = $true)]
        [string]$Cmd
    )

    Clear-Host
    Write-Host "=== Confirm Launch: $Title ===`n" -ForegroundColor Cyan
    Write-Host "  Dir : " -NoNewline
    Write-Host $Dir -ForegroundColor Green
    Write-Host "  Cmd : " -NoNewline
    Write-Host $Cmd -ForegroundColor Yellow
    Write-Host "`nPress [Y] to execute, [N] / [ESC] to skip..." -ForegroundColor DarkCyan
    while ($true) {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if (($k.Character -eq 'y') -or ($k.Character -eq 'Y')) { return $true }
        if (($k.Character -eq 'n') -or ($k.Character -eq 'N')) { return $false }
        if ($k.VirtualKeyCode -eq 27) { return $false }
    }
}

function Show-WorktreeMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Repo
    )

    $menuItems = @(
        [PSCustomObject]@{ Action = "Add"; Label = "Add New Worktree" }
        [PSCustomObject]@{ Action = "Remove"; Label = "Remove Existing Worktree" }
    )

    $selected = Show-Menu `
        -Title "Worktree Management -- $($Repo.Title)" `
        -Items $menuItems `
        -LabelScript { param($item) $item.Label } `
        -MultiSelect $false

    if (-not $selected) {
        return
    }

    if ($selected.Action -eq "Add") {
        $result = Add-GitWorktree -BareDir $Repo.BareGitDir -BareRootDir $Repo.Dir
        if ($result) {
            Clear-Host
            Write-Host "`nWorktree created successfully at: $result" -ForegroundColor Green
            Start-Sleep -Milliseconds 1000
        }
    }
    elseif ($selected.Action -eq "Remove") {
        if (-not $Repo.Worktrees -or $Repo.Worktrees.Count -eq 0) {
            $Repo.Worktrees = Get-WorktreesForBare -BareDir $Repo.BareGitDir
        }

        if (-not $Repo.Worktrees -or $Repo.Worktrees.Count -eq 0) {
            Clear-Host
            Write-Host "`n=== No Worktrees Found ===" -ForegroundColor Yellow
            Write-Host "No worktrees to remove." -ForegroundColor DarkCyan
            Write-Host "Press any key to continue..." -ForegroundColor DarkCyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            return
        }

        $worktreeToRemove = Show-Menu `
            -Title "Select Worktree to Remove -- $($Repo.Title)" `
            -Items $Repo.Worktrees `
            -LabelScript { param($wt) "[$($wt.Branch)]  $($wt.Path)" } `
            -MultiSelect $false

        if ($worktreeToRemove) {
            $removed = Remove-GitWorktree -BareDir $Repo.BareGitDir -WorktreePath $worktreeToRemove.Path
            if ($removed) {
                # Refresh worktree list after removal
                $Repo.Worktrees = Get-WorktreesForBare -BareDir $Repo.BareGitDir
            }
        }
    }
}
