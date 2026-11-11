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
    } elseif ($h -eq '1drv.ms' -or $h -match '(^|\.)onedrive\.live\.com$') {
        if ($h -match 'onedrive\.live\.com$' -and $path -match '^/(redir|embed|download)(\.aspx)?$') {
            $b = New-Object UriBuilder($uri); $b.Path = '/download'; $final = $b.Uri.AbsoluteUri
        } else {
            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($uri.AbsoluteUri)).TrimEnd('=').Replace('/', '_').Replace('+', '-')
            $final = "https://api.onedrive.com/v1.0/shares/u!$b64/root/content"
        }
        $r.Label = 'OneDrive link (best effort)'
    } elseif ($h -match '\.sharepoint\.com$') {
        $b = New-Object UriBuilder($uri); $b.Query = Set-QueryParam $query 'download' '1'; $final = $b.Uri.AbsoluteUri
        $r.Label = 'SharePoint / OneDrive for Business link (best effort)'
    }
    $r.Url = $final
    if ($script:DefaultDirectUrl -and $final -eq $script:DefaultDirectUrl) { $r.IsDefault = $true }
    $leaf = [Uri]::UnescapeDataString(@($uri.AbsolutePath -split '/')[-1])
    if ($leaf -match '\.zip$' -and (Get-SafeScenarioName ($leaf -replace '\.zip$', ''))) { $r.FileHint = $leaf } else { $r.FileHint = 'Download_' + (Get-UrlHash $final).Substring(0, 8) + '.zip' }
    return $r
}
function Get-ContentDispositionName([string]$cd) {
    if (-not $cd) { return $null }
    $m = [regex]::Match($cd, "filename\*\s*=\s*(?:UTF-8|utf-8)?''([^;]+)")
    if ($m.Success) { $n = [Uri]::UnescapeDataString($m.Groups[1].Value.Trim('"')) }
    else { $m = [regex]::Match($cd, 'filename\s*=\s*"?([^";]+)"?'); if (-not $m.Success) { return $null }; $n = $m.Groups[1].Value }
    $n = @($n -split '[\\/]')[-1].Trim()
    if ($n) { return $n }; return $null
}
# One tiny request (bytes 0-0): total size, server file name, whether it's a web page.
function Get-RemoteInfo([string]$url) {
    $info = New-Object psobject -Property @{ Size = [int64]-1; FileName = $null; IsHtml = $false; Ranges = $false }
    try {
        Initialize-Net
        $r = New-Req $url 0 0
        $resp = $r.GetResponse()
        try {
            $info.FileName = Get-ContentDispositionName $resp.Headers['Content-Disposition']
            if ($info.FileName) { $script:LastRemoteFileName = $info.FileName }
            if ($resp.ContentType -like 'text/html*') { $info.IsHtml = $true; return $info }
            $cr = $resp.Headers['Content-Range']
            if ($cr -and $cr -match '/(\d+)$') { $info.Size = [int64]$Matches[1]; $info.Ranges = $true }
            elseif ($resp.ContentLength -gt 0) { $info.Size = [int64]$resp.ContentLength }
        } finally { $resp.Close() }
    } catch { Write-Log "Size check failed: $($_.Exception.Message)" }
    return $info
}
function Get-RemoteSize([string]$url) { return (Get-RemoteInfo $url).Size }
# True if the file looks like a zip: local-header 'PK\3\4' at the start, or an end-of-central-directory
# (PK\5\6) / zip64 (PK\6\6) record near the end.
function Test-ZipFile([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    try {
        $len = $fs.Length; if ($len -lt 22) { return $false }
        $h = New-Object byte[] 4; [void]$fs.Read($h, 0, 4)
        if ($h[0] -eq 0x50 -and $h[1] -eq 0x4B -and $h[2] -eq 3 -and $h[3] -eq 4) { return $true }
        $n = [int][Math]::Min([int64]70000, $len); [void]$fs.Seek(-$n, [IO.SeekOrigin]::End)
        $t = New-Object byte[] $n; $got = 0; while ($got -lt $n) { $k = $fs.Read($t, $got, $n - $got); if ($k -le 0) { break }; $got += $k }
        for ($i = $got - 4; $i -ge 0; $i--) { if ($t[$i] -eq 0x50 -and $t[$i + 1] -eq 0x4B -and (($t[$i + 2] -eq 5 -and $t[$i + 3] -eq 6) -or ($t[$i + 2] -eq 6 -and $t[$i + 3] -eq 6))) { return $true } }
        return $false
    } finally { $fs.Dispose() }
}
$script:NotZipMessage = "The link gave a web page (or some other file), not a zip. Use a direct download link to the .zip, or download it in your browser and tick 'I already have the zip'."

# Downloads in bounded byte-range chunks (Google Drive serves these reliably for big files;
# a single whole-file request often gets the "Quota exceeded" page). Resumes from <dest>.part.
function Invoke-ResumableDownload([string]$url, [string]$dest, [int64]$expected, [int]$maxRetries = 30, [int64]$stopAfter = 0, [int64]$chunk = 256MB, [string]$kind = 'Drive', [string]$key = '') {
    Initialize-Net
    $part = "$dest.part"; $keyFile = "$dest.part.src"
    # resume state is tied to the link: a different link throws away the old partial file (our own temp file)
    if ($key) {
        $old = $null; if (Test-Path -LiteralPath $keyFile) { $old = ([IO.File]::ReadAllText($keyFile)).Trim() }
        if ((Test-Path -LiteralPath $part) -and $old -ne $key) {
            Write-Log 'The download link is different from the one the partial download came from; starting the download over.'
            Remove-Item -LiteralPath $part -Force
        }
        [IO.File]::WriteAllText($keyFile, $key)
    }
    $attempt = 0; $currentUrl = $url
    $sw = [Diagnostics.Stopwatch]::StartNew(); $lastUi = -1000; $startDone = [int64]-1
    $buf = New-Object byte[] (1MB)
    while ($true) {
        Check-Cancel
        $have = [int64]0
        if (Test-Path -LiteralPath $part) { $have = (Get-Item -LiteralPath $part).Length }
        if ($startDone -lt 0) { $startDone = $have; if ($have -gt 0) { Write-Log ("Resuming download at {0}" -f (Format-Size $have)) } else { Write-Log 'Starting download from Google Drive...' } }
        if ($expected -gt 0 -and $have -eq $expected) { break }
        if ($expected -gt 0 -and $have -gt $expected) {
            Write-Log 'Partial file is larger than expected; setting it aside and restarting.'
            Move-Item -LiteralPath $part -Destination "$part.bad_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force; $startDone = 0; continue
        }
        $to = [int64]-1; if ($expected -gt 0 -and $chunk -gt 0) { $to = [Math]::Min([int64]$expected, [int64]($have + $chunk)) - 1 }
        $resp = $null; $in = $null; $out = $null
        try {
            $req = New-Req $currentUrl $have $to
            $resp = $req.GetResponse()
            $cdName = Get-ContentDispositionName $resp.Headers['Content-Disposition']; if ($cdName) { $script:LastRemoteFileName = $cdName }
            if ($resp.ContentType -like 'text/html*') {
                $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $html = $sr.ReadToEnd(); $sr.Close(); $resp.Close(); $resp = $null
                if ($kind -ne 'Drive') { throw 'NOTZIP' }
                if ($html -match 'Quota exceeded|too many users') { throw 'QUOTA' }
                if ($html -match 'accounts\.google\.com/(ServiceLogin|v3/signin)|Request access|You need access') { throw 'The Google Drive file is not shared publicly (sign-in required). Ask the scenario author to set sharing to "Anyone with the link".' }
                $alt = Get-DriveConfirmUrl $html $script:DriveFileId
                if ($alt -and $alt -ne $currentUrl) { Write-Log 'Google Drive returned a confirmation page; following it.'; $currentUrl = $alt; continue }
                throw 'NOTZIP'
            }
            $status = [int]$resp.StatusCode
            $append = $true
            if ($status -ne 206) {
                if ($have -gt 0 -or $to -ge 0) { Write-Log "Server ignored the byte range (HTTP $status); downloading the whole file in one go." }
                $append = $false; $have = 0; $startDone = 0
                if ($expected -le 0 -and $resp.ContentLength -gt 0) { $expected = $resp.ContentLength }
            } elseif ($expected -le 0) {
                $cr = $resp.Headers['Content-Range']; if ($cr -and $cr -match '/(\d+)$') { $expected = [int64]$Matches[1] }
            }
            $mode = [IO.FileMode]::Create; if ($append -and $have -gt 0) { $mode = [IO.FileMode]::Append }
            $out = New-Object IO.FileStream($part, $mode, [IO.FileAccess]::Write, [IO.FileShare]::Read, 1MB)
            $in = $resp.GetResponseStream()
            $done = $have; $got = [int64]0; $first = ($mode -eq [IO.FileMode]::Create)
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                if ($first) {
                    $first = $false
                    if (-not ($n -ge 2 -and $buf[0] -eq 0x50 -and $buf[1] -eq 0x4B)) { throw 'NOTZIP' }   # not 'PK': a web page or other file
                }
                $out.Write($buf, 0, $n); $done += $n; $got += $n
                if ($sw.ElapsedMilliseconds - $lastUi -ge 400) {
                    $lastUi = $sw.ElapsedMilliseconds
                    $speed = ($done - $startDone) / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
                    $pct = 0; $eta = ''
                    if ($expected -gt 0) { $pct = [int](100 * $done / $expected); if ($speed -gt 0) { $eta = ', ' + ([TimeSpan]::FromSeconds([int](($expected - $done) / $speed))).ToString() + ' left' } }
                    Report $pct ("Downloading: {0} of {1} ({2}/s{3})" -f (Format-Size $done), (Format-Size $expected), (Format-Size $speed), $eta)
                    Check-Cancel
                }
                if ($stopAfter -gt 0 -and $done -ge $stopAfter) { throw [System.OperationCanceledException]'test-stop' }
            }
            $out.Close(); $out = $null
            if ($to -ge 0 -and $status -eq 206 -and $got -ne ($to - $have + 1)) { throw ("Chunk ended early ({0} of {1})" -f (Format-Size $got), (Format-Size ($to - $have + 1))) }
            if ($got -eq 0 -and $expected -gt 0) { throw 'No data received' }
            $attempt = 0
            if ($expected -le 0) { break }          # size unknown: single streamed request
        } catch [System.OperationCanceledException] {
            throw
        } catch {
            $msg = $_.Exception.Message
            if ($msg -eq 'NOTZIP') {
                if ($out) { $out.Close(); $out = $null }
                if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -eq 0) { Remove-Item -LiteralPath $part -Force }
                throw $script:NotZipMessage
            }
            if ($script:Cancel -or $msg -like '*Cancelled by user*' -or $msg -like '*not shared publicly*') { throw }
            $attempt++
            if ($msg -eq 'QUOTA') { $msg = 'Google Drive says "Quota exceeded" (too many downloads of this file today)' }
            if ($attempt -gt $maxRetries) {
                if ($msg -like '*Quota*') { throw ($msg + '. Your progress is saved: run the installer again later to resume, or download the zip in your browser and use "I already have the zip".') }
                throw "Download failed after $maxRetries retries: $msg (run the installer again to resume)"
            }
            $wait = [Math]::Min(60, 3 * $attempt)
            Write-Log "Download interrupted ($msg). Retry $attempt/$maxRetries in $wait s..."
            $t = [Diagnostics.Stopwatch]::StartNew(); while ($t.Elapsed.TotalSeconds -lt $wait) { Start-Sleep -Milliseconds 200; Check-Cancel }
        } finally {
            if ($out) { $out.Close() }; if ($in) { $in.Close() }; if ($resp) { $resp.Close() }
        }
    }
    if (-not (Test-ZipFile $part)) {
        $bad = "$part.notzip_$(Get-Date -Format yyyyMMdd_HHmmss)"; Move-Item -LiteralPath $part -Destination $bad
        Write-Log "Downloaded file is not a zip; kept it as $bad for inspection."
        throw $script:NotZipMessage
    }
    if (Test-Path -LiteralPath $dest) { Move-Item -LiteralPath $dest -Destination "$dest.old_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force }
    Move-Item -LiteralPath $part -Destination $dest
    if ($key) { [IO.File]::WriteAllText("$dest.src", $key); if (Test-Path -LiteralPath $keyFile) { Remove-Item -LiteralPath $keyFile -Force } }
    Write-Log ("Download complete: {0} ({1})" -f $dest, (Format-Size (Get-Item -LiteralPath $dest).Length))
}

# ----------------------------------------------------------------- zip handling
function Open-Zip([string]$path) {
    try { Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop } catch {}
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch {}
    return [IO.Compression.ZipFile]::OpenRead($path)
}
# Finds the folder inside the archive that is the scenario root: the shallowest folder that holds at least two of
# Content/, Playfields/, Sectors/ (or Content/Configuration/). Returns the prefix ('' = archive root, or e.g. 'Ascension-Reborn/').
function Get-ScenarioPrefix([string[]]$names) {
    $markers = @('Content/', 'Playfields/', 'Sectors/')
    $hits = @{}; $cfg = $null
    foreach ($n in $names) {
        $n2 = $n -replace '\\', '/'
        foreach ($mk in $markers) {
            $i = -1
            if ($n2.StartsWith($mk, [StringComparison]::OrdinalIgnoreCase)) { $i = 0 }
            else { $j = $n2.IndexOf('/' + $mk, [StringComparison]::OrdinalIgnoreCase); if ($j -ge 0) { $i = $j + 1 } }
            if ($i -ge 0) { $p = $n2.Substring(0, $i); if (-not $hits.ContainsKey($p)) { $hits[$p] = @{} }; $hits[$p][$mk] = 1 }
        }
        $k = $n2.IndexOf('Content/Configuration/', [StringComparison]::OrdinalIgnoreCase)
        if ($k -ge 0 -and ($k -eq 0 -or $n2[$k - 1] -eq '/')) { $p = $n2.Substring(0, $k); if ($null -eq $cfg -or $p.Length -lt $cfg.Length) { $cfg = $p } }
    }
    $best = $null
    foreach ($p in $hits.Keys) { if ($hits[$p].Count -ge 2 -and ($null -eq $best -or $p.Length -lt $best.Length)) { $best = $p } }
    if ($null -ne $best) { return $best }
    if ($null -ne $cfg) { return $cfg }
    # fallback: strip a single common top folder
    $tops = @{}
    foreach ($n in $names) { $n2 = $n -replace '\\', '/'; $s = $n2.IndexOf('/'); if ($s -lt 0) { return '' }; $tops[$n2.Substring(0, $s)] = 1 }
    if ($tops.Count -eq 1) { return (@($tops.Keys)[0] + '/') }
    return ''
}
# Returns a cleaned folder name, or $null if it is unsafe (path separators, '..', bad characters, reserved names, empty).
function Get-SafeScenarioName([string]$n) {
    if ($null -eq $n) { return $null }
    $n = $n.Trim().TrimEnd('.', ' ').Trim()
    if (-not $n) { return $null }
    if ($n -match '[\\/]' -or $n.Contains('..') -or $n -match '[<>:"|?*\x00-\x1f]') { return $null }
    if ($n.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $null }
    if ($n -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$') { return $null }
    if ($n.Length -gt 100) { return $null }
    return $n
}
# Scenario name: zip's scenario-root folder -> zip file name without .zip -> 'Ascension-Reborn'.
function Resolve-ScenarioName([string]$prefix, [string]$zipPath, [string]$override) {
    $cands = @()
    if ($override) { $cands += New-Object psobject -Property @{ Raw = $override; Source = 'installer.json (scenarioName)' } }
    $segs = @(($prefix -replace '\\', '/').Split('/') | Where-Object { $_ -ne '' })
    if ($segs.Count) { $cands += New-Object psobject -Property @{ Raw = $segs[$segs.Count - 1]; Source = "the archive's top folder '$prefix'" } }
    if ($zipPath) {
        $leaf = @($zipPath -split '[\\/]')[-1] -replace '\.zip$', ''
        $cands += New-Object psobject -Property @{ Raw = $leaf; Source = 'the zip file name' }
    }
    $cands += New-Object psobject -Property @{ Raw = $script:ScenarioName; Source = 'the default name' }
    foreach ($c in $cands) {
        $n = Get-SafeScenarioName $c.Raw
        if ($n) { return (New-Object psobject -Property @{ Name = $n; Source = $c.Source }) }
        if ($c.Raw) { Write-Log ("Ignoring unsafe scenario name '{0}' from {1}." -f $c.Raw, $c.Source) }
    }
    return (New-Object psobject -Property @{ Name = $script:ScenarioName; Source = 'the default name' })
}
# Reads only the zip's directory (fast): scenario name, where it came from, prefix, entry count, uncompressed size.
function Get-ArchiveScenarioInfo([string]$zipPath, [string]$nameHint, [string]$override) {
    $zip = Open-Zip $zipPath
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $t = [int64]0; foreach ($e in $zip.Entries) { $t += $e.Length }
    } finally { $zip.Dispose() }
    $prefix = Get-ScenarioPrefix $names
    $hint = $zipPath; if ($nameHint -and $nameHint -match '\.zip$') { $hint = $nameHint }
    $r = Resolve-ScenarioName $prefix $hint $override
    return (New-Object psobject -Property @{ Name = $r.Name; Source = $r.Source; Prefix = $prefix; Count = $names.Count; Uncompressed = $t })
}
function Expand-ZipWithProgress([string]$zipPath, [string]$dest, [int]$pctFrom = 0, [int]$pctTo = 100) {
    $zip = Open-Zip $zipPath
    try {
        $entries = @($zip.Entries)
        $prefix = Get-ScenarioPrefix ($entries | ForEach-Object { $_.FullName })
        Write-Log ("Archive has {0} entries; scenario root inside archive: '{1}'" -f $entries.Count, $prefix)
        $total = [int64]0; foreach ($e in $entries) { $total += $e.Length }
        $destFull = (Get-FullPathSafe $dest) + [IO.Path]::DirectorySeparatorChar
        [void][IO.Directory]::CreateDirectory($destFull)
        $done = [int64]0; $buf = New-Object byte[] (1MB); $sw = [Diagnostics.Stopwatch]::StartNew(); $lastUi = -1000; $count = 0; $skipped = 0
        foreach ($e in $entries) {
            $name = $e.FullName -replace '\\', '/'
            if ($prefix -and -not $name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $rel = $name.Substring($prefix.Length)
            if (-not $rel) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $destFull ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase) -and ($target + [IO.Path]::DirectorySeparatorChar) -ne $destFull) { throw "Unsafe path in archive: $name" }
            if ($name.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($target); continue }
            $ti = New-Object IO.FileInfo($target)
            if ($ti.Exists -and $ti.Length -eq $e.Length -and [Math]::Abs(($ti.LastWriteTime - $e.LastWriteTime.DateTime).TotalSeconds) -lt 2.1) { $done += $e.Length; $skipped++; continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $in = $e.Open()
            try {
                $out = Open-TargetFile $target (1MB)
                try {
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                        $out.Write($buf, 0, $n); $done += $n
                        if ($sw.ElapsedMilliseconds - $lastUi -ge 400) {
                            $lastUi = $sw.ElapsedMilliseconds
                            Report ([int]($pctFrom + ($pctTo - $pctFrom) * $done / [Math]::Max([int64]1, [int64]$total))) ("Extracting: {0} of {1}  ({2})" -f (Format-Size $done), (Format-Size $total), $rel)
                            Check-Cancel
                        }
                    }
                } finally { $out.Close() }
            } finally { $in.Close() }
            if ((New-Object IO.FileInfo($target)).Length -ne $e.Length) { throw "Size mismatch extracting $rel" }
            try { [IO.File]::SetLastWriteTime($target, $e.LastWriteTime.DateTime) } catch {}
            $count++
        }
        Write-Log ("Extracted {0} files, {1} already up to date ({2})" -f $count, $skipped, (Format-Size $done))
    } finally { $zip.Dispose() }
}
function Get-ZipUncompressedSize([string]$zipPath) {
    $zip = Open-Zip $zipPath
    try { $t = [int64]0; foreach ($e in $zip.Entries) { $t += $e.Length }; return $t } finally { $zip.Dispose() }
}

# ----------------------------------------------------------------- folder copy (merge / overwrite)
function Get-TreeSize([string]$dir) {
    $t = [int64]0
    foreach ($f in [IO.Directory]::EnumerateFiles($dir, '*', [IO.SearchOption]::AllDirectories)) { $t += (New-Object IO.FileInfo($f)).Length }
    return $t
}
# Copies $src into $dst, overwriting; skips files that already match (same size and timestamp).
function Copy-TreeMerge([string]$src, [string]$dst, [int]$pctFrom = 0, [int]$pctTo = 100, [string]$label = 'Copying') {
    $srcFull = Get-FullPathSafe $src; $dstFull = Get-FullPathSafe $dst
    $files = @([IO.Directory]::EnumerateFiles($srcFull, '*', [IO.SearchOption]::AllDirectories))
    $total = [int64]0; foreach ($f in $files) { $total += (New-Object IO.FileInfo($f)).Length }
    $done = [int64]0; $copied = 0; $skipped = 0; $buf = New-Object byte[] (4MB); $sw = [Diagnostics.Stopwatch]::StartNew(); $lastUi = -1000
    foreach ($f in $files) {
        $fi = New-Object IO.FileInfo($f)
        $rel = $f.Substring($srcFull.Length).TrimStart('\','/')
        $target = Join-Path $dstFull $rel
        $ti = New-Object IO.FileInfo($target)
        if ($ti.Exists -and $ti.Length -eq $fi.Length -and [Math]::Abs(($ti.LastWriteTimeUtc - $fi.LastWriteTimeUtc).TotalSeconds) -lt 2.1) {
            $done += $fi.Length; $skipped++; continue
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        if ($ti.Exists -and $ti.IsReadOnly) { $ti.IsReadOnly = $false }
        $in = New-Object IO.FileStream($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 4MB)
        try {
            $out = Open-TargetFile $target (4MB)
            try {
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n); $done += $n
                    if ($sw.ElapsedMilliseconds - $lastUi -ge 400) {
                        $lastUi = $sw.ElapsedMilliseconds
                        Report ([int]($pctFrom + ($pctTo - $pctFrom) * $done / [Math]::Max([int64]1, [int64]$total))) ("{0}: {1} of {2}  ({3})" -f $label, (Format-Size $done), (Format-Size $total), $rel)
                        Check-Cancel
                    }
                }
            } finally { $out.Close() }
        } finally { $in.Close() }
        [IO.File]::SetLastWriteTimeUtc($target, $fi.LastWriteTimeUtc)
        $copied++
    }
    Write-Log ("{0}: {1} files copied, {2} already up to date ({3})" -f $label, $copied, $skipped, (Format-Size $total))
}

function Test-WriteAccess([string]$dir) {
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        $t = Join-Path $dir ('.ar_write_test_' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($t, 'x'); Remove-Item -LiteralPath $t -Force   # our own temp probe file
        return $true
    } catch { return $false }
}
function Test-EmpyrionRunning {
    try { return [bool](Get-Process -Name 'Empyrion*' -ErrorAction SilentlyContinue) } catch { return $false }
}

# ----------------------------------------------------------------- folder-in-use handling
function Get-ErrMsg($err) {
    $e = $err.Exception
    while ($e.InnerException -and ($e -is [System.Management.Automation.MethodInvocationException] -or $e -is [System.Management.Automation.RuntimeException])) { $e = $e.InnerException }
    return $e.Message
}
function Get-InUseMessage([string]$path, [string]$detail) {
    return ("Windows won't let the installer move or change:`n{0}`n`n({1})`n`n" -f $path, $detail) +
           "Something is still using this folder. Please close:`n" +
           "  - File Explorer windows showing this folder (or anything inside it)`n" +
           "  - Editors or tools with scenario files open (Notepad++, VS Code, Playfield Studio, ...)`n" +
           "  - Empyrion, Empyrion Admin Helper (EAH) and any dedicated server`n" +
           "  - An antivirus or backup scan running on this folder`n" +
           "or run the installer as administrator.`n`nNothing has been changed. Click Retry when ready."
}
function Request-Retry([string]$msg) {
    if ($script:AskRetry) { return [bool](& $script:AskRetry $msg) }
    return $false
}
# Probe: rename the folder to a temp sibling and straight back. Returns $null if movable, else the error text.
# The rename is atomic, so a failure leaves the folder exactly as it was.
function Test-DirMovable([string]$dir) {
    $probe = '{0}.__ar_movetest_{1}' -f $dir.TrimEnd('\','/'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    try { & $script:MoveDirImpl $dir $probe } catch { return (Get-ErrMsg $_) }
    $err = $null
    for ($i = 0; $i -lt 20; $i++) {
        try { & $script:MoveDirImpl $probe $dir; return $null } catch { $err = Get-ErrMsg $_; Start-Sleep -Milliseconds 500 }
    }
    throw "CRITICAL: the scenario folder was briefly renamed to '$probe' for a move test and could not be renamed back ($err). Please rename it back to '$(Split-Path -Leaf $dir)' by hand."
}
# Loops Test-DirMovable with the Retry/Cancel prompt. Throws on Cancel.
function Wait-DirMovable([string]$dir) {
    while ($true) {
        $err = Test-DirMovable $dir
        if (-not $err) { return }
        Write-Log "Folder is in use and can't be moved: $dir ($err)"
        if (-not (Request-Retry (Get-InUseMessage $dir $err))) {
            throw "The existing scenario folder is in use, so it could not be backed up:`n$dir`n`nNothing was changed. Close File Explorer windows, editors, Empyrion / EAH / dedicated server or antivirus scans using it (or run as administrator), then run the installer again."
        }
        Write-Log 'Retrying...'
    }
}
# Moves $dir into $bkRoot as a single atomic rename. Creates $bkRoot only right before the move, and removes it
# again (if it is still empty and we created it) when the move fails. Rolls back if the folder ended up moved.
function Backup-ScenarioFolder([string]$dir, [string]$bkRoot) {
    while ($true) {
        Wait-DirMovable $dir
        $createdRoot = $false
        $bk = $null
        try {
            if (-not (Test-Path -LiteralPath $bkRoot)) { [void][IO.Directory]::CreateDirectory($bkRoot); $createdRoot = $true }
            $base = Join-Path $bkRoot ('{0}_{1}' -f (Split-Path -Leaf $dir), (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $bk = $base; $n = 2; while (Test-Path -LiteralPath $bk) { $bk = "{0}_{1}" -f $base, $n; $n++ }
            Write-Log "Backing up existing scenario to $bk"
            & $script:MoveDirImpl $dir $bk
            Write-Log 'Backup done (folder moved, nothing deleted).'
            return $bk
        } catch {
            $err = Get-ErrMsg $_
            Write-Log "Backup move failed: $err"
            if ($bk -and -not (Test-Path -LiteralPath $dir) -and (Test-Path -LiteralPath $bk)) {
                Write-Log 'Rolling back: moving the folder back to its original place...'
                try { & $script:MoveDirImpl $bk $dir; Write-Log 'Rolled back.' }
                catch { throw "CRITICAL: the backup move failed and the folder could not be moved back. Your scenario is safe at:`n$bk`nMove it back to $dir by hand. ($(Get-ErrMsg $_))" }
            }
            if ($createdRoot -and (Test-Path -LiteralPath $bkRoot) -and -not @(Get-ChildItem -LiteralPath $bkRoot -Force).Count) {
                try { [IO.Directory]::Delete($bkRoot, $false); Write-Log "Removed the empty $bkRoot this run created." } catch {}
            }
            if (-not (Request-Retry (Get-InUseMessage $dir $err))) {
                throw "The existing scenario folder could not be backed up:`n$dir`n($err)`n`nNothing was changed. Close File Explorer windows, editors, Empyrion / EAH / dedicated server or antivirus scans using it (or run as administrator), then run the installer again."
            }
            Write-Log 'Retrying...'
        }
    }
}
# Opens a file for writing, offering Retry/Cancel when it is locked (used for in-place updates and SharedData copies).
function Open-TargetFile([string]$path, [int]$bufSize) {
    while ($true) {
        try { return (New-Object IO.FileStream($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, $bufSize)) }
        catch {
            $err = Get-ErrMsg $_
            Write-Log "Can't write $path ($err)"
            if (-not (Request-Retry (Get-InUseMessage $path $err).Replace('Nothing has been changed. ', ''))) { throw "Can't write $path ($err). Close whatever is using it (or run as administrator) and run the installer again." }
        }
    }
}
function Get-DefaultTestFolder([string]$emp) {
    $n = $script:TestFolderName
    try { if ($emp) { return (Join-Path ([IO.Path]::GetPathRoot((Get-FullPathSafe $emp))) $n) } } catch {}
    if ($script:IsWin) { return "$env:SystemDrive\$n" }
    return (Join-Path ([IO.Path]::GetTempPath()) $n)
}
function Test-PathInside([string]$child, [string]$parent) {
    $c = (Get-FullPathSafe $child) + [IO.Path]::DirectorySeparatorChar; $p = (Get-FullPathSafe $parent) + [IO.Path]::DirectorySeparatorChar
    return $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
}

# ----------------------------------------------------------------- the install pipeline
# $opt: hashtable with EmpyrionPath, ArchivePath, DownloadFolder, SaveFolders[], OverwriteInPlace, DeleteArchiveAfter, SkipSpaceCheck,
#       TestMode, TestFolder
function Invoke-Install($opt) {
    Write-Log "$($script:Product) $($script:Version)  (log: $($script:LogFile))"
    $test = [bool]$opt['TestMode']
    $emp = $null; if ($opt.EmpyrionPath) { $emp = Get-FullPathSafe $opt.EmpyrionPath }
    $saves = @($opt.SaveFolders | Where-Object { $_ })
    if ($test) {
        if (-not $opt['TestFolder']) { throw 'TEST MODE: no test folder given.' }
        $root = Get-FullPathSafe $opt['TestFolder']
        if ($emp -and ((Test-PathInside $root $emp) -or (Test-PathInside $emp $root))) { throw "TEST MODE: the test folder must be outside your Empyrion folder ($emp). Pick e.g. $(Get-DefaultTestFolder $emp)." }
        Write-Log '=================================================================='
        Write-Log "TEST MODE: installing into $root"
        Write-Log 'TEST MODE: your real Empyrion scenario folder is NOT touched.'
        Write-Log '=================================================================='
        if (-not $saves.Count) {
            $ts = Join-Path (Join-Path (Join-Path $root 'Saves') 'Games') 'TestGame'
            [void][IO.Directory]::CreateDirectory($ts); $saves = @($ts)
            Write-Log "TEST MODE: SharedData will be copied to $(Join-Path $ts 'SharedData')"
        } else { Write-Log ('TEST MODE: SharedData will ALSO be copied into the save(s) you ticked: ' + ($saves -join '; ')) }
    } else {
        if (-not (Test-EmpyrionDir $emp)) { throw "This does not look like an Empyrion folder: $emp" }
        if (Test-EmpyrionRunning) { throw 'Empyrion is running. Close the game (and any local dedicated server) first, then try again.' }
        $root = $emp
    }
    # download link (only when there's no local zip)
    $link = $null
    if (-not $opt.ArchivePath) {
        $link = Resolve-DownloadUrl $opt['DownloadUrl']
        if ($link.Kind -in @('Invalid', 'Mega', 'DriveFolder')) { throw $link.Message }
        Write-Log ("Download link: {0} (host: {1}){2}" -f $link.Label, $link.Host, $(if ($link.IsDefault) { ' - the default link' } else { '' }))
    }
    # scenario name: read from the zip now if we have it; for a download use the default name (default link) or wait for the zip
    $scenName = $script:ScenarioName; $nameFinal = $false; $nameKnown = $true
    if ($opt.ArchivePath -and (Test-Path -LiteralPath $opt.ArchivePath)) {
        $info = Get-ArchiveScenarioInfo $opt.ArchivePath
        $scenName = $info.Name; $nameFinal = $true
        Write-Log ("Scenario name: '{0}' (from {1})" -f $scenName, $info.Source)
    } elseif ($link -and $link.IsDefault -and $script:DefaultNameKnown) { Write-Log ("Scenario name: '{0}' for now (checked again once the zip is downloaded)" -f $scenName) }
    else { $nameKnown = $false; Write-Log 'Scenario name: will be read from the zip once it is downloaded.' }
    $script:LastScenarioName = $scenName
    $scenDir = Join-Path (Join-Path (Join-Path $root 'Content') 'Scenarios') $scenName
    $bkRoot  = Join-Path (Join-Path $root 'Content') 'Scenarios_Backups'   # outside Scenarios so the game doesn't list it
    if ($nameKnown) { Write-Log "Target folder: $scenDir" }
    if (-not (Test-WriteAccess (Split-Path -Parent $scenDir))) { throw "No write access to $(Split-Path -Parent $scenDir). Run the installer as administrator." }
    if ($opt.ArchivePath -and (Test-Path -LiteralPath $scenDir) -and (Test-PathInside $opt.ArchivePath $scenDir)) { throw "The zip is inside the scenario folder that is about to be replaced ($scenDir). Move the zip somewhere else first." }
    # check early (before a long download) that an existing scenario can be moved to the backup folder
    if ($nameKnown -and (Test-Path -LiteralPath $scenDir) -and -not $opt.OverwriteInPlace) { Report 0 'Checking the existing scenario folder...'; Wait-DirMovable $scenDir }

    # 1) archive: local file or download
    $zipPath = $opt.ArchivePath
    $downloaded = $false
    $script:LastRemoteFileName = $null; $remote = [int64]-1
    if (-not $zipPath) {
        $url = $link.Url; $key = Get-UrlHash $url
        $dl = $opt.DownloadFolder; if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
        [void][IO.Directory]::CreateDirectory($dl)
        $zipPath = Join-Path $dl $link.FileHint
        Report 0 'Checking the download link...'
        $ri = Get-RemoteInfo $url
        $remote = $ri.Size
        if ($ri.IsHtml -and $link.Kind -ne 'Drive') { throw $script:NotZipMessage }
        if ($remote -le 0 -and $link.IsDefault -and $script:DefaultIsBuiltin) { Write-Log 'Drive did not report a size; using the known size.'; $remote = $script:FallbackArchiveSize }
        if ($remote -gt 0) { Write-Log ("Archive size: {0}" -f (Format-Size $remote)) } else { Write-Log 'The server did not report the file size.' }
        $existing = [int64]-1; if (Test-Path -LiteralPath $zipPath) { $existing = (Get-Item -LiteralPath $zipPath).Length }
        $srcKey = $null; if (Test-Path -LiteralPath "$zipPath.src") { $srcKey = ([IO.File]::ReadAllText("$zipPath.src")).Trim() }
        if ($existing -gt 0 -and $existing -eq $remote -and ($srcKey -eq $key -or (-not $srcKey -and $link.IsDefault)) -and (Test-ZipFile $zipPath)) { Write-Log "Found a complete copy already at $zipPath; reusing it." }
        else {
            if (-not $opt.SkipSpaceCheck -and $remote -gt 0) {
                $have = [int64]0; if (Test-Path -LiteralPath "$zipPath.part") { $have = (Get-Item -LiteralPath "$zipPath.part").Length }
                $estUnc = [int64]([double]$remote * $script:FallbackUncompressed / $script:FallbackArchiveSize)   # ratio measured on the Nov 2026 archive
                $needs = @(@{ Path = $dl; Bytes = ($remote - $have) }, @{ Path = $scenDir; Bytes = $estUnc })
                foreach ($s in $saves) { $needs += @{ Path = $s; Bytes = $estUnc } }
                $p = Test-DiskSpace $needs; if ($p.Count) { throw ("Not enough disk space:`n" + ($p -join "`n")) }
            }
            $chunk = [int64]0; if ($link.Kind -eq 'Drive') { $chunk = 256MB }
            Invoke-ResumableDownload $url $zipPath $remote 30 0 $chunk $link.Kind $key
            $downloaded = $true
        }
    }
    if (-not (Test-Path -LiteralPath $zipPath)) { throw "Archive not found: $zipPath" }
    Check-Cancel

    # 2) validate archive + space for extraction
    Report 0 'Reading archive...'
    if (-not (Test-ZipFile $zipPath)) { throw "This file is not a zip: $zipPath" }
    $ovr = $null; if ($link -and $link.IsDefault) { $ovr = $script:ConfigScenarioName }
    $info = Get-ArchiveScenarioInfo $zipPath $script:LastRemoteFileName $ovr
    $unc = $info.Uncompressed
    Write-Log ("Archive OK: {0} entries, {1} uncompressed" -f $info.Count, (Format-Size $unc))
    if (-not $nameKnown) {
        Write-Log ("Scenario name: '{0}' (from {1})" -f $info.Name, $info.Source)
        $scenName = $info.Name; $script:LastScenarioName = $scenName
        $scenDir = Join-Path (Join-Path (Join-Path $root 'Content') 'Scenarios') $scenName
        Write-Log "Target folder: $scenDir"
        if (Test-PathInside $zipPath $scenDir) { throw "The zip is inside the scenario folder that is about to be replaced ($scenDir). Move the zip somewhere else first." }
    } elseif ($info.Name -ne $scenName) {
        Write-Log ("Scenario name from the downloaded archive: '{0}' (from {1}); installing there instead of '{2}'." -f $info.Name, $info.Source, $scenName)
        $scenName = $info.Name; $script:LastScenarioName = $scenName
        $scenDir = Join-Path (Join-Path (Join-Path $root 'Content') 'Scenarios') $scenName
        Write-Log "Target folder: $scenDir"
        if (Test-PathInside $zipPath $scenDir) { throw "The zip is inside the scenario folder that is about to be replaced ($scenDir). Move the zip somewhere else first." }
    } elseif (-not $nameFinal) { Write-Log ("Scenario name confirmed from the archive: '{0}' (from {1})" -f $scenName, $info.Source) }
    if (-not $opt.SkipSpaceCheck -and (-not $downloaded -or -not $nameKnown -or $remote -le 0)) {
        $needs = @(@{ Path = $scenDir; Bytes = $unc }); foreach ($s in $saves) { $needs += @{ Path = $s; Bytes = $unc } }
        $p = Test-DiskSpace $needs; if ($p.Count) { throw ("Not enough disk space:`n" + ($p -join "`n")) }
    }

    # 3) back up existing scenario (move, never delete)
    if (Test-Path -LiteralPath $scenDir) {
        if ($opt.OverwriteInPlace) { Write-Log "Existing scenario will be updated in place: $scenDir" }
        else { [void](Backup-ScenarioFolder $scenDir $bkRoot) }
    }

    # 4) extract
    $span = 100; if ($saves.Count) { $span = 55 }
    Expand-ZipWithProgress $zipPath $scenDir 0 $span
    $sharedSrc = Join-Path $scenDir 'SharedData'
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $scenDir 'Content') 'Configuration'))) { Write-Log 'WARNING: Content\Configuration not found in the installed scenario. The archive layout may be unexpected.' }
    Write-Log "Scenario installed to $scenDir"

    # 5) SharedData -> save folders
    if ($saves.Count) {
        if (-not (Test-Path -LiteralPath $sharedSrc)) { throw "The scenario has no SharedData folder ($sharedSrc)." }
        $i = 0; $per = (100 - $span) / $saves.Count
        foreach ($s in $saves) {
            $dst = Join-Path $s 'SharedData'
            Write-Log "Copying SharedData -> $dst"
            Copy-TreeMerge $sharedSrc $dst ([int]($span + $i * $per)) ([int]($span + ($i + 1) * $per)) ("SharedData -> " + (Split-Path -Leaf $s))
            $i++
        }
    }

    if ($opt.DeleteArchiveAfter -and $downloaded) {
        Write-Log "Removing downloaded archive $zipPath (as requested)"
        Remove-Item -LiteralPath $zipPath -Force
    }
    Report 100 'Done.'
    if ($test) { Write-Log "TEST MODE: test install of '$scenName' finished in $root (scenario: $scenDir). Your real Empyrion folder was not touched." }
    else { Write-Log "Install finished. Start Empyrion and choose '$scenName' under New Game > Scenarios." }
}

# ----------------------------------------------------------------- console mode
function Start-Console {
    $libs = Get-SteamLibraries (Get-SteamRoots)
    $inst = Find-EmpyrionInstalls $libs
    if ($ListOnly) {
        Write-Host 'Steam libraries:'; $libs | ForEach-Object { Write-Host "  $_" }
        Write-Host 'Empyrion installs:'; $inst | ForEach-Object { Write-Host ("  [{0}] {1}" -f $_.Kind, $_.Path) }
        foreach ($i in $inst) { Write-Host "Save folders in $($i.Path):"; $sv = Get-SaveFolders $i.Path; $sv | ForEach-Object { Write-Host ("  [{0}] {1}  (SharedData: {2})" -f $_.Kind, $_.Path, $_.HasShared) } }
        return
    }
    $emp = $EmpyrionPath
    if (-not $emp) {
        $g = @($inst | Where-Object { $_.Kind -eq 'Game' }); if (-not $g.Count) { $g = @($inst) }
        if ($g.Count) { $emp = $g[0].Path }
        elseif (-not $TestInstall) { throw 'Empyrion not found. Pass -EmpyrionPath "<folder>".' }
    }
    if ($emp) { Write-Log "Empyrion folder: $emp" }
    $tf = $null
    if ($TestInstall) { $tf = $TestFolder; if (-not $tf) { $tf = Get-DefaultTestFolder $emp } }
    if (-not [Console]::IsInputRedirected) {
        $script:AskRetry = { param($m) Write-Host "`n$m`n"; return ((Read-Host 'Type R and press Enter to retry, or just Enter to cancel') -match '^\s*r') }
    }
    $saves = @()
    if (-not $SkipSharedData) {
        foreach ($sf in @($SaveFolder | Where-Object { $_ })) {
            # "-File" passes "A,B" or "A;B" as one string: split it when the pieces are real folders
            if (-not (Test-Path -LiteralPath $sf)) {
                $parts = @($sf -split '[;,]' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
                if ($parts.Count -gt 1 -and -not @($parts | Where-Object { -not (Test-Path -LiteralPath $_) }).Count) { $saves += $parts; continue }
            }
            $saves += $sf
        }
        foreach ($sf in $saves) { if (-not (Test-Path -LiteralPath $sf -PathType Container)) { throw "Save folder not found: $sf" } }
    }
    if (-not $SkipSharedData -and -not $saves.Count) { Write-Log 'No -SaveFolder given: SharedData will only be installed inside the scenario (new games pick it up automatically).' }
    Invoke-Install @{ EmpyrionPath = $emp; ArchivePath = $ArchivePath; DownloadFolder = $DownloadFolder; SaveFolders = $saves; DownloadUrl = $DownloadUrl;
                      OverwriteInPlace = [bool]$OverwriteInPlace; DeleteArchiveAfter = [bool]$DeleteArchiveAfter; SkipSpaceCheck = [bool]$SkipSpaceCheck;
                      TestMode = [bool]$TestInstall; TestFolder = $tf }
}

# ----------------------------------------------------------------- installer.json
function Get-WindowTitle { if ($script:Title) { return "$($script:Title) - $($script:Product) $($script:Version)" }; return "$($script:Product) $($script:Version)" }
function Get-HeaderTitle { if ($script:Title) { return $script:Title }; return "$($script:Product) for Empyrion - Galactic Survival" }
function Add-ConfigNote([string]$m) { $script:ConfigNotes += $m; Write-Log $m }
# Where to look: -Config <path>, else installer.json next to the exe (the launcher passes its folder), else next to this .ps1.
function Find-InstallerConfig([string]$explicit) {
    if ($explicit) { return $explicit }
    $dirs = @()
    if ($env:SCENARIO_INSTALLER_DIR) { $dirs += $env:SCENARIO_INSTALLER_DIR }
    if ($PSScriptRoot) { $dirs += $PSScriptRoot }
    foreach ($d in $dirs) { $p = Join-Path $d 'installer.json'; if (Test-Path -LiteralPath $p -PathType Leaf) { return $p } }
    return $null
}
# Reads installer.json and applies it. Invalid file -> logged, built-in defaults kept. Returns $true if applied.
function Import-InstallerConfig([string]$path) {
    if (-not $path) { return $false }
    $script:ConfigPath = $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-ConfigNote "Config file not found: $path - using the built-in defaults."; return $false }
    try {
        $len = (Get-Item -LiteralPath $path).Length
        if ($len -gt 64KB) { throw "file is too big ($len bytes)" }
        $raw = [IO.File]::ReadAllText($path)
        if (-not $raw.Trim()) { throw 'file is empty' }
        $j = $raw | ConvertFrom-Json
        if ($null -eq $j -or $j -isnot [Management.Automation.PSCustomObject]) { throw 'expected a JSON object like { "defaultUrl": "..." }' }
    } catch {
        Add-ConfigNote ("installer.json is invalid ({0}): {1} - ignoring it and using the built-in defaults." -f $path, (Get-ErrMsg $_))
        return $false
    }
    $known = @('defaultUrl', 'scenarioName', 'testFolderName', 'title')
    $vals = @{}
    foreach ($pr in $j.PSObject.Properties) {
        $k = @($known | Where-Object { $_ -eq $pr.Name })   # -eq is case-insensitive
        if (-not $k.Count) { if (-not $pr.Name.StartsWith('_')) { Add-ConfigNote "installer.json: unknown setting '$($pr.Name)' ignored." }; continue }
        if ($null -eq $pr.Value -or ($pr.Value -is [string] -and -not $pr.Value.Trim())) { continue }
        if ($pr.Value -isnot [string]) { Add-ConfigNote "installer.json: '$($k[0])' must be text - ignored."; continue }
        $vals[$k[0]] = $pr.Value.Trim()
    }
    $applied = @()
    if ($vals.ContainsKey('defaultUrl')) {
        $saved = @($script:DefaultDownloadUrl, $script:DriveFileId, $script:DefaultDirectUrl)
        $script:DefaultDownloadUrl = $vals.defaultUrl; $script:DriveFileId = $null; $script:DefaultDirectUrl = $null
        $lk = Resolve-DownloadUrl $vals.defaultUrl
        if ($lk.Kind -eq 'Drive' -or $lk.Kind -eq 'Direct') {
            if ($lk.Kind -eq 'Drive') { $script:DriveFileId = $lk.Id } else { $script:DefaultDirectUrl = $lk.Url }
            if ($lk.Kind -eq 'Drive' -and $lk.Id -eq $saved[1]) { $script:DriveFileId = $saved[1] }   # same file as built in: keep its known size/name
            else { $script:DefaultIsBuiltin = $false; $script:DefaultNameKnown = $false; $script:ArchiveName = $null }
            $applied += "defaultUrl ($($lk.Label), host: $($lk.Host))"
        } else {
            $script:DefaultDownloadUrl = $saved[0]; $script:DriveFileId = $saved[1]; $script:DefaultDirectUrl = $saved[2]
            Add-ConfigNote ("installer.json: defaultUrl ignored ({0})" -f @($lk.Message -split "`n")[0])
        }
    }
    if ($vals.ContainsKey('scenarioName')) {
        $n = Get-SafeScenarioName $vals.scenarioName
        if ($n) {
            $script:ScenarioName = $n; $script:LastScenarioName = $n; $script:ConfigScenarioName = $n; $script:DefaultNameKnown = $true
            if (-not $script:DefaultIsBuiltin) { $script:ArchiveName = "$n.zip" }
            $applied += "scenarioName '$n'"
        } else { Add-ConfigNote "installer.json: scenarioName '$($vals.scenarioName)' is not a safe folder name - ignored." }
    }
    if (-not $script:DefaultNameKnown) { $script:ScenarioName = 'Scenario'; $script:LastScenarioName = 'Scenario' }   # last-resort fallback for someone else's default link
    if ($vals.ContainsKey('testFolderName')) {
        $n = Get-SafeScenarioName $vals.testFolderName
        if ($n) { $script:TestFolderName = $n; $applied += "testFolderName '$n'" } else { Add-ConfigNote "installer.json: testFolderName '$($vals.testFolderName)' is not a safe folder name - ignored." }
    }
    if ($vals.ContainsKey('title')) {
        $t = ($vals.title -replace '[\x00-\x1f]', ' ').Trim()
        if ($t.Length -gt 80) { $t = $t.Substring(0, 80).Trim() }
        if ($t) { $script:Title = $t; $applied += "title '$t'" }
    }
    if ($applied.Count) { Add-ConfigNote ("Using {0}: {1}" -f $path, ($applied -join ', ')) } else { Add-ConfigNote "Using $path (no settings changed)." }
    return $true
}

# ----------------------------------------------------------------- GUI layout math (pure, unit-tested)
$script:GuiBottomBarH = 92      # progress bar + status + Install/Close buttons (at 96 DPI)
$script:GuiMinClientW = 560; $script:GuiMinClientH = 330
# Form bounds: natural size clamped to the working area minus a margin, centred. Returns X, Y, W, H, MinW, MinH.
function Get-FormBounds([int]$natW, [int]$natH, [int]$waX, [int]$waY, [int]$waW, [int]$waH, [int]$margin = 10, [int]$minW = 0, [int]$minH = 0) {
    $maxW = [Math]::Max(200, $waW - 2 * $margin); $maxH = [Math]::Max(200, $waH - 2 * $margin)
    $w = [Math]::Min($natW, $maxW); $h = [Math]::Min($natH, $maxH)
    $mw = [Math]::Min($minW, $w); $mh = [Math]::Min($minH, $h)
    $x = $waX + [int][Math]::Floor(($waW - $w) / 2); $y = $waY + [int][Math]::Floor(($waH - $h) / 2)
    return (New-Object psobject -Property @{ X = $x; Y = $y; W = $w; H = $h; MinW = $mw; MinH = $mh })
}

# ----------------------------------------------------------------- GUI
function Enable-DpiAwareness {
    # system-DPI aware: crisp text at 125/150 % instead of a blurry bitmap-stretched window
    try {
        if (-not ('ScenarioInstallerNative.Dpi' -as [type])) {
            Add-Type -Namespace ScenarioInstallerNative -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
        }
        [void][ScenarioInstallerNative.Dpi]::SetProcessDPIAware()
    } catch {}
}
function Start-Gui {
    Enable-DpiAwareness
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object Windows.Forms.Form
    $form.SuspendLayout()
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
    $form.Text = (Get-WindowTitle)
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)
    $form.FormBorderStyle = 'Sizable'; $form.MaximizeBox = $true; $form.MinimizeBox = $true
    $form.StartPosition = 'Manual'
    $form.ClientSize = New-Object Drawing.Size(762, 746)
    try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {}

    # bottom bar (always visible) + scrolling content panel
    $bottom = New-Object Windows.Forms.Panel; $bottom.Size = New-Object Drawing.Size(760, $script:GuiBottomBarH)
    $content = New-Object Windows.Forms.Panel; $content.Size = New-Object Drawing.Size(760, 636); $content.AutoScroll = $true
    function Add-Ctl($ctl, $x, $y, $w, $h) { $ctl.Location = New-Object Drawing.Point($x, $y); $ctl.Size = New-Object Drawing.Size($w, $h); $content.Controls.Add($ctl); return $ctl }
    function Add-Bottom($ctl, $x, $y, $w, $h) { $ctl.Location = New-Object Drawing.Point($x, $y); $ctl.Size = New-Object Drawing.Size($w, $h); $bottom.Controls.Add($ctl); return $ctl }
    function New-Label($t) { $l = New-Object Windows.Forms.Label; $l.Text = $t; return $l }

    $hdr = Add-Ctl (New-Label (Get-HeaderTitle)) 12 10 720 26; $hdr.AutoEllipsis = $true
    $hdr.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
    $lblSub = Add-Ctl (New-Label '') 12 38 720 20

    # 1 Empyrion folder
    [void](Add-Ctl (New-Label '1. Empyrion folder (found automatically - change it if needed):') 12 66 720 18)
    $cbEmp = Add-Ctl (New-Object Windows.Forms.ComboBox) 12 86 620 24
    $btnEmp = Add-Ctl (New-Object Windows.Forms.Button) 640 85 90 26; $btnEmp.Text = 'Browse...'
    $lblEmp = Add-Ctl (New-Label '') 12 112 720 18

    # 2 Archive
    [void](Add-Ctl (New-Label '2. Download link (paste your own: Google Drive, Dropbox, OneDrive or a direct .zip link) and download folder:') 12 138 720 18)
    $txtUrl = Add-Ctl (New-Object Windows.Forms.TextBox) 12 158 560 24; $txtUrl.Text = $script:DefaultDownloadUrl
    $btnUrlReset = Add-Ctl (New-Object Windows.Forms.Button) 580 157 150 26; $btnUrlReset.Text = 'Reset to default'
    $txtDl = Add-Ctl (New-Object Windows.Forms.TextBox) 12 188 620 24
    $txtDl.Text = Join-Path $env:USERPROFILE 'Downloads'
    $btnDl = Add-Ctl (New-Object Windows.Forms.Button) 640 187 90 26; $btnDl.Text = 'Browse...'
    $chkHave = Add-Ctl (New-Object Windows.Forms.CheckBox) 12 216 260 22; $chkHave.Text = 'I already have the zip (skip download):'
    $txtZip = Add-Ctl (New-Object Windows.Forms.TextBox) 276 216 356 24; $txtZip.Enabled = $false
    $btnZip = Add-Ctl (New-Object Windows.Forms.Button) 640 215 90 26; $btnZip.Text = 'Browse...'; $btnZip.Enabled = $false
    $lblName = Add-Ctl (New-Label '') 12 244 720 18; $lblName.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $script:GuiScenName = $script:ScenarioName

    # 3 Saves
    [void](Add-Ctl (New-Label '3. Copy SharedData into these saves (tick one or more). Single-player saves are in Saves\Games; servers you joined are in Saves\Cache:') 12 270 720 34)
    $lstSaves = Add-Ctl (New-Object Windows.Forms.CheckedListBox) 12 306 620 90; $lstSaves.IntegralHeight = $false; $lstSaves.CheckOnClick = $true; $lstSaves.HorizontalScrollbar = $true
    $btnAddSave = Add-Ctl (New-Object Windows.Forms.Button) 640 306 90 26; $btnAddSave.Text = 'Add folder...'
    $btnRefresh = Add-Ctl (New-Object Windows.Forms.Button) 640 336 90 26; $btnRefresh.Text = 'Refresh'
    [void](Add-Ctl (New-Label 'Starting a brand-new game? You can leave all unticked: the game copies SharedData itself when you create a game from the scenario.') 12 400 720 32)

    # options
    $chkOver = Add-Ctl (New-Object Windows.Forms.CheckBox) 12 434 720 22; $chkOver.Text = 'Update an existing copy of this scenario in place (default: move the old copy to Content\Scenarios_Backups first)'
    $chkDel  = Add-Ctl (New-Object Windows.Forms.CheckBox) 12 456 720 22; $chkDel.Text = 'Delete the downloaded zip after a successful install (frees ~19 GB)'

    # test mode
    $chkTest = Add-Ctl (New-Object Windows.Forms.CheckBox) 12 482 720 22
    $chkTest.Text = 'TEST INSTALL - install to a test folder instead (does not touch your real scenario):'
    $chkTest.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold); $chkTest.ForeColor = 'DarkOrange'
    $txtTest = Add-Ctl (New-Object Windows.Forms.TextBox) 30 506 602 24; $txtTest.Enabled = $false
    $btnTest = Add-Ctl (New-Object Windows.Forms.Button) 640 505 90 26; $btnTest.Text = 'Browse...'; $btnTest.Enabled = $false
    $script:TestAuto = $true

    # log: about 5 lines, inside the scrolling area
    [void](Add-Ctl (New-Label 'Log:') 12 540 720 16)
    $log = Add-Ctl (New-Object Windows.Forms.TextBox) 12 558 718 84; $log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true

    # bottom bar: progress, status, buttons (Dock=Bottom, never scrolls away)
    $bar = Add-Bottom (New-Object Windows.Forms.ProgressBar) 12 8 736 22; $bar.Maximum = 100; $bar.Anchor = 'Top,Left,Right'
    $lblStat = Add-Bottom (New-Label 'Ready.') 12 32 736 20; $lblStat.Anchor = 'Top,Left,Right'; $lblStat.AutoEllipsis = $true
    $btnGo = Add-Bottom (New-Object Windows.Forms.Button) 538 56 100 30; $btnGo.Text = 'Install'; $btnGo.Anchor = 'Top,Right'
    $btnCancel = Add-Bottom (New-Object Windows.Forms.Button) 648 56 100 30; $btnCancel.Text = 'Close'; $btnCancel.Anchor = 'Top,Right'
    $bottom.Dock = [Windows.Forms.DockStyle]::Bottom
    $content.Dock = [Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($bottom); $form.Controls.Add($content); $content.BringToFront()   # Fill must be docked last
    $form.ResumeLayout($false)

    # size to the screen: natural size, clamped to the working area (minus a margin), centred
    $fitToScreen = {
        $wa = [Windows.Forms.Screen]::FromControl($form).WorkingArea
        $scale = 1.0; try { $scale = $form.CurrentAutoScaleDimensions.Width / 96.0 } catch {}; if ($scale -le 0) { $scale = 1.0 }
        $maxR = 0; $maxB = 0
        foreach ($c in $content.Controls) { if ($c.Right -gt $maxR) { $maxR = $c.Right }; if ($c.Bottom -gt $maxB) { $maxB = $c.Bottom } }
        $pad = [int](12 * $scale)
        $natClientW = $maxR + $pad + [Windows.Forms.SystemInformation]::VerticalScrollBarWidth
        $natClientH = $maxB + $pad + $bottom.Height
        $ncW = $form.Width - $form.ClientSize.Width; $ncH = $form.Height - $form.ClientSize.Height
        $b = Get-FormBounds ($natClientW + $ncW) ($natClientH + $ncH) $wa.X $wa.Y $wa.Width $wa.Height ([int](10 * $scale)) ([int]($script:GuiMinClientW * $scale) + $ncW) ([int]($script:GuiMinClientH * $scale) + $ncH)
        $form.MinimumSize = New-Object Drawing.Size($b.MinW, $b.MinH)
        $form.Bounds = New-Object Drawing.Rectangle($b.X, $b.Y, $b.W, $b.H)
        $script:GuiFit = $b
    }
    $form.Add_Load($fitToScreen)
    $script:AskRetry = { param($m) return ([Windows.Forms.MessageBox]::Show($form, $m, "$($script:Product) - folder in use", 'RetryCancel', 'Warning') -eq 'Retry') }
    $script:LogBox = $log
    $script:ProgressCb = { param($p, $t) $bar.Value = $p; $lblStat.Text = $t; [System.Windows.Forms.Application]::DoEvents() }
    $script:SaveItems = New-Object System.Collections.ArrayList

    $pickFolder = {
        param([string]$desc, [string]$start)
        $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = $desc; $d.ShowNewFolderButton = $true
        if ($start -and (Test-Path -LiteralPath $start)) { $d.SelectedPath = $start }
        if ($d.ShowDialog($form) -eq 'OK') { return $d.SelectedPath }; return $null
    }
    $refreshSaves = {
        $lstSaves.Items.Clear(); [void]$script:SaveItems.Clear()
        $emp = $cbEmp.Text.Trim()
        if (Test-EmpyrionDir $emp) {
            foreach ($s in (Get-SaveFolders $emp)) {
                $tag = ''; if ($s.HasShared) { $tag = '  (has SharedData)' }
                [void]$lstSaves.Items.Add(("[{0}] {1}{2}" -f $s.Kind, $s.Name, $tag), $false); [void]$script:SaveItems.Add($s.Path)
            }
        }
    }
    $detectName = {
        $script:GuiScenName = $script:ScenarioName
        $z = $txtZip.Text.Trim()
        if ($chkHave.Checked -and $z -and (Test-Path -LiteralPath $z -PathType Leaf)) {
            try {
                $i = Get-ArchiveScenarioInfo $z; $script:GuiScenName = $i.Name
                $lblName.ForeColor = 'DarkGreen'; $lblName.Text = ("Scenario name: {0}   (from {1}; {2} files)" -f $i.Name, $i.Source, $i.Count)
                Write-Log ("Zip checked: scenario name '{0}' (from {1})" -f $i.Name, $i.Source)
            } catch { $lblName.ForeColor = 'DarkRed'; $lblName.Text = 'Could not read this zip: ' + $_.Exception.Message }
        } elseif ($chkHave.Checked) { $lblName.ForeColor = 'DarkRed'; $lblName.Text = 'Pick your zip to see the scenario name.' }
        else {
            $lk = Resolve-DownloadUrl $txtUrl.Text
            if ($lk.Kind -in @('Invalid', 'Mega', 'DriveFolder')) { $script:GuiScenName = '<name from the zip>'; $lblName.ForeColor = 'DarkRed'; $lblName.Text = @($lk.Message -split "`n")[0] }
            elseif ($lk.IsDefault -and $script:DefaultNameKnown) { $lblName.ForeColor = [Drawing.SystemColors]::ControlText; $lblName.Text = "Scenario name: $($script:ScenarioName)   (default download; confirmed from the zip after downloading)" }
            else { $script:GuiScenName = '<name from the zip>'; $lblName.ForeColor = 'DarkBlue'; $lblName.Text = ("{0} ({1}) - the scenario name is read from the zip after downloading" -f $lk.Label, $lk.Host) }
        }
    }
    $updateMode = {
        $p = $cbEmp.Text.Trim()
        $lblSub.Text = "Scenario: $($script:GuiScenName)   -   installs it into Empyrion, then copies its SharedData into the save(s) you pick."
        if ($script:TestAuto) { $script:SettingTest = $true; $txtTest.Text = Get-DefaultTestFolder $(if (Test-EmpyrionDir $p) { $p } else { $null }); $script:SettingTest = $false }
        if ($chkTest.Checked) {
            $form.Text = (Get-WindowTitle) + '   [TEST MODE]'
            $hdr.Text = "$($script:Product) - TEST INSTALL MODE"; $hdr.ForeColor = 'DarkOrange'
            $btnGo.Text = 'Test install'
            $lblEmp.ForeColor = 'DarkOrange'; $lblEmp.Text = 'TEST MODE - will install to: ' + (Join-Path $txtTest.Text.Trim() "Content\Scenarios\$($script:GuiScenName)") + '  (real scenario untouched)'
        } else {
            $form.Text = (Get-WindowTitle)
            $hdr.Text = (Get-HeaderTitle); $hdr.ForeColor = [Drawing.SystemColors]::ControlText
            $btnGo.Text = 'Install'
            if (Test-EmpyrionDir $p) { $lblEmp.ForeColor = 'DarkGreen'; $lblEmp.Text = "OK - will install to: " + (Join-Path $p "Content\Scenarios\$($script:GuiScenName)") }
            else { $lblEmp.ForeColor = 'DarkRed'; $lblEmp.Text = 'Not an Empyrion folder. Pick the folder that contains Empyrion.exe / the Content folder.' }
        }
    }
    $validateEmp = {
        & $updateMode
        & $refreshSaves
    }

    $form.Add_Shown({
        foreach ($n in $script:ConfigNotes) { $log.AppendText(('{0:HH:mm:ss}  {1}' -f (Get-Date), $n) + "`r`n") }
        & $detectName
        Write-Log 'Looking for Steam and Empyrion...'
        try {
            $libs = Get-SteamLibraries (Get-SteamRoots)
            foreach ($l in $libs) { Write-Log "Steam library: $l" }
            $inst = Find-EmpyrionInstalls $libs
            foreach ($i in $inst) { [void]$cbEmp.Items.Add($i.Path); Write-Log ("Found {0}: {1}" -f $i.Kind, $i.Path) }
            if ($cbEmp.Items.Count) { $cbEmp.SelectedIndex = 0 } else { Write-Log 'Empyrion was not found automatically. Click Browse... and pick your Empyrion folder.' }
        } catch { Write-Log "Auto-detect error: $_" }
        & $validateEmp
    })
    $cbEmp.Add_SelectedIndexChanged($validateEmp); $cbEmp.Add_Leave($validateEmp)
    $btnEmp.Add_Click({ $p = & $pickFolder 'Select your "Empyrion - Galactic Survival" (or Dedicated Server) folder' $cbEmp.Text; if ($p) { $cbEmp.Text = $p; & $validateEmp } })
    $btnDl.Add_Click({ $p = & $pickFolder 'Folder to download the scenario zip into' $txtDl.Text; if ($p) { $txtDl.Text = $p } })
    $chkHave.Add_CheckedChanged({ $txtZip.Enabled = $chkHave.Checked; $btnZip.Enabled = $chkHave.Checked; $txtDl.Enabled = -not $chkHave.Checked; $btnDl.Enabled = -not $chkHave.Checked; $txtUrl.Enabled = -not $chkHave.Checked; $btnUrlReset.Enabled = -not $chkHave.Checked; & $detectName; & $updateMode })
    $txtUrl.Add_TextChanged({ & $detectName; & $updateMode })
    $btnUrlReset.Add_Click({ $txtUrl.Text = $script:DefaultDownloadUrl; Write-Log 'Download link reset to the default.' })
    $txtZip.Add_Leave({ & $detectName; & $updateMode })
    $btnZip.Add_Click({ $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = 'Zip archive (*.zip)|*.zip'; if ($d.ShowDialog($form) -eq 'OK') { $txtZip.Text = $d.FileName; & $detectName; & $updateMode } })
    $btnRefresh.Add_Click($refreshSaves)
    $chkTest.Add_CheckedChanged({
        $txtTest.Enabled = $chkTest.Checked; $btnTest.Enabled = $chkTest.Checked
        if ($chkTest.Checked) { Write-Log "TEST MODE ON: will install into $($txtTest.Text) - your real scenario is not touched." } else { Write-Log 'TEST MODE OFF: normal install into your Empyrion folder.' }
        & $updateMode
    })
    $txtTest.Add_TextChanged({ if (-not $script:SettingTest) { $script:TestAuto = $false; & $updateMode } })
    $btnTest.Add_Click({ $p = & $pickFolder 'Test install folder (a scratch folder OUTSIDE your Empyrion folder)' $txtTest.Text; if ($p) { $txtTest.Text = $p } })
    $btnAddSave.Add_Click({
        $start = $cbEmp.Text.Trim(); if (Test-Path -LiteralPath (Join-Path $start 'Saves')) { $start = Join-Path $start 'Saves' }
        $p = & $pickFolder 'Pick a save folder, e.g. ...\Saves\Games\<GameName> or a dedicated server''s Saves\Games\<GameName>' $start
        if ($p) {
            if ((Split-Path -Leaf $p) -ieq 'SharedData') { $p = Split-Path -Parent $p }
            [void]$lstSaves.Items.Add("[Custom] $p", $true); [void]$script:SaveItems.Add($p)
        }
    })
    $script:Busy = $false
    $btnCancel.Add_Click({ if ($script:Busy) { $script:Cancel = $true; Write-Log 'Cancelling... (the download can be resumed later)' } else { $form.Close() } })
    $form.Add_FormClosing({ param($s, $e) if ($script:Busy) { $script:Cancel = $true; $e.Cancel = $true } })

    $btnGo.Add_Click({
        $emp = $cbEmp.Text.Trim()
        $test = $chkTest.Checked
        if (-not $test -and -not (Test-EmpyrionDir $emp)) { [void][Windows.Forms.MessageBox]::Show($form, 'Please choose a valid Empyrion folder first.', $script:Product); return }
        if ($test -and -not $txtTest.Text.Trim()) { [void][Windows.Forms.MessageBox]::Show($form, 'Please choose a test folder.', $script:Product); return }
        if (-not (Test-EmpyrionDir $emp)) { $emp = $null }
        if ($chkHave.Checked -and -not (Test-Path -LiteralPath $txtZip.Text)) { [void][Windows.Forms.MessageBox]::Show($form, 'Please pick the scenario zip you already have.', $script:Product); return }
        if (-not $chkHave.Checked) {
            $lk = Resolve-DownloadUrl $txtUrl.Text
            if ($lk.Kind -in @('Invalid', 'Mega', 'DriveFolder')) { [void][Windows.Forms.MessageBox]::Show($form, $lk.Message, $script:Product, 'OK', 'Warning'); return }
        }
        $saves = @(); foreach ($i in $lstSaves.CheckedIndices) { $saves += $script:SaveItems[$i] }
        if ($test -and $saves.Count) {
            $r = [Windows.Forms.MessageBox]::Show($form, "TEST MODE: the scenario goes to the test folder, but you ticked $($saves.Count) REAL save(s). SharedData will be copied into those real saves too.`n`nContinue?", "$($script:Product) - TEST MODE", 'YesNo', 'Warning')
            if ($r -ne 'Yes') { return }
        }
        if (-not $test -and -not $saves.Count) {
            $r = [Windows.Forms.MessageBox]::Show($form, "No save is ticked, so SharedData will only be installed inside the scenario (fine for a NEW game).`n`nContinue?", $script:Product, 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
        }
        if ($chkDel.Checked -and $chkHave.Checked) { $chkDel.Checked = $false }
        $zip = $null; if ($chkHave.Checked) { $zip = $txtZip.Text }
        foreach ($c in @($btnGo, $btnEmp, $btnDl, $btnZip, $btnAddSave, $btnRefresh, $cbEmp, $txtDl, $txtZip, $chkHave, $chkOver, $chkDel, $lstSaves, $chkTest, $txtTest, $btnTest, $txtUrl, $btnUrlReset)) { $c.Enabled = $false }
        $btnCancel.Text = 'Cancel'; $script:Busy = $true; $script:Cancel = $false
        $ok = $false
        try {
            Invoke-Install @{ EmpyrionPath = $emp; ArchivePath = $zip; DownloadFolder = $txtDl.Text; SaveFolders = $saves; DownloadUrl = $txtUrl.Text;
                              OverwriteInPlace = $chkOver.Checked; DeleteArchiveAfter = $chkDel.Checked; SkipSpaceCheck = $false;
                              TestMode = $test; TestFolder = $txtTest.Text.Trim() }
            $ok = $true
        } catch {
            Write-Log "ERROR: $($_.Exception.Message)"
            $lblStat.Text = 'Stopped: ' + $_.Exception.Message
            [void][Windows.Forms.MessageBox]::Show($form, $_.Exception.Message + "`n`nLog: $($script:LogFile)", "$($script:Product) - not finished", 'OK', 'Warning')
        } finally {
            $script:Busy = $false; $btnCancel.Text = 'Close'
            foreach ($c in @($btnGo, $btnEmp, $btnAddSave, $btnRefresh, $cbEmp, $chkHave, $chkOver, $chkDel, $lstSaves, $chkTest)) { $c.Enabled = $true }
            $txtTest.Enabled = $chkTest.Checked; $btnTest.Enabled = $chkTest.Checked
            $txtUrl.Enabled = -not $chkHave.Checked; $btnUrlReset.Enabled = -not $chkHave.Checked
            $txtDl.Enabled = -not $chkHave.Checked; $btnDl.Enabled = -not $chkHave.Checked; $txtZip.Enabled = $chkHave.Checked; $btnZip.Enabled = $chkHave.Checked
        }
        if ($ok -and $test) { [void][Windows.Forms.MessageBox]::Show($form, "TEST install of '$($script:LastScenarioName)' finished in:`n$($txtTest.Text.Trim())`n`nYour real Empyrion scenario was not touched. Check the log for details.", "$($script:Product) - TEST MODE", 'OK', 'Information') }
        elseif ($ok) { [void][Windows.Forms.MessageBox]::Show($form, "$($script:LastScenarioName) is installed.`n`nStart Empyrion > New Game > Scenarios > $($script:LastScenarioName), or load the save(s) you picked.", $script:Product, 'OK', 'Information') }
    })

    [void]$form.ShowDialog()
}

# ----------------------------------------------------------------- entry point
if ($env:AR_INSTALLER_NO_MAIN -eq '1') { return }   # lets tests dot-source the functions
try {
    [void](Import-InstallerConfig (Find-InstallerConfig $Config))
    if ($NoGui -or $ListOnly -or -not $script:IsWin) { Start-Console }
    else {
        if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
            $ps = Join-Path $PSHOME 'powershell.exe'; if (-not (Test-Path $ps)) { $ps = 'powershell.exe' }
            $a = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"")
            if ($Config) { $a += @('-Config', "`"$Config`"") }
            Start-Process $ps -ArgumentList $a
            return
        }
        Start-Gui
    }
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
