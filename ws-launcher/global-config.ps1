# ============================================================
# ws-launcher – global.json laden und Auflösen (PowerShell 5.1+)
# Erwartet beim Dot-Source: $GlobalConfig, $Config (aus config.ps1)
# Setzt: $GlobalDefaults, ggf. $GitBash, $GitBashProfile, $Config.*
#
# Referenz-Syntax:
#   $use:key  – in services/definitions (z. B. cmd: "($use:cmdBackend)")
#   $ref:key  – Pfad referenziert anderen Pfad (z. B. "C:/git/other": "$($ref:ct-angular-ui-bare)")
# ============================================================

function Resolve-DefinitionsInValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,
        [hashtable]$Definitions
    )
    if (-not $Definitions -or $Definitions.Count -eq 0) { return $Value }
    if ($null -eq $Value) { return $Value }
    if ($Value -is [string]) {
        $result = [regex]::Replace($Value, '\(\$use:([^)]+)\)|\$\(\$use:([^)]+)\)', {
            param($m)
            $k = if ($m.Groups[1].Success) { $m.Groups[1].Value.Trim() } else { $m.Groups[2].Value.Trim() }
            if ($Definitions.ContainsKey($k)) { return $Definitions[$k] }
            return $m.Value
        })
        return $result
    }
    if ($Value -is [System.Collections.IList] -or $Value -is [array]) {
        $out = @()
        foreach ($item in @($Value)) {
            $out += Resolve-DefinitionsInValue -Value $item -Definitions $Definitions
        }
        return $out
    }
    if ($Value -is [PSCustomObject] -or $Value.GetType().Name -eq 'PSCustomObject') {
        $out = [PSCustomObject]@{}
        foreach ($p in $Value.PSObject.Properties) {
            $resolved = Resolve-DefinitionsInValue -Value $p.Value -Definitions $Definitions
            $out | Add-Member -NotePropertyName $p.Name -NotePropertyValue $resolved -Force
        }
        return $out
    }
    return $Value
}

function Resolve-GlobalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawPath,
        [Parameter(Mandatory = $true)]
        [array]$TopDirObjects
    )
    $normalized = $RawPath.Replace('/', '\')
    if ([System.IO.Path]::IsPathRooted($normalized)) {
        $res = Resolve-Path -Path $normalized -ErrorAction SilentlyContinue
        if ($res) { return $res.Path }
        return $null
    }
    foreach ($obj in $TopDirObjects) {
        $candidate = Join-Path $obj.path $normalized
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Sync-ConfigApplications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ResolvedConfig
    )
    $prop = $ResolvedConfig.PSObject.Properties['applications']
    if (-not $prop) { $prop = $ResolvedConfig.PSObject.Properties['Applications'] }
    if (-not $prop) { return }
    $arr = @($prop.Value)
    $script:Config.Applications = $arr
    $Config.Applications = $arr
}

function Sync-ConfigIde {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ResolvedConfig
    )
    if ($null -eq $ResolvedConfig.PSObject.Properties['ide']) { return }
    $ide = $ResolvedConfig.ide
    $cmd = "code"
    $args = @()
    if ($ide -is [string]) {
        $t = $ide.Trim()
        if ($t) { $cmd = $t }
    }
    elseif ($ide -and $ide.PSObject.Properties) {
        if ($ide.command) { $cmd = [string]$ide.command }
        elseif ($ide.executable) { $cmd = [string]$ide.executable }
        if ($ide.arguments) { $args = @($ide.arguments) }
    }
    $script:Config.IdeCommand = $cmd
    $script:Config.IdeArguments = $args
    $Config.IdeCommand = $cmd
    $Config.IdeArguments = $args
}

function Initialize-GlobalConfig {
    [CmdletBinding()]
    param()

    $script:GlobalDefaults = @()
    if (-not (Test-Path -LiteralPath $GlobalConfig)) {
        return
    }
    try {
        $json = Get-Content -LiteralPath $GlobalConfig -Raw | ConvertFrom-Json
        $definitions = @{}
        if ($json.definitions) {
            foreach ($p in $json.definitions.PSObject.Properties) {
                $definitions[$p.Name] = $p.Value
            }
        }
        if ($json.config) {
            $c = Resolve-DefinitionsInValue -Value $json.config -Definitions $definitions
            if ($null -ne $c.PSObject.Properties['GitBash'])          { $script:GitBash = $c.GitBash }
            if ($null -ne $c.PSObject.Properties['GitBashProfile'])   { $script:GitBashProfile = $c.GitBashProfile }
            if ($null -ne $c.PSObject.Properties['RepoConfigFile'])   { $script:RepoConfigFile = $c.RepoConfigFile }
            if ($null -ne $c.PSObject.Properties['TopDirs'])           { $script:Config.TopDirs = @($c.TopDirs) }
            if ($null -ne $c.PSObject.Properties['Services'])         { $script:Config.Services = @($c.Services) }
            Sync-ConfigApplications -ResolvedConfig $c
            Sync-ConfigIde -ResolvedConfig $c
        }
        if ($json.defaults) {
            $script:GlobalDefaults = @(Resolve-DefinitionsInValue -Value $json.defaults -Definitions $definitions)
        }
        else {
            $pathOrder = @()
            $pathToServices = @{}
            $refsToResolve = @()
            foreach ($prop in $json.PSObject.Properties) {
                if ($prop.Name -eq 'config' -or $prop.Name -eq 'definitions') { continue }
                $val = $prop.Value
                if (-not $val) { continue }
                $ref = $null
                $override = $null
                if ($val -is [string]) {
                    $m = [regex]::Match($val.Trim(), '^\(\$ref:([^)]+)\)$|^\$\(\$ref:([^)]+)\)$')
                    if ($m.Success) {
                        $ref = if ($m.Groups[1].Success) { $m.Groups[1].Value.Trim() } else { $m.Groups[2].Value.Trim() }
                    }
                }
                elseif ($val.PSObject.Properties['$ref']) {
                    $ref = $val.'$ref'
                    if ($val.PSObject.Properties['override']) {
                        $override = $val.override
                    }
                    elseif ($val.PSObject.Properties['env']) {
                        $override = [PSCustomObject]@{ env = $val.env }
                    }
                }
                if ($ref) {
                    $refsToResolve += [PSCustomObject]@{ path = $prop.Name; ref = $ref; override = $override }
                }
                elseif ($val.services) {
                    $pathOrder += $prop.Name
                    $pathToServices[$prop.Name] = Resolve-DefinitionsInValue -Value $val.services -Definitions $definitions
                }
            }
            foreach ($r in $refsToResolve) {
                if (-not $pathToServices.ContainsKey($r.ref)) { continue }
                $pathOrder += $r.path
                $sourceServices = $pathToServices[$r.ref]
                if (-not $r.override) {
                    $pathToServices[$r.path] = $sourceServices
                    continue
                }
                $serviceFieldNames = @("env", "cmd", "title", "dir")
                $globalOverrides = @{}
                $perServiceOverrides = @{}
                foreach ($keyProp in $r.override.PSObject.Properties) {
                    $k = $keyProp.Name
                    if ($serviceFieldNames -contains $k) {
                        $globalOverrides[$k] = $keyProp.Value
                    }
                    else {
                        $perServiceOverrides[$k] = $keyProp.Value
                    }
                }
                $cloned = @()
                foreach ($svc in @($sourceServices)) {
                    $copy = [PSCustomObject]@{}
                    foreach ($p in $svc.PSObject.Properties) {
                        $copy | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
                    }
                    foreach ($k in $globalOverrides.Keys) {
                        $resolved = Resolve-DefinitionsInValue -Value $globalOverrides[$k] -Definitions $definitions
                        $copy | Add-Member -NotePropertyName $k -NotePropertyValue $resolved -Force
                    }
                    $svcTitle = $copy.title
                    if ($perServiceOverrides.ContainsKey($svcTitle)) {
                        $sOver = $perServiceOverrides[$svcTitle]
                        foreach ($keyProp in $sOver.PSObject.Properties) {
                            $resolved = Resolve-DefinitionsInValue -Value $keyProp.Value -Definitions $definitions
                            $copy | Add-Member -NotePropertyName $keyProp.Name -NotePropertyValue $resolved -Force
                        }
                    }
                    $cloned += $copy
                }
                $pathToServices[$r.path] = $cloned
            }
            foreach ($p in $pathOrder) {
                $script:GlobalDefaults += [PSCustomObject]@{ path = $p; services = $pathToServices[$p] }
            }
        }
        if ($VerbosePreference -eq 'Continue') {
            Write-Verbose "global.json (resolved): $GlobalConfig"
            if ($definitions -and $definitions.Count -gt 0) {
                $defJson = ($definitions.GetEnumerator() | ForEach-Object { "  $($_.Key) = $($_.Value)" }) -join "`n"
                Write-Verbose "Definitions:`n$defJson"
            }
            Write-Verbose "Path defaults (resolved):"
            foreach ($entry in $script:GlobalDefaults) {
                Write-Verbose "  [$($entry.path)] $($entry.services.Count) service(s)"
                foreach ($s in @($entry.services)) {
                    $envPart = if ($s.env) { "env=$($s.env)" } else { "env=" }
                    $cmdPart = if ($s.cmd) { "cmd=$($s.cmd)" } else { "cmd=" }
                    Write-Verbose "    - $($s.title): $envPart, $cmdPart"
                }
            }
        }
    }
    catch {
        Write-Host "[WARN] Failed to parse global.json: $_" -ForegroundColor DarkYellow
    }
}
