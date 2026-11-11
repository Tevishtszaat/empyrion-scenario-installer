# Shared setup for the test suites: dot-source this first ( . "$PSScriptRoot/_common.ps1" ).
# Loads the installer's functions without running it, and defines paths + Check.
$env:AR_INSTALLER_NO_MAIN = '1'
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Src = Join-Path $script:RepoRoot 'src/Install-Scenario.ps1'
$script:Fix = Join-Path $PSScriptRoot 'fixtures'
$script:TmpRoot = Join-Path ([IO.Path]::GetTempPath()) 'scenario-installer-tests'
[void][IO.Directory]::CreateDirectory($script:TmpRoot)
. (Join-Path $script:Fix 'New-Fixtures.ps1')
. $script:Src
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Check($name, $cond) { if ($cond) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name" } }
function Get-TestDir([string]$name) { return (Join-Path $script:TmpRoot $name) }
