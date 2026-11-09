# Builds dist/ScenarioInstaller.exe (a small .NET Framework 4.8 launcher with Install-Scenario.ps1 embedded)
# and copies the release files into dist/.
# Needs PowerShell 7 (pwsh), which ships the Roslyn C# compiler. Works on Windows, Linux and macOS.
# The .NET Framework 4.8 reference assemblies are downloaded once from nuget.org into .build/refs
# (or pass -RefsDir to a folder that contains mscorlib.dll, System.dll, System.Core.dll, System.Windows.Forms.dll).
#   pwsh -NoProfile -File src/launcher/build.ps1
param([string]$RefsDir, [string]$OutDir)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$here = $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
[void][IO.Directory]::CreateDirectory($OutDir)

if (-not $RefsDir) {
    $RefsDir = Join-Path $root '.build/refs/build/.NETFramework/v4.8'
    if (-not (Test-Path (Join-Path $RefsDir 'mscorlib.dll'))) {
        $pkg = Join-Path $root '.build/refs.nupkg'
        [void][IO.Directory]::CreateDirectory((Split-Path $pkg))
        Write-Host 'Downloading Microsoft.NETFramework.ReferenceAssemblies.net48 1.0.3 from nuget.org...'
        Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.NETFramework.ReferenceAssemblies.net48/1.0.3' -OutFile $pkg
        Expand-Archive -LiteralPath $pkg -DestinationPath (Join-Path $root '.build/refs') -Force
    }
}

# release copy of the script: UTF-8 with BOM + CRLF (what Windows PowerShell 5.1 likes best); the source must be ASCII
$srcText = [IO.File]::ReadAllText((Join-Path $root 'src/Install-Scenario.ps1'))
if ($srcText -match '[^\x00-\x7F]') { throw 'src/Install-Scenario.ps1 must be plain ASCII.' }
$crlf = ($srcText -replace "`r`n", "`n") -replace "`n", "`r`n"
$ps1Out = Join-Path $OutDir 'Install-Scenario.ps1'
[IO.File]::WriteAllText($ps1Out, $crlf, (New-Object Text.UTF8Encoding($true)))
$tok = $null; $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($ps1Out, [ref]$tok, [ref]$errs)
if ($errs.Count) { throw "Install-Scenario.ps1 has parse errors: $($errs[0].Message)" }

$code = [IO.File]::ReadAllText((Join-Path $here 'Launcher.cs'))
$tree = [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($code)
$mr = @('mscorlib.dll', 'System.dll', 'System.Core.dll', 'System.Windows.Forms.dll') | ForEach-Object { [Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $RefsDir $_)) }
$opts = New-Object Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions([Microsoft.CodeAnalysis.OutputKind]::WindowsApplication)
$opts = $opts.WithPlatform([Microsoft.CodeAnalysis.Platform]::AnyCpu).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release).WithDeterministic($true)
$comp = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('ScenarioInstaller', [Microsoft.CodeAnalysis.SyntaxTree[]]@($tree), [Microsoft.CodeAnalysis.MetadataReference[]]$mr, $opts)
$ico = [IO.File]::OpenRead((Join-Path $here 'app.ico')); $man = [IO.File]::OpenRead((Join-Path $here 'app.manifest'))
$w32 = $comp.CreateDefaultWin32Resources($true, $false, $man, $ico)
$ps1Bytes = [IO.File]::ReadAllBytes($ps1Out)
$res = New-Object Microsoft.CodeAnalysis.ResourceDescription('Install-Scenario.ps1', [Func[IO.Stream]] { New-Object IO.MemoryStream(, $ps1Bytes) }.GetNewClosure(), $true)
$exe = Join-Path $OutDir 'ScenarioInstaller.exe'
$out = [IO.File]::Create($exe)
try { $r = $comp.Emit($out, $null, $null, $w32, [Microsoft.CodeAnalysis.ResourceDescription[]]@($res)) } finally { $out.Close(); $ico.Close(); $man.Close() }
if (-not $r.Success) { $r.Diagnostics | ForEach-Object { Write-Host $_.ToString() }; Remove-Item $exe; throw 'Build failed.' }

Copy-Item (Join-Path $root 'Install-Scenario.bat') $OutDir -Force
Copy-Item (Join-Path $root 'installer.example.json') $OutDir -Force
$rt = ([IO.File]::ReadAllText((Join-Path $root 'docs/README.txt')) -replace "`r`n", "`n") -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $OutDir 'README.txt'), $rt)
Write-Host "Built $exe"
Get-ChildItem $OutDir -File | ForEach-Object { '{0,-28} {1,9}  {2}' -f $_.Name, $_.Length, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
