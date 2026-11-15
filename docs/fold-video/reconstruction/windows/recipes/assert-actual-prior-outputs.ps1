param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $Root 'stage\common-private-umd.ps1')
$Root=Assert-PrivateRoot $Root;Assert-Packet $Root
$expected=@(
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c13-r1\out\native-alias\neptune_umd.dll';sha256='5AEBF0DD71CBA109786523DA5478B5DEEE470BCA201E667993016A2BA01708DA';bytes=1337344},
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c13-r1\out\native-alias\neptune_umd_arm64.dll';sha256='5AEBF0DD71CBA109786523DA5478B5DEEE470BCA201E667993016A2BA01708DA';bytes=1337344},
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c13-r1\out\native-alias\neptune_umd_ec.dll';sha256='62BAF7282E1819FAE111316D2A7591063010FC3DB4A660D9140F7DEFF4A56CD1';bytes=1243136},
 [pscustomobject]@{path='C:\codex-kmd-native-job\c13-colorkey-trace-r1\artifact\viogpu3d-nativejob.sys';sha256='F91D91416051A6C9E2BBFC7E312BB0579A5F099C2F297115BA71D7D868D038D7';bytes=248184},
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c14-r1\out\native-alias\neptune_umd.dll';sha256='36E9DE601D70CBCA947C79ABB7C7E6F295D8F264F940A8381394BDAC58D0D2F4';bytes=1337344},
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c14-r1\out\native-alias\neptune_umd_arm64.dll';sha256='36E9DE601D70CBCA947C79ABB7C7E6F295D8F264F940A8381394BDAC58D0D2F4';bytes=1337344},
 [pscustomobject]@{path='C:\codex-woa-umd\native-job-publisher-c14-r1\out\native-alias\neptune_umd_ec.dll';sha256='1FB9652E7FED01A9C1BEF1F39099B45D181BE8BE5E53D64E7A51E30789E6F82B';bytes=1243136},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r2\out\native-alias\neptune_umd.dll';sha256='E37D8D8CA021EE23A3CC8B72818CD12ACE9AAAA17A8655E045C02B76E6F842BA';bytes=1356800},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r2\out\native-alias\neptune_umd_arm64.dll';sha256='E37D8D8CA021EE23A3CC8B72818CD12ACE9AAAA17A8655E045C02B76E6F842BA';bytes=1356800},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r2\out\native-alias\neptune_umd_ec.dll';sha256='39CBADBBC912733E960E2BCAA9C83D3C8B0C4A9DB7F4EB30839F9441CE912DE5';bytes=1263616},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r3\out\native-alias\neptune_umd.dll';sha256='6C1D1C4039CA3D9748FBA4C8D24EA184C27F87165A535CE25AA87908BEFCE4A8';bytes=1356800},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r3\out\native-alias\neptune_umd_arm64.dll';sha256='6C1D1C4039CA3D9748FBA4C8D24EA184C27F87165A535CE25AA87908BEFCE4A8';bytes=1356800},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-stream-c15-r3\out\native-alias\neptune_umd_ec.dll';sha256='44E2E72393E45A05EFC937C54C2098E5DFD9A5BF7D23372C151239A8276C2243';bytes=1263616},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-submit-diag-c18-r1\out\native-alias\neptune_umd.dll';sha256='5B6BACE9B1363681C1011C2375BC12D5A7DF98F9F78F3B0BA2E3C99DF6E1B22F';bytes=1360384},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-submit-diag-c18-r1\out\native-alias\neptune_umd_arm64.dll';sha256='5B6BACE9B1363681C1011C2375BC12D5A7DF98F9F78F3B0BA2E3C99DF6E1B22F';bytes=1360384},
 [pscustomobject]@{path='C:\codex-woa-umd\runtime-submit-diag-c18-r1\out\native-alias\neptune_umd_ec.dll';sha256='54D7F4E781FDF7F49D894C480A7F59763434182EC83633114179D2D8C898D5A3';bytes=1267712},
 [pscustomobject]@{path='C:\codex-woa-umd\present-batch-c19-r1\out\native-alias\neptune_umd.dll';sha256='21EA6DC5C01F627DE665F0D01F5EF89476647F84B56BDC1DE747BDD2D258C6B8';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\present-batch-c19-r1\out\native-alias\neptune_umd_arm64.dll';sha256='21EA6DC5C01F627DE665F0D01F5EF89476647F84B56BDC1DE747BDD2D258C6B8';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\present-batch-c19-r1\out\native-alias\neptune_umd_ec.dll';sha256='6333DF83DDD99B8D61432CE15B72C081E43B3A1A847EFFA5085B082CB79ABC02';bytes=1267712},
 [pscustomobject]@{path='C:\codex-woa-umd\resource-opened-init-c20-r1\out\native-alias\neptune_umd.dll';sha256='57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\resource-opened-init-c20-r1\out\native-alias\neptune_umd_arm64.dll';sha256='57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\resource-opened-init-c20-r1\out\native-alias\neptune_umd_ec.dll';sha256='9CC91ED21D0FA367CCF070483A83949C9695504D26CAB4F939E3613A2E598C2D';bytes=1267712},
 [pscustomobject]@{path='C:\codex-woa-umd\video-cpu-setters-c38-r1\out\native-alias\neptune_umd.dll';sha256='1214854B909284D0D9DCF057288A0BA53749F1C7EF24E5654C1D7B77A9C23812';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\video-cpu-setters-c38-r1\out\native-alias\neptune_umd_arm64.dll';sha256='1214854B909284D0D9DCF057288A0BA53749F1C7EF24E5654C1D7B77A9C23812';bytes=1360896},
 [pscustomobject]@{path='C:\codex-woa-umd\video-cpu-setters-c38-r1\out\native-alias\neptune_umd_ec.dll';sha256='027A0433EE195F83E77644E12B79908823879715D04ECDD45DB2132E5DD208C8';bytes=1267712},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-present-batch-c42-r1\out\native-alias\neptune_umd.dll';sha256='5E3DED208360696B5B9CDB11FEDE2FED75BDFFBC41872D1C51F161101762A958';bytes=1360384},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-present-batch-c42-r1\out\native-alias\neptune_umd_arm64.dll';sha256='5E3DED208360696B5B9CDB11FEDE2FED75BDFFBC41872D1C51F161101762A958';bytes=1360384},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-present-batch-c42-r1\out\native-alias\neptune_umd_ec.dll';sha256='A5AF38E4335612A6941781B04BA3EED5181D02DA904BAD903FB51E13B3B1EBCA';bytes=1267712},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-publisher-flush-c43-r1\out\native-alias\neptune_umd.dll';sha256='2294CFCCB45DD32719424240313AE927341D8C7917B9E8CD72B963FF6650F923';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-publisher-flush-c43-r1\out\native-alias\neptune_umd_arm64.dll';sha256='2294CFCCB45DD32719424240313AE927341D8C7917B9E8CD72B963FF6650F923';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\qualified-publisher-flush-c43-r1\out\native-alias\neptune_umd_ec.dll';sha256='1D89B58BCD6E4E44D31DBAFF609956ED95D0A1D5B284812530D5ADD91B2BB1B8';bytes=1276416},
 [pscustomobject]@{path='C:\codex-woa-umd\flush-scope-log-c44-r1\out\native-alias\neptune_umd.dll';sha256='E4A74517AFEFCA69DB18E3F9BBD83AC8090B1CB55915A56F4D076D7B0E9DD25E';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\flush-scope-log-c44-r1\out\native-alias\neptune_umd_arm64.dll';sha256='E4A74517AFEFCA69DB18E3F9BBD83AC8090B1CB55915A56F4D076D7B0E9DD25E';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\flush-scope-log-c44-r1\out\native-alias\neptune_umd_ec.dll';sha256='4B06CA690221FCF6C54A43823CFDF899DB43603556215D6ABD6C0CD8421A6FBF';bytes=1276416},
 [pscustomobject]@{path='C:\codex-woa-umd\unless-no-commands-flush-c45-r1\out\native-alias\neptune_umd.dll';sha256='515D6BA86567BB83A658AA8E8FF641C3A494B776E2904F07EA81A883FBBC0416';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\unless-no-commands-flush-c45-r1\out\native-alias\neptune_umd_arm64.dll';sha256='515D6BA86567BB83A658AA8E8FF641C3A494B776E2904F07EA81A883FBBC0416';bytes=1365504},
 [pscustomobject]@{path='C:\codex-woa-umd\unless-no-commands-flush-c45-r1\out\native-alias\neptune_umd_ec.dll';sha256='F3BF14324F3A0A7471DC656F065C0A399C4EE2356D772CEBC83547805481A711';bytes=1276416}
)
$observed=@()
foreach($e in $expected){
 if(-not[IO.File]::Exists($e.path)){throw ('Required actual C13/C14/C15/R5/C18/C19/C20/C38/C42/C43/C44/C45/F91 artifact absent: '+$e.path)}
 $f=Get-Item -LiteralPath $e.path
 if($f.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Required actual C13/C14/C15/R5/C18/C19/C20/C38/C42/C43/C44/C45/F91 artifact is reparse point'}
 if($f.Length-ne$e.bytes-or(Get-FileHash -LiteralPath $e.path -Algorithm SHA256).Hash-ne$e.sha256){throw ('Required actual C13/C14/C15/R5/C18/C19/C20/C38/C42/C43/C44/C45/F91 artifact differs: '+$e.path)}
 $observed+=[ordered]@{path=$e.path;bytes=$f.Length;sha256=$e.sha256}
}
$proof=Join-Path $Root 'actual-prior-output-preflight.json'
$packetHash=(Get-FileHash -LiteralPath (Join-Path $Root 'stage\packet-manifest.json') -Algorithm SHA256).Hash
$bytes=[Text.UTF8Encoding]::new($false).GetBytes((([ordered]@{status='actual_C13_C14_C15_R5_C18_C19_C20_C38_C42_C43_C44_C45_F91_thirty_seven_artifacts_verified';root=$Root;packetSha256=$packetHash;files=$observed;observedAt=(Get-Date -Format o)}|ConvertTo-Json -Depth 5)+"`r`n"))
$file=[IO.File]::Open($proof,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
'ACTUAL_C13_C14_C15_R5_C18_C19_C20_C38_C42_C43_C44_C45_F91_THIRTY_SEVEN_ARTIFACTS_VERIFIED_BEFORE_PREPARE'
