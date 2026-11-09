# Layout math tests for the 1.0.4 GUI (WinForms itself can't run on Linux)
. "$PSScriptRoot/_common.ps1"
$src = $Src

$text = Get-Content $src -Raw
$content = [regex]::Matches($text, 'Add-Ctl \((?:[^()]|\([^()]*\))*\) (\d+) (\d+) (\d+) (\d+)')
$bottomC = [regex]::Matches($text, 'Add-Bottom \((?:[^()]|\([^()]*\))*\) (\d+) (\d+) (\d+) (\d+)')
Check 'found content controls' ($content.Count -ge 25)
Check 'found 4 bottom-bar controls' ($bottomC.Count -eq 4)
$maxR = 0; $maxB = 0
foreach ($m in $content) { $r = [int]$m.Groups[1].Value + [int]$m.Groups[3].Value; $b = [int]$m.Groups[2].Value + [int]$m.Groups[4].Value; if ($r -gt $maxR) { $maxR = $r }; if ($b -gt $maxB) { $maxB = $b } }
$barBottom = 0; foreach ($m in $bottomC) { $b = [int]$m.Groups[2].Value + [int]$m.Groups[4].Value; if ($b -gt $barBottom) { $barBottom = $b }
    Check "bottom control fits 760 wide ($($m.Value.Substring(0,40)))" (([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) -le 760 - 12) }
Check 'bottom bar holds its controls' ($barBottom -le $script:GuiBottomBarH)
Check 'content fits initial 762 client incl. scrollbar' (($maxR + 12 + 17) -le 762)
Check 'no content overlap with log: log is the lowest' ($maxB -eq 642)
Write-Host "content extent ${maxR}x${maxB}; bottom bar $($script:GuiBottomBarH)"

# no two content controls overlap vertically in the same column band (cheap sanity check)
$rects = foreach ($m in $content) { ,@([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value, [int]$m.Groups[4].Value) }
$ov = 0
for ($i = 0; $i -lt $rects.Count; $i++) { for ($j = $i + 1; $j -lt $rects.Count; $j++) {
    $a = $rects[$i]; $c = $rects[$j]
    if ($a[0] -lt $c[0] + $c[2] -and $c[0] -lt $a[0] + $a[2] -and $a[1] -lt $c[1] + $c[3] -and $c[1] -lt $a[1] + $a[3]) { $ov++; Write-Host "overlap: $($a -join ',') / $($c -join ',')" } } }
Check 'no overlapping content controls' ($ov -eq 0)

$rows = @()
foreach ($wa in @(@(1024, 560), @(1280, 680), @(1366, 728), @(1920, 1040), @(1024, 578))) {
    foreach ($scale in @(1.0, 1.25, 1.5)) {
        $ncW = [int](16 * $scale); $ncH = [int](39 * $scale); $capTop = $ncH - [int](8 * $scale)
        $natCW = [int](($maxR + 12 + 17) * $scale); $natCH = [int](($maxB + 12 + $script:GuiBottomBarH) * $scale)
        $b = Get-FormBounds ($natCW + $ncW) ($natCH + $ncH) 0 0 $wa[0] $wa[1] ([int](10 * $scale)) ([int]($script:GuiMinClientW * $scale) + $ncW) ([int]($script:GuiMinClientH * $scale) + $ncH)
        $tag = "$($wa[0])x$($wa[1])@$([int]($scale*100))%"
        $cH = $b.H - $ncH; $barH = [int]($script:GuiBottomBarH * $scale)
        $btnBottom = $b.Y + $capTop + $cH - [int](($script:GuiBottomBarH - 86) * $scale)
        $btnRight = $b.X + [int](8 * $scale) + ($b.W - $ncW) - [int](12 * $scale)
        Check "$tag form inside working area" ($b.X -ge 0 -and $b.Y -ge 0 -and ($b.X + $b.W) -le $wa[0] -and ($b.Y + $b.H) -le $wa[1])
        Check "$tag Install/Close buttons on screen" ($btnBottom -le $wa[1] -and $btnRight -le $wa[0])
        Check "$tag some content visible above the bar" (($cH - $barH) -ge 100)
        Check "$tag minimum size <= size" ($b.MinW -le $b.W -and $b.MinH -le $b.H)
        Check "$tag centred" ([Math]::Abs(($wa[0] - $b.W) / 2 - $b.X) -le 1 -and [Math]::Abs(($wa[1] - $b.H) / 2 - $b.Y) -le 1)
        $rows += '{0,-16} form {1,4}x{2,-4} at {3,3},{4,-3} client-h {5,4} content-view {6,4}/{7,-4} scroll={8}' -f $tag, $b.W, $b.H, $b.X, $b.Y, $cH, ($cH - $barH), [int](($maxB + 12) * $scale), (($cH - $barH) -lt [int](($maxB + 12) * $scale))
    }
}
$rows | ForEach-Object { Write-Host $_ }
# non-zero origin (second monitor / taskbar on top)
$b = Get-FormBounds 776 767 1920 40 1366 728 10 0 0
Check 'offset working area respected' ($b.X -ge 1920 -and $b.Y -ge 40 -and ($b.Y + $b.H) -le 768)
# natural size used when it fits
$b = Get-FormBounds 776 767 0 0 1920 1040 10 600 400
Check 'natural size when it fits' ($b.W -eq 776 -and $b.H -eq 767 -and $b.MinW -eq 600)
Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
