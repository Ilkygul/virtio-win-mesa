# C46 UMD-only replacement on new cold child; existing C35 kernel/mode stay selected.
# Source proposal only. Root stages/inspects/reboots; this helper never loads drivers.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Install','Restore')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$RunId,
 [Parameter(Mandatory=$true)][string]$Nonce,
 [Parameter(Mandatory=$true)][string]$GenerationId,
 [Parameter(Mandatory=$true)][string]$RunDir,
 [Parameter(Mandatory=$true)][string]$ExpectedScopeSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedGenerationReceiptSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedArtifactSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedBuildMarker,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedNewNativeSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedNewEcSha256,
 [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][long]$ExpectedNewNativeBytes,
 [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][long]$ExpectedNewEcBytes,
 [string]$ExpectedInstallIntentSha256,
 [string]$ExpectedInstallReceiptSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$guard=Join-Path $PSScriptRoot 'assert-c46-root-scope.ps1'
if((Get-FileHash -LiteralPath $guard -Algorithm SHA256).Hash-ne'A9D96B3ADEF143D886597710390A8479BA642BB14F48B526AB86D2B44C95B309'){throw 'Reviewed C46 Root scope guard differs'}
. $guard
$leaseArgs=@{RunId=$RunId;Nonce=$Nonce;GenerationId=$GenerationId;RunDir=$RunDir;ExpectedScopeSha256=$ExpectedScopeSha256;ExpectedGenerationReceiptSha256=$ExpectedGenerationReceiptSha256;ExpectedArtifactSha256=$ExpectedArtifactSha256;ExpectedBuildMarker=$ExpectedBuildMarker;ExpectedNewNativeSha256=$ExpectedNewNativeSha256;ExpectedNewEcSha256=$ExpectedNewEcSha256;ExpectedNewNativeBytes=$ExpectedNewNativeBytes;ExpectedNewEcBytes=$ExpectedNewEcBytes}
$null=Assert-C46RootScope @leaseArgs
Assert-C11 ($Nonce-match'^[A-Fa-f0-9]{64}$') 'UMD operation requires exact64hex nonce'
Assert-C11 ([Environment]::Is64BitProcess) 'Use64bit Windows PowerShell'
Assert-C11 (-not[string]::IsNullOrWhiteSpace($PSCommandPath)) 'Run reviewed helper as a file'
$RunDir=Get-C11CanonicalPath $RunDir
$store='C:\WINDOWS\System32\DriverStore\FileRepository\viogpu3d.inf_arm64_67b20e2085b3653e'
$stage=Join-Path $RunDir 'umd-c46-stage';$backup=Join-Path $RunDir 'umd-c46-backup'
$version='100.6.101.58200'
$oldKernel='1CA24128E436F6A0EEDA4896DE01B3FE3B5EC0BFED51B4CDE3076AB501DE51E4'
Assert-C11 ($ExpectedArtifactSha256-ne$oldKernel) 'Inherited F91 must differ from original1CA'
$patch='CA08B3134F9A6885539EA0C82BD3DDCBED7C0B8E988B39F42D9718F9DC6DE2A7'
$signer='C92E73E2CCB11F327B786F9CAEA213D7CCC92F08'
$items=@(
 [pscustomobject]@{name='neptune_umd.dll';old='57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A';oldBytes=1360896;new=$ExpectedNewNativeSha256;newBytes=$ExpectedNewNativeBytes;machine=0xAA64},
 [pscustomobject]@{name='neptune_umd_arm64.dll';old='57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A';oldBytes=1360896;new=$ExpectedNewNativeSha256;newBytes=$ExpectedNewNativeBytes;machine=0xAA64},
 [pscustomobject]@{name='neptune_umd_ec.dll';old='9CC91ED21D0FA367CCF070483A83949C9695504D26CAB4F939E3613A2E598C2D';oldBytes=1267712;new=$ExpectedNewEcSha256;newBytes=$ExpectedNewEcBytes;machine=0x8664}
)
function Assert-NewPath([string]$Path){Assert-C11NoReparse $Path;Assert-C11 (-not(Test-Path -LiteralPath $Path)) ('Fresh-only path exists: '+$Path)}
function Read-PinnedJson([string]$Path,[string]$Hash){
 Assert-C11 ($Hash-match'^[A-Fa-f0-9]{64}$') 'Explicit external JSON hash required'
 Assert-C11 ((Get-C11Hash $Path)-eq$Hash) ('Pinned JSON differs: '+$Path)
 return ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)
}
function Read-ServiceSnapshot {
 $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\VioGpu3D',$false)
 Assert-C11 ($null-ne$key) 'VioGpu3D service missing'
 try{
  $result=[ordered]@{}
  foreach($name in @('ImagePath','Start','Type','ErrorControl')){
   Assert-C11 ($key.GetValueNames()-contains$name) ('Missing service value: '+$name)
   $result[$name]=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
   $result[$name+'Kind']=[string]$key.GetValueKind($name)
  }
  return [pscustomobject]$result
 }finally{$key.Dispose()}
}
function Assert-SameService($Actual,$Expected){
 foreach($name in @('ImagePath','ImagePathKind','Start','StartKind','Type','TypeKind','ErrorControl','ErrorControlKind')){
  Assert-C11 ([string]$Actual.$name-ceq[string]$Expected.$name) ('Kernel selection/service differs: '+$name)
 }
}
function Assert-Binary([string]$Path,[string]$Hash,[long]$Bytes,[int]$Machine){
 Assert-C11 ((Get-C11Hash $Path)-eq$Hash) ('File hash differs: '+$Path)
 Assert-C11 ((Get-Item -LiteralPath $Path).Length-eq$Bytes) ('File size differs: '+$Path)
 Assert-C11 ([Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileVersion-ceq$version) ('File version differs: '+$Path)
 $data=[IO.File]::ReadAllBytes($Path)
 Assert-C11 ($data.Length-ge64 -and $data[0]-eq0x4D -and $data[1]-eq0x5A) 'Not MZ PE'
 $offset=[BitConverter]::ToInt32($data,0x3c)
 Assert-C11 ($offset-ge0 -and $offset-le($data.Length-24)) 'PE offset outside file'
 Assert-C11 ([BitConverter]::ToUInt32($data,$offset)-eq0x4550 -and [BitConverter]::ToUInt16($data,$offset+4)-eq$Machine) 'Unexpected PE machine'
}
function Assert-Acl([string]$Path,[string]$Sddl){Assert-C11 ((Get-Acl -LiteralPath $Path).Sddl-ceq$Sddl) ('ACL differs: '+$Path)}
function Set-SavedAcl([string]$Path,[string]$Sddl){
 $acl=New-Object Security.AccessControl.FileSecurity
 $acl.SetSecurityDescriptorSddlForm($Sddl)
 Set-Acl -LiteralPath $Path -AclObject $acl
 Assert-Acl $Path $Sddl
}
$ExpectedKernelSelectionIntentSha256='C3F864F72CB0E2EDB4152B7D1B887231BC6F0D3F9D4BA0959CC5B662E136BFDF'
$kernelIntentPath='C:\Users\Public\hwdec\codex\gpu-test-c23-r1\kmd-nativejob-c35-runtime-r1\selection-intent.json'
$kernelIntent=Read-PinnedJson $kernelIntentPath $ExpectedKernelSelectionIntentSha256
function Assert-KernelSelected {
 $null=Assert-C46RootScope @leaseArgs
 Assert-C11 ((Get-C11Hash $kernelIntentPath)-eq$ExpectedKernelSelectionIntentSha256) 'Kernel intent changed'
 Assert-C11 ($kernelIntent.schema-ceq'codex-c35-kmd-selection-intent-v1') 'Wrong kernel selection intent schema'
 Assert-C11 ($kernelIntent.runId-ceq'c35-runtime-r1' -and $kernelIntent.buildMarker-ceq$ExpectedBuildMarker) 'Inherited C35 kernel identity differs'
 Assert-C11 ($kernelIntent.sourcePatchSha256-eq$patch) 'Inherited C35 kernel source hash differs'
 $selected='\SystemRoot\System32\drivers\codex\kmd-nativejob-c35-runtime-r1\viogpu3d-nativejob.sys'
 $physical='C:\Windows\System32\drivers\codex\kmd-nativejob-c35-runtime-r1\viogpu3d-nativejob.sys'
 Assert-C11 ($kernelIntent.newImagePath-ceq$selected -and $kernelIntent.artifact.path-ieq$physical) 'Kernel destination differs'
 Assert-C11 ($kernelIntent.artifact.sha256-eq$ExpectedArtifactSha256 -and $kernelIntent.artifact.version-ceq$version -and $kernelIntent.artifact.signer-eq$signer -and $kernelIntent.artifact.signature-ceq'Valid' -and $kernelIntent.artifact.embedded-eq$true -and $kernelIntent.artifact.machine-ceq'ARM64') 'Kernel intent artifact differs'
 Assert-C11 ($kernelIntent.expectedSelectedService.ImagePath-ceq$selected -and $kernelIntent.expectedSelectedService.ImagePathKind-ceq$kernelIntent.newImagePathKind -and $kernelIntent.newImagePathKind-ceq$kernelIntent.originalService.ImagePathKind) 'Kernel selection value/kind differs'
 foreach($name in @('Start','StartKind','Type','TypeKind','ErrorControl','ErrorControlKind')){Assert-C11 ([string]$kernelIntent.expectedSelectedService.$name-ceq[string]$kernelIntent.originalService.$name) ('Kernel changed unrelated field: '+$name)}
 Assert-SameService (Read-ServiceSnapshot) $kernelIntent.expectedSelectedService
 Assert-C11 ((Get-C11Hash $physical)-eq$ExpectedArtifactSha256) 'Selected kernel file differs'
 $sig=Get-AuthenticodeSignature -LiteralPath $physical
 Assert-C11 ([string]$sig.Status-ceq'Valid' -and $sig.SignerCertificate.Thumbprint-eq$signer -and [string]$sig.SignatureType-ceq'Authenticode') 'Selected kernel embedded signature is not Valid/C92'
 Assert-C11 ((Get-C11Hash (Join-Path $store 'viogpu3d.sys'))-eq$oldKernel) 'Original DriverStore kernel changed'
}
Assert-C11NoReparse $store
Assert-KernelSelected
$installIntentPath=Join-Path $RunDir 'umd-c46-install-intent.json'
$installReceiptPath=Join-Path $RunDir 'umd-c46-install-receipt.json'
$records=@()
if($Mode-ceq'Install'){
 Assert-NewPath $backup;Assert-NewPath $installIntentPath;Assert-NewPath $installReceiptPath
 Assert-C11 ([IO.Directory]::Exists($stage)) 'Stage exactly three built UMDs under RunDir/umd-c46-stage'
 Assert-C11NoReparse $stage
 foreach($item in $items){
  $target=Join-Path $store $item.name;$source=Join-Path $stage $item.name
  Assert-Binary $target $item.old $item.oldBytes $item.machine
  Assert-Binary $source $item.new $item.newBytes $item.machine
  $acl=Get-Acl -LiteralPath $target
  $record=[ordered]@{name=$item.name;target=$target;stage=$source;backup=(Join-Path $backup $item.name);prepared=($target+'.codex-c46-'+$Nonce+'-prepared');renamedOld=($target+'.codex-c46-'+$Nonce+'-old');restorePrepared=($target+'.codex-c46-'+$Nonce+'-restore');retiredNew=($target+'.codex-c46-'+$Nonce+'-retired-new');oldSha256=$item.old;newSha256=$item.new;oldBytes=$item.oldBytes;newBytes=$item.newBytes;machine=$item.machine;originalSddl=$acl.Sddl;backupSddl=$null}
  foreach($name in @('prepared','renamedOld','restorePrepared','retiredNew')){Assert-NewPath $record[$name]}
  $records+=[pscustomobject]$record
 }
 # All3 source/target/ACL/path guards passed before backup or DriverStore write.
 $null=New-Item -ItemType Directory -Path $backup -ErrorAction Stop
 foreach($record in $records){
  Copy-Item -LiteralPath $record.target -Destination $record.backup
  $record.backupSddl=(Get-Acl -LiteralPath $record.backup).Sddl
  Assert-Binary $record.backup $record.oldSha256 $record.oldBytes $record.machine
 }
 $intent=[ordered]@{schema='codex-c46-umd-install-intent-v1';runId=$RunId;nonce=$Nonce;generationId=$GenerationId;scopeSha256=$ExpectedScopeSha256;generationReceiptSha256=$ExpectedGenerationReceiptSha256;kernelSelectionIntentSha256=$ExpectedKernelSelectionIntentSha256;kernelArtifactSha256=$ExpectedArtifactSha256;driverDirectory=$store;backupDirectory=$backup;version=$version;scriptSha256=(Get-C11Hash $PSCommandPath);preparedUtc=[DateTime]::UtcNow.ToString('o');files=$records;scope='Exact3new C46 video-setter UMDs in isolated C46 child; inherited C35 kernel intent is validated, never replaced. No KMD/service/INF/CAT/loader/policy change. Hot rename preserves old mapped images; ROOT reboot and loaded-module hashes are mandatory for runtime proof.'}
 Write-C11NewJson $installIntentPath $intent
 foreach($record in $records){
  Copy-Item -LiteralPath $record.stage -Destination $record.prepared
  Set-SavedAcl $record.prepared $record.originalSddl
  Assert-Binary $record.prepared $record.newSha256 $record.newBytes $record.machine
 }
 $installIntentHash=Get-C11Hash $installIntentPath
 Write-C11NewJson (Join-Path $RunDir 'umd-c46-prepared.json') ([ordered]@{schema='codex-c46-umd-prepared-v1';installIntentSha256=$installIntentHash;allThreeBackupsAndPreparedVerified=$true;files=$records})
 $index=0
 foreach($record in $records){
  Assert-KernelSelected
  Assert-Binary $record.target $record.oldSha256 $record.oldBytes $record.machine;Assert-Acl $record.target $record.originalSddl
  Assert-Binary $record.prepared $record.newSha256 $record.newBytes $record.machine;Assert-Acl $record.prepared $record.originalSddl
  Move-Item -LiteralPath $record.target -Destination $record.renamedOld
  Write-C11NewJson (Join-Path $RunDir ('umd-c46-install-'+$index+'-old-renamed.json')) ([ordered]@{name=$record.name;installIntentSha256=$installIntentHash;oldRenamed=$record.renamedOld;utc=[DateTime]::UtcNow.ToString('o')})
  Move-Item -LiteralPath $record.prepared -Destination $record.target
  Assert-Binary $record.target $record.newSha256 $record.newBytes $record.machine;Assert-Acl $record.target $record.originalSddl
  Write-C11NewJson (Join-Path $RunDir ('umd-c46-install-'+$index+'-new-selected.json')) ([ordered]@{name=$record.name;installIntentSha256=$installIntentHash;sha256=(Get-C11Hash $record.target);sddl=(Get-Acl -LiteralPath $record.target).Sddl;utc=[DateTime]::UtcNow.ToString('o')})
  $index++
 }
 Assert-KernelSelected
 foreach($record in $records){Assert-Binary $record.target $record.newSha256 $record.newBytes $record.machine;Assert-Acl $record.target $record.originalSddl;Assert-Binary $record.renamedOld $record.oldSha256 $record.oldBytes $record.machine}
 $receipt=[ordered]@{schema='codex-c46-umd-install-receipt-v1';status='installed_pending_root_reboot_no_runtime_proof';runId=$RunId;nonce=$Nonce;generationId=$GenerationId;installIntentSha256=$installIntentHash;kernelSelectionIntentSha256=$ExpectedKernelSelectionIntentSha256;kernelArtifactSha256=$ExpectedArtifactSha256;generationReceiptSha256=$ExpectedGenerationReceiptSha256;allThreeVerified=$true;service=(Read-ServiceSnapshot);files=$records;vmActions=$false;utc=[DateTime]::UtcNow.ToString('o')}
 Write-C11NewJson $installReceiptPath $receipt
 [ordered]@{status=$receipt.status;intent=$installIntentPath;intentSha256=$installIntentHash;receipt=$installReceiptPath;receiptSha256=(Get-C11Hash $installReceiptPath);vmActions=$false}|ConvertTo-Json
 return
}
# Restore only a complete, externally pinned installation. An interrupted
# mutation is preserved for root inspection/whole-overlay rollback, not guessed.
$intent=Read-PinnedJson $installIntentPath $ExpectedInstallIntentSha256
$receipt=Read-PinnedJson $installReceiptPath $ExpectedInstallReceiptSha256
Assert-C11 ($intent.schema-ceq'codex-c46-umd-install-intent-v1' -and $receipt.schema-ceq'codex-c46-umd-install-receipt-v1' -and $receipt.status-ceq'installed_pending_root_reboot_no_runtime_proof' -and $receipt.allThreeVerified-eq$true) 'Not a complete UMD install receipt'
foreach($document in @($intent,$receipt)){
 foreach($pair in @(@('runId',$RunId),@('nonce',$Nonce),@('generationId',$GenerationId))){Assert-C11 ([string]$document.($pair[0])-ceq[string]$pair[1]) ('UMD receipt identity differs: '+$pair[0])}
 Assert-C11 ($document.generationReceiptSha256-eq$ExpectedGenerationReceiptSha256) 'UMD receipt generation hash differs'
 Assert-C11 ($document.kernelSelectionIntentSha256-eq$ExpectedKernelSelectionIntentSha256 -and $document.kernelArtifactSha256-eq$ExpectedArtifactSha256) 'UMD receipt kernel hash differs'
}
Assert-C11 ($receipt.installIntentSha256-eq$ExpectedInstallIntentSha256 -and $intent.driverDirectory-ceq$store -and $intent.backupDirectory-ceq$backup -and $intent.version-ceq$version -and $intent.scopeSha256-eq$ExpectedScopeSha256) 'UMD intent/receipt binding differs'
Assert-C11 (@($intent.files).Count-eq3 -and @($receipt.files).Count-eq3) 'Exactly3 recorded files required'
foreach($item in $items){
 $found=@($intent.files|Where-Object{$_.name-ceq$item.name});Assert-C11 ($found.Count-eq1) 'UMD file identity duplicate/missing'
 $record=$found[0];$target=Join-Path $store $item.name
 Assert-C11 ($record.target-ceq$target -and $record.backup-ceq(Join-Path $backup $item.name) -and $record.renamedOld-ceq($target+'.codex-c46-'+$Nonce+'-old') -and $record.restorePrepared-ceq($target+'.codex-c46-'+$Nonce+'-restore') -and $record.retiredNew-ceq($target+'.codex-c46-'+$Nonce+'-retired-new')) 'Recorded restore path differs'
 Assert-C11 ($record.oldSha256-eq$item.old -and $record.newSha256-eq$item.new -and $record.oldBytes-eq$item.oldBytes -and $record.newBytes-eq$item.newBytes -and $record.machine-eq$item.machine) 'Recorded restore bytes differ'
 Assert-Binary $record.target $item.new $item.newBytes $item.machine;Assert-Acl $record.target $record.originalSddl
 Assert-Binary $record.backup $item.old $item.oldBytes $item.machine;Assert-Acl $record.backup $record.backupSddl
 Assert-Binary $record.renamedOld $item.old $item.oldBytes $item.machine;Assert-Acl $record.renamedOld $record.originalSddl
 Assert-NewPath $record.restorePrepared;Assert-NewPath $record.retiredNew
 $records+=$record
}
$restoreIntentPath=Join-Path $RunDir 'umd-c46-restore-intent.json';$restoreReceiptPath=Join-Path $RunDir 'umd-c46-restore-receipt.json'
Assert-NewPath $restoreIntentPath;Assert-NewPath $restoreReceiptPath
Write-C11NewJson $restoreIntentPath ([ordered]@{schema='codex-c46-umd-restore-intent-v1';runId=$RunId;nonce=$Nonce;generationId=$GenerationId;installIntentSha256=$ExpectedInstallIntentSha256;installReceiptSha256=$ExpectedInstallReceiptSha256;generationReceiptSha256=$ExpectedGenerationReceiptSha256;kernelSelectionIntentSha256=$ExpectedKernelSelectionIntentSha256;files=$records;utc=[DateTime]::UtcNow.ToString('o')})
foreach($record in $records){Copy-Item -LiteralPath $record.backup -Destination $record.restorePrepared;Set-SavedAcl $record.restorePrepared $record.originalSddl;Assert-Binary $record.restorePrepared $record.oldSha256 $record.oldBytes $record.machine}
$index=0
foreach($record in $records){
 Assert-KernelSelected
 Assert-Binary $record.target $record.newSha256 $record.newBytes $record.machine;Assert-Acl $record.target $record.originalSddl
 Assert-Binary $record.restorePrepared $record.oldSha256 $record.oldBytes $record.machine;Assert-Acl $record.restorePrepared $record.originalSddl
 Move-Item -LiteralPath $record.target -Destination $record.retiredNew
 Write-C11NewJson (Join-Path $RunDir ('umd-c46-restore-'+$index+'-new-retired.json')) ([ordered]@{name=$record.name;restoreIntentSha256=(Get-C11Hash $restoreIntentPath);retiredNew=$record.retiredNew;utc=[DateTime]::UtcNow.ToString('o')})
 Move-Item -LiteralPath $record.restorePrepared -Destination $record.target
 Assert-Binary $record.target $record.oldSha256 $record.oldBytes $record.machine;Assert-Acl $record.target $record.originalSddl
 Write-C11NewJson (Join-Path $RunDir ('umd-c46-restore-'+$index+'-old-selected.json')) ([ordered]@{name=$record.name;sha256=(Get-C11Hash $record.target);sddl=(Get-Acl -LiteralPath $record.target).Sddl;utc=[DateTime]::UtcNow.ToString('o')})
 $index++
}
Assert-KernelSelected
foreach($record in $records){Assert-Binary $record.target $record.oldSha256 $record.oldBytes $record.machine;Assert-Acl $record.target $record.originalSddl}
Write-C11NewJson $restoreReceiptPath ([ordered]@{schema='codex-c46-umd-restore-receipt-v1';status='restored_C20_pending_root_reboot_no_runtime_proof';runId=$RunId;nonce=$Nonce;installIntentSha256=$ExpectedInstallIntentSha256;installReceiptSha256=$ExpectedInstallReceiptSha256;generationReceiptSha256=$ExpectedGenerationReceiptSha256;kernelSelectionIntentSha256=$ExpectedKernelSelectionIntentSha256;files=$records;vmActions=$false;utc=[DateTime]::UtcNow.ToString('o')})
[ordered]@{status='restored_C20_pending_root_reboot_no_runtime_proof';receipt=$restoreReceiptPath;receiptSha256=(Get-C11Hash $restoreReceiptPath);next='C20 UMD restored; root reboot and loaded-module hashes required. F91 and Native1/runtime marker remain unchanged; cold C37 parent config rollback remains primary.';vmActions=$false}|ConvertTo-Json
