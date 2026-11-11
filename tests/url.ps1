. "$PSScriptRoot/_common.ps1"
$id='1jtetatjWTRW-JWj1YJkHJP77fXZLd-vh'; $dd="https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t"
Write-Host '== URL normalization'
foreach ($u in @("https://drive.google.com/file/d/$id/view?usp=drive_link","https://drive.google.com/file/d/$id/view","https://drive.google.com/file/d/$id","https://drive.google.com/open?id=$id","https://drive.google.com/uc?id=$id&export=download","https://docs.google.com/uc?export=download&id=$id","https://drive.usercontent.google.com/download?id=$id&export=download","https://drive.google.com/u/0/uc?id=$id","  https://drive.google.com/file/d/$id/view  ", '')) {
    $r=Resolve-DownloadUrl $u; Check ("Drive default: '$u'") ($r.Kind -eq 'Drive' -and $r.Url -eq $dd -and $r.IsDefault -and $r.FileHint -eq 'Ascension-Reborn.zip')
}
$r=Resolve-DownloadUrl 'https://drive.google.com/file/d/0B_OtherFileId123456/view?usp=sharing&resourcekey=0-abc'
Check 'Drive other id + resourcekey' ($r.Kind -eq 'Drive' -and -not $r.IsDefault -and $r.Url -eq 'https://drive.usercontent.google.com/download?id=0B_OtherFileId123456&export=download&confirm=t&resourcekey=0-abc' -and $r.FileHint -eq 'Drive_0B_OtherFileId123456.zip')
foreach ($u in @('https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp?usp=sharing','https://drive.google.com/drive/u/0/folders/1AbCdEfGhIjKlMnOp','https://drive.google.com/embeddedfolderview?id=1AbCdEfGhIjKlMnOp')) {
    $r=Resolve-DownloadUrl $u; Check "Drive folder: $u" ($r.Kind -eq 'DriveFolder' -and $r.Message -like '*FOLDER link*')
}
Check 'Drive link without id' ((Resolve-DownloadUrl 'https://drive.google.com/drive/my-drive').Kind -eq 'Invalid')
$r=Resolve-DownloadUrl 'https://www.dropbox.com/s/abc123/My%20Scen.zip?dl=0'
Check 'Dropbox dl=0 -> dl=1' ($r.Kind -eq 'Direct' -and $r.Url -eq 'https://www.dropbox.com/s/abc123/My%20Scen.zip?dl=1' -and $r.FileHint -eq 'My Scen.zip' -and $r.Label -like 'Dropbox*')
$r=Resolve-DownloadUrl 'https://www.dropbox.com/scl/fi/xyz/Pack.zip?rlkey=k1&st=s2&dl=0'
Check 'Dropbox scl keeps rlkey' ($r.Url -eq 'https://www.dropbox.com/scl/fi/xyz/Pack.zip?rlkey=k1&st=s2&dl=1')
Check 'Dropbox no query' ((Resolve-DownloadUrl 'https://dropbox.com/s/a/b.zip').Url -eq 'https://dropbox.com/s/a/b.zip?dl=1')
Check 'Dropbox raw=1 replaced' ((Resolve-DownloadUrl 'https://www.dropbox.com/s/a/b.zip?raw=1').Url -eq 'https://www.dropbox.com/s/a/b.zip?dl=1')
$r=Resolve-DownloadUrl 'https://1drv.ms/u/s!AbCdEf123'
Check '1drv.ms -> OneDrive shares API' ($r.Kind -eq 'Direct' -and $r.Url -like 'https://api.onedrive.com/v1.0/shares/u!*/root/content' -and $r.Url -notmatch '[=+]' -and $r.Label -like 'OneDrive*')
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('https://1drv.ms/u/s!AbCdEf123')).TrimEnd('=').Replace('/','_').Replace('+','-')
Check '1drv.ms encoding' ($r.Url -eq "https://api.onedrive.com/v1.0/shares/u!$b64/root/content")
Check 'onedrive redir -> download' ((Resolve-DownloadUrl 'https://onedrive.live.com/redir?resid=ABC!123&authkey=!xyz').Url -eq 'https://onedrive.live.com/download?resid=ABC!123&authkey=!xyz')
Check 'onedrive embed -> download' ((Resolve-DownloadUrl 'https://onedrive.live.com/embed?cid=1&resid=2').Url -eq 'https://onedrive.live.com/download?cid=1&resid=2')
Check 'sharepoint download=1' ((Resolve-DownloadUrl 'https://contoso-my.sharepoint.com/:u:/g/personal/x/EAbc?e=Q1').Url -eq 'https://contoso-my.sharepoint.com/:u:/g/personal/x/EAbc?e=Q1&download=1')
foreach ($u in @('https://mega.nz/file/AbC#key','https://mega.co.nz/#!abc!key','https://www.mega.nz/folder/x')) { Check "MEGA: $u" ((Resolve-DownloadUrl $u).Kind -eq 'Mega' -and (Resolve-DownloadUrl $u).Message -like "*I already have the zip*") }
foreach ($u in @('ftp://example.com/a.zip','file:///C:/a.zip','C:\Downloads\a.zip','javascript:alert(1)','not a link','\\server\share\a.zip','example.com/a.zip')) { Check "reject: $u" ((Resolve-DownloadUrl $u).Kind -eq 'Invalid') }
$r=Resolve-DownloadUrl 'https://example.com/files/Cool%20Pack.zip?token=SECRET123'
Check 'direct: file hint from path, host only' ($r.Kind -eq 'Direct' -and $r.FileHint -eq 'Cool Pack.zip' -and $r.Host -eq 'example.com')
Check 'direct: no .zip -> hashed name' ((Resolve-DownloadUrl 'https://example.com/get?f=1').FileHint -match '^Download_[0-9a-f]{8}\.zip$')
Check 'direct: unsafe name -> hashed' ((Resolve-DownloadUrl 'https://example.com/..%2F..%2Fevil.zip').FileHint -match '^Download_')
Check 'http allowed' ((Resolve-DownloadUrl 'http://example.com/a.zip').Kind -eq 'Direct')
Check 'Content-Disposition parse' ((Get-ContentDispositionName 'attachment; filename="My Pack.zip"') -eq 'My Pack.zip' -and (Get-ContentDispositionName "attachment; filename*=UTF-8''My%20Pack%202.zip") -eq 'My Pack 2.zip' -and (Get-ContentDispositionName 'attachment; filename="..\..\x.zip"') -eq 'x.zip')

Write-Host '== downloads against the mock server'
$S='http://127.0.0.1:8765'; $T=$Fix; $D=(Get-TestDir 'armock4'); if (Test-Path $D) { Remove-Item $D -Recurse -Force }; New-Item -ItemType Directory $D | Out-Null
$big = [IO.File]::ReadAllBytes("$T/Big Pack.zip")
function SameAsBig($f) { $x=[IO.File]::ReadAllBytes($f); ($x.Length -eq $big.Length) -and ([Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData($x)) -eq [Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData($big))) }
$ri = Get-RemoteInfo "$S/range/Big%20Pack.zip"
Check 'remote info with Range: size + name' ($ri.Size -eq $big.Length -and $ri.Ranges -and $ri.FileName -eq 'Big Pack.zip')
$ri2 = Get-RemoteInfo "$S/norange/Big%20Pack.zip"
Check 'remote info without Range: size from Content-Length' ($ri2.Size -eq $big.Length -and -not $ri2.Ranges)
# Range server: stop partway, resume
$u="$S/range/Big%20Pack.zip"; $k=Get-UrlHash $u; $dst="$D/a.zip"
try { Invoke-ResumableDownload $u $dst $big.Length 3 (2MB) 0 'Direct' $k } catch [System.OperationCanceledException] {}
$p1=(Get-Item "$dst.part").Length
Invoke-ResumableDownload $u $dst $big.Length 3 0 0 'Direct' $k
Check "range: resumed from $p1 bytes, file identical" ($p1 -ge 2MB -and $p1 -lt $big.Length -and (SameAsBig $dst) -and ((Get-Content $script:LogFile -Tail 5) -join ' ') -match 'Resuming download at')
Check 'range: .src written, .part.src cleared' ((Test-Path "$dst.src") -and -not (Test-Path "$dst.part.src") -and ([IO.File]::ReadAllText("$dst.src")) -eq $k)
# Drive-style bounded chunks against the Range server
$dst="$D/chunks.zip"; Invoke-ResumableDownload $u $dst $big.Length 3 0 (1MB) 'Direct' $k
Check 'bounded 1 MB chunks: identical' (SameAsBig $dst)
# no-Range server: resume falls back to a full download
$u2="$S/norange/Big%20Pack.zip"; $k2=Get-UrlHash $u2; $dst="$D/b.zip"
try { Invoke-ResumableDownload $u2 $dst $big.Length 3 (2MB) 0 'Direct' $k2 } catch [System.OperationCanceledException] {}
Invoke-ResumableDownload $u2 $dst $big.Length 3 0 0 'Direct' $k2
Check 'no Range: restarted, full download identical' ((SameAsBig $dst) -and ((Get-Content $script:LogFile -Tail 6) -join ' ') -match 'ignored the byte range')
# unknown length (connection-close body)
$dst="$D/c.zip"; Invoke-ResumableDownload "$S/nolen/Big%20Pack.zip" $dst -1 3 0 0 'Direct' (Get-UrlHash 'x')
Check 'no Content-Length: streamed download identical' (SameAsBig $dst)
# HTML rejection
$err=$null; try { Invoke-ResumableDownload "$S/html" "$D/h.zip" -1 3 0 0 'Direct' 'k' } catch { $err=$_.Exception.Message }
Check 'text/html rejected without retries' ($err -like '*web page*not a zip*' -and -not (Test-Path "$D/h.zip"))
$err=$null; try { Invoke-ResumableDownload "$S/fakezip" "$D/f.zip" -1 3 0 0 'Direct' 'k' } catch { $err=$_.Exception.Message }
Check 'HTML served as octet-stream rejected (PK sniff)' ($err -like '*not a zip*' -and -not (Test-Path "$D/f.zip") -and -not (Test-Path "$D/f.zip.part"))
Check 'Test-ZipFile: zip yes, html no' ((Test-ZipFile "$T/Big Pack.zip") -and -not (Test-ZipFile "$PSScriptRoot/mockserver.py"))
# URL change resets the partial download
$dst="$D/u.zip"; $uA="$S/range/Big%20Pack.zip"; $uB="$S/range/Cool%20Pack.zip"
try { Invoke-ResumableDownload $uA $dst $big.Length 3 (2MB) 0 'Direct' (Get-UrlHash $uA) } catch [System.OperationCanceledException] {}
$cool=[IO.File]::ReadAllBytes("$T/Cool Pack.zip")
Invoke-ResumableDownload $uB $dst $cool.Length 3 0 0 'Direct' (Get-UrlHash $uB)
$got=[IO.File]::ReadAllBytes($dst)
Check 'changed link: partial discarded, new file correct' ($got.Length -eq $cool.Length -and [Convert]::ToBase64String($got) -eq [Convert]::ToBase64String($cool) -and ((Get-Content $script:LogFile -Tail 6) -join ' ') -match 'different from the one the partial download came from')
# partial with no .src (older version) and a link -> reset too
$dst="$D/v.zip"; [IO.File]::WriteAllBytes("$dst.part", [byte[]](1..100)); Invoke-ResumableDownload $uB $dst $cool.Length 3 0 0 'Direct' (Get-UrlHash $uB)
Check 'partial without link record: reset' (([IO.File]::ReadAllBytes($dst)).Length -eq $cool.Length -and (Test-ZipFile $dst))

Write-Host '== full installs from links'
$M=(Get-TestDir 'armock5'); if (Test-Path $M) { Remove-Item $M -Recurse -Force }
$E="$M/Empyrion - Galactic Survival"; $SC="$E/Content/Scenarios"; New-Item -ItemType Directory -Force "$SC/Ascension-Reborn/Content","$M/dl" | Out-Null; 'x' | Set-Content "$E/EmpyrionLauncher.exe"; 'keep' | Set-Content "$SC/Ascension-Reborn/Content/k.txt"
function Opt([hashtable]$x) { $o=@{ EmpyrionPath=$E; ArchivePath=$null; DownloadFolder="$M/dl"; SaveFolders=@(); OverwriteInPlace=$false; DeleteArchiveAfter=$false; SkipSpaceCheck=$false; TestMode=$false; TestFolder=$null; DownloadUrl=$null }; foreach($k in $x.Keys){$o[$k]=$x[$k]}; $o }
$secret="$S/range/Big%20Pack.zip?token=SECRET_TOKEN_123"
Invoke-Install (Opt @{ DownloadUrl=$secret })
$lg=(Get-Content $script:LogFile -Tail 30) -join "`n"
Check 'link install -> Scenarios/Big Scenario' ((Test-Path "$SC/Big Scenario/Sectors/Sectors.yaml") -and $lg -match "Scenario name: 'Big Scenario'" -and (Test-Path "$SC/Ascension-Reborn/Content/k.txt"))
Check 'log has host only, no query string' ($lg -match 'host: 127\.0\.0\.1' -and ((Get-Content $script:LogFile -Raw) -notmatch 'SECRET_TOKEN') -and $lg -notmatch 'Big%20Pack')
Invoke-Install (Opt @{ DownloadUrl=$secret })
Check 'same link again: reuses the complete zip' (((Get-Content $script:LogFile -Tail 30) -join ' ') -match 'reusing it')
Invoke-Install (Opt @{ DownloadUrl="$S/norange/Flat%20Pack.zip" })
Check 'flat zip from link -> name from server file name' (Test-Path "$SC/Flat Pack/Content/Configuration/Config.ecf")
$err=$null; try { Invoke-Install (Opt @{ DownloadUrl="$S/html" }) } catch { $err=$_.Exception.Message }
Check 'html link -> clear error, nothing installed' ($err -like '*not a zip*')
foreach ($bad in @('https://mega.nz/file/x#y','ftp://x/y.zip','https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp')) { $err=$null; try { Invoke-Install (Opt @{ DownloadUrl=$bad }) } catch { $err=$_.Exception.Message }; Check "install refuses $bad" ($err -and -not (Test-Path "$M/dl/Download_*")) }
Invoke-Install (Opt @{ DownloadUrl="$S/range/Cool%20Pack.zip"; TestMode=$true; TestFolder="$M/test" })
Check 'link + test mode -> test/Content/Scenarios/Cool Scenario' (Test-Path "$M/test/Content/Scenarios/Cool Scenario/Playfields/Arid/playfield.yaml")
Write-Host "`n$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
