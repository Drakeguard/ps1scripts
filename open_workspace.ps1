#ps1
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string[]] $TopDirs,
  [switch] $Reload
)

# ===== CONFIG =====
$GitBash           = "C:\Program Files\Git\bin\bash.exe"
$LocalOverrideFile = ".run-cmd"
$CacheFile         = "$env:USERPROFILE\.ws-launcher-cache.json"

$Config = @{
  TopDirs  = @( "C:\git\ct" )
  Services = @(
    # [PSCustomObject]@{ Title = "My Service"; Dir = "C:\git\ct\repo"; Cmd = "npm start"; Exec = $true }
  )
}

# ===== LOADING SCREEN =====

function Show-Loading ([string]$Message = "Scanning repositories...") {
  Clear-Host
  Write-Host ""
  Write-Host "  $Message" -ForegroundColor Cyan
  Write-Host ""
}

function Show-LoadingProgress ([string]$Item) {
  Write-Host "  + $Item" -ForegroundColor DarkGray
}

# ===== CACHE =====

function Read-Cache {
  if (-not (Test-Path $CacheFile)) { return $null }
  try {
    $raw = Get-Content $CacheFile -Raw | ConvertFrom-Json
    return @($raw | ForEach-Object {
      $entry = $_
      [PSCustomObject]@{
        Title     = [string]$entry.Title
        Dir       = [string]$entry.Dir
        Cmd       = [string]$entry.Cmd
        Exec      = [bool]$entry.Exec
        IsBare    = [bool]$entry.IsBare
        MenuLabel = [string]$entry.MenuLabel
        Worktrees = @($entry.Worktrees | ForEach-Object {
          [PSCustomObject]@{
            Path   = [string]$_.Path
            Branch = [string]$_.Branch
          }
        })
      }
    })
  } catch {
    Write-Host "  [warn] Cache read failed, re-scanning..." -ForegroundColor DarkYellow
    return $null
  }
}

function Write-Cache ([array]$Repos) {
  try {
    $Repos | ConvertTo-Json -Depth 5 | Set-Content $CacheFile -Encoding UTF8
  } catch {
    Write-Host "  [warn] Could not write cache: $_" -ForegroundColor DarkYellow
  }
}

# ===== GIT HELPERS =====

function Test-BareRepo ([string]$Dir) {
  if (-not $Dir) { return $false }
  return (& git -C $Dir rev-parse --is-bare-repository 2>$null) -eq "true"
}

function Test-GitRepo ([string]$Dir) {
  if (-not $Dir) { return $false }
  & git -C $Dir rev-parse --git-dir 2>$null | Out-Null
  return $LASTEXITCODE -eq 0
}

function Get-WorktreesForBare ([string]$BareDir) {
  $worktrees = @()
  $path = $branch = $null
  $isBareRoot = $false

  # -z uses NUL as separator
  $raw = & git -C $BareDir worktree list --porcelain -z 2>$null
  $fields = $raw -split '\0' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

  foreach ($field in $fields) {
    if ($field -match '^worktree (.+)') {
      # INLINED FLUSH
      if ($path -and -not $isBareRoot) {
        $worktrees += [PSCustomObject]@{
          Path   = $path.Replace('/', '\')
          Branch = if ($branch) { $branch } else { "(detached)" }
        }
      }
      # Reset state for the NEW worktree we just found
      $path = $Matches[1].Trim()
      $branch = $null
      $isBareRoot = $false
    }
    elseif ($field -match '^branch refs/heads/(.+)') {
      $branch = $Matches[1].Trim()
    }
    elseif ($field -eq "bare") {
      $isBareRoot = $true
    }
  }
  
  # FINAL INLINED FLUSH for the last item
  if ($path -and -not $isBareRoot) {
    $worktrees += [PSCustomObject]@{
      Path   = $path.Replace('/', '\')
      Branch = if ($branch) { $branch } else { "(detached)" }
    }
  }

  return $worktrees
}
# ===== REPO DISCOVERY =====

function New-RepoEntry ([string]$Title, [string]$Dir, [string]$Cmd = "", [bool]$Exec = $true) {
  Show-LoadingProgress $Title

  $isBare    = Test-BareRepo $Dir
  $worktrees = if ($isBare) { Get-WorktreesForBare $Dir } else { @() }

  $bareSuffix = if ($isBare) { " [bare]" } else { "" }
  $modePrefix = if ($Exec)   { "[RUN]"   } else { "[OPEN]" }

  return [PSCustomObject]@{
    Title     = $Title
    Dir       = $Dir
    Cmd       = $Cmd
    Exec      = $Exec
    IsBare    = $isBare
    MenuLabel = "$modePrefix$bareSuffix  $Title  ($Dir)"
    Worktrees = $worktrees
  }
}

function Find-GitRepos ([string]$TopDir) {
  if (-not (Test-Path $TopDir)) { return @() }
  return Get-ChildItem -Path $TopDir -Directory |
    Where-Object   { Test-GitRepo $_.FullName } |
    ForEach-Object { New-RepoEntry $_.Name $_.FullName }
}

function Get-EffectiveCmd ([string]$Dir, [string]$DefaultCmd) {
  if ([string]::IsNullOrWhiteSpace($Dir)) { return $DefaultCmd }
  $overridePath = Join-Path $Dir $LocalOverrideFile
  if (Test-Path $overridePath) {
    $override = (Get-Content $overridePath -Raw).Trim()
    if ($override) { return $override }
  }
  return $DefaultCmd
}

function Resolve-RepoList {
  if (-not $Reload) {
    $cached = Read-Cache
    if ($cached -and $cached.Count -gt 0) { return $cached }
  }

  Show-Loading "Scanning repositories, please wait..."

  $effectiveTopDirs = if ($TopDirs -and $TopDirs.Count -gt 0) { $TopDirs } else { $Config.TopDirs }

  $explicit   = @($Config.Services | ForEach-Object { New-RepoEntry $_.Title $_.Dir $_.Cmd $_.Exec })
  $discovered = @($effectiveTopDirs | ForEach-Object { Find-GitRepos $_ })

  $all = @($explicit + $discovered | Where-Object { $_ })

  Write-Cache $all
  return $all
}

# ===== INTERACTIVE MENU =====

function Show-Menu {
  param(
    [string]      $Title,
    [array]       $Items,
    [scriptblock] $LabelScript,
    [bool]        $MultiSelect = $false,
    [scriptblock] $KeyHandler  = $null
  )

  if (-not $Items -or $Items.Count -eq 0) { return $null }

  $idx      = 0
  $selected = [bool[]](@($false) * $Items.Count)

  while ($true) {
    # Recompute labels on every outer loop iteration (triggered by Refresh)
    $labels = @($Items | ForEach-Object { & $LabelScript $_ })

    while ($true) {
      Clear-Host
      Write-Host "=== $Title ===" -ForegroundColor Cyan
      $hint = if ($MultiSelect) {
        "[UP/DOWN] Move  [SPACE] Toggle  [A] All  [R] Rescan  [ENTER] Confirm  [ESC] Cancel"
      } else {
        "[UP/DOWN] Move  [ENTER] Confirm  [ESC] Cancel"
      }
      Write-Host "$hint`n" -ForegroundColor DarkCyan

      for ($i = 0; $i -lt $Items.Count; $i++) {
        $ptr   = if ($i -eq $idx) { ">" } else { " " }
        $color = if ($i -eq $idx) { "Yellow" } else { "White" }
        $lines = $labels[$i] -split "`n"

        if ($MultiSelect) {
          $chk = if ($selected[$i]) { "[X]" } else { "[ ]" }
          Write-Host "$ptr $chk $($lines[0])" -ForegroundColor $color
        } else {
          Write-Host "$ptr  $($lines[0])" -ForegroundColor $color
        }
        # Render indented worktree sub-lines
        if ($lines.Count -gt 1) {
          for ($j = 1; $j -lt $lines.Count; $j++) {
            Write-Host "       $($lines[$j])" -ForegroundColor DarkGray
          }
        }
      }

      $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

      # Delegate to custom key handler first
      if ($KeyHandler) {
        $action = & $KeyHandler $k $Items[$idx]
        if ($action -eq "Refresh") { break }   # Break inner loop -> recompute labels
        if ($action -eq "Exit")    { return $null }
      }

      switch ($k.VirtualKeyCode) {
        38 { if ($idx -gt 0)                { $idx-- } }
        40 { if ($idx -lt $Items.Count - 1) { $idx++ } }
        32 { if ($MultiSelect)              { $selected[$idx] = -not $selected[$idx] } }
        65 {
          if ($MultiSelect) {
            $v = $selected -contains $false
            for ($j = 0; $j -lt $selected.Count; $j++) { $selected[$j] = $v }
          }
        }
        13 {
          if ($MultiSelect) {
            return @(0..($Items.Count - 1) | Where-Object { $selected[$_] } | ForEach-Object { $Items[$_] })
          }
          return $Items[$idx]
        }
        27 { return $null }
      }
    }
  }
}

# ===== PICKERS =====

function Select-Repos ([array]$Services) {
  $handler = {
    param($key, $currentItem)
    if ($key.Character -eq 'r' -or $key.Character -eq 'R') {
      if ($currentItem.IsBare) {
        Clear-Host
        Write-Host ""
        Write-Host "  Rescanning worktrees for '$($currentItem.Title)'..." -ForegroundColor Cyan
        Write-Host ""
        $currentItem.Worktrees = Get-WorktreesForBare $currentItem.Dir
        $count = $currentItem.Worktrees.Count
        Write-Host "  Found $count worktree(s)." -ForegroundColor Green
        Write-Cache $Services
        Start-Sleep -Milliseconds 600
        return "Refresh"
      } else {
        return "Continue"
      }
    }
    return "Continue"
  }

  return Show-Menu `
    -Title       "Select Repos to Launch" `
    -Items       $Services `
    -LabelScript {
      param($s)
      $base = $s.MenuLabel
      if ($s.IsBare -and $s.Worktrees -and $s.Worktrees.Count -gt 0) {
        $wtLines = $s.Worktrees |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
          ForEach-Object { "- [$($_.Branch)]  $($_.Path)" }
        return "$base`n$($wtLines -join "`n")"
      }
      return $base
    } `
    -MultiSelect $true `
    -KeyHandler  $handler
}

function Select-Worktree ($Srv) {
  $worktrees = @($Srv.Worktrees | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) })

  if ($worktrees.Count -eq 0) {
    Write-Host "No worktrees found for: $($Srv.Dir)" -ForegroundColor Red
    Start-Sleep -Seconds 2
    return $null
  }
  if ($worktrees.Count -eq 1) { return $worktrees[0] }

  return Show-Menu `
    -Title       "Select Worktree -- $($Srv.Title)" `
    -Items       $worktrees `
    -LabelScript { param($wt) "[$($wt.Branch)]  $($wt.Path)" } `
    -MultiSelect $false
}

function Confirm-Launch ([string]$Title, [string]$Dir, [string]$Cmd) {
  Clear-Host
  Write-Host "=== Confirm Launch: $Title ===" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  Dir : " -NoNewline; Write-Host $Dir  -ForegroundColor Green
  Write-Host "  Cmd : " -NoNewline; Write-Host $Cmd  -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Press [Y] to execute, [N] / [ESC] to skip..." -ForegroundColor DarkCyan

  while ($true) {
    $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($k.Character -eq 'y' -or $k.Character -eq 'Y') { return $true  }
    if ($k.Character -eq 'n' -or $k.Character -eq 'N') { return $false }
    if ($k.VirtualKeyCode -eq 27)                       { return $false }
  }
}

# ===== LAUNCH =====

function Start-GitBashTab ([string]$Title, [string]$Dir, [string]$Cmd, [bool]$Exec) {
  if ($Exec) {
    wt.exe -w 0 new-tab -p "Git Bash" --title $Title -d $Dir -- "$GitBash" -li -c "$Cmd"
  } else {
    wt.exe -w 0 new-tab -p "Git Bash" --title $Title -d $Dir -- "$GitBash" -li -c "echo 'Open: $Dir'; exec bash"
  }
}

function Launch-Service ($Srv) {
  if ($Srv.IsBare) {
    $wt = Select-Worktree $Srv
    if (-not $wt) {
      Write-Host "Skipped '$($Srv.Title)' -- no worktree selected." -ForegroundColor DarkYellow
      return
    }
    $launchDir = $wt.Path
  } else {
    $launchDir = $Srv.Dir
  }

  $cmd = Get-EffectiveCmd $launchDir $Srv.Cmd

  if ($Srv.Exec -and $cmd) {
    if (-not (Confirm-Launch $Srv.Title $launchDir $cmd)) {
      Write-Host "Skipped '$($Srv.Title)'." -ForegroundColor DarkYellow
      return
    }
  }

  Start-GitBashTab $Srv.Title $launchDir $cmd $Srv.Exec
}

# ===== MAIN =====

$Services = Resolve-RepoList

if (-not $Services -or $Services.Count -eq 0) {
  Write-Host "No repos found. Check your TopDirs / Services config." -ForegroundColor Red
  exit 1
}

$toRun = Select-Repos $Services

if (-not $toRun -or $toRun.Count -eq 0) {
  Write-Host "`nNo repos selected. Exiting." -ForegroundColor DarkYellow
  exit 0
}

Write-Host "`nLaunching $($toRun.Count) service(s)...`n" -ForegroundColor Green

foreach ($s in $toRun) {
  Launch-Service $s
}
