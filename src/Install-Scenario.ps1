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

# ... rest of the file remains identical to the original, with only the above changes ...
