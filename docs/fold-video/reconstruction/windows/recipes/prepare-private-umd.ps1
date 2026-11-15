param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $Root 'stage\common-private-umd.ps1')
$Root=Assert-PrivateRoot $Root;Assert-Packet $Root;Assert-LeasedOriginals $Root
$prior=Get-Content -LiteralPath (Join-Path $Root 'actual-prior-output-preflight.json') -Raw|ConvertFrom-Json
if($prior.status-ne'actual_C13_C14_C15_R5_C18_C19_C20_C38_C42_C43_C44_C45_F91_thirty_seven_artifacts_verified'-or$prior.root-ne$Root-or$prior.packetSha256-ne(Get-FileHash -LiteralPath (Join-Path $Root 'stage\packet-manifest.json') -Algorithm SHA256).Hash){throw 'Mandatory exact original C13/C14/C15/R5/C18/C19/C20/C38/C42/C43/C44/F91 artifact preflight proof missing'}
$original='C:\mesa\src';$src=Join-Path $Root 'src'
foreach($name in @('src','out','evidence','build-arm64','build-arm64ec','prefix-arm64','prefix-arm64ec','prepare-result.json','original-source-footprint.json','original-neptune-hashes.json','protected-before.json','source-approved.json','private-neptune-approved.json','arm64-cross.ini','arm64ec-cross.ini','build-private-umd.ps1','retrieval','windows-artifacts.tar.gz')){if(Test-Path -LiteralPath (Join-Path $Root $name)){throw ('Fresh-only owned path exists '+$name)}}
$changes=Get-Content (Join-Path $Root 'stage\changes.json') -Raw|ConvertFrom-Json
$allowedReplacements=@(
 'src/virtio/neptune/neptune-protocol/npt_protocol_transport.h',
 'src/virtio/neptune/npt_com.c',
 'src/virtio/neptune/npt_common.h',
 'src/virtio/neptune/npt_device.c',
 'src/virtio/neptune/npt_device.h',
 'src/virtio/neptune/npt_entry_d3d11.c',
 'src/virtio/neptune/npt_event.c',
 'src/virtio/neptune/npt_event.h',
 'src/virtio/neptune/npt_overrides.h',
 'src/virtio/neptune/npt_overrides_d3d11_context.c',
 'src/virtio/neptune/npt_overrides_d3d11_device.c',
 'src/virtio/neptune/npt_renderer.h',
 'src/virtio/neptune/npt_renderer_virtgpu_win32.c',
 'src/virtio/neptune/npt_resource.c',
 'src/virtio/neptune/npt_ring.c',
 'src/virtio/neptune/npt_ring.h',
 'src/virtio/neptune/triton/meson.build',
 'src/virtio/neptune/triton/triton.h',
 'src/virtio/neptune/triton/tritonDDI.c',
 'src/virtio/neptune/triton/tritonDxgi.c',
 'src/virtio/neptune/triton/tritonKm.c',
 'src/virtio/neptune/triton/tritonKm.h',
 'src/virtio/neptune/triton/tritonQuery.c',
 'src/virtio/neptune/triton/tritonResource.c',
 'src/virtio/neptune/triton/tritonState.c',
 'src/virtio/neptune/triton/tritonVideo.c',
 'src/virtio/neptune/triton/tritonView.c'
)
$allowedAdds=@(
 'src/virtio/neptune/npt_publisher_batch.h',
 'src/virtio/neptune/npt_runtime_stream.h',
 'src/virtio/neptune/triton/tritonRuntimeWrites.h'
)
if($changes.Count-ne30){throw 'Exact C46 27 REPLACE plus three ADD changes required'}
$seen=@{};$addCount=0;$replaceCount=0
foreach($f in $changes){
 if($f.path-match'(^[\\/]|:|(^|[\\/])\.\.?([\\/]|$))'-or$seen.ContainsKey($f.path)){throw 'Unsafe or duplicate changed-source path'}
 $seen[$f.path]=$true
 if($f.proposedSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or ($f.proposedBytes -isnot [int] -and $f.proposedBytes -isnot [long]) -or [long]$f.proposedBytes -le 0){throw ('Missing frozen source bytes/hash '+$f.path)}
 if($f.operation-ceq'ADD'){
  if($allowedAdds -cnotcontains $f.path -or $f.baselineAbsent -isnot [bool] -or -not $f.baselineAbsent -or $f.originalInventoryMember -isnot [bool] -or $f.originalInventoryMember){throw 'Only explicit absent publisher/runtime/write-feed headers ADD allowed'}
  if($f.PSObject.Properties.Name-contains'baselineSha256'){throw 'ADD must not invent a baseline hash, including null'}
  if([long]$f.proposedBytes-gt65536){throw 'Header ADD exceeds bounded64KiB'}
  if(Test-Path -LiteralPath (Join-Path $original $f.path)){throw 'ADD header already exists in original C8 tree'}
  $addCount++
 }elseif($f.operation-ceq'REPLACE'){
  if($allowedReplacements-cnotcontains$f.path-or$f.baselineSha256-notmatch'^[A-Fa-f0-9]{64}$'){throw 'Unreviewed replacement path/baseline'}
  if((Get-FileHash (Join-Path $original $f.path) -Algorithm SHA256).Hash-ne$f.baselineSha256){throw ('Original source lease failed '+$f.path)}
  $replaceCount++
 }else{throw 'Only explicit REPLACE or ADD operations allowed'}
}
if($addCount-ne3-or$replaceCount-ne27){throw 'Exact C15 replacement/add counts required'}
function Footprint([string]$Dir){@(Get-ChildItem -LiteralPath $Dir -File -Recurse -Force|Where-Object{$_.FullName-notmatch '\\\.git\\'}|ForEach-Object{[ordered]@{relative=$_.FullName.Substring($Dir.Length+1);bytes=$_.Length;mtime=$_.LastWriteTimeUtc.Ticks}})}
$foot=Footprint $original;$foot|ConvertTo-Json -Depth 4|Set-Content (Join-Path $Root 'original-source-footprint.json') -Encoding UTF8
$neptune=Join-Path $original 'src\virtio\neptune'
$sourceHashes=@(Get-ChildItem $neptune -File -Recurse|Where-Object{$_.Extension-notin@('.pfx','.p12','.pem','.key','.cer','.pyc')}|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash;bytes=$_.Length}})
if($sourceHashes.Count-ne440){throw 'Original C8 Neptune inventory must contain exactly440 files'}
$sourceHashes|ConvertTo-Json -Depth 4|Set-Content (Join-Path $Root 'original-neptune-hashes.json') -Encoding UTF8
$protectedRoots=@('C:\codex-woa-umd\d3d11-native-dma-gate-r1\out','C:\codex-kmd-read-lease\readlease-20261113-230216-r3\artifact','C:\codex-woa-umd\gpu-gate-proof-candidate8-20261113-163658\out','C:\pkg3d','C:\codex-kmd-trace\trace-20261113-182538\artifact','C:\codex-woa-umd\native-job-gpu-retire-c12-r3\out','C:\codex-kmd-native-job\nativejob-20261114-014532-r2\artifact','C:\codex-woa-umd\native-job-publisher-c13-r1\out','C:\codex-kmd-native-job\c13-colorkey-trace-r1\artifact','C:\codex-woa-umd\native-job-publisher-c14-r1\out','C:\codex-woa-umd\runtime-stream-c15-r2\out','C:\codex-woa-umd\runtime-stream-c15-r3\out','C:\codex-woa-umd\runtime-submit-diag-c18-r1\out','C:\codex-woa-umd\present-batch-c19-r1\out','C:\codex-woa-umd\resource-opened-init-c20-r1\out','C:\codex-woa-umd\resource-opened-init-c20-r1\src\src\virtio\neptune','C:\codex-woa-umd\video-cpu-setters-c38-r1\out','C:\codex-woa-umd\video-cpu-setters-c38-r1\src\src\virtio\neptune','C:\codex-woa-umd\qualified-present-batch-c42-r1\out','C:\codex-woa-umd\qualified-present-batch-c42-r1\src\src\virtio\neptune','C:\codex-woa-umd\qualified-publisher-flush-c43-r1\out','C:\codex-woa-umd\qualified-publisher-flush-c43-r1\src\src\virtio\neptune','C:\codex-woa-umd\flush-scope-log-c44-r1\out','C:\codex-woa-umd\flush-scope-log-c44-r1\src\src\virtio\neptune','C:\codex-woa-umd\unless-no-commands-flush-c45-r1\out','C:\codex-woa-umd\unless-no-commands-flush-c45-r1\src\src\virtio\neptune')
$protected=@();foreach($d in $protectedRoots){if(Test-Path $d){$protected+=@(Get-ChildItem $d -Recurse -File|Where-Object{$_.Extension-notin@('.pfx','.p12','.pem','.key','.cer')}|ForEach-Object{[ordered]@{path=$_.FullName;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash;bytes=$_.Length}})}}
foreach($f in @('C:\codex-woa-umd\present-write-batching-20261113-133134\build-arm64\src\virtio\neptune\triton\neptune_umd.dll','C:\codex-woa-umd\present-write-batching-20261113-133134\build-arm64ec-v3\src\virtio\neptune\triton\neptune_umd.dll')){if(Test-Path $f){$protected+=[ordered]@{path=$f;sha256=(Get-FileHash $f -Algorithm SHA256).Hash;bytes=(Get-Item $f).Length}}}
[ordered]@{roots=$protectedRoots;files=$protected}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Root 'protected-before.json') -Encoding UTF8
& robocopy.exe $original $src /E /XJ /R:0 /W:0 /XD .git .vs __pycache__ builddir out /XF *.pfx *.p12 *.pem *.key *.cer *.pyc /NFL /NDL /NP /LOG:$(Join-Path $Root 'source-copy.log')|Out-Null
if($LASTEXITCODE-ge8){throw ('Private source robocopy failed '+$LASTEXITCODE)}
$approved=@()
foreach($f in $changes){
 $to=Join-Path $src $f.path;$from=Join-Path $Root ('stage\guest-proposed\'+$f.path)
 if((Get-FileHash $from -Algorithm SHA256).Hash-ne$f.proposedSha256-or(Get-Item -LiteralPath $from).Length-ne[long]$f.proposedBytes){throw ('Staged frozen source differs '+$f.path)}
 if($f.operation-ceq'ADD'){
  if(Test-Path -LiteralPath $to){throw 'ADD header already exists in fresh private C8 copy'}
  $inputFile=[IO.File]::Open($from,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{$outputFile=[IO.File]::Open($to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try{$inputFile.CopyTo($outputFile);$outputFile.Flush($true)}finally{$outputFile.Dispose()}
  }finally{$inputFile.Dispose()}
 }else{
  if((Get-FileHash $to -Algorithm SHA256).Hash-ne$f.baselineSha256){throw ('Copied source baseline differs '+$f.path)}
  Copy-Item -LiteralPath $from -Destination $to
 }
 if((Get-FileHash $to -Algorithm SHA256).Hash-ne$f.proposedSha256-or(Get-Item -LiteralPath $to).Length-ne[long]$f.proposedBytes){throw 'Private posthash/size failed'}
 $approved+=[ordered]@{operation=$f.operation;relative=$f.path;sha256=$f.proposedSha256;bytes=[long]$f.proposedBytes}
}
[ordered]@{files=$approved}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Root 'source-approved.json') -Encoding UTF8
$privateDir=Join-Path $src 'src\virtio\neptune'
$privateHashes=@(Get-ChildItem -LiteralPath $privateDir -File -Recurse -Force|ForEach-Object{[ordered]@{relative=$_.FullName.Substring($privateDir.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;bytes=$_.Length}})
$neptuneBefore=@($sourceHashes|ForEach-Object{$_.path.Substring($neptune.Length+1)})
$expectedNames=@($neptuneBefore)+@('npt_publisher_batch.h','npt_runtime_stream.h','triton\tritonRuntimeWrites.h')
if($neptuneBefore.Count-ne440-or$privateHashes.Count-ne443-or$expectedNames.Count-ne443){throw 'Exact original440 plus three explicit new headers required'}
if(@(Compare-Object $expectedNames @($privateHashes|ForEach-Object{$_.relative})).Count){throw 'Private full Neptune copy must be original440 plus only the three allowed headers'}
$expectedPrivate=@{}
foreach($f in $sourceHashes){$expectedPrivate[$f.path.Substring($neptune.Length+1)]=$f.sha256}
foreach($f in $changes){$rel=$f.path.Replace('/','\');$prefix='src\virtio\neptune\';if(-not$rel.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected changed-source prefix'};$expectedPrivate[$rel.Substring($prefix.Length)]=$f.proposedSha256}
foreach($f in $privateHashes){if($expectedPrivate[$f.relative]-ne$f.sha256){throw ('Compiler input differs from exact C8+C14+C15 27-replacement/three-header proposal '+$f.relative)}}
$privateHashes|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Root 'private-neptune-approved.json') -Encoding UTF8
Assert-PrivateNeptune $Root

foreach($f in @('arm64-cross.ini','arm64ec-cross.ini','build-private-umd.ps1')){Copy-Item (Join-Path $Root ('stage\'+$f)) (Join-Path $Root $f)}
[ordered]@{status='private_source_ready';sourceFiles=$foot.Count;neptuneHashCount=$sourceHashes.Count;protectedFiles=$protected.Count;changes=$approved.Count;originalNeptuneFiles=440;privateNeptuneFiles=443;addedHeaders=$allowedAdds;finished=(Get-Date -Format o)}|ConvertTo-Json|Set-Content (Join-Path $Root 'prepare-result.json') -Encoding UTF8
'PRIVATE_UMD_SOURCE_READY'
