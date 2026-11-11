# Runs every test suite in its own pwsh process and prints a summary. Exit code 1 if anything failed.
#   pwsh -NoProfile -File tests/run-all.ps1
# The url suite needs python3 (for the small local HTTP server in mockserver.py, port 8765).
# Tested with PowerShell 7.4 on Linux. lock.ps1 uses chmod, so run it on Linux/macOS.
$ErrorActionPreference = 'Stop'
$suites = @('unit', 'name', 'lock', 'url', 'config', 'gui')
. (Join-Path $PSScriptRoot 'fixtures/New-Fixtures.ps1')
$pw = (Get-Process -Id $PID).Path
$py = @('python3', 'python') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
$server = $null
if ($py) {
    $server = Start-Process $py -ArgumentList @((Join-Path $PSScriptRoot 'mockserver.py'), '8765', (Join-Path $PSScriptRoot 'fixtures')) -PassThru -NoNewWindow
    $up = $false
    for ($i = 0; $i -lt 50 -and -not $up; $i++) { Start-Sleep -Milliseconds 100; try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 8765); $c.Close(); $up = $true } catch {} }
    if (-not $up) { Write-Warning 'mock server did not start' }
} else { Write-Warning 'python3 not found: skipping the url suite'; $suites = $suites | Where-Object { $_ -ne 'url' } }
$rows = @(); $bad = 0
try {
    foreach ($s in $suites) {
        $out = & $pw -NoProfile -File (Join-Path $PSScriptRoot "$s.ps1") 2>&1 | Out-String
        $code = $LASTEXITCODE
        $m = [regex]::Matches($out, '(\d+) passed, (\d+) failed')
        $sum = if ($m.Count) { $m[$m.Count - 1].Value } else { 'no summary' }
        $fails = @($out -split "`n" | Where-Object { $_ -match '^FAIL' })
        if ($code -ne 0 -or $fails.Count -or -not $m.Count) { $bad++; $fails | ForEach-Object { Write-Host "  [$s] $_" }; if (-not $m.Count) { Write-Host $out } }
        $rows += '{0,-8} {1}  (exit {2})' -f $s, $sum, $code
    }
} finally { if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
$rows | ForEach-Object { Write-Host $_ }
if ($bad) { Write-Host "$bad suite(s) FAILED"; exit 1 } else { Write-Host 'ALL SUITES PASSED' }
