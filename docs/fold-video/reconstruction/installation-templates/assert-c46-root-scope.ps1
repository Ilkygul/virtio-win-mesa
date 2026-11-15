# Read-only C46 UMD-only scope gate. Android identity/FD facts are Root attestations,
# externally SHA-pinned; Windows cannot independently observe Android backing.
function Assert-C11([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function Get-C11CanonicalPath([string]$Path) {
    Assert-C11 ([IO.Path]::IsPathRooted($Path)) 'Absolute Windows path required'
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}
function Assert-C11NoReparse([string]$Path) {
    $cursor=Get-C11CanonicalPath $Path
    while($cursor){
        if(Test-Path -LiteralPath $cursor){
            Assert-C11 (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "Reparse point refused: $cursor"
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent-eq$cursor){break};$cursor=$parent
    }
}
function Get-C11Hash([string]$Path) {
    Assert-C11 ([IO.File]::Exists($Path)) "Missing file: $Path"
    Assert-C11NoReparse $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Write-C11NewJson([string]$Path,$Value) {
    Assert-C11NoReparse $Path
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 10)+"`r`n")
    $file=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
}
function Assert-C46RootScope {
 param([string]$RunId,[string]$Nonce,[string]$GenerationId,[string]$RunDir,
       [string]$ExpectedScopeSha256,[string]$ExpectedGenerationReceiptSha256,
       [string]$ExpectedArtifactSha256,[string]$ExpectedBuildMarker,
       [string]$ExpectedNewNativeSha256,[string]$ExpectedNewEcSha256,
       [long]$ExpectedNewNativeBytes,[long]$ExpectedNewEcBytes)
 Assert-C11 ($RunId-match'^c46-[A-Za-z0-9_-]{1,48}$' -and $Nonce-match'^[A-Fa-f0-9]{64}$') 'C46 identity/nonce required'
 foreach($h in @($ExpectedScopeSha256,$ExpectedGenerationReceiptSha256)){Assert-C11 ($h-match'^[A-Fa-f0-9]{64}$') 'External Root SHA256 required'}
 Assert-C11 ($ExpectedArtifactSha256-eq'F91D91416051A6C9E2BBFC7E312BB0579A5F099C2F297115BA71D7D868D038D7' -and $ExpectedBuildMarker-ceq'CAPTION_COLORKEY') 'Only exact existing F91 allowed'
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 Assert-C11 ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'Elevated administrator required; no auto elevation'
 Assert-C11 ([Environment]::Is64BitProcess -and $env:SystemRoot-ieq'C:\Windows') 'Audited64bit C:\Windows only'
 $directory=Get-C11CanonicalPath $RunDir
 Assert-C11 ([IO.Path]::GetFileName($directory)-ceq('umd-runtime-'+$RunId) -and [IO.Directory]::Exists($directory)) 'Fresh Root-created C46 directory required'
 Assert-C11NoReparse $directory
 $scopePath=Join-Path $directory 'c46-root-scope.json'
 Assert-C11 ((Get-C11Hash $scopePath)-eq$ExpectedScopeSha256) 'Root scope hash differs'
 $scope=[IO.File]::ReadAllText($scopePath)|ConvertFrom-Json
 Assert-C11 ($scope.schema-ceq'codex-c46-root-scope-v1' -and $scope.runId-ceq$RunId -and $scope.nonce-ceq$Nonce -and $scope.generationId-ceq$GenerationId) 'Scope identity differs'
 Assert-C11 ($scope.generationReceiptSha256-eq$ExpectedGenerationReceiptSha256 -and $scope.artifactSha256-eq$ExpectedArtifactSha256 -and $scope.buildMarker-ceq$ExpectedBuildMarker) 'Generation/kernel binding differs'
 Assert-C11 ((Get-C11CanonicalPath $scope.dedicatedRunDir)-ceq$directory) 'Scope RunDir differs'
 Assert-C11 ($scope.inheritedKernelSelectionIntentSha256-eq'C3F864F72CB0E2EDB4152B7D1B887231BC6F0D3F9D4BA0959CC5B662E136BFDF') 'Inherited C35 kernel intent pin differs'
 Assert-C11 ($scope.vmUuid-ceq'c1003be0-3fa5-427c-9aae-1056cc4865d6') 'Only isolated C23 VM UUID allowed'
 Assert-C11 ($scope.overlayPath.StartsWith('/data/') -and $scope.basePath.StartsWith('/data/') -and $scope.overlayPath-cne$scope.basePath -and $scope.overlayPath-match'(?i)c46.*\.qcow2$') 'Distinct new C46 child required'
 Assert-C11 ($scope.basePath-ceq'/data/media/0/DroidVM/Codex GPU test C23/windows-test-c35-runtime-r1.qcow2' -and $scope.baselineVarsPath-ceq'/data/data/cn.classfun.droidvm/usr/share/droidvm/codex-c35-runtime-r1.vars.fd') 'Exact frozen C35/C37 parent and VARS required'
 Assert-C11 ($scope.varsPath.StartsWith('/data/') -and $scope.varsPath-cne$scope.baselineVarsPath -and $scope.varsPath-match'(?i)c46.*\.fd$') 'Isolated C46 private VARS copy required'
 foreach($name in @('generationReceiptSha256','baseColdProofSha256','actualFdProofSha256','baselineVarsSha256','hostConfigSha256','artifactVerificationSha256')){Assert-C11 ($scope.$name-match'^[A-Fa-f0-9]{64}$') ('Missing Root proof pin: '+$name)}
 foreach($name in @('freshOverlayOfColdC37Parent','baseAndLkgFrozen','persistedAndLiveSelectionMatch','actualFdOverlayAndPrivateVarsOnly','baseBackingReadOnlyValidated','grandparentC33ReadOnlyValidated','noProductionDiskOrVarsOpen','hostC37AndC33Fp32PairAndCachePreserved','baselineWhitelistAndStrictMarkersPreserved')){Assert-C11 ($scope.$name-is[bool] -and $scope.$name) ('Missing Root actual attestation: '+$name)}
 Assert-C11 ([long]$scope.mainPid-gt0 -and [long]$scope.mainStartTicks-gt0 -and $scope.phoneBootId-match'^[A-Fa-f0-9]{8}(-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}$') 'Root actual main/birth/boot required'
 $created=[DateTimeOffset]::Parse($scope.createdUtc).ToUniversalTime();$expires=[DateTimeOffset]::Parse($scope.expiresUtc).ToUniversalTime();$now=[DateTimeOffset]::UtcNow
 Assert-C11 ($created-le$now.AddMinutes(2) -and $expires-gt$now -and $expires-gt$created -and ($expires-$created).TotalHours-le4) 'Scope expired/future/over4h'
 foreach($name in @('triton-nowarp','triton-presentwritesync','triton-dwmwritesync')){
  $marker=Join-Path 'C:\Users\Public' $name;Assert-C11NoReparse $marker
  Assert-C11 ([IO.File]::Exists($marker) -and (Get-Item -LiteralPath $marker).Length-eq0) ('Required unchanged empty marker: '+$name)
 }
 foreach($h in @($ExpectedNewNativeSha256,$ExpectedNewEcSha256)){Assert-C11 ($h-match'^[A-Fa-f0-9]{64}$') 'Root must bind actual new C46 artifact hashes'}
 Assert-C11 ($ExpectedNewNativeBytes-gt0 -and $ExpectedNewEcBytes-gt0 -and $scope.newNativeSha256-eq$ExpectedNewNativeSha256 -and $scope.newEcSha256-eq$ExpectedNewEcSha256 -and [long]$scope.newNativeBytes-eq$ExpectedNewNativeBytes -and [long]$scope.newEcBytes-eq$ExpectedNewEcBytes) 'Root build-artifact binding differs'
 Assert-C11 ($ExpectedNewNativeSha256-ne'57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A' -and $ExpectedNewEcSha256-ne'9CC91ED21D0FA367CCF070483A83949C9695504D26CAB4F939E3613A2E598C2D') 'New C46 binaries must differ from old C20'
 $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\VioGpu3D\Parameters',$false)
 try{Assert-C11 ($null-ne$key -and $key.GetValueKind('NativeGpuJobV1').ToString()-ceq'DWord' -and $key.GetValue('NativeGpuJobV1')-eq1) 'Existing Native DWORD1 must remain unchanged'}finally{if($key){$key.Dispose()}}
 $marker='C:\Users\Public\triton-runtimestream';Assert-C11NoReparse $marker
 Assert-C11 ([IO.File]::Exists($marker) -and (Get-Item -LiteralPath $marker).Length-eq0) 'Existing empty runtime marker required'
 return $scope
}
