# Tested C46 host set — prerelease source/build notes

This bundle describes the tested C46 Windows UMD + F91 KMD + C37 renderer + C33 FP32 DXVK combination. It is a feature-branch prerelease, not a production driver release. It starts no build or installation. The published snapshot commits are bound in `manifests/source-pins.json`; their complete Git trees match the archived compiled sources.

## Exact source state

The original PC repositories were shallow. Their recorded bases are:

| Component | Actual remote | Original HEAD |
|---|---|---|
| crosvm | `https://github.com/Droid-VM/crosvm` | `8db213546ca924a33ce5c14dfb04efbce9badadb` |
| Virgl/Neptune | `https://github.com/Droid-VM/virglrenderer` | `4d54b39e7ec8733faf9ebe97de0a217fbe7bbb53` |
| DXVK | `https://github.com/osy/dxvk` | `c8cf25a65f4151634b4e8ab4ad48fc37937d63be` |

These unpublished HEADs are provenance, not guaranteed fetchable revisions. Selected Git bundles preserve the objects present on the PC, but cannot supply ancestors missing beyond its shallow boundaries. Use the published snapshot commits below; complete original history is not claimed.

| Retained final source | Published commit |
|---|---|
| virgl | [43753f2ffb42](https://github.com/Ilkygul/virglrenderer/commit/43753f2ffb42a9a3627a9ea708961efb162c8edc) |
| dxvk | [b7e4b740e589](https://github.com/Ilkygul/dxvk/commit/b7e4b740e589a83cdae360b7e57978e4c32634e2) |
| rust | [75203094a002](https://github.com/Ilkygul/crosvm/commit/75203094a00250cecdf5da90f92ba1d7edb00f47) |

These are already the **final compiled postimages**. Do not reapply C15, C33 or C37 patches to them. The patch sequence below describes historical reconstruction only. The DXVK snapshot includes the recorded source subprojects; the Rust source preserves its sibling dependency symlinks. The release source archives also retain the original minigbm/minijail source contents needed at those sibling paths.

The C15 compiled source snapshot already includes four Rust postimages, 36 Virgl postimages, six terminal-video DXVK postimages, and the original dirty DXVK working overlay. The four exact Rust files are in `source-overlays/c15-rust`; the complete manifests identify the other postimages. A clean upstream HEAD plus only the latest patch is insufficient.

For C37, start with that C15 Virgl snapshot and apply the six patches in `manifests/source-pins.json` order: C19 atlas trace, C24 Draw/input trace, C25 DXBC capture, C22 checkpoint telemetry, C36 ready wake, C37 bounded GPU polling. The union is seven final files in a 707-entry compiler source snapshot. The historical builder uses these final postimages, not a fresh patch search.

For C33, start with the exact F19/C15 DXVK snapshot, including its five original dirty source files and terminal R4 changes. Apply `patches/c33/minprecision-fp32.patch`; only `src/dxvk/dxvk_shader_ir.cpp` changes, with 1267 entries unchanged. `original-working-overlay.patch` records the pre-existing overlay and must not be applied a second time over the compiled C15 snapshot. Explicit native F16 and integer options retain their existing behavior. C34 cache-key and C47/C48 optimization proposals are not included.

`recipes/` contains byte-exact copies of the actual historical scripts and crossfile. Their original private paths, fresh-root checks and local lease contracts are retained as evidence. They are not portable installers and must not be run against the old build roots. No WOL, SSH/SCP, host-IP, daemon credential, private key, VM disk or VARS file is included.

## Dependencies and toolchain

Use the Android/AOSP Soong environment that supplies the existing `crosvm_device_only_bin`, `libvirglrenderer` and `virgl_render_server` targets. The tested image ID is `sha256:c522b381183b9094b0b3596a7c97db160d90cc737998fb9fa17aa3a6fba71f55`. Native display client source/static-archive hashes and Android config hashes are in `manifests/toolchain-pins.json`.

Keep `external/minigbm` at `b7c93249f685222a524c51403719493cc114ff5d` and `external/minijail` at `ab6cd0f786481e2deecfe6f8563ae0d2416bd460`. Preserve crosvm's disclosed sibling links to those trees and the selected patched Virgl tree. Keep the generated `power_monitor/out/generated.rs` input; it may legally be empty. Do not import old compiler objects as new build evidence.

DXVK uses Linux x86-64-host Android NDK **28.2.13676358**, target **API30/AArch64**, Meson 1.12.1 and Ninja 1.13.2.git.kitware.jobserver-pipe-1. Tool hashes, versions and the three source subprojects are recorded. Build both D3D11 and DXGI from the same fresh source/object tree; their internal class ABI is paired.

The historical Soong build used a protected read-only lower dependency output tree with private COW changes. This bundle does not contain a complete AOSP platform manifest or prove an independent clean-room, bit-for-bit rebuild. Its exact binary hashes identify the tested outputs; new builds must record their own outputs honestly.

## Direct build commands in a fresh workspace

The following are compiler commands, not device commands. Use the pinned snapshot commits and a fresh, writable build workspace. Never reuse a historical private build directory. Place the selected source snapshots in the AOSP `external/crosvm` and `external/virglrenderer` locations, preserving the dependency topology above.

```sh
cd "$AOSP_WORKSPACE"
source build/envsetup.sh
lunch aosp_arm64 trunk_staging eng
NINJA_ARGS="-k 0" ALLOW_MISSING_DEPENDENCIES=true TARGET_BUILD_UNBUNDLED=true \
  m out/soong/.intermediates/external/crosvm/crosvm_device_only/crosvm_device_only_bin/android_arm64_armv8-a/crosvm \
    out/soong/.intermediates/external/virglrenderer/libvirglrenderer/android_arm64_armv8-a_shared/libvirglrenderer.so \
    out/soong/.intermediates/external/virglrenderer/virgl_render_server/android_arm64_armv8-a/virgl_render_server -j8
```

C37 itself rebuilt only the latter two targets; crosvm remained the selected C15/6AC binary. A new three-target build is a new build result, not proof that its crosvm hash must equal the historical binary.

For the matched DXVK pair, use a fresh source checkout and build directory. Set `ANDROID_NDK_HOME` to NDK28.2.13676358 and `DXVK_SOURCE` to the published C33 snapshot. The copied crossfile is exact historical evidence; change only its NDK installation prefix for the new host:

```sh
test -n "${ANDROID_NDK_HOME:?}" && test -n "${DXVK_SOURCE:?}" && test -n "${BUILD_WORKSPACE:?}"
test ! -e "$BUILD_WORKSPACE/dxvk-build"
sed "s|/home/igul/droidvm-build/android-sdk/ndk/28.2.13676358|$ANDROID_NDK_HOME|g" \
  recipes/c33/android-aarch64.effective.txt > "$BUILD_WORKSPACE/android-aarch64.txt"
meson setup "$BUILD_WORKSPACE/dxvk-build" "$DXVK_SOURCE" \
  --cross-file "$BUILD_WORKSPACE/android-aarch64.txt" \
  -Dbuildtype=release -Dnative_headless=true \
  -Dnative_sdl2=disabled -Dnative_sdl3=disabled -Dnative_glfw=disabled \
  -Denable_d3d8=false -Denable_d3d9=false -Denable_d3d10=false -Db_ndebug=true \
  --wrap-mode=nodownload
ninja -C "$BUILD_WORKSPACE/dxvk-build" -j8
```

Dependencies must already be present; do not silently download different subprojects. Preserve both unstripped libraries. Pack only new copies with `llvm-strip --strip-unneeded`, then `patchelf --set-rpath '$ORIGIN'` with literal `$ORIGIN`. Record `llvm-readelf -h -d -n` output and verify ELF64 little-endian AArch64 for every Android artifact. Keep compiler warnings and effective options. The C33 receipts retain 287 warning lines and 237 new objects/archives.

## Build output versus installation

`SHA256SUMS-tested-host-binaries.txt` and `manifests/tested-host-binaries.json` identify the five tested Android outputs. Run `sha256sum -c` in a directory containing those files; this verifies files and installs nothing. Keep the C33 D3D11/DXGI pair together. Use the C46 native/alias/EC DLLs and F91 SYS identified in `RELEASE-ASSETS.md`; host binaries alone do not replace the Windows driver.

Installation is a separately approved, reversible test-overlay operation. Use a dedicated test child and private VARS, retain the original/base chain read-only, and keep an exact rollback config and five-file backup. Normal Windows shutdown and the reviewed full VMM/native/mapping/QCOW/VARS-FD drain must precede any host rename. A successful guest shutdown request alone is not that proof.

Stage under a new test-only private directory with the recorded ownership/SELinux/ACL requirements; do not overwrite active libraries or guess generic permissions. Bind the artifact hashes, current full persistent and live VM config, lease, child, parent and new Windows boot before consuming the existing owned install/restore workflow. First verify actual loaded modules, F91 Code0 and the new boot's DWM identity; only then activate the qualified mode. The selected controlled mode uses NativeGpuJobV1/runtime-stream ON, force-present OFF and DWM force-sync ON. Existing bound receipts are evidence, not reusable authorization for a different boot.

Keep an isolated cache for C33, for example a new worker-writable test cache directory selected through `DXVK_SHADER_CACHE_PATH`; do not inherit an older F19 IR cache. C33's hardcoded FP32 policy is not a new cache-key bit. C34's cache-key proposal remains untested and excluded. Do not publish or ship personal runtime cache contents.

## Observed gains and limits

C33 fixed the observed Task Manager white glyph/search blocks while retaining the hardware path. The selected native completion path preserves real finite GPU completion and produced complete geometry in the bounded C46 direct demo capture, but direct rendering remains roughly 28 API presents/s in that short test, not smooth60. The older private-copy demo can reach complete geometry near60; that is not a universal application fix.

Video remains around30 displayed non-dropped frames/s in the relevant measurements, with visible hitches. A later Edge GPU-process loss was traced upstream of Map to a failed32MiB RES_INFO/shmem allocation; its precise pool/window failure cause is unresolved. Neither RAM exhaustion nor a larger-pool repair is proven. General shared-image ownership, teardown recovery, arbitrary applications, fold transitions and production installation are not fully validated. C47 gave no measured gain; C47/C48 are parked and excluded from this tested release set.
