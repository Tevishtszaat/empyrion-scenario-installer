<#
.SYNOPSIS
  Scenario Installer for Empyrion - Galactic Survival (default scenario: Ascension-Reborn).

.DESCRIPTION
  1. Finds your Empyrion install (Steam registry + libraryfolders.vdf), or lets you browse.
  2. Downloads the scenario zip from Google Drive (resumable, with retries), or uses a zip you already have.
  3. Extracts it to <Empyrion>\Content\Scenarios\<ScenarioName>, where <ScenarioName> is the zip's top folder
     (fallback: the zip file name, then 'Ascension-Reborn')
     (an existing copy is moved to <Empyrion>\Content\Scenarios_Backups\..., never deleted).
  4. Copies the scenario's SharedData into the save / server-cache folder(s) you pick
     (<Empyrion>\Saves\Games\<Game>\SharedData or <Empyrion>\Saves\Cache\<Game>\SharedData).

  Run with no parameters for the GUI. Parameters allow an unattended / console install.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -STA -File Install-Scenario.ps1
.NOTES
  Optional installer.json next to the exe / .ps1 (or -Config <path>) changes the defaults:
    { "defaultUrl": "...", "scenarioName": "...", "testFolderName": "...", "title": "..." }
  Without it, the built-in defaults (the Ascension-Reborn Google Drive link) are used.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Install-Scenario.ps1 -NoGui -EmpyrionPath "D:\Steam\steamapps\common\Empyrion - Galactic Survival" -SaveFolder "D:\...\Saves\Games\MyGame"
#>
[CmdletBinding()]
param(
    [switch]$NoGui,                 # console mode
    [string]$EmpyrionPath,          # override auto-detect
    [string]$ArchivePath,           # use an already-downloaded scenario zip (skip download)
    [string]$DownloadUrl,           # download link (Google Drive / Dropbox / OneDrive / direct zip). Default: the Ascension-Reborn Drive link
    [string]$DownloadFolder,        # where to put the downloaded zip (default: %USERPROFILE%\Downloads)
    [string[]]$SaveFolder,          # one or more save/cache folders to receive SharedData
    [switch]$SkipSharedData,        # don't copy SharedData into any save
    [switch]$OverwriteInPlace,      # don't back up an existing scenario folder, overwrite files in place
    [switch]$DeleteArchiveAfter,    # remove the downloaded zip after a successful install
    [switch]$SkipSpaceCheck,
    [switch]$ListOnly,              # console: just print detected folders and exit
    [switch]$TestInstall,           # install into a separate test folder instead of the real Empyrion folder
    [string]$TestFolder,            # test folder root (default: <Empyrion drive>\AR_InstallTest, or testFolderName from installer.json)
    [string]$Config                 # installer.json to use (default: installer.json next to the exe / .ps1, if present)
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------- constants
$script:Product        = 'Scenario Installer'
$script:ScenarioName   = 'Ascension-Reborn'   # default / fallback only: the real name comes from the zip's top folder
$script:DriveFileId    = '1jtetatjWTRW-JWj1YJkHJP77fXZLd-vh'
$script:ArchiveName    = 'Ascension-Reborn.zip'
$script:DefaultDownloadUrl = 'https://drive.google.com/file/d/1jtetatjWTRW-JWj1YJkHJP77fXZLd-vh/view?usp=drive_link'
$script:LastRemoteFileName = $null
$script:FallbackArchiveSize = [int64]19072427908      # used only if Drive doesn't report a size
$script:FallbackUncompressed = [int64]20788872025
$script:AppIds = [ordered]@{ '383120' = 'Empyrion - Galactic Survival'; '530870' = 'Empyrion - Dedicated Server' }
$script:Version = '1.0.6'
$script:Cancel = $false
$script:LogBox = $null
$script:ProgressCb = $null       # scriptblock(percent:int, text:string)
$script:LastScenarioName = 'Ascension-Reborn'
$script:AskRetry = $null         # scriptblock(message:string) -> $true to retry (GUI: Retry/Cancel box)
$script:MoveDirImpl = { param($from, $to) [IO.Directory]::Move($from, $to) }   # same-volume rename: all-or-nothing (tests may override)
$script:LogFile = Join-Path ([IO.Path]::GetTempPath()) 'ScenarioInstaller.log'
$script:IsWin = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$script:TestFolderName = 'AR_InstallTest'
$script:Title = $null                 # optional window/header title (installer.json "title")
$script:DefaultIsBuiltin = $true      # default link is the built-in Ascension-Reborn one (known size/name)
$script:DefaultNameKnown = $true      # the default link's scenario name is known before downloading
$script:ConfigScenarioName = $null    # installer.json "scenarioName": forced name for the default download
$script:DefaultDirectUrl = $null      # normalized default link when it is not a Google Drive link
$script:ConfigPath = $null; $script:ConfigNotes = @()

# ----------------------------------------------------------------- helpers
function Write-Log([string]$msg) {
    $line = '{0:HH:mm:ss}  {1}' -f (Get-Date), $msg
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
    if ($script:LogBox) { $script:LogBox.AppendText($line + "`r`n"); Pump } else { Write-Host $line }
}
function Pump { if ($script:LogBox) { [System.Windows.Forms.Application]::DoEvents() } }
function Report([int]$pct, [string]$text) {
    if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
    if ($script:ProgressCb) { & $script:ProgressCb $pct $text }
    else { Write-Progress -Activity $script:Product -Status $text -PercentComplete $pct }
}
function Check-Cancel { Pump; if ($script:Cancel) { throw 'Cancelled by user.' } }
function Format-Size([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N1} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f ($b / 1KB)
}
function Get-FullPathSafe([string]$p) { return [IO.Path]::GetFullPath($p).TrimEnd('\','/') }

# ----------------------------------------------------------------- Steam / Empyrion discovery
function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    if ($script:IsWin) {
        $keys = @(
            @{ Path = 'HKCU:\Software\Valve\Steam';               Name = 'SteamPath'   },
            @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam';   Name = 'InstallPath' },
            @{ Path = 'HKLM:\SOFTWARE\Valve\Steam';               Name = 'InstallPath' }
        )
        foreach ($k in $keys) {
            try {
                $v = (Get-ItemProperty -Path $k.Path -Name $k.Name -ErrorAction Stop).($k.Name)
                if ($v) { $roots.Add(($v -replace '/', '\\')) }
            } catch {}
        }
        foreach ($d in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) { if ($d -and $d -ne '\Steam') { $roots.Add($d) } }
    } else {
        # Linux and macOS common Steam locations (including Flatpak Steam on Linux)
        $home = if ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
        $cands = @(
            (Join-Path $home '.steam/steam'),
            (Join-Path $home '.local/share/Steam'),
            (Join-Path $home '.steam/root'),
            (Join-Path $home 'Library/Application Support/Steam'),
            (Join-Path $home '.var/app/com.valvesoftware.Steam/.local/share/Steam')
        )
        foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { $roots.Add($c) } }
    }
    $out = @(); $seen = @{}
    foreach ($r in $roots) {
        try { $f = Get-FullPathSafe $r } catch { continue }
        if (-not $seen.ContainsKey($f.ToLowerInvariant()) -and (Test-Path -LiteralPath $f)) { $seen[$f.ToLowerInvariant()] = 1; $out += $f }
    }
    return ,$out
}

# Parses libraryfolders.vdf (new format: "path" "X:\\Lib"; old format: "1" "X:\\Lib")
function Get-VdfLibraryPaths([string]$vdfText) {
    $paths = @()
    foreach ($m in [regex]::Matches($vdfText, '"path"\s+"((?:[^"\\]|\\.)*)"', 'IgnoreCase')) {
        $paths += ($m.Groups[1].Value -replace '\\\\', '\')
    }
    if ($paths.Count -eq 0) {
        foreach ($m in [regex]::Matches($vdfText, '^\s*"\d+"\s+"((?:[^"\\]|\\.)*)"\s*$', 'Multiline')) {
            $v = $m.Groups[1].Value -replace '\\\\', '\'
            if ($v -match '^[A-Za-z]:\\|^/|^\\\\') { $paths += $v }
        }
    }
    return ,$paths
}

# Reads "installdir" from an appmanifest_*.acf
function Get-AcfInstallDir([string]$acfText) {
    $m = [regex]::Match($acfText, '"installdir"\s+"((?:[^"\\]|\\.)*)"', 'IgnoreCase')
    if ($m.Success) { return ($m.Groups[1].Value -replace '\\\\', '\') }
    return $null
}

function Get-SteamLibraries([string[]]$steamRoots) {
    $libs = @(); $seen = @{}
    foreach ($root in $steamRoots) {
        $cands = @($root)
        foreach ($vdf in @((Join-Path (Join-Path $root 'steamapps') 'libraryfolders.vdf'), (Join-Path (Join-Path $root 'config') 'libraryfolders.vdf'))) {
            if (Test-Path -LiteralPath $vdf) {
                try { $cands += Get-VdfLibraryPaths ([IO.File]::ReadAllText($vdf)) } catch { Write-Log "Could not read $vdf : $_" }
            }
        }
        foreach ($c in $cands) {
            try { $f = Get-FullPathSafe $c } catch { continue }
            if (-not $seen.ContainsKey($f.ToLowerInvariant()) -and (Test-Path -LiteralPath $f)) { $seen[$f.ToLowerInvariant()] = 1; $libs += $f }
        }
    }
    return ,$libs
}

function Test-EmpyrionDir([string]$p) {
    if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Container)) { return $false }
    foreach ($marker in @('EmpyrionLauncher.exe','Empyrion.exe','EmpyrionDedicated.exe','EmpyrionDedicated.cmd')) {
        if (Test-Path -LiteralPath (Join-Path $p $marker)) { return $true }
    }
    return (Test-Path -LiteralPath (Join-Path (Join-Path $p 'Content') 'Scenarios')) -or
           (Test-Path -LiteralPath (Join-Path $p 'Empyrion_Data')) -or
           (Test-Path -LiteralPath (Join-Path $p 'EmpyrionDedicated_Data'))
}

# Returns objects: @{ Path; Kind } for every Empyrion client / dedicated server install found
function Find-EmpyrionInstalls([string[]]$libraries) {
    $found = @(); $seen = @{}
    foreach ($lib in $libraries) {
        $sa = Join-Path $lib 'steamapps'
        foreach ($id in $script:AppIds.Keys) {
            $dirName = $script:AppIds[$id]
            $acf = Join-Path $sa "appmanifest_$id.acf"
            if (Test-Path -LiteralPath $acf) {
                try { $d = Get-AcfInstallDir ([IO.File]::ReadAllText($acf)); if ($d) { $dirName = $d } } catch {}
            }
            $p = Join-Path (Join-Path $sa 'common') $dirName
            if ((Test-EmpyrionDir $p) -and -not $seen.ContainsKey($p.ToLowerInvariant())) {
                $seen[$p.ToLowerInvariant()] = 1
                $kind = 'Game'; if ($id -eq '530870') { $kind = 'Dedicated Server' }
                $found += New-Object psobject -Property @{ Path = $p; Kind = $kind }
            }
        }
    }
    return ,$found
}

# Lists candidate save folders: Saves\Games\* and Saves\Cache\* (excluding _SharedDataZips)
function Get-SaveFolders([string]$empyrion) {
    $res = @()
    foreach ($sub in @('Games','Cache')) {
        $d = Join-Path (Join-Path $empyrion 'Saves') $sub
        if (Test-Path -LiteralPath $d) {
            foreach ($g in (Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
                if ($g.Name -like '_*') { continue }
                $res += New-Object psobject -Property @{ Path = $g.FullName; Kind = $sub; Name = $g.Name; HasShared = (Test-Path -LiteralPath (Join-Path $g.FullName 'SharedData')) }
            }
        }
    }
    return ,$res
}

# ----------------------------------------------------------------- disk space
function Get-FreeBytes([string]$path) {
    $p = $path
    while ($p -and -not (Test-Path -LiteralPath $p)) { $p = Split-Path -Parent $p }
    if (-not $p) { return [int64]-1 }
    try {
        $root = [IO.Path]::GetPathRoot((Get-FullPathSafe $p) + [IO.Path]::DirectorySeparatorChar)
        return [int64](New-Object IO.DriveInfo($root)).AvailableFreeSpace
    } catch { return [int64]-1 }
}
function Get-VolumeKey([string]$path) {
    try { return [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($path)).ToLowerInvariant() } catch { return $path }
}
# $needs = list of @{Path; Bytes}. Sums per volume and compares with free space. Returns list of problems.
function Test-DiskSpace($needs) {
    $byVol = @{}; $sample = @{}
    foreach ($n in $needs) {
        $k = Get-VolumeKey $n.Path
        if (-not $byVol.ContainsKey($k)) { $byVol[$k] = [int64]0; $sample[$k] = $n.Path }
        $byVol[$k] += [int64]$n.Bytes
    }
    $problems = @()
    foreach ($k in $byVol.Keys) {
        $free = Get-FreeBytes $sample[$k]
        $need = [int64]($byVol[$k] * 1.03) + 500MB
        Write-Log ("Drive {0}: needs about {1}, free {2}" -f $k, (Format-Size $need), (Format-Size $free))
        if ($free -ge 0 -and $free -lt $need) { $problems += ("Drive {0} needs about {1} free but only has {2}." -f $k, (Format-Size $need), (Format-Size $free)) }
    }
    return ,$problems
}

# ----------------------------------------------------------------- download (Google Drive, resumable)
function Initialize-Net {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    try { [Net.ServicePointManager]::DefaultConnectionLimit = 8 } catch {}
}
function Get-DriveUrl([string]$id, [string]$uuid) {
    $u = "https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"
    if ($uuid) { $u += "&uuid=$uuid" }
    return $u
}
function New-Req([string]$url, [int64]$from, [int64]$to = -1) {
    $r = [Net.HttpWebRequest]::Create($url)
    $r.UserAgent = "ScenarioInstaller/$($script:Version)"
    $r.AllowAutoRedirect = $true
    $r.Timeout = 60000
    $r.ReadWriteTimeout = 120000
    if ($to -ge $from -and $to -ge 0) { $r.AddRange([int64]$from, [int64]$to) }
    elseif ($from -gt 0) { $r.AddRange([int64]$from) }
    return $r
}
# Parses a Drive HTML interstitial ("can't scan for viruses") into a direct URL, or $null
function Get-DriveConfirmUrl([string]$html, [string]$id) {
    $action = [regex]::Match($html, 'action="([^"]+)"')
    if (-not $action.Success) { return $null }
    $q = @()
    foreach ($m in [regex]::Matches($html, '<input[^>]+type="hidden"[^>]*>')) {
        $n = [regex]::Match($m.Value, 'name="([^"]+)"'); $v = [regex]::Match($m.Value, 'value="([^"]*)"')
        if ($n.Success) { $q += ($n.Groups[1].Value + '=' + [Uri]::EscapeDataString([Net.WebUtility]::HtmlDecode($v.Groups[1].Value))) }
    }
    if ($q.Count -eq 0) { return $null }
    return ([Net.WebUtility]::HtmlDecode($action.Groups[1].Value) + '?' + ($q -join '&'))
}
function Get-UrlHash([string]$u) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($u))) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-QueryParam([string]$query, [string]$name) {
    $m = [regex]::Match($query, '(?:^|[?&])' + [regex]::Escape($name) + '=([^&#]*)', 'IgnoreCase')
    if ($m.Success) { return [Uri]::UnescapeDataString($m.Groups[1].Value) }
    return $null
}
function Set-QueryParam([string]$query, [string]$name, [string]$value) {
    $parts = @($query.TrimStart('?').Split('&') | Where-Object { $_ -and ($_ -notmatch ('^' + [regex]::Escape($name) + '(=|$)')) })
    $parts += ($name + '=' + $value)
    return ($parts -join '&')
}
# Turns whatever link the player pasted into something we can download.
# Kind: Drive | Direct | Mega | DriveFolder | Invalid.  Message is set for the last three.
function Resolve-DownloadUrl([string]$raw) {
    $r = New-Object psobject -Property @{ Kind = 'Invalid'; Url = $null; Host = ''; Id = $null; Label = ''; Message = ''; FileHint = $null; IsDefault = $false; Original = $raw }
    $u = ''; if ($raw) { $u = $raw.Trim().Trim('"', "'", '<', '>', ' ') }
    if (-not $u) { $u = $script:DefaultDownloadUrl }
    $uri = $null
    if (-not [Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$uri) -or ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https')) {
        $r.Message = 'That is not a web link. Paste an http:// or https:// download link (Google Drive, Dropbox, OneDrive or a direct link to a .zip).'
        return $r
    }
    $h = $uri.Host.ToLowerInvariant(); $r.Host = $h
    $path = $uri.AbsolutePath; $query = $uri.Query
    if ($h -match '(^|\.)mega\.(nz|co\.nz|io)$') {
        $r.Kind = 'Mega'; $r.Label = 'MEGA'
        $r.Message = "MEGA links can't be downloaded by the installer (MEGA decrypts files inside your browser).`nOpen the link in your browser, download the zip, then tick 'I already have the zip' and pick that file."
        return $r
    }
    if ($h -eq 'drive.google.com' -or $h -eq 'docs.google.com' -or $h -eq 'drive.usercontent.google.com') {
        if ($path -match '/folders?/|/embeddedfolderview' -or (Get-QueryParam $query 'folderid')) {
            $r.Kind = 'DriveFolder'; $r.Label = 'Google Drive folder'
            $r.Message = "That is a Google Drive FOLDER link, not a file link.`nOpen the folder, right-click the scenario zip > Share > Copy link, and paste that link instead."
            return $r
        }
        $id = $null
        $m = [regex]::Match($path, '/(?:file/)?d/([A-Za-z0-9_-]{10,})')
        if ($m.Success) { $id = $m.Groups[1].Value } else { $id = Get-QueryParam $query 'id' }
        if (-not $id -or $id -notmatch '^[A-Za-z0-9_-]{10,}$') { $r.Message = "Couldn't find the file ID in this Google Drive link. Use the file's Share > Copy link."; return $r }
        $r.Kind = 'Drive'; $r.Id = $id; $r.Label = 'Google Drive file'
        $r.Url = Get-DriveUrl $id $null
        $rk = Get-QueryParam $query 'resourcekey'; if ($rk) { $r.Url += '&resourcekey=' + [Uri]::EscapeDataString($rk) }
        $r.IsDefault = ($id -eq $script:DriveFileId)
        if ($r.IsDefault -and $script:ArchiveName) { $r.FileHint = $script:ArchiveName } else { $r.FileHint = "Drive_$id.zip" }
        return $r
    }
    $r.Kind = 'Direct'; $r.Label = 'Direct download link'; $final = $uri.AbsoluteUri
    if ($h -match '(^|\.)dropbox\.com$') {
        $q = @($query.TrimStart('?').Split('&') | Where-Object { $_ -and ($_ -notmatch '^(dl|raw)(=|$)') }) + 'dl=1'
        $b = New-Object UriBuilder($uri); $b.Query = ($q -join '&')
        $final = $b.Uri.AbsoluteUri; $r.Label = 'Dropbox link'
    } elseif ($h -e