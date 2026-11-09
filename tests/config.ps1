# installer.json: loading, validation, fallback to the built-in defaults, and its effect on installs.
. "$PSScriptRoot/_common.ps1"
$C = Get-TestDir 'config'; if (Test-Path $C) { Remove-Item $C -Recurse -Force }; New-Item -ItemType Directory -Force $C | Out-Null
$BuiltinUrl = $script:DefaultDownloadUrl; $BuiltinId = $script:DriveFileId
function J([string]$name, [string]$text) { $p = Join-Path $C $name; [IO.File]::WriteAllText($p, $text); return $p }
function Notes { $script:ConfigNotes -join "`n" }

Write-Host '== no config: built-in defaults'
$env:SCENARIO_INSTALLER_DIR = $null
Check 'no installer.json found next to the source' ($null -eq (Find-InstallerConfig $null))
Check 'Import with no path -> false' (-not (Import-InstallerConfig $null))
Check 'built-in default link is the Ascension-Reborn Drive file' ($script:DefaultDownloadUrl -like "*$BuiltinId*" -and (Resolve-DownloadUrl '').IsDefault -and (Resolve-DownloadUrl '').FileHint -eq 'Ascension-Reborn.zip')
Check 'built-in names' ($script:ScenarioName -eq 'Ascension-Reborn' -and $script:TestFolderName -eq 'AR_InstallTest' -and (Get-WindowTitle) -eq "Scenario Installer $($script:Version)")

Write-Host '== lookup order'
$d1 = Join-Path $C 'exe dir'; New-Item -ItemType Directory -Force $d1 | Out-Null; '{}' | Set-Content (Join-Path $d1 'installer.json')
$env:SCENARIO_INSTALLER_DIR = $d1
Check 'installer.json next to the exe (launcher env) is found' ((Find-InstallerConfig $null) -eq (Join-Path $d1 'installer.json'))
Check '-Config wins' ((Find-InstallerConfig '/x/other.json') -eq '/x/other.json')
$env:SCENARIO_INSTALLER_DIR = $null

Write-Host '== full valid config (Dropbox link)'
$p = J 'full.json' '{ "_comment": "hi", "defaultUrl": "https://www.dropbox.com/s/abc/Cool%20Pack.zip?dl=0", "scenarioName": "My Scenario", "testFolderName": "MS_Test", "title": "My Server Pack" }'
. $Src
Check 'applied' (Import-InstallerConfig $p)
$lk = Resolve-DownloadUrl ''
Check 'empty link -> configured default, marked default' ($lk.Kind -eq 'Direct' -and $lk.Url -eq 'https://www.dropbox.com/s/abc/Cool%20Pack.zip?dl=1' -and $lk.IsDefault)
Check 'pasted configured link (dl=1 form) is also the default' ((Resolve-DownloadUrl 'https://www.dropbox.com/s/abc/Cool%20Pack.zip?dl=1').IsDefault)
Check 'built-in Drive link no longer the default' (-not (Resolve-DownloadUrl $BuiltinUrl).IsDefault)
Check 'scenario name / test folder / title' ($script:ScenarioName -eq 'My Scenario' -and $script:ConfigScenarioName -eq 'My Scenario' -and (Get-DefaultTestFolder '/games/Empyrion') -like '*MS_Test' -and (Get-WindowTitle) -eq "My Server Pack - Scenario Installer $($script:Version)" -and (Get-HeaderTitle) -eq 'My Server Pack')
Check 'built-in size not used for another link' (-not $script:DefaultIsBuiltin)
Check 'log names host only' ((Notes) -match 'host: www\.dropbox\.com' -and (Notes) -notmatch 'abc/Cool' -and (Notes) -notmatch '_comment')

Write-Host '== custom Drive default without scenarioName'
$p = J 'drive.json' '{ "defaultUrl": "https://drive.google.com/file/d/0B_SomeoneElsesFile1234/view?usp=sharing" }'
. $Src
Check 'applied' (Import-InstallerConfig $p)
$lk = Resolve-DownloadUrl ''
Check 'Drive default, generic file name' ($lk.Kind -eq 'Drive' -and $lk.IsDefault -and $lk.Id -eq '0B_SomeoneElsesFile1234' -and $lk.FileHint -eq 'Drive_0B_SomeoneElsesFile1234.zip')
Check 'name unknown until the zip is read; fallback is generic' (-not $script:DefaultNameKnown -and $script:ScenarioName -eq 'Scenario')

Write-Host '== same Drive file as built in'
$p = J 'same.json' ('{ "defaultUrl": "https://drive.google.com/open?id=' + $BuiltinId + '" }')
. $Src
[void](Import-InstallerConfig $p)
Check 'keeps the known name/size' ($script:DefaultIsBuiltin -and $script:DefaultNameKnown -and (Resolve-DownloadUrl '').FileHint -eq 'Ascension-Reborn.zip')

Write-Host '== invalid files -> ignored, defaults kept'
$bad = @{ 'syntax.json' = '{ "defaultUrl": "https://x/a.zip", '; 'array.json' = '[1,2]'; 'string.json' = '"hello"'; 'number.json' = '5'; 'empty.json' = '   '; 'trailing.json' = '{ "title": "x" } }' }
foreach ($k in $bad.Keys) {
    $p = J $k $bad[$k]
    . $Src
    $r = Import-InstallerConfig $p
    Check "invalid $k ignored" (-not $r -and $script:DefaultDownloadUrl -eq $BuiltinUrl -and $script:ScenarioName -eq 'Ascension-Reborn' -and -not $script:Title -and (Notes) -match 'invalid' -and (Get-Content $script:LogFile -Tail 3 | Out-String) -match 'invalid')
}
$p = Join-Path $C 'huge.json'; [IO.File]::WriteAllText($p, '{ "title": "' + ('x' * 70000) + '" }')
. $Src
Check 'oversized file ignored' (-not (Import-InstallerConfig $p) -and -not $script:Title)
. $Src
Check 'missing -Config file -> defaults + note' (-not (Import-InstallerConfig (Join-Path $C 'nope.json')) -and (Notes) -match 'not found' -and $script:DefaultDownloadUrl -eq $BuiltinUrl)

Write-Host '== bad values: that field ignored, the rest applied'
$p = J 'mixed.json' '{ "defaultUrl": "ftp://example.com/a.zip", "scenarioName": "..\\evil", "testFolderName": "C:\\abs", "title": 42, "colour": "red", "ignored": null }'
. $Src
[void](Import-InstallerConfig $p)
Check 'ftp link refused' ($script:DefaultDownloadUrl -eq $BuiltinUrl -and $script:DefaultIsBuiltin -and (Notes) -match 'defaultUrl ignored')
Check 'unsafe scenarioName / testFolderName refused' ($script:ScenarioName -eq 'Ascension-Reborn' -and $script:TestFolderName -eq 'AR_InstallTest' -and (Notes) -match "scenarioName '\.\.\\evil' is not a safe" -and (Notes) -match 'testFolderName')
Check 'non-text title refused, unknown key noted' (-not $script:Title -and (Notes) -match "'title' must be text" -and (Notes) -match "unknown setting 'colour'")
$p = J 'mega.json' ('{ "defaultUrl": "https://mega.nz/file/abc#key", "title": "  Long\ttitle ' + ('y' * 100) + '" }')
. $Src
[void](Import-InstallerConfig $p)
Check 'MEGA default refused' ($script:DefaultDownloadUrl -eq $BuiltinUrl -and (Notes) -match 'MEGA')
Check 'title cleaned and capped at 80' ($script:Title.Length -eq 80 -and $script:Title -notmatch "`t")
$p = J 'case.json' '{ "DEFAULTURL": "https://example.com/files/Pack.zip", "ScenarioName": "Case Ok" }'
. $Src
[void](Import-InstallerConfig $p)
Check 'keys are case-insensitive' ((Resolve-DownloadUrl '').Url -eq 'https://example.com/files/Pack.zip' -and $script:ScenarioName -eq 'Case Ok')

Write-Host '== installs with a config'
$M = Get-TestDir 'config-e2e'; if (Test-Path $M) { Remove-Item $M -Recurse -Force }
$E = "$M/Empyrion - Galactic Survival"; $SC = "$E/Content/Scenarios"; New-Item -ItemType Directory -Force "$SC", "$M/dl" | Out-Null; 'x' | Set-Content "$E/EmpyrionLauncher.exe"
function Opt([hashtable]$x) { $o = @{ EmpyrionPath = $E; ArchivePath = $null; DownloadFolder = "$M/dl"; SaveFolders = @(); OverwriteInPlace = $false; DeleteArchiveAfter = $false; SkipSpaceCheck = $true; TestMode = $false; TestFolder = $null; DownloadUrl = $null }; foreach ($k in $x.Keys) { $o[$k] = $x[$k] }; $o }
function Use-MockDownload([string]$zip) {
    $script:DlSrc = $zip
    function script:Get-RemoteInfo([string]$url) { return (New-Object psobject -Property @{ Size = [int64](Get-Item -LiteralPath $script:DlSrc).Length; FileName = $null; IsHtml = $false; Ranges = $true }) }
    function script:Invoke-ResumableDownload($url, $dest, $expected, $maxRetries, $stopAfter, $chunk, $kind, $key) { Copy-Item -LiteralPath $script:DlSrc -Destination $dest -Force; [IO.File]::WriteAllText("$dest.src", $key) }
}
$p = J 'forced.json' '{ "defaultUrl": "https://drive.google.com/file/d/0B_SomeoneElsesFile1234/view", "scenarioName": "Forced Name" }'
. $Src; [void](Import-InstallerConfig $p); Use-MockDownload "$Fix/Cool Pack.zip"
Invoke-Install (Opt @{})
Check 'default download + scenarioName -> Scenarios/Forced Name, saved as Forced Name.zip' ((Test-Path "$SC/Forced Name/Content/Configuration/Config.ecf") -and -not (Test-Path "$SC/Cool Scenario") -and (Test-Path "$M/dl/Forced Name.zip"))
Invoke-Install (Opt @{ ArchivePath = "$Fix/Other.zip" })
Check 'own zip still named from the zip' (Test-Path "$SC/Other Name/Sectors/Sectors.yaml")
Use-MockDownload "$Fix/Flat Pack.zip"
Invoke-Install (Opt @{ DownloadUrl = 'https://example.com/get/Flat%20Pack.zip' })
Check 'pasted link ignores scenarioName' (Test-Path "$SC/Flat Pack/Sectors/Sectors.yaml")
$p = J 'noname.json' '{ "defaultUrl": "https://example.com/files/whatever.bin" }'
. $Src; [void](Import-InstallerConfig $p); Use-MockDownload "$Fix/Other.zip"
Remove-Item "$SC/Other Name" -Recurse -Force
Invoke-Install (Opt @{})
Check 'custom default without scenarioName -> name from the zip' ((Test-Path "$SC/Other Name/Sectors/Sectors.yaml") -and -not (Test-Path "$SC/Scenario") -and -not (Test-Path "$SC/Ascension-Reborn"))

Write-Host '== whole script with -Config (console)'
$pw = (Get-Process -Id $PID).Path
$env:AR_INSTALLER_NO_MAIN = $null
$out = & $pw -NoProfile -File $Src -NoGui -ListOnly -Config (J 'cli-bad.json' '{ nope') 2>&1 | Out-String
Check 'invalid -Config: logged, still runs (exit 0)' ($LASTEXITCODE -eq 0 -and $out -match 'installer.json is invalid' -and $out -match 'Empyrion installs:')
$out = & $pw -NoProfile -File $Src -NoGui -ListOnly -Config (J 'cli-ok.json' '{ "title": "CLI Pack" }') 2>&1 | Out-String
Check 'valid -Config applied' ($LASTEXITCODE -eq 0 -and $out -match "Using .*cli-ok.json: title 'CLI Pack'")
$cp = Join-Path $C 'cli-dir'; New-Item -ItemType Directory -Force $cp | Out-Null; Copy-Item $Src $cp; '{ "testFolderName": "Next_To_Ps1" }' | Set-Content (Join-Path $cp 'installer.json')
$out = & $pw -NoProfile -File (Join-Path $cp 'Install-Scenario.ps1') -NoGui -ListOnly 2>&1 | Out-String
Check 'installer.json next to the .ps1 is picked up' ($out -match "testFolderName 'Next_To_Ps1'")
$env:AR_INSTALLER_NO_MAIN = '1'
$ex = Join-Path $RepoRoot 'installer.example.json'
. $Src
Check 'installer.example.json is valid and applies all four fields' ((Import-InstallerConfig $ex) -and (Notes) -match 'defaultUrl' -and (Notes) -match 'scenarioName' -and (Notes) -match 'testFolderName' -and (Notes) -match 'title')
Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
