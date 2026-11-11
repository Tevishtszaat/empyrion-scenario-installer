. "$PSScriptRoot/_common.ps1"
$zip="$Fix/mock_small.zip"
$M=(Get-TestDir 'armock2')
function Reset-Mock {
    if (Test-Path $M) { & chmod -R u+w $M; Remove-Item $M -Recurse -Force }
    $script:E="$M/Empyrion - Galactic Survival"; $script:Scen="$E/Content/Scenarios/Ascension-Reborn"
    New-Item -ItemType Directory -Force "$Scen/Content/Configuration","$Scen/SharedData/Content/Bundles","$E/Saves/Games/RealSave/SharedData" | Out-Null
    'x' | Set-Content "$E/EmpyrionLauncher.exe"
    1..50 | % { "file $_" | Set-Content "$Scen/Content/Configuration/f$_.ecf" }
    'real' | Set-Content "$Scen/SharedData/Content/Bundles/real.bundle"
}
function Snap($d) { (Get-ChildItem $d -Recurse -File | % { $_.FullName.Substring($d.Length) + ':' + $_.Length } | Sort-Object) -join '|' }
function Leftovers { @(Get-ChildItem "$E/Content/Scenarios" -Force | ? Name -like '*__ar_movetest_*').Count }
function Opt([hashtable]$extra) { $o=@{ EmpyrionPath=$E; ArchivePath=$zip; DownloadFolder=$null; SaveFolders=@(); OverwriteInPlace=$false; DeleteArchiveAfter=$false; SkipSpaceCheck=$false; TestMode=$false; TestFolder=$null }; foreach($k in $extra.Keys){$o[$k]=$extra[$k]}; $o }
$realMove = $script:MoveDirImpl; $script:moves=0; $script:lastMsg=$null; $script:asked=0; $script:locked=$false

Write-Host "`n== A: folder locked, user cancels"
Reset-Mock; $before=Snap $Scen
$script:locked=$true
$script:MoveDirImpl = { param($a,$b) $script:moves++; if ($script:locked) { throw [System.UnauthorizedAccessException]"Access to the path '$a' is denied." }; [IO.Directory]::Move($a,$b) }
$script:AskRetry = { param($m) $script:asked++; $script:lastMsg=$m; $false }; $script:asked=0
$err=$null; try { Invoke-Install (Opt @{}) } catch { $err=$_.Exception.Message }
Check 'A error shown' ($err -like '*in use*Nothing was changed*')
Check 'A Retry/Cancel asked once' ($script:asked -eq 1)
Check 'A scenario intact' ((Snap $Scen) -eq $before)
Check 'A no Scenarios_Backups created' (-not (Test-Path "$E/Content/Scenarios_Backups"))
Check 'A no probe leftovers' ((Leftovers) -eq 0)
Check 'A prompt lists Explorer/EAH/antivirus/admin' ($script:lastMsg -match 'File Explorer' -and $script:lastMsg -match 'EAH' -and $script:lastMsg -match 'antivirus' -and $script:lastMsg -match 'administrator')
Check 'A fails before extracting anything' (-not (Test-Path "$Scen/SharedData/Content/Bundles/asc_test.manifest"))

Write-Host "`n== B: locked, user closes Explorer and clicks Retry"
Reset-Mock; $before=Snap $Scen
$script:locked=$true
$script:asked=0; $script:AskRetry = { param($m) $script:asked++; if ($script:asked -ge 2) { $script:locked=$false }; $true }
$err=$null; try { Invoke-Install (Opt @{}) } catch { $err=$_.Exception.Message; Write-Host "B err: $err" }
$bk=@(Get-ChildItem "$E/Content/Scenarios_Backups" -Directory -EA 0)
Check 'B succeeded after retries' (-not $err -and $script:asked -eq 2)
Check 'B backup holds the old scenario' ($bk.Count -eq 1 -and (Snap $bk[0].FullName) -eq $before)
Check 'B new scenario installed' (Test-Path "$Scen/SharedData/Content/Bundles/asc_test.manifest")
Check 'B no probe leftovers' ((Leftovers) -eq 0)

Write-Host "`n== A2: Scenarios folder truly read-only -> clear no-write-access message"
Reset-Mock; $before=Snap $Scen; $script:MoveDirImpl = $realMove
& chmod 555 "$E/Content/Scenarios"
$err=$null; try { Invoke-Install (Opt @{}) } catch { $err=$_.Exception.Message }
& chmod 755 "$E/Content/Scenarios"
Check 'A2 message' ($err -like '*No write access*administrator*')
Check 'A2 intact, no backup dir' ((Snap $Scen) -eq $before -and -not (Test-Path "$E/Content/Scenarios_Backups"))

Write-Host "`n== C: probe passes but the real move is refused (cancel)"
Reset-Mock; $before=Snap $Scen
$script:MoveDirImpl = { param($a,$b) if ($b -like '*Scenarios_Backups*') { throw [System.IO.IOException]"The process cannot access the file because it is being used by another process." }; [IO.Directory]::Move($a,$b) }
$script:asked=0; $script:AskRetry = { param($m) $script:asked++; $false }
$err=$null; try { Invoke-Install (Opt @{}) } catch { $err=$_.Exception.Message }
Check 'C error' ($err -like '*could not be backed up*')
Check 'C scenario intact' ((Snap $Scen) -eq $before)
Check 'C empty Scenarios_Backups it created was removed' (-not (Test-Path "$E/Content/Scenarios_Backups"))

Write-Host "`n== D: move fails partway (folder moved, then error) -> rollback"
Reset-Mock; $before=Snap $Scen
$script:MoveDirImpl = { param($a,$b) [IO.Directory]::Move($a,$b); if ($b -like '*Scenarios_Backups*') { throw [System.IO.IOException]"simulated failure after move" } }
$script:asked=0; $script:AskRetry = { param($m) $script:asked++; $false }
$err=$null; try { Invoke-Install (Opt @{}) } catch { $err=$_.Exception.Message }
Check 'D error' ($err -like '*could not be backed up*')
Check 'D rolled back: scenario back in place and intact' ((Snap $Scen) -eq $before)
Check 'D no Scenarios_Backups left' (-not (Test-Path "$E/Content/Scenarios_Backups"))

Write-Host "`n== E: pre-existing empty Scenarios_Backups (left by an earlier failed run) is left alone on failure"
Reset-Mock; New-Item -ItemType Directory "$E/Content/Scenarios_Backups" | Out-Null
$script:MoveDirImpl = { param($a,$b) if ($b -like '*Scenarios_Backups*') { throw [System.IO.IOException]"in use" }; [IO.Directory]::Move($a,$b) }
try { Invoke-Install (Opt @{}) } catch {}
Check 'E existing empty Scenarios_Backups kept' ((Test-Path "$E/Content/Scenarios_Backups") -and -not @(Get-ChildItem "$E/Content/Scenarios_Backups" -Force).Count)
$script:MoveDirImpl = $realMove

Write-Host "`n== F: in-place update with a locked file, Retry"
Reset-Mock; Invoke-Install (Opt @{ OverwriteInPlace=$true }) | Out-Null
$lf="$Scen/Content/Configuration/BlocksConfig.ecf"; 'changed' | Set-Content $lf; & chmod 444 $lf
$script:asked=0; $script:AskRetry = { param($m) $script:asked++; & chmod 644 $lf; $true }
$err=$null; try { Invoke-Install (Opt @{ OverwriteInPlace=$true }) } catch { $err=$_.Exception.Message }
Check 'F locked file retried and rewritten' (-not $err -and $script:asked -ge 1 -and (Get-Content $lf -First 1) -like '{ Block*')
'changed again' | Set-Content $lf; & chmod 444 $lf; $script:AskRetry = { param($m) $false }
$err=$null; try { Invoke-Install (Opt @{ OverwriteInPlace=$true }) } catch { $err=$_.Exception.Message }
& chmod 644 $lf
Check 'F locked file + cancel -> clear error' ($err -like "*Can't write*")

Write-Host "`n== G: TEST MODE"
Reset-Mock; $before=Snap $Scen; $beforeSave=Snap "$E/Saves"
$T="$M/AR_InstallTest"
$script:AskRetry = $null
Invoke-Install (Opt @{ TestMode=$true; TestFolder=$T })
Check 'G real scenario untouched' ((Snap $Scen) -eq $before)
Check 'G real saves untouched' ((Snap "$E/Saves") -eq $beforeSave)
Check 'G no real Scenarios_Backups' (-not (Test-Path "$E/Content/Scenarios_Backups"))
Check 'G scenario in test folder' (Test-Path "$T/Content/Scenarios/Ascension-Reborn/Content/Configuration/BlocksConfig.ecf")
Check 'G SharedData in TestGame' (Test-Path "$T/Saves/Games/TestGame/SharedData/Content/Bundles/asc_test.manifest")
$log=(Get-Content $script:LogFile -Tail 40) -join "`n"
Check 'G log shows TEST MODE' ($log -match 'TEST MODE: installing into' -and $log -match "test install of 'Ascension-Reborn' finished")
Invoke-Install (Opt @{ TestMode=$true; TestFolder=$T })
Check 'G second test run backs up inside test folder' (@(Get-ChildItem "$T/Content/Scenarios_Backups" -Directory).Count -eq 1)
Invoke-Install (Opt @{ TestMode=$true; TestFolder=$T; SaveFolders=@("$E/Saves/Games/RealSave") })
Check 'G ticked real save gets SharedData' (Test-Path "$E/Saves/Games/RealSave/SharedData/Content/Bundles/asc_test.manifest")
Check 'G ...but not TestGame-only path forced' ((Snap $Scen) -eq $before)
$err=$null; try { Invoke-Install (Opt @{ TestMode=$true; TestFolder="$E/sub" }) } catch { $err=$_.Exception.Message }
Check 'G test folder inside Empyrion rejected' ($err -like '*must be outside*')
$err=$null; try { Invoke-Install (Opt @{ TestMode=$true; TestFolder=$T; EmpyrionPath=$null }) } catch { $err=$_.Exception.Message }
Check 'G test mode works without an Empyrion folder' (-not $err)
Check 'G disk check uses test drive' (((Get-Content $script:LogFile -Tail 60) -join "`n") -match 'Drive /: needs')
Reset-Mock; Copy-Item $zip "$Scen/inside.zip"
$err=$null; try { Invoke-Install (Opt @{ ArchivePath="$Scen/inside.zip" }) } catch { $err=$_.Exception.Message }
Check 'G zip inside scenario folder guarded' ($err -like '*inside the scenario folder*')

Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
