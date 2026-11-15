$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$c46InstallArgs=@{
RunId='c46-present-tail-pair-r1'
Nonce='__C46_FRESH_NONCE_64HEX__'
GenerationId='__C46_FRESH_GENERATION_UUID__'
RunDir='C:\Users\Public\hwdec\codex\gpu-test-c23-r1\umd-runtime-c46-present-tail-pair-r1'
ExpectedScopeSha256='__C46_SCOPE_SHA256__'
ExpectedGenerationReceiptSha256='__C46_GENERATION_RECEIPT_SHA256__'
ExpectedArtifactSha256='F91D91416051A6C9E2BBFC7E312BB0579A5F099C2F297115BA71D7D868D038D7'
ExpectedBuildMarker='CAPTION_COLORKEY'
ExpectedNewNativeSha256='__C46_NEW_NATIVE_SHA256__'
ExpectedNewEcSha256='__C46_NEW_EC_SHA256__'
ExpectedNewNativeBytes=[long]::Parse('__C46_NEW_NATIVE_BYTES__')
ExpectedNewEcBytes=[long]::Parse('__C46_NEW_EC_BYTES__')
}
$r=$c46InstallArgs.RunDir
foreach($n in @('assert-c46-root-scope.ps1','deploy-c46-umd-overlay.ps1')){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile(($r+'\'+$n),[ref]$t,[ref]$e);if(@($e).Count){throw($e|Out-String)}}
if((Get-FileHash ($r+'\assert-c46-root-scope.ps1')).Hash -cne 'A9D96B3ADEF143D886597710390A8479BA642BB14F48B526AB86D2B44C95B309'){throw 'Scope guard differs'}
if((Get-FileHash ($r+'\deploy-c46-umd-overlay.ps1')).Hash -cne 'D1F8ACB93128B0232AAF96C5340E3B4C381DC66F0B5A4DC6E81C5EC23F1A063B'){throw 'Installer differs'}
if((Get-FileHash ($r+'\generation-receipt.private.json')).Hash -cne $c46InstallArgs.ExpectedGenerationReceiptSha256){throw 'Generation file differs'}
. ($r+'\assert-c46-root-scope.ps1')
$x=Assert-C46RootScope @c46InstallArgs
[ordered]@{parse='PASS';scopeVerified=$true;scopeSha256=$c46InstallArgs.ExpectedScopeSha256;newNativeSha256=$c46InstallArgs.ExpectedNewNativeSha256;newEcSha256=$c46InstallArgs.ExpectedNewEcSha256;staged=@(Get-ChildItem ($r+'\umd-c46-stage')|ForEach-Object{[ordered]@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash $_.FullName).Hash}})}|ConvertTo-Json -Depth 4
