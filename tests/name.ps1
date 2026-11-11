. "$PSScriptRoot/_common.ps1"
$T=$Fix
Write-Host "== unit: sanitizing"
Check 'safe: trims' ((Get-SafeScenarioName '  Padded Name  ') -eq 'Padded Name')
Check 'safe: trailing dot' ((Get-SafeScenarioName 'name.') -eq 'name')
Check 'reject ..' ($null -eq (Get-SafeScenarioName '..'))
Check 'reject a..b' ($null -eq (Get-SafeScenarioName 'bad..name'))
Check 'reject /' ($null -eq (Get-SafeScenarioName 'a/b'))
Check 'reject \' ($null -eq (Get-SafeScenarioName 'a\b'))
Check 'reject :' ($null -eq (Get-SafeScenarioName 'C:x'))
Check 'reject CON' ($null -eq (Get-SafeScenarioName 'CON'))
Check 'reject blank' ($null -eq (Get-SafeScenarioName '   '))
Write-Host "== unit: name resolution"
$real = Get-Content (Join-Path $Fix "sample-listing.txt")
$p = Get-ScenarioPrefix $real; $r = Resolve-ScenarioName $p '/x/Ascension-Reborn.zip'
Check 'real Drive archive -> Ascension-Reborn (top folder)' ($p -eq 'Ascension-Reborn/' -and $r.Name -eq 'Ascension-Reborn' -and $r.Source -like '*top folder*')
$p = Get-ScenarioPrefix @('Cool/','Cool/Content/Configuration/a.ecf','Cool/Playfields/x/p.yaml','Cool/SharedData/Content/Bundles/b')
Check 'top folder Cool' ((Resolve-ScenarioName $p '/x/whatever.zip').Name -eq 'Cool')
$p = Get-ScenarioPrefix @('Scenarios/Foo/Content/Configuration/a.ecf','Scenarios/Foo/Playfields/x','readme.txt'.Replace('readme','Scenarios/readme'))
Check 'nested Scenarios/Foo -> Foo' ((Resolve-ScenarioName $p '/x/z.zip').Name -eq 'Foo')
$p = Get-ScenarioPrefix @('Pack/Playfields/a/p.yaml','Pack/Sectors/Sectors.yaml')
Check 'markers without Content/Configuration -> Pack' ($p -eq 'Pack/')
$p = Get-ScenarioPrefix @('Content/Configuration/a.ecf','Playfields/x/p.yaml','SharedData/Content/Bundles/b')
$r = Resolve-ScenarioName $p 'C:\dl\Flat Scenario.zip'
Check 'no top folder -> zip file name' ($p -eq '' -and $r.Name -eq 'Flat Scenario' -and $r.Source -eq 'the zip file name')
$r = Resolve-ScenarioName '' '/dl/...zip'
Check 'no top folder + unsafe zip name -> Ascension-Reborn' ($r.Name -eq 'Ascension-Reborn' -and $r.Source -eq 'the default name')
$r = Resolve-ScenarioName 'bad..name/' '/dl/Good Zip.zip'
Check 'unsafe top folder -> zip file name' ($r.Name -eq 'Good Zip')
$r = Resolve-ScenarioName '  Spaced  /' '/dl/z.zip'
Check 'top folder trimmed' ($r.Name -eq 'Spaced')
$r = Resolve-ScenarioName '' $null
Check 'nothing -> Ascension-Reborn' ($r.Name -eq 'Ascension-Reborn')

Write-Host "== e2e"
$M=(Get-TestDir 'armock3'); if (Test-Path $M) { Remove-Item $M -Recurse -Force }
$E="$M/Empyrion - Galactic Survival"; $SC="$E/Content/Scenarios"
New-Item -ItemType Directory -Force "$SC/Ascension-Reborn/Content","$E/Saves/Games/RealSave" | Out-Null
'x' | Set-Content "$E/EmpyrionLauncher.exe"; 'real AR' | Set-Content "$SC/Ascension-Reborn/Content/keep.txt"
function Snap($d) { (Get-ChildItem $d -Recurse -File | % { $_.FullName.Substring($d.Length) + ':' + $_.Length } | Sort-Object) -join '|' }
function Opt([hashtable]$x) { $o=@{ EmpyrionPath=$E; ArchivePath=$null; DownloadFolder=$null; SaveFolders=@(); OverwriteInPlace=$false; DeleteArchiveAfter=$false; SkipSpaceCheck=$false; TestMode=$false; TestFolder=$null }; foreach($k in $x.Keys){$o[$k]=$x[$k]}; $o }
function LogTail { (Get-Content $script:LogFile -Tail 40) -join "`n" }
$arBefore = Snap "$SC/Ascension-Reborn"
Invoke-Install (Opt @{ ArchivePath="$T/Cool Pack.zip"; SaveFolders=@("$E/Saves/Games/RealSave") })
Check 'installs to Scenarios/Cool Scenario' (Test-Path "$SC/Cool Scenario/Content/Configuration/Config.ecf")
Check 'Ascension-Reborn untouched' ((Snap "$SC/Ascension-Reborn") -eq $arBefore)
Check 'log shows name + source' ((LogTail) -match "Scenario name: 'Cool Scenario' \(from the archive's top folder 'Cool Scenario/'\)" -and (LogTail) -match "choose 'Cool Scenario'")
Check 'SharedData to save' (Test-Path "$E/Saves/Games/RealSave/SharedData/Content/Bundles/asc_x.manifest")
Check 'LastScenarioName set' ($script:LastScenarioName -eq 'Cool Scenario')
Invoke-Install (Opt @{ ArchivePath="$T/Cool Pack.zip" })
$bk=@(Get-ChildItem "$E/Content/Scenarios_Backups" -Directory)
Check 'backup named Cool Scenario_<timestamp>' ($bk.Count -eq 1 -and $bk[0].Name -match '^Cool Scenario_\d{8}_\d{6}$')
# in-use check targets the detected folder
$script:MoveDirImpl = { param($a,$b) if ($a -like '*Cool Scenario') { throw [System.UnauthorizedAccessException]"Access to the path '$a' is denied." }; [IO.Directory]::Move($a,$b) }
$script:AskRetry = { param($m) $script:msg=$m; $false }; $script:msg=$null
$err=$null; try { Invoke-Install (Opt @{ ArchivePath="$T/Cool Pack.zip" }) } catch { $err=$_.Exception.Message }
Check 'in-use check uses detected folder' ($err -like '*Cool Scenario*' -and $script:msg -like '*Scenarios*Cool Scenario*')
$script:MoveDirImpl = { param($a,$b) [IO.Directory]::Move($a,$b) }; $script:AskRetry=$null
Invoke-Install (Opt @{ ArchivePath="$T/Flat Pack.zip" })
Check 'flat zip -> Scenarios/Flat Pack' (Test-Path "$SC/Flat Pack/Content/Configuration/Config.ecf")
Invoke-Install (Opt @{ ArchivePath="$T/Unsafe Fallback.zip" })
Check 'unsafe top folder -> Scenarios/Unsafe Fallback' ((Test-Path "$SC/Unsafe Fallback/Sectors/Sectors.yaml") -and -not (Test-Path "$SC/bad..name") -and (LogTail) -match "Ignoring unsafe scenario name 'bad..name'")
$TF="$M/AR_InstallTest"
Invoke-Install (Opt @{ ArchivePath="$T/Cool Pack.zip"; TestMode=$true; TestFolder=$TF })
Check 'test mode -> test/Content/Scenarios/Cool Scenario' ((Test-Path "$TF/Content/Scenarios/Cool Scenario/Content/Configuration/Config.ecf") -and (Test-Path "$TF/Saves/Games/TestGame/SharedData/Content/Bundles/asc_x.manifest"))
Check 'test mode log names scenario' ((LogTail) -match "TEST MODE: test install of 'Cool Scenario'")
# download path: provisional default name, then the archive's real name
function Get-RemoteInfo([string]$url) { return (New-Object psobject -Property @{ Size = [int64]1000; FileName = $null; IsHtml = $false; Ranges = $true }) }
$script:DlSrc = "$T/Other.zip"
function Invoke-ResumableDownload($url, $dest, $expected, $maxRetries, $stopAfter, $chunk, $kind, $key) { Copy-Item -LiteralPath $script:DlSrc -Destination $dest -Force; [IO.File]::WriteAllText("$dest.src", $key) }
$DL="$M/dl"; New-Item -ItemType Directory -Force $DL | Out-Null
Invoke-Install (Opt @{ DownloadFolder=$DL; SkipSpaceCheck=$true })
Check 'download: provisional then switched to Other Name' ((LogTail) -match "for now" -and (LogTail) -match "installing there instead of 'Ascension-Reborn'" -and (Test-Path "$SC/Other Name/Playfields/Arid/playfield.yaml"))
Check 'download: Ascension-Reborn still untouched' ((Snap "$SC/Ascension-Reborn") -eq $arBefore)
Remove-Item "$DL/Ascension-Reborn.zip"; $script:DlSrc = "$T/AR_default.zip"
Invoke-Install (Opt @{ DownloadFolder=$DL; SkipSpaceCheck=$true })
Check 'default link still installs as Ascension-Reborn (old copy backed up)' ((LogTail) -match "confirmed from the archive: 'Ascension-Reborn'" -and (Test-Path "$SC/Ascension-Reborn/Sectors/Sectors.yaml") -and @(Get-ChildItem "$E/Content/Scenarios_Backups" -Directory | ? Name -like 'Ascension-Reborn_*').Count -eq 1)
Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
