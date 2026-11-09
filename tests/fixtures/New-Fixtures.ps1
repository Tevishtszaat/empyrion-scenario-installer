# Creates the large test fixture (Big Pack.zip, ~6 MB, stored) on first use so it isn't kept in git.
$big = Join-Path $PSScriptRoot 'Big Pack.zip'
if (-not (Test-Path -LiteralPath $big)) {
    Add-Type -AssemblyName System.IO.Compression
    $fs = [IO.File]::Create($big)
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        $files = [ordered]@{ 'Big Scenario/Content/Configuration/Config.ecf' = [Text.Encoding]::ASCII.GetBytes('cfg')
                             'Big Scenario/Playfields/Arid/playfield.yaml' = [Text.Encoding]::ASCII.GetBytes('pf')
                             'Big Scenario/Sectors/Sectors.yaml' = [Text.Encoding]::ASCII.GetBytes('sec') }
        foreach ($k in $files.Keys) { $s = $za.CreateEntry($k, [IO.Compression.CompressionLevel]::NoCompression).Open(); $s.Write($files[$k], 0, $files[$k].Length); $s.Dispose() }
        $rnd = New-Object Random 42; $buf = New-Object byte[] (6MB); $rnd.NextBytes($buf)
        $s = $za.CreateEntry('Big Scenario/SharedData/Content/Bundles/big', [IO.Compression.CompressionLevel]::NoCompression).Open(); $s.Write($buf, 0, $buf.Length); $s.Dispose()
        $za.Dispose()
    } finally { $fs.Dispose() }
}
