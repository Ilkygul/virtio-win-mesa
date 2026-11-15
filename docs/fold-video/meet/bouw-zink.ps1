# Zink (OpenGL on Vulkan/Venus) as a WGL ICD for the Fold guest: libgallium_wgl.dll, ARM64.
$ErrorActionPreference = 'Stop'
$Root = 'C:\fold-zink'; $src = 'C:\fold-umd\u49\src'; $log = "$Root\log"
New-Item -ItemType Directory -Force $log | Out-Null
$vsroot = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -products * -latest -property installationPath | Select-Object -First 1
foreach ($line in (cmd /c "`"$vsroot\VC\Auxiliary\Build\vcvarsall.bat`" x64 >nul && set")) { if ($line -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] } }
$tools = 'C:\mesa\tools'; $py = "$tools\py\tools"; $meson = "$py\Scripts\meson.exe"; $ninja = "$tools\ninja\ninja.exe"
$env:PATH = "$py;$py\Scripts;$tools\ninja;$tools\wfb;$env:PATH"; $env:PYTHONUTF8 = '1'; $env:VSLANG = '1033'
$b = "$Root\build-arm64"
if (-not (Test-Path "$b\build.ninja")) {
  & $meson setup $b $src --cross-file C:\fold-umd\u49\arm64-cross.ini --default-library=static -Dbuildtype=release -Db_ndebug=true -Db_vscrt=mt `
    -Dplatforms=windows -Dllvm=disabled -Dgallium-drivers=zink -Dvulkan-drivers= -Dvulkan-layers= -Dtools= -Dvideo-codecs= `
    -Dopengl=true -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dglx=disabled -Dgbm=disabled -Dneptune=false `
    -Dc_args=/experimental:c11atomics *>&1 | Out-File "$log\configure.log" -Encoding UTF8
  if ($LASTEXITCODE) { Get-Content "$log\configure.log" -Tail 30; throw 'configure failed' }
}
& $ninja -C $b -j 8 *>&1 | Out-File "$log\build.log" -Encoding UTF8
if ($LASTEXITCODE) { Get-Content "$log\build.log" -Tail 30; throw 'build failed' }
Get-ChildItem $b -Recurse -Include libgallium_wgl.dll, opengl32.dll | % { "{0} {1} {2}" -f $_.FullName, $_.Length, (Get-FileHash $_.FullName).Hash.Substring(0,12) }
