# Prerelease assets to upload

Upload the existing tested files, not new recompilations, to a feature-branch prerelease. These are not a production installer or a claim that every application is correct.

| Asset | Bytes | SHA256 |
|---|---:|---|
| `android/crosvm` | 13081544 | `6ACBBCAEC64A67501DB335EEA70E4CA5CA4E49C047AA9447E08AA7048DC7ABD7` |
| `android/libvirglrenderer.so` | 4691248 | `B5A31380261A48350795F35F0C017785F0937C0C9B7015676D357960415870C7` |
| `android/virgl_render_server` | 3002312 | `E1204FDD39D2B17A5089F2A99ECA8BEE35C6221AE2752897D34D559890EFE604` |
| `android/libdxvk_d3d11.so` | 5906440 | `B964E83618F109C8E68DD69FF3BC192A3470D34E4B53CEB89308654FA39404DE` |
| `android/libdxvk_dxgi.so` | 3871041 | `5E6E08A4592A6BAE52B87FCE4442369E11B631D0BBAB5CB7905CADD2E5224740` |
| `windows/neptune_umd.dll` | 1366528 | `2A7DC660ABF7AC3A6B49991C55FC7B44859F670ADE1D9E8033BE7F62B07E744D` |
| `windows/neptune_umd_arm64.dll` | 1366528 | `2A7DC660ABF7AC3A6B49991C55FC7B44859F670ADE1D9E8033BE7F62B07E744D` |
| `windows/neptune_umd_ec.dll` | 1276416 | `0D472DA041603FDF0182FF3D903848E10A4035404E3576C1D0E544B5FE7BBC32` |
| `windows/viogpu3d-nativejob.sys` | 248184 | `F91D91416051A6C9E2BBFC7E312BB0579A5F099C2F297115BA71D7D868D038D7` |

Include this build bundle, filled source snapshot commit/URL pins, a complete package SHA256 manifest and concise known limitations. Optional unstripped Android libraries may be a separate debugging asset with their own hashes. Do not invent PDBs or signing claims. The signed F91 SYS alone is not a complete INF/CAT/PnP installation package.

Exclude source transport helpers, host IPs, daemon credentials, signing/private keys, caches, raw user captures, private VM configurations, disks and VARS. The selected base-history bundles are shallow archival evidence, not standalone complete-history Git source releases; normal clone failures at their missing boundaries are documented separately.
