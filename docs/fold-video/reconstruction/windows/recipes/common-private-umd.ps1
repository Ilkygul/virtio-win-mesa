$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Assert-PrivateRoot([string]$Value) {
 $fixed='C:\codex-woa-umd\present-signal-flush-pair-c46-r1'
 if([IO.Path]::GetFullPath($Value).TrimEnd('\')-ne$fixed){throw 'Unexpected C42 UMD private root'}
 if(-not(Test-Path -LiteralPath $fixed -PathType Container)){throw 'Owned staging root absent'}
 if((Get-Item -LiteralPath $fixed).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Private root is reparse point'}
 return $fixed
}
function Assert-Packet([string]$Root) {
 if($PSVersionTable.PSVersion.Major-ne5-or$PSVersionTable.PSVersion.Minor-ne1){throw 'Windows PowerShell5.1 required'}
 $manifest=Join-Path $Root 'stage\packet-manifest.json'
 $gate=Get-Content -LiteralPath (Join-Path $Root 'parse-gate.json') -Raw|ConvertFrom-Json
 if($gate.status-ne'powershell51_parser_passed'-or$gate.errors-ne0-or$gate.packetSha256-ne(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash){throw 'Exact packet PS5.1 parser gate missing'}
 $packet=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 foreach($e in $packet.files){
  if($e.path-match'(^[\\/]|:|(^|[\\/])\.\.?([\\/]|$))'){throw 'Unsafe packet path'}
  $p=Join-Path (Join-Path $Root 'stage') ($e.path.Replace('/','\'))
  if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash-ne$e.sha256){throw ('Staged packet differs '+$e.path)}
 }
}
function Assert-LeasedOriginals([string]$Root) {
 $expected=Get-Content -LiteralPath (Join-Path $Root 'stage\protected-original-source-leases.json') -Raw|ConvertFrom-Json
 foreach($d in $expected.roots){
  if(-not$d.exists){continue}
  if(-not(Test-Path -LiteralPath $d.root -PathType Container)){throw 'Protected original root absent'}
  $actual=@(Get-ChildItem -LiteralPath $d.root -File -Recurse -Force|Where-Object{$_.Extension-notin@('.pfx','.p12','.pem','.key','.cer')})
  $leasedFiles=@($d.files|Where-Object{[IO.Path]::GetExtension($_.path)-notin@('.pfx','.p12','.pem','.key','.cer')})
  $old=@($leasedFiles|ForEach-Object{$_.path})
  if(@(Compare-Object $old @($actual|ForEach-Object{$_.FullName})).Count){throw ('Protected source file set changed '+$d.root)}
  foreach($e in $leasedFiles){if((Get-FileHash -LiteralPath $e.path -Algorithm SHA256).Hash-ne$e.sha256){throw ('Original source lease mismatch '+$e.path)}}
 }
}
function Assert-PrivateNeptune([string]$Root) {
 $expected=Get-Content -LiteralPath (Join-Path $Root 'private-neptune-approved.json') -Raw|ConvertFrom-Json
 $dir=Join-Path $Root 'src\src\virtio\neptune'
 $now=@(Get-ChildItem -LiteralPath $dir -File -Recurse -Force)
 if(@(Compare-Object @($expected|ForEach-Object{$_.relative}) @($now|ForEach-Object{$_.FullName.Substring($dir.Length+1)})).Count){throw 'Private compiler source name set changed'}
 foreach($e in $expected){if((Get-FileHash -LiteralPath (Join-Path $dir $e.relative) -Algorithm SHA256).Hash-ne$e.sha256){throw ('Private compiler source hash changed '+$e.relative)}}
}
