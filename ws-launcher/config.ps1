# ============================================================
# ws-launcher – Konfiguration (PowerShell 5.1+)
# ============================================================

# Git Bash (bei Dot-Source in Aufrufer-Skript sichtbar)
$GitBash        = "C:\Program Files\Git\bin\bash.exe"
$GitBashProfile = "Git Bash"

# Dateinamen / Pfade
$RepoConfigFile = ".ws-config.json"
$GlobalConfig   = Join-Path $env:USERPROFILE ".ws-launcher\global.json"
$CacheFile      = Join-Path $env:USERPROFILE ".ws-launcher\cache.json"

# Suchpfade und optionale feste Services
$Config = [ordered]@{
    TopDirs        = @("C:\git\ct")
    Services       = @()
    Applications   = @()
    IdeCommand     = "code"
    IdeArguments   = @()
}
