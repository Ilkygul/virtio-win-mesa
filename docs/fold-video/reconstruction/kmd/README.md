# F91: exact retained C13 KMD source snapshot

This is the actual **104-file source/build input subset** retrieved from the
successful C13 ARM64 build. All104 hashes and sizes match its final private
source inventory; all13 patched files match its declared postimages. There
are no source symlinks. Files retain exact source bytes/line endings.

`source104-postimages.json` supplies SHA256 and Git-blob-SHA1 for snapshot
import. Its tree assumes100644 file modes because Windows did not attest
executable bits. It is not a claim to contain the entire upstream repository.

## Origin and snapshot publication

The build copied its original104 inputs from `C:\winbuild\src`. Neither an
original KMD Git HEAD nor an original Git remote was attested in the examined
retrieval. Do not infer those from folder names, a binary version or the Mesa
UMD dependency URL in `viogpu3d/BUILDING.md`.

Root's publication target is **Ilkygul/viogpu3d-pvm**, as a newly identified
snapshot branch. That target is a publication choice, not proof that this was
the original repository or that the snapshot has verified upstream ancestry.
The Windows UMD is a separate component from the KMD.

`original1CA-to-F91-C13.patch` is the complete13-file patch SHA256
`CA08B3134F9A6885539EA0C82BD3DDCBED7C0B8E988B39F42D9718F9DC6DE2A7`:
original1CA baseline + C12 semantic patch + exact ZwWaitForSingleObject
compiler-declaration fix + C13 bounded colorkey trace. It does not inherit the
unselected C11 experiments. Apply only to the matching original baseline;
`original104-inputs.json` and `changed13-source-manifest.json` pin that baseline
and the exact replacements. The publication manifests remove only personal
absolute baselinePath fields; source bytes and hashes are unchanged.

## Actual build and preserved binary

The actual build used VS2022 Build Tools MSVC14.44.35207, WDK/SDK10.0.26100.0,
WindowsKernelModeDriver10.0, `Win11 Release|ARM64`. Its exact MSBuild arguments
are in `evidence/build-command.json`; private evaluation and the fresh15-TU
proof are preserved. The unsigned rebuild produced:

- SHA256 `1CD7128D93269F62225CF5E4BE79035BAC19C4882C17A43A227DAE0BEF164653`,246784bytes.
- Existing signed F91: SHA256 `F91D91416051A6C9E2BBFC7E312BB0579A5F099C2F297115BA71D7D868D038D7`,248184bytes.

The historical recipes are copied byte-for-byte from the actual retrieval.
They require their original exact packet/private-root/preflight inputs and
are not a newly runnable public installer or signing workflow. No build,
signature operation, device change or certificate policy change was run to
prepare this snapshot. No private key or PFX is included.

**Clean-rebuild dependency gap:** the actual build set
`BuildProjectReferences=false` and copied an existing ARM64 `virtiolib.lib`
with SHA256 `7ECA4DFA0062B7FC0FE1D0B8CF0468B29C637755A991F1FDC849EA958D012535`
from `VirtIO/objfre_win11_arm64/arm64`. That library is not in this source
retrieval or the checked local C11/C12/C13 build artifact sets. VirtIO source
and its project are included, but a separately reproduced library build is
not attested. Consequently this package does not claim a bit-identical clean
rebuild from an empty machine. It preserves the exact tested source subset,
the known dependency hash, actual recipe/evaluation and existing signed binary
identity. Signing again would also require an authorized signing identity;
the private C92 key is intentionally not a distributed input.

BuildVM signing exited0, but `/kp` verification exited1 with an untrusted
local test-root chain. Guest Valid+C92 checks were separate. This source
package does not confer production trust, support general power transitions,
or establish universal GPU completion/runtime safety.
