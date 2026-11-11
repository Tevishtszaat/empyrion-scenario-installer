. "$PSScriptRoot/_common.ps1"
# VDF new format
$vdfNew=@'
"libraryfolders"
{
	"0"
	{
		"path"		"C:\\Program Files (x86)\\Steam"
		"label"		""
		"apps"
		{
			"228980"		"1"
		}
	}
	"1"
	{
		"path"		"E:\\SteamLibrary"
		"apps"	{ "383120" "21474836480" }
	}
}
'@
$r=Get-VdfLibraryPaths $vdfNew
Check 'vdf new count' ($r.Count -eq 2)
Check 'vdf new path' ($r[1] -eq 'E:\SteamLibrary' -and $r[0] -eq 'C:\Program Files (x86)\Steam')
$vdfOld=@'
"LibraryFolders"
{
	"TimeNextStatsReport"		"1580000000"
	"ContentStatsID"		"-123"
	"1"		"D:\\Games\\Steam"
	"2"		"E:\\SteamLibrary"
}
'@
$r=Get-VdfLibraryPaths $vdfOld
Check 'vdf old' ($r.Count -eq 2 -and $r[0] -eq 'D:\Games\Steam' -and $r[1] -eq 'E:\SteamLibrary')
Check 'acf' ((Get-AcfInstallDir "`"AppState`"`n{`n`t`"appid`"`t`t`"383120`"`n`t`"installdir`"`t`t`"Empyrion - Galactic Survival`"`n}") -eq 'Empyrion - Galactic Survival')
# Mock Steam tree
$m=(Get-TestDir 'armock'); if(Test-Path $m){Remove-Item $m -Recurse -Force}
$steam="$m/Steam"; $lib2="$m/Lib2"
New-Item -ItemType Directory -Force "$steam/steamapps","$lib2/steamapps/common/Empyrion - Galactic Survival/Content/Scenarios","$lib2/steamapps/common/Empyrion - Dedicated Server/Content/Scenarios" | Out-Null
"x" | Set-Content "$lib2/steamapps/common/Empyrion - Galactic Survival/EmpyrionLauncher.exe"
"`"AppState`"{ `"installdir`" `"Empyrion - Galactic Survival`" }" | Set-Content "$lib2/steamapps/appmanifest_383120.acf"
"`"libraryfolders`"{ `"0`" { `"path`" `"$steam`" } `"1`" { `"path`" `"$lib2`" } }" | Set-Content "$steam/steamapps/libraryfolders.vdf"
$libs=Get-SteamLibraries @($steam)
Check 'libraries' ($libs.Count -eq 2)
$inst=Find-EmpyrionInstalls $libs
Check 'find installs' ($inst.Count -eq 2 -and $inst[0].Kind -eq 'Game' -and $inst[1].Kind -eq 'Dedicated Server')
$emp=$inst[0].Path
New-Item -ItemType Directory -Force "$emp/Saves/Games/MySave/SharedData","$emp/Saves/Games/Other","$emp/Saves/Cache/Srv_1.2.3.4_99/SharedData","$emp/Saves/Cache/_SharedDataZips" | Out-Null
$sv=Get-SaveFolders $emp
Check 'save folders' ($sv.Count -eq 3 -and -not ($sv | ? Name -eq '_SharedDataZips'))
Check 'hasShared' (($sv | ? Name -eq 'MySave').HasShared -and -not ($sv | ? Name -eq 'Other').HasShared)
# prefix detection with real listing
$names = Get-Content (Join-Path $Fix 'sample-listing.txt')
Check 'prefix real' ((Get-ScenarioPrefix $names) -eq 'Ascension-Reborn/')
Check 'prefix flat' ((Get-ScenarioPrefix @('Content/','Content/Configuration/Config.ecf','SharedData/Content/Bundles/x')) -eq '')
Check 'prefix nested' ((Get-ScenarioPrefix @('Scenarios/','Scenarios/Ascension-Reborn/Content/Configuration/a.ecf','Scenarios/Ascension-Reborn/Playfields/x')) -eq 'Scenarios/Ascension-Reborn/')
Check 'prefix renamed top' ((Get-ScenarioPrefix @('AR v2/x.txt','AR v2/Playfields/a')) -eq 'AR v2/')
# Drive confirm page parse
$html='<form id="download-form" action="https://drive.usercontent.google.com/download" method="get"><input type="hidden" name="id" value="abc"><input type="hidden" name="export" value="download"><input type="hidden" name="confirm" value="t"><input type="hidden" name="uuid" value="1234-5678"></form>'
Check 'confirm parse' ((Get-DriveConfirmUrl $html 'abc') -eq 'https://drive.usercontent.google.com/download?id=abc&export=download&confirm=t&uuid=1234-5678')
# Disk space
$p=Test-DiskSpace @(@{Path=$TmpRoot;Bytes=1MB})
Check 'space ok' ($p.Count -eq 0)
$p=Test-DiskSpace @(@{Path=(Join-Path $TmpRoot 'nonexist/deeper');Bytes=900TB})
Check 'space fail' ($p.Count -eq 1)
"`n$pass passed, $fail failed"
if ($script:fail) { exit 1 }
