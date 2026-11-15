# Retained Fold stack: C46 / F91 / C37 / C33

**Partial result; general goal open.** The native Windows UI correction and complete direct hardware3D are retained. Video still stutters and the known RES_INFO/readback GPU loss is unresolved. This is an experimental preservation package for the existing separate test VM, not a stable or production driver installer. The earlier classic-titlebar demo remains a separate limited release.

C47 was actually installed, loaded after normal reboot and tested at identical RAM4/DPI200/native landscape/960×640/privatecopy0/vsync1: **27.1571 API-fps versus C46 27.5761**. Both bounded scenes had complete visible geometry and no new GPU error; neither was smooth60. C47/C48 optimization work is parked.

## Exact retained code

| Component | Actual published commit |
|---|---|
| windows | [27cbe9982e42](https://github.com/Ilkygul/virtio-win-mesa/commit/27cbe9982e4255b727878f34d5e582a1f99ccab8) |
| kmd | [925658417bde](https://github.com/Ilkygul/viogpu3d-pvm/commit/925658417bde30c74ae1069fa5dc8eb08516a7cf) |
| virgl | [43753f2ffb42](https://github.com/Ilkygul/virglrenderer/commit/43753f2ffb42a9a3627a9ea708961efb162c8edc) |
| dxvk | [b7e4b740e589](https://github.com/Ilkygul/dxvk/commit/b7e4b740e589a83cdae360b7e57978e4c32634e2) |
| rust | [75203094a002](https://github.com/Ilkygul/crosvm/commit/75203094a00250cecdf5da90f92ba1d7edb00f47) |

The Windows443, kernel104, renderer707, DXVK1268 and crosvm1856 source entries have published byte/mode manifests. Host snapshot tree hashes were verified on GitHub against actual compiled source archives. Original shallow history is not invented. The F91 publication repository is a chosen snapshot destination; original KMD ancestry was not attested.

## Reconstruct and restore

1. Use the source commits above or download the exact source assets from the experimental release. The C15 source archive also supplies the minigbm/minijail sibling sources; C37 and C33 archives are already the final postimages. Do not reapply historical patches over final snapshots.
2. Follow [Windows build commands](windows/BUILD.md), [host build commands and cache policy](host/BUILD.md), and [F91 subset/rebuild limits](kmd/README.md). These preserve the actual compiler commands and prerequisites; they do not claim a new clean-room build or production signing.
3. Verify downloaded runtime bytes with the included SHA256SUMS and runtime-manifest. The package contains the three C46 UMDs, existing signed F91, C37 renderer/server, matched C33 DXVK pair and crosvm6AC. Keep the pair together and retain the matching pre-existing DroidVM/Turnip/kernel environment pinned in host-platform-pins.json. It is not a self-contained Android platform.
4. Use the dedicated test VM, private VARS and cold rollback. Before changing host libraries, request normal Windows shutdown, then verify full VMM/native/maps/disk/VARS descriptor drain. Never unload the pool with active mappings. Never reuse a child after its parent has been opened writable. Stage new bytes in fresh private paths and preserve original ACL/ownership/SELinux state.
5. Apply only the configuration subset in configuration.example.json to the matching existing test setup. Start the same owned VM, verify actual disk/VARS descriptors, new Windows boot, F91 signature/Code0 and the actually loaded native UMD before enabling the qualified mode. The code uses the existing kernel service and architecture-specific DriverStore paths; these are not generic copy-to-System32 instructions.

The actual protected UMD installation command journal was: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <fresh-bound-run>/parse-and-preflight.ps1`, then the same invocation of `<fresh-bound-run>/install-umds.ps1`, followed by normal `shutdown.exe /s /t 0`. The existing [historical protected transaction templates](installation-templates/README.md) are archived here. Those helpers consume fresh externally pinned scope/boot/artifact facts; old bound receipts are not reusable launchers. No automatic installer or trust-policy change is shipped.

Use an isolated C33 shader cache: FP32 lowering changed without a new old-option cache-key bit. C34 is untested and excluded. Existing working C33 cache is retained; personal cache contents are not published.

## What currently works and what remains

Unmodified Task Manager and Start became readable with the C33 correction; the ordinary native driver path is retained. Direct15-cube3D gives complete pictures but about27–28API-fps. Edge uses the QTI AV1 hardware decode path at low Windows CPU, but about27–31 nondropped browserframes/s with many drops and visible hitches. No general application or smooth60 claim is made.

A diagnostic READ Map of17,132,544bytes encountered a failing32MiB RES_INFO/shmem operation, normalized to E_OUTOFMEMORY/deviceRemoved and an Edge GPU-process exit. A later32MiB mapping succeeded. Extra RAM and a successful repetition are not repair proof; the first underlying mapping failure remains the next stability task. One older startup MEMORY_MANAGEMENT crash is also unexplained.

C46/RAM4 is actually restored on the Fold; C47 is retired after its parent resumed writable operation. Production Windows disk is protected. See the single current status at [experiment-register.md](../experiment-register.md); older decisions there are history.
