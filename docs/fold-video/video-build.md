# Build the Triton C4 video-view fix

This builds the native Windows Triton UMD from `Ilkygul/virtio-win-mesa`, branch `venus-pvm`, with the reviewed video-view lifetime/rebinding patch. Use a dedicated source checkout containing that patch and two fresh build directories. Do not substitute a later combined driver source tree for the minimal video-only change.

The progress branch is `codex/video-view-lifetime-20261113`, based on
`venus-pvm` commit `7aa561423dc52adf1e8088877da3816c4f32c189`.
The expected SHA256 of `src/virtio/neptune/triton/tritonVideo.c` is
`3AF92E7A74FEF55820231CEA66F87B7816E227F6F3C2A9BD731883D768A8E055`.
For a new checkout, run:

```powershell
git clone --branch codex/video-view-lifetime-20261113 --single-branch `
    https://github.com/Ilkygul/virtio-win-mesa.git C:\work\mesa-video-c4
if ($LASTEXITCODE) { throw 'Clone failed' }
git -C C:\work\mesa-video-c4 rev-parse HEAD
Get-FileHash C:\work\mesa-video-c4\src\virtio\neptune\triton\tritonVideo.c -Algorithm SHA256
```

The original combined C4 native ARM64 and ARM64EC builds were built and exercised in video tests. Later combined C8 sources retain the same C4 `tritonVideo.c` implementation. The minimal video-only publication against `venus-pvm` has **not** received a new binary build/runtime test. Historical results do not certify this independently reconstructed package, fix the remaining presentation artifacts, or establish support for additional codecs.

## Inputs and tools

The observed Windows build environment used:

- Visual Studio 2022 Build Tools, MSVC toolset `14.44.35207` / compiler `19.44.35230`, including ARM64 and ARM64EC tools/libraries.
- Windows SDK/WDK `10.0.26100.0`, including the D3D UMD DDI headers, resource compiler and ARM64/x64 import libraries.
- Python `3.12.8`, Meson `1.12.1`, Ninja `1.12.1`; Mesa's Python generator dependencies and its normal subproject dependencies must be available. Preserve the dependency versions/checksums used by the checkout, including the zlib fallback when required.

These are Meson/Ninja UMD builds. They do not invoke an MSBuild KMD project, rebuild a `.sys`, run driver packaging, sign a driver, or change an INF. MSBuild can be installed with Visual Studio, but there is no MSBuild command in this procedure.

Use the installed SDK/WDK headers through the developer environment. Do not publish Microsoft header copies, signing assets or machine certificates. If headers such as `d3d10umddi.h` are missing, repair the local SDK/WDK installation or its include paths before proceeding.

The build options and target below come from the current repository's [Meson options](https://github.com/Ilkygul/virtio-win-mesa/blob/venus-pvm/meson.options), [Neptune build](https://github.com/Ilkygul/virtio-win-mesa/blob/venus-pvm/src/virtio/neptune/meson.build) and [Triton target](https://github.com/Ilkygul/virtio-win-mesa/blob/venus-pvm/src/virtio/neptune/triton/meson.build). The version resource is [neptune_umd.rc](https://github.com/Ilkygul/virtio-win-mesa/blob/venus-pvm/src/virtio/neptune/triton/neptune_umd.rc).

## Isolate the workspace

Example layout; replace the paths and package version with your own reviewed inputs:

```text
C:\work\mesa-video-c4\                 dedicated patched venus-pvm checkout
C:\work\video-c4-build\
  arm64-cross.ini
  arm64ec-cross.ini
  build-arm64\
  build-arm64ec\
  prefix-arm64\
  prefix-arm64ec\
  out\native-alias\
  out\arm64x\                         optional, separate loader layout
```

Before building, record the source revision, reviewed patch/diff and source hashes. Confirm that `src/virtio/neptune/triton/tritonVideo.c` contains the C4 change and that unrelated C5–C8 diagnostics are absent from a video-only publication. Preserve the source file's encoding/line endings; do not replace it with a whole-file snapshot from a different combined checkout.

Record hashes and file lists for existing shared sources, build outputs and installed/staged driver packages. Compare them after the build. The source checkout, both build trees, prefixes, logs and output directories in this procedure must belong to this build. Do not reuse or clean another build directory, reset existing sources, overwrite shared outputs, or invoke a generic packaging wrapper that clears them.

## Configure the compiler environments

Run in Windows PowerShell. `meson`, `ninja` and the selected Python environment must already be on `PATH`. All generated files stay under the new build root.

```powershell
$ErrorActionPreference = 'Stop'
$Src = 'C:\work\mesa-video-c4'
$Root = 'C:\work\video-c4-build'
$DriverVersion = '<INF_VERSION>'  # four numbers; match the intended KMD/INF package
$SdkVersion = '10.0.26100.0'
$SdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
if ($DriverVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Set the package version first' }
if (Test-Path $Root) { throw 'Use a fresh, dedicated build root' }
New-Item -ItemType Directory $Root | Out-Null

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$VsRoot = & $vswhere -products * -latest -property installationPath | Select-Object -First 1
if (-not $VsRoot) { throw 'Visual Studio not found' }
function Get-VcEnvironment([string]$Arch) {
    $result = @{}
    foreach ($line in (cmd /c "`"$VsRoot\VC\Auxiliary\Build\vcvarsall.bat`" $Arch >nul && set")) {
        if ($line -match '^([^=]+)=(.*)$') { $result[$Matches[1]] = $Matches[2] }
    }
    if (-not $result.ContainsKey('INCLUDE')) { throw 'Developer environment failed' }
    return $result
}
$ArmEnvironment = Get-VcEnvironment 'x64_arm64'
$BuildEnvironment = Get-VcEnvironment 'x64'
foreach ($entry in $BuildEnvironment.GetEnumerator()) {
    Set-Item -Path ('env:' + $entry.Key) -Value $entry.Value
}
$env:PYTHONUTF8 = '1'
$ArmBin = $ArmEnvironment['PATH'] -split ';' |
    Where-Object { $_ -and (Test-Path (Join-Path $_ 'cl.exe')) } |
    Select-Object -First 1
if (-not $ArmBin) { throw 'ARM64 cross compiler not found' }
$VcLib = [IO.Path]::GetFullPath((Join-Path $ArmBin '..\..\..\lib'))

$NativeLibs = @(
    (Join-Path $VcLib 'arm64'),
    (Join-Path $SdkRoot "Lib\$SdkVersion\ucrt\arm64"),
    (Join-Path $SdkRoot "Lib\$SdkVersion\um\arm64")
)
$EcLibs = @(
    (Join-Path $VcLib 'arm64'),
    (Join-Path $VcLib 'arm64ec'),
    (Join-Path $VcLib 'x64'),
    (Join-Path $SdkRoot "Lib\$SdkVersion\ucrt\x64"),
    (Join-Path $SdkRoot "Lib\$SdkVersion\um\x64")
)
foreach ($dir in @($NativeLibs + $EcLibs | Select-Object -Unique)) {
    if (-not (Test-Path $dir)) { throw "Missing target library directory: $dir" }
}
if (-not (Test-Path (Join-Path $VcLib 'arm64\msvcrt.lib'))) {
    throw 'Mixed ARM64/ARM64EC CRT archive missing'
}
function Write-CrossFile([string]$Path, [string[]]$Libraries, [bool]$Ec) {
    $linkArgs = @($Libraries | ForEach-Object { "'/LIBPATH:$_'" })
    if ($Ec) { $linkArgs += "'/MACHINE:ARM64EC'" }
    $linkText = $linkArgs -join ', '
    @"
[binaries]
c = '$ArmBin\cl.exe'
cpp = '$ArmBin\cl.exe'
ar = '$ArmBin\lib.exe'
c_ld = '$ArmBin\link.exe'
cpp_ld = '$ArmBin\link.exe'
pkg-config = 'false'
[built-in options]
c_link_args = [$linkText]
cpp_link_args = [$linkText]
[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
"@ | Set-Content -LiteralPath $Path -Encoding ascii
}
Write-CrossFile (Join-Path $Root 'arm64-cross.ini') $NativeLibs $false
Write-CrossFile (Join-Path $Root 'arm64ec-cross.ini') $EcLibs $true
```

The EC library order above is intentional for the observed MSVC toolset: the `arm64` CRT archives contain ARM64EC members, followed by the EC import libraries and x64-ABI SDK libraries. A plain x64 DLL is not an ARM64EC replacement. Check the actual installed library contents/toolset when using another version; do not remove a global SDK or silently mix an older payload into the package.

## Build matching native ARM64 and ARM64EC payloads

Continue in the same PowerShell session:

```powershell
$Target = 'src/virtio/neptune/triton/neptune_umd.dll'
$NativeBuild = Join-Path $Root 'build-arm64'
$EcBuild = Join-Path $Root 'build-arm64ec'
$Common = @(
    '--default-library=static', '-Dbuildtype=release', '-Db_ndebug=true',
    '-Dplatforms=windows', '-Dvideo-codecs=', '-Dllvm=disabled',
    '-Dgallium-drivers=', '-Dvulkan-drivers=', '-Dvulkan-layers=', '-Dtools=',
    '-Dgles1=disabled', '-Dgles2=disabled', '-Dopengl=false', '-Degl=disabled',
    '-Dgbm=disabled', '-Dglx=disabled', '-Dneptune=true', '-Dnpt_wine=false',
    '-Dnpt_umd=ddi', "-Dnpt_umd_version=$DriverVersion"
)
& meson setup $NativeBuild $Src --cross-file (Join-Path $Root 'arm64-cross.ini') `
    --prefix (Join-Path $Root 'prefix-arm64') @Common `
    -Db_vscrt=mt '-Dc_args=/experimental:c11atomics'
if ($LASTEXITCODE) { throw 'Native configure failed' }
& ninja -C $NativeBuild -j 6 $Target
if ($LASTEXITCODE) { throw 'Native build failed' }

& meson setup $EcBuild $Src --cross-file (Join-Path $Root 'arm64ec-cross.ini') `
    --prefix (Join-Path $Root 'prefix-arm64ec') @Common `
    -Db_vscrt=md '-Dc_args=/experimental:c11atomics /arm64EC' '-Dcpp_args=/arm64EC'
if ($LASTEXITCODE) { throw 'EC configure failed' }

# Meson identifies this compiler as ARM64 and can emit the wrong machine
# option for static archives. Correct only this dedicated EC build graph.
$EcNinja = Join-Path $EcBuild 'build.ninja'
$text = [IO.File]::ReadAllText($EcNinja)
$fixed = $text -replace '(?i)/MACHINE:ARM64(?![A-Za-z0-9])', '/MACHINE:ARM64EC'
if ($fixed -ne $text) {
    [IO.File]::WriteAllText($EcNinja, $fixed, (New-Object Text.UTF8Encoding($false)))
}
& ninja -C $EcBuild -j 6 $Target
if ($LASTEXITCODE) { throw 'EC build failed' }
```

Recheck the generated EC machine options after any Meson regeneration. Do not apply this replacement to native output, source files or another build. Fresh build trees rebuild every translation unit and all private view wrappers consistently for each architecture. `-Dvideo-codecs=` disables unrelated Mesa codec frontends; it does not remove `tritonVideo.c` from the Triton target.

Keep the complete configure/build output, `meson-logs`, compiler/linker versions and final source hashes. The current Triton Meson target intentionally uses `/FORCE:MULTIPLE` and `/IGNORE:4006` for repeated DDI constants; historical builds emitted `LNK4088`. Record that warning rather than claiming a warning-free UMD build. A successful link alone is not a runtime test.

## Package the native-alias layout

```powershell
$Native = Join-Path $NativeBuild $Target
$Ec = Join-Path $EcBuild $Target
foreach ($file in @($Native, $Ec)) {
    if ((Get-Item $file).VersionInfo.FileVersion -ne $DriverVersion) {
        throw "Payload version mismatch: $file"
    }
}
$Alias = Join-Path $Root 'out\native-alias'
New-Item -ItemType Directory $Alias | Out-Null
Copy-Item $Native (Join-Path $Alias 'neptune_umd.dll')
Copy-Item $Native (Join-Path $Alias 'neptune_umd_arm64.dll')
Copy-Item $Ec (Join-Path $Alias 'neptune_umd_ec.dll')
Get-ChildItem $Alias -File | Get-FileHash -Algorithm SHA256
```

In this layout, `neptune_umd.dll` and `neptune_umd_arm64.dll` are byte-identical native ARM64 payloads. The EC payload is separate. Keep the intended existing loader/registration layout; building a different layout does not authorize changing driver registration.

For an **optional separate ARM64X forwarder package**, the current repository provides [make-arm64x.bat](https://github.com/Ilkygul/virtio-win-mesa/blob/venus-pvm/src/virtio/neptune/triton/tools/make-arm64x.bat):

```powershell
$ForwarderOutput = Join-Path $Root 'out\arm64x'
$Packager = Join-Path $Src 'src\virtio\neptune\triton\tools\make-arm64x.bat'
& cmd /c "`"$Packager`" `"$Native`" `"$Ec`" `"$ForwarderOutput`""
if ($LASTEXITCODE) { throw 'ARM64X forwarder packaging failed' }
foreach ($file in Get-ChildItem $ForwarderOutput -File -Filter '*.dll') {
    if ($file.VersionInfo.FileVersion -ne $DriverVersion) { throw 'Forwarder/payload version mismatch' }
}
```

That directory contains an ARM64X `neptune_umd.dll` forwarder plus `_arm64` and `_ec` payloads. Its export list comes from the same source `.def`; its version resource must match both payloads and the intended INF/KMD version. Keep it separate from the native-alias directory.

Use `dumpbin /headers` on both payloads and any forwarder, `dumpbin /loadconfig` on the EC payload, and `dumpbin /exports` on the forwarder. Native ARM64 is `AA64`; the observed EC payload reports `8664` with hybrid metadata, so `8664` alone does not prove it is ARM64EC. Save hashes, sizes, file versions and these PE reports locally. Recheck protected shared sources/output file lists and hashes before releasing the build workspace.

## On-demand build-host lifecycle

When using a shared build PC, use its approved wake mechanism only when this build is needed. Take its build lock before copying or building and start the existing Windows build VM directly. Do not use a generic driver build/package wrapper for this standalone UMD procedure. For a host providing the existing helpers, the lifecycle is:

```sh
~/bin/bouw-lock take video-c4 "isolated C4 UMD build"
~/winbuild/vm.sh start
# Run the dedicated Windows Meson/Ninja build; retrieve and verify artifacts.
# Confirm no other build jobs need the VM before stopping it.
~/winbuild/vm.sh stop
# Verify the clean stop completed, then release the lease.
~/bin/bouw-lock release video-c4
~/bin/bouw-pc-uit
```

Respect a refused stop/poweroff or another owner's lock; do not force it. Collect and verify artifacts before shutdown. Do not leave the VM/PC on by default after the session. Publication should contain the reviewed source change and these instructions, not local binaries, signing material, machine identifiers or raw private logs.
