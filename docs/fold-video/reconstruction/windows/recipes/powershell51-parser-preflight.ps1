param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$PacketSha256)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major-ne5-or$PSVersionTable.PSVersion.Minor-ne1){throw 'PowerShell5.1 required'}
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
if($Root-ne'C:\codex-woa-umd\present-signal-flush-pair-c46-r1'){throw 'Unexpected private root'}
$stage=Join-Path $Root 'stage';$manifest=Join-Path $stage 'packet-manifest.json'
if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash-ne$PacketSha256){throw 'Reviewed packet SHA failed'}
$m=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
foreach($e in $m.files){if($e.path-match'(^[\\/]|:|(^|[\\/])\.\.?([\\/]|$))'){throw 'Unsafe staged path'};if((Get-FileHash -LiteralPath (Join-Path $stage ($e.path.Replace('/','\'))) -Algorithm SHA256).Hash-ne$e.sha256){throw ('Staged bytes differ '+$e.path)}}
$proof=@();$count=0
foreach($f in Get-ChildItem -LiteralPath $stage -File -Filter '*.ps1'){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors);$bad=@($errors|Where-Object{$null-ne$_});$count+=$bad.Count;$proof+=[ordered]@{name=$f.Name;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash;errors=@($bad|ForEach-Object{[ordered]@{line=$_.Extent.StartLineNumber;message=$_.Message}})}}
$gate=Join-Path $Root 'parse-gate.json';if(Test-Path -LiteralPath $gate){throw 'Parser gate already exists'}
$status=if($count-eq0){'powershell51_parser_passed'}else{'powershell51_parser_failed'}
[ordered]@{status=$status;packetSha256=$PacketSha256;errors=$count;psVersion=[string]$PSVersionTable.PSVersion;scripts=$proof}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $gate -Encoding UTF8
if($count){throw 'Actual PS5.1 parse failed'}
'POWERSHELL51_C15_UMD_PACKET_PARSE_OK'
