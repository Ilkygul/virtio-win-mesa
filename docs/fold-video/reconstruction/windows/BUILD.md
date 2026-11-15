# Reconstruct the tested C46 Windows UMD

This bundle records the actual successful C46 build. It does not install a
driver, change a VM or authorize a build. Native/alias SHA256 is
`2A7DC660ABF7AC3A6B49991C55FC7B44859F670ADE1D9E8033BE7F62B07E744D`
(1,366,528 bytes); ARM64EC is
`0D472DA041603FDF0182FF3D903848E10A4035404E3576C1D0E544B5FE7BBC32`
(1,276,416 bytes). Version is `100.6.101.58200`.

## Source inputs and immutable base revision

- `source443-sha256.json` pins every compiler-visible Neptune source file.
  It matches all 443 actual retrieved C46 files, not a proposed-only tree.
- `c8-to-c46-complete.patch` SHA256
  `8240EEE61E0088BAD6CD3BEB5CF29B29F3B21A1823DBAD865F96269A16C27B41`
  reconstructs C46 from the original C8 snapshot: 27 replacements +3 new
  headers. Apply it only to that original baseline, never to C45/C46/C47.
  The new headers are npt_publisher_batch.h, npt_runtime_stream.h and
  triton/tritonRuntimeWrites.h. ADD entries do not invent baseline hashes.
- `inputs/original-neptune-hashes.json` pins all 440 original C8 files;
  `inputs/original-c8-source-leases.json` pins affected baseline paths.
- A complete Mesa source checkout is required around `src/virtio/neptune`.
  This package is not a standalone Neptune-only build project. The actual
  original source was `C:\mesa\src`, upstream `osy/virtio-win-mesa` commit
  `fc5f1fc8a389e125e7d5f979f7b88a2708d161ee` with pre-existing local changes.
  The retained compiler-visible postimages are now committed in this repository
  at `27cbe9982e4255b727878f34d5e582a1f99ccab8`; use that source and the
  exact companion `wddm_hw.h` supplied here (Git blob
  `35dac98e642a25acfc70bdf4a7f41d221b1f073d`, already identical in that commit). All440 original snapshot files
  were re-read on the build VM and matched the original C46 build inventory.
  A bare upstream HEAD alone omits the dirty baseline; the final443 manifest
  and committed postimages are authoritative. Uncompiled experimental Venus
  guest changes from the original worktree are not compiled by this D3D11
  recipe (`-Dvulkan-drivers=`). They remain historical source in the branch;
  no Vulkan validation or removal is implied. `inputs/wddm_hw.h` is the exact retrieved companion header at
  `src/virtio/virtio-gpu/wddm_hw.h` in the full tree.

If using the published already-C46 source, do not reapply the patch. Before
compiling, verify the exact file set and all source hashes in PowerShell:

```powershell
$src = 'C:\codex-repro\c46-r1\src' # complete, owned full Mesa source tree
$bundle = 'C:\codex-repro\c46-windows'
$pins = Get-Content -LiteralPath "$bundle\source443-sha256.json" -Raw | ConvertFrom-Json
$neptune = Join-Path $src 'src\virtio\neptune'
$expected = @($pins.files | ForEach-Object { $_.path.Substring('src/virtio/neptune/'.Length).Replace('/','\') })
$actual = @(Get-ChildItem -LiteralPath $neptune -File -Recurse -Force | ForEach-Object { $_.FullName.Substring($neptune.Length+1) })
if (@(Compare-Object $expected $actual).Count) { throw 'Neptune source set differs' }
foreach ($f in $pins.files) {
  $p = Join-Path $src ($f.path.Replace('/','\'))
  if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.proposedSha256 -or (Get-Item -LiteralPath $p).Length -ne $f.proposedBytes) { throw "Source mismatch: $($f.path)" }
}
```

## Actual compiler, SDK and commands

Tested tools: VS2022 Build Tools MSVC **14.44.35207** (HostX64/ARM64), Windows
SDK **10.0.26100.0**, the Meson/Ninja/Python tools under `C:\mesa\tools`.
`inputs/toolchain-hashes.json` contains their actual hashes. The crossfiles
preserve exact MSVC/SDK library paths; changing tool versions is a new build
environment, not a byte-for-byte binary reproduction guarantee.

`actual-commands/` records the four real configure/build invocations. Below
are the same configure flags, target, concurrency and scoped EC graph
correction with only a fresh output/source prefix. Run in an x64 VS developer
PowerShell environment initialized with the matching vcvarsall.bat. The
recorded build script shows the exact environment initialization. These
publication instructions have not themselves been executed as another build.

```powershell
$Root = 'C:\codex-repro\c46-r1'
$src = Join-Path $Root 'src'
$bundle = 'C:\codex-repro\c46-windows'
$meson = 'C:\mesa\tools\py\tools\Scripts\meson.exe'
$ninja = 'C:\mesa\tools\ninja\ninja.exe'
$env:PATH = 'C:\mesa\tools\py\tools;C:\mesa\tools\py\tools\Scripts;C:\mesa\tools\ninja;C:\mesa\tools\wfb;' + $env:PATH
$env:PYTHONDONTWRITEBYTECODE = '1'; $env:PYTHONUTF8 = '1'; $env:VSLANG = '1033'
foreach ($dir in @('build-arm64','build-arm64ec','prefix-arm64','prefix-arm64ec')) {
  if (Test-Path -LiteralPath (Join-Path $Root $dir)) { throw "Fresh output required: $dir" }
}
Copy-Item -LiteralPath "$bundle\recipes\arm64-cross.ini" -Destination "$Root\arm64-cross.ini"
Copy-Item -LiteralPath "$bundle\recipes\arm64ec-cross.ini" -Destination "$Root\arm64ec-cross.ini"
$common = @('--default-library=static','-Dbuildtype=release','-Db_ndebug=true','-Dplatforms=windows','-Dvideo-codecs=','-Dllvm=disabled','-Dgallium-drivers=','-Dvulkan-drivers=','-Dvulkan-layers=','-Dtools=','-Dgles1=disabled','-Dgles2=disabled','-Dopengl=false','-Degl=disabled','-Dgbm=disabled','-Dglx=disabled','-Dneptune=true','-Dnpt_wine=false','-Dnpt_umd=ddi','-Dnpt_umd_version=100.6.101.58200')
$target = 'src/virtio/neptune/triton/neptune_umd.dll'
$native = Join-Path $Root 'build-arm64'; $ec = Join-Path $Root 'build-arm64ec'
& $meson (@('setup',$native,$src,'--cross-file',"$Root\arm64-cross.ini",'--prefix',"$Root\prefix-arm64")+$common+@('-Db_vscrt=mt','-Dc_args=/experimental:c11atomics'))
if ($LASTEXITCODE) { throw 'Native configure failed' }
& $ninja '-C' $native '-j' '6' '-v' $target
if ($LASTEXITCODE) { throw 'Native build failed' }
& $meson (@('setup',$ec,$src,'--cross-file',"$Root\arm64ec-cross.ini",'--prefix',"$Root\prefix-arm64ec")+$common+@('-Db_vscrt=md','-Dc_args=/experimental:c11atomics /arm64EC','-Dcpp_args=/arm64EC'))
if ($LASTEXITCODE) { throw 'EC configure failed' }
$graph = Join-Path $ec 'build.ninja'
$text = [IO.File]::ReadAllText($graph)
$fixed = $text -replace '(?i)/MACHINE:ARM64(?![A-Za-z0-9])','/MACHINE:ARM64EC'
if ($text -ne $fixed) { [IO.File]::WriteAllText($graph,$fixed,(New-Object Text.UTF8Encoding($false))) }
& $ninja '-C' $ec '-j' '6' '-v' $target
if ($LASTEXITCODE) { throw 'EC build failed' }
```

Native output is `$native\$target`; EC output is `$ec\$target`. The tested
package uses native bytes as both `neptune_umd.dll` and
`neptune_umd_arm64.dll`, with EC as `neptune_umd_ec.dll`. It does not generate
a new forwarder. Verify version, native AA64, EC 8664/ARM64X + CHPE version2,
OpenAdapter10_2/OpenAdapter12 and complete source hashes after build. The
actual release build emitted no PDB and retained 14 known warnings per
architecture; neither absence of warnings nor bit-identical output with a
different toolchain is promised.

## Archived private recipes and intentionally omitted input

`recipes/` contains the exact successful build/finalize/failure bodies, both
crossfiles, common/prepare/parser/prior-output scripts. These are historical
protected-session scripts, not a standalone public launcher: they require a
fixed private root, an exact full packet, a PS5.1 parse receipt, fresh prior37
output proofs and protected-source/output manifests. The included historical
packet manifest identifies those original members; it is not the manifest of
this smaller publication bundle. Do not fabricate receipts or remove their
gates to run them. The direct build commands above document the compiler
operation independently of those session-specific protections.

One of the historical six recipe files is deliberately not copied:
`win-build-transport.py` (SHA256
`FC38EB539DBA0649EAE8FD7CD457A728B0CD3B356005254835071A7E4D48BF64`)
contains a personal known-hosts path and private SSH jump-host/user settings.
It performs transport only and is unnecessary for a direct Windows build.
Private lease, host-controller, full VM config, protection snapshots, signing
keys and historical output trees are excluded. A public protected-session
launcher would additionally need freshly generated local parse/input/output
proofs; this bundle does not claim to provide those.

C47 and parked C48 are excluded. Host C37, C33 DXVK and signed F91 KMD have
their own source/build provenance; this Windows package does not rebuild them.
