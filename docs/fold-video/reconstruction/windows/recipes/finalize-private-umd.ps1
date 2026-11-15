param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $Root 'stage\common-private-umd.ps1')
$Root=Assert-PrivateRoot $Root;Assert-Packet $Root;Assert-PrivateNeptune $Root;Assert-LeasedOriginals $Root
$original='C:\mesa\src';$src=Join-Path $Root 'src'
$before=Get-Content (Join-Path $Root 'original-source-footprint.json') -Raw|ConvertFrom-Json
$after=@(Get-ChildItem $original -File -Recurse -Force|Where-Object{$_.FullName-notmatch '\\\.git\\'}|ForEach-Object{[PSCustomObject]@{relative=$_.FullName.Substring($original.Length+1);bytes=$_.Length;mtime=$_.LastWriteTimeUtc.Ticks}})
if(@(Compare-Object $before $after -Property relative,bytes,mtime).Count){throw 'Original source footprint changed'}
$hashes=Get-Content (Join-Path $Root 'original-neptune-hashes.json') -Raw|ConvertFrom-Json
foreach($f in $hashes){if((Get-FileHash $f.path -Algorithm SHA256).Hash-ne$f.sha256){throw ('Original Neptune source changed '+$f.path)}}
$protect=Get-Content (Join-Path $Root 'protected-before.json') -Raw|ConvertFrom-Json
foreach($f in $protect.files){if((Get-FileHash $f.path -Algorithm SHA256).Hash-ne$f.sha256){throw ('Protected output changed '+$f.path)}}
foreach($dir in $protect.roots){if(Test-Path $dir){$now=@(Get-ChildItem $dir -Recurse -File|Where-Object{$_.Extension-notin@('.pfx','.p12','.pem','.key','.cer')}|ForEach-Object{$_.FullName});$old=@($protect.files|Where-Object{$_.path.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase)}|ForEach-Object{$_.path});if(@(Compare-Object $old $now).Count){throw ('Protected file set changed '+$dir)}}}
[ordered]@{status='all_originals_unchanged';sourceFootprintFiles=$before.Count;neptuneSourceHashes=$hashes.Count;protectedOutputHashes=$protect.files.Count;protectedFileSetsUnchanged=$true;finished=(Get-Date -Format o)}|ConvertTo-Json|Set-Content (Join-Path $Root 'protected-after.json') -Encoding UTF8
$post=Get-Content -LiteralPath (Join-Path $Root 'stage\complete-postimage.json') -Raw|ConvertFrom-Json
foreach($entry in $post.files){$path=Join-Path $src $entry.path;if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-ne$entry.proposedSha256-or(Get-Item -LiteralPath $path).Length-ne[long]$entry.proposedBytes){throw ('Final C15 combined source mismatch '+$entry.path)}}
$ret=Join-Path $Root 'retrieval';if(Test-Path $ret){throw 'Retrieval already exists'};New-Item -ItemType Directory $ret|Out-Null
foreach($dir in @('out','evidence')){Copy-Item (Join-Path $Root $dir) $ret -Recurse}
Copy-Item -LiteralPath (Join-Path $Root 'stage') -Destination (Join-Path $ret 'reviewed-packet') -Recurse
foreach($f in Get-ChildItem $Root -File|Where-Object{$_.Extension-notin @('.tar','.gz')}){Copy-Item $f.FullName $ret}
$sourceDest=Join-Path $ret 'source';New-Item -ItemType Directory $sourceDest|Out-Null
Copy-Item (Join-Path $src 'src\virtio\neptune') $sourceDest -Recurse
Copy-Item (Join-Path $src 'src\virtio\virtio-gpu\wddm_hw.h') $sourceDest
foreach($a in @('arm64','arm64ec')){foreach($meta in @('build.ninja','compile_commands.json')){Copy-Item -LiteralPath (Join-Path $Root ('build-'+$a+'\'+$meta)) -Destination (Join-Path $ret ($a+'-'+$meta))};Copy-Item (Join-Path $Root ('build-'+$a+'\meson-logs')) (Join-Path $ret ('meson-logs-'+$a)) -Recurse}
$files=@(Get-ChildItem $ret -File -Recurse|ForEach-Object{if($_.Extension-in@('.pfx','.p12','.key','.pem')){throw 'Forbidden file in retrieval'};[ordered]@{relative=$_.FullName.Substring($ret.Length+1);bytes=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
[ordered]@{status='built_not_deployed';files=$files;protectedOriginalsUnchanged=$true}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $ret 'retrieval-manifest.json') -Encoding UTF8
& tar.exe -czf (Join-Path $Root 'windows-artifacts.tar.gz') -C $ret .
if($LASTEXITCODE){throw 'Retrieval archive failed'}
[ordered]@{path=(Join-Path $Root 'windows-artifacts.tar.gz');bytes=(Get-Item (Join-Path $Root 'windows-artifacts.tar.gz')).Length;sha256=(Get-FileHash (Join-Path $Root 'windows-artifacts.tar.gz') -Algorithm SHA256).Hash;files=$files.Count}|ConvertTo-Json
