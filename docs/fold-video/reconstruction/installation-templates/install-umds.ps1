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
& ($c46InstallArgs.RunDir+'\deploy-c46-umd-overlay.ps1') -Mode Install @c46InstallArgs
