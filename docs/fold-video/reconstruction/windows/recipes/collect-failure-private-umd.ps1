param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $Root 'stage\common-private-umd.ps1')
$Root=Assert-PrivateRoot $Root;Assert-Packet $Root
$errors=@();try{Assert-LeasedOriginals $Root}catch{$errors+=$_.Exception.Message}
try{Assert-PrivateNeptune $Root}catch{$errors+=$_.Exception.Message}
$ret=Join-Path $Root 'failure-retrieval';if(Test-Path -LiteralPath $ret){throw 'Failure evidence already exists'}
New-Item -ItemType Directory $ret|Out-Null
foreach($name in @('evidence','out')){if(Test-Path -LiteralPath (Join-Path $Root $name)){Copy-Item -LiteralPath (Join-Path $Root $name) -Destination $ret -Recurse}}
foreach($a in @('arm64','arm64ec')){$logs=Join-Path $Root ('build-'+$a+'\meson-logs');if(Test-Path -LiteralPath $logs){Copy-Item -LiteralPath $logs -Destination (Join-Path $ret ('meson-logs-'+$a)) -Recurse}}
foreach($f in Get-ChildItem -LiteralPath $Root -File|Where-Object{$_.Extension-in@('.json','.log','.ps1','.ini')}){Copy-Item -LiteralPath $f.FullName -Destination $ret}
$files=@(Get-ChildItem -LiteralPath $ret -File -Recurse|ForEach-Object{if($_.Extension-in@('.pfx','.p12','.pem','.key','.cer')){throw 'Forbidden failure artifact'};[ordered]@{relative=$_.FullName.Substring($ret.Length+1);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
[ordered]@{status='FAILED_NOT_DEPLOYABLE';protectedCheckErrors=$errors;files=$files}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $ret 'failure-manifest.json') -Encoding UTF8
& tar.exe -czf (Join-Path $Root 'windows-failure-artifacts.tar.gz') -C $ret .
if($LASTEXITCODE){throw 'Failure archive failed'}
[ordered]@{status='FAILED_NOT_DEPLOYABLE';path=(Join-Path $Root 'windows-failure-artifacts.tar.gz');sha256=(Get-FileHash -LiteralPath (Join-Path $Root 'windows-failure-artifacts.tar.gz') -Algorithm SHA256).Hash}|ConvertTo-Json
