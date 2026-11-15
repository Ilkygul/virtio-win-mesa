param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $Root 'stage\common-private-umd.ps1')
$Root=Assert-PrivateRoot $Root;Assert-Packet $Root;Assert-PrivateNeptune $Root
$src=Join-Path $Root 'src';$e=Join-Path $Root 'evidence';$version='100.6.101.58200'
$lease=Get-Content (Join-Path $Root 'source-approved.json') -Raw|ConvertFrom-Json
foreach($f in $lease.files){$path=Join-Path $src $f.relative;if((Get-FileHash $path -Algorithm SHA256).Hash-ne$f.sha256){throw ('Private source lease mismatch '+$f.relative)}}
foreach($dir in @('build-arm64','build-arm64ec','prefix-arm64','prefix-arm64ec','out')){if(Test-Path (Join-Path $Root $dir)){throw ('Fresh-only build directory exists '+$dir)}}
New-Item -ItemType Directory $e|Out-Null
$vswhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsroot=& $vswhere -products * -latest -property installationPath|Select-Object -First 1
if(-not $vsroot){throw 'Visual Studio missing'}
foreach($line in (cmd /c "`"$vsroot\VC\Auxiliary\Build\vcvarsall.bat`" x64 >nul && set")){if($line -match '^([^=]+)=(.*)$'){Set-Item -Path "env:$($Matches[1])" -Value $Matches[2]}}
$tools='C:\mesa\tools';$py=Join-Path $tools 'py\tools';$meson=Join-Path $py 'Scripts\meson.exe';$ninja=Join-Path $tools 'ninja\ninja.exe'
$env:PATH="$py;$py\Scripts;$tools\ninja;$tools\wfb;$env:PATH";$env:PYTHONDONTWRITEBYTECODE='1';$env:PYTHONUTF8='1';$env:VSLANG='1033'
$common=@('--default-library=static','-Dbuildtype=release','-Db_ndebug=true','-Dplatforms=windows','-Dvideo-codecs=','-Dllvm=disabled','-Dgallium-drivers=','-Dvulkan-drivers=','-Dvulkan-layers=','-Dtools=','-Dgles1=disabled','-Dgles2=disabled','-Dopengl=false','-Degl=disabled','-Dgbm=disabled','-Dglx=disabled','-Dneptune=true','-Dnpt_wine=false','-Dnpt_umd=ddi',"-Dnpt_umd_version=$version")
$target='src/virtio/neptune/triton/neptune_umd.dll'
# Capture the exact compiler-visible full Neptune source set and tools before msvc.
Copy-Item -LiteralPath (Join-Path $Root 'private-neptune-approved.json') -Destination (Join-Path $e 'compiler-visible-source-hashes.json')
$toolFiles=@($meson,$ninja,(Join-Path $py 'python.exe'))
foreach($a in @('cl.exe','link.exe','lib.exe')){$toolFiles+=Join-Path $vsroot ('VC\Tools\MSVC\14.44.35207\bin\HostX64\ARM64\'+$a)}
@($toolFiles|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})|ConvertTo-Json -Depth 4|Set-Content (Join-Path $e 'toolchain-hashes.json') -Encoding UTF8
function Run-Logged([string]$Exe,[string[]]$Arguments,[string]$Name){
 [ordered]@{exe=$Exe;arguments=$Arguments;started=(Get-Date -Format o)}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $e ($Name+'-command.json')) -Encoding UTF8
 & $Exe @Arguments *>&1|Out-File (Join-Path $e ($Name+'.log')) -Encoding UTF8
 $code=$LASTEXITCODE
 [ordered]@{exit=$code;finished=(Get-Date -Format o)}|ConvertTo-Json|Set-Content (Join-Path $e ($Name+'-exit.json')) -Encoding UTF8
 if($code){Get-Content (Join-Path $e ($Name+'.log')) -Tail 60;throw ($Name+' failed '+$code)}
}
$native=Join-Path $Root 'build-arm64';$ec=Join-Path $Root 'build-arm64ec'
Run-Logged $meson (@('setup',$native,$src,'--cross-file',(Join-Path $Root 'arm64-cross.ini'),'--prefix',(Join-Path $Root 'prefix-arm64'))+$common+@('-Db_vscrt=mt','-Dc_args=/experimental:c11atomics')) 'configure-native'
Run-Logged $ninja @('-C',$native,'-j','6','-v',$target) 'build-native'
Run-Logged $meson (@('setup',$ec,$src,'--cross-file',(Join-Path $Root 'arm64ec-cross.ini'),'--prefix',(Join-Path $Root 'prefix-arm64ec'))+$common+@('-Db_vscrt=md','-Dc_args=/experimental:c11atomics /arm64EC','-Dcpp_args=/arm64EC')) 'configure-ec'
$graph=Join-Path $ec 'build.ninja';$text=[IO.File]::ReadAllText($graph);$fixed=$text -replace '(?i)/MACHINE:ARM64(?![A-Za-z0-9])','/MACHINE:ARM64EC'
if($text-ne$fixed){[IO.File]::WriteAllText($graph,$fixed,(New-Object Text.UTF8Encoding($false)))}
Run-Logged $ninja @('-C',$ec,'-j','6','-v',$target) 'build-ec'
$n=Join-Path $native $target;$c=Join-Path $ec $target
if((Get-Item $n).VersionInfo.FileVersion-ne$version-or(Get-Item $c).VersionInfo.FileVersion-ne$version){throw 'Matching version failed'}
$out=Join-Path $Root 'out\native-alias';New-Item -ItemType Directory $out|Out-Null
Copy-Item $n (Join-Path $out 'neptune_umd.dll');Copy-Item $n (Join-Path $out 'neptune_umd_arm64.dll');Copy-Item $c (Join-Path $out 'neptune_umd_ec.dll')
& dumpbin.exe /headers $n|Out-File (Join-Path $e 'native-headers.txt') -Encoding UTF8
if($LASTEXITCODE){throw 'dumpbin metadata command failed'}
& dumpbin.exe /headers $c|Out-File (Join-Path $e 'ec-headers.txt') -Encoding UTF8
if($LASTEXITCODE){throw 'dumpbin metadata command failed'}
& dumpbin.exe /loadconfig $c|Out-File (Join-Path $e 'ec-loadconfig.txt') -Encoding UTF8
if($LASTEXITCODE){throw 'dumpbin metadata command failed'}
& dumpbin.exe /exports $n|Out-File (Join-Path $e 'native-exports.txt') -Encoding UTF8
if($LASTEXITCODE){throw 'dumpbin metadata command failed'}
& dumpbin.exe /exports $c|Out-File (Join-Path $e 'ec-exports.txt') -Encoding UTF8
if($LASTEXITCODE){throw 'dumpbin metadata command failed'}
Assert-PrivateNeptune $Root

foreach($pair in @(@('native',$n),@('arm64ec',$c))){
 $dest=Join-Path $Root ('out\'+$pair[0]);New-Item -ItemType Directory $dest|Out-Null
 Copy-Item -LiteralPath $pair[1] -Destination (Join-Path $dest 'neptune_umd.dll')
 Get-ChildItem -LiteralPath (Split-Path -Parent $pair[1]) -File -Filter '*.pdb'|Copy-Item -Destination $dest
 & dumpbin.exe /dependents $pair[1]|Out-File (Join-Path $e ($pair[0]+'-dependents.txt')) -Encoding UTF8
 if($LASTEXITCODE){throw 'dumpbin dependents failed'}
}
if((Get-Content (Join-Path $e 'native-headers.txt') -Raw)-notmatch'AA64 machine \(ARM64\)'){throw 'Native AA64 identity failed'}
if((Get-Content (Join-Path $e 'ec-headers.txt') -Raw)-notmatch'8664 machine \(x64\) \(ARM64X\)'){throw 'Matching ARM64X EC identity failed'}
if((Get-Content (Join-Path $e 'ec-loadconfig.txt') -Raw)-notmatch'arm64ec'){throw 'EC hybrid code metadata absent'}
foreach($a in @('native','ec')){if((Get-Content (Join-Path $e ($a+'-exports.txt')) -Raw)-notmatch'OpenAdapter10_2'){throw 'Required D3D11 loader export absent'}}
foreach($f in $lease.files){if((Get-FileHash (Join-Path $src $f.relative) -Algorithm SHA256).Hash-ne$f.sha256){throw ('Source changed during build '+$f.relative)}}
[ordered]@{status='built_not_deployed';version=$version;freshBuilds=$true;files=@(Get-ChildItem $out -File|ForEach-Object{[ordered]@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash;version=$_.VersionInfo.FileVersion}})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Root 'umd-artifact-manifest.json') -Encoding UTF8
'PRIVATE_C15_PUBLISHER_NATIVE_EC_BUILD_ONLY_OK'
