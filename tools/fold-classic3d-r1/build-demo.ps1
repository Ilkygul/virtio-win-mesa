# Build the bundled demo into a NEW directory. No installation or execution.
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$source=Join-Path $PSScriptRoot 'native-present-copy-probe.cpp'
$expected='667F84D52F32EB6B265F03ABB4A45227959DC664814172F595DDA233F733FDEE'
if(-not[IO.File]::Exists($source)-or(Get-FileHash -LiteralPath $source).Hash-cne$expected){throw 'Bundled source exact hash differs'}
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Use a new output directory; no existing outputs are overwritten'}
$vswhere="${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if(-not[IO.File]::Exists($vswhere)){throw 'Existing Visual Studio vswhere required'}
$vsroot=& $vswhere -products * -latest -requires Microsoft.Component.MSBuild -property installationPath|Select-Object -First 1
if(-not$vsroot){throw 'Visual Studio not found'}
$vcvars=Join-Path $vsroot 'VC\Auxiliary\Build\vcvarsall.bat'
if(-not[IO.File]::Exists($vcvars)){throw 'Existing C++ ARM64 build tools required'}
$environmentLines=& cmd.exe /c "`"$vcvars`" x64_arm64 >nul && set"
if($LASTEXITCODE){throw 'ARM64 toolchain initialization failed'}
foreach($line in $environmentLines){if($line-match'^([^=]+)=(.*)$'){Set-Item -Path "env:$($Matches[1])" -Value $Matches[2]}}
$env:VSLANG='1033'
[void](Get-Command cl.exe -ErrorAction Stop);[void](Get-Command dumpbin.exe -ErrorAction Stop)
[void][IO.Directory]::CreateDirectory($destination)
[IO.File]::Copy($source,(Join-Path $destination 'native-present-copy-probe.cpp'),$false)
Push-Location -LiteralPath $destination
try{
 # Exact successful original MSVC command, including library set and debug flags.
 & cl.exe /nologo /std:c++17 /EHsc /O2 /MT /Zi /W4 /Fd:native-present-copy-probe-compiler.pdb /Fe:native-present-copy-probe.exe native-present-copy-probe.cpp /link /DEBUG /PDB:native-present-copy-probe.pdb d3d11.lib dxgi.lib d3dcompiler.lib user32.lib gdi32.lib *>&1 | Tee-Object -FilePath compile-output.log
 $compileExit=$LASTEXITCODE
 if($compileExit){throw ('ARM64 compile failed; preserve log: '+$compileExit)}
 & dumpbin.exe /headers native-present-copy-probe.exe|Out-File pe-headers.txt -Encoding UTF8
 if($LASTEXITCODE){throw 'PE header inspection failed'}
 & dumpbin.exe /imports native-present-copy-probe.exe|Out-File pe-imports.txt -Encoding UTF8
 if($LASTEXITCODE){throw 'PE import inspection failed'}
 if(-not(Select-String -Path pe-headers.txt -Pattern 'AA64 machine')){throw 'Output is not native ARM64'}
 if((Get-FileHash -LiteralPath $source).Hash-cne$expected){throw 'Original package source changed during build'}
 $names=@('native-present-copy-probe.cpp','native-present-copy-probe.exe','native-present-copy-probe.pdb','native-present-copy-probe-compiler.pdb','compile-output.log','pe-headers.txt','pe-imports.txt')
 $files=@($names|ForEach-Object{[ordered]@{name=$_;bytes=(Get-Item -LiteralPath $_).Length;sha256=(Get-FileHash -LiteralPath $_).Hash}})
 $compiler=(Get-Command cl.exe).Source
 [ordered]@{status='BUILT_NOT_RUN_OR_INSTALLED';architecture='ARM64';sourceExpected=$expected;compileExit=$compileExit;compilerPath=$compiler;compilerVersion=([Diagnostics.FileVersionInfo]::GetVersionInfo($compiler)).FileVersion;warnings=@(Get-Content compile-output.log|Where-Object{$_-match'warning [A-Z]+[0-9]+'});files=$files;limits='Local rebuild can differ from release binary hash; do not silently replace the pinned release EXE. No driver or runtime validation.'}|ConvertTo-Json -Depth 6|Set-Content build-manifest.json -Encoding UTF8
 Get-Content build-manifest.json
}finally{Pop-Location}
