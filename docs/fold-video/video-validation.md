# Video-view lifetime fix and bounded validation

C4 retains the backing resource and video enumerator references for video views. Before decoder BeginFrame or video-processor Blt uses a view, it checks whether that resource now has a different backing identity. If needed, it creates a replacement host view before releasing the old view. The checks cover the enabled current, past, future and stereo input surfaces. Failure returns without issuing work through a stale view. Rebuild the native ARM64 and ARM64EC views together because the private view wrappers changed.

The sampled C4 video comparisons no longer showed the earlier alternating old-scene pattern. There were **zero `video: refresh` log hits** in those tests. Consequently, the observation does not establish that lazy refresh executed or caused the improvement; retained object lifetimes also changed. **Visual glitches remain**, and the video path is not declared pixel-correct or complete.

The published video source unit is byte-identical to the previously built C4
unit. This branch applies only that unit to its recorded upstream parent; the
complete branch has not been freshly built and runtime-tested as published.
The measurements came from a development image containing additional diagnostic
changes. They are bounded evidence from that image, not release qualification
of this branch. Those unrelated diagnostic changes are excluded from this patch.

## Build procedure

See [video-build.md](video-build.md) for the native ARM64 and ARM64EC build, packaging and on-demand build-host lifecycle.

## Correctness test

1. Keep host libraries, guest configuration and synchronization settings fixed between baseline and patched runs. Start a fresh isolated browser and play the same public clip at the same codec, resolution and frame rate.
2. Confirm the actual media track, decoder name and platform-decoder property. A hardware-acceleration checkbox or GPU capability page alone is insufficient. Confirm continuous frame and media-time progress.
3. Capture a separate physical-display correctness pass. Inspect consecutive frames and the full clip for old/new scene alternation, stale title frames, missing content and corruption. Recordings can perturb scheduling and cap their own frame rate; they do not prove a higher physical refresh rate.
4. Count actual `video: refresh` messages separately. Zero hits limit conclusions about execution of the identity-refresh branch. Retain remaining glitches as failures even when aggregate frame-rate counters look healthy.

## CPU comparison

The compact aggregate evidence is [cpu-decode-comparison.json](cpu-decode-comparison.json). This comparison measures hardware/software decode mode on the same development stack; it does not measure the isolated CPU effect of C4.

The public clip was [Big Buck Bunny](https://www.youtube.com/watch?v=aqz-KE-bpKQ), AV1 Main, 1920x1080 at 60 fps, with the observed playback interval approximately 70–95 seconds. After warmup, one 20-second CPU sample was collected per mode on a six-vCPU guest. Both samples had stable test-browser process sets. No screen recording ran during CPU measurement.

| Guest CPU measurement | Hardware decode | Software decode |
|---|---:|---:|
| Actual decoder | D3D11VideoDecoder | Dav1dVideoDecoder |
| Platform decoder | true | false |
| Isolated Edge process-tree CPU | 6.645584% | 22.438113% |
| Whole Windows guest CPU | 11.020249% | 28.526890% |
| Browser presentation rate, approximate | 59.1 fps | 59.1 fps |
| Browser dropped frames, approximate | 1.5% | 1.5% |

The Android `c2.qti.av1.decoder` running interval covered the hardware CPU sample, alongside guest `D3D11VideoDecoder`, platform-decoder `true` and advancing frames. The software case independently reported `Dav1dVideoDecoder` and platform-decoder `false`.

Hardware decode used approximately **70% less Edge CPU** and **61% less whole-guest CPU** relative to software in these samples. These are guest CPU measurements; host decoder CPU and power were not measured. One sequential pair is an indication, not a repeated thermal/cache-controlled benchmark. Browser counters do not establish physical pixel correctness.

To repeat the CPU method:

1. Use a dedicated test-browser profile and its own CDP endpoint. Keep unrelated applications untouched. Launch the hardware case without a software-decode override.
2. Create a new owned YouTube target, request 1080p, seek to 60 seconds, mute and play, then allow warmup. Confirm AV1 Main, 1920x1080/60 and `D3D11VideoDecoder` with platform-decoder `true`. Associate hardware-codec activity with that interval and verify frame progress.
3. Observe playback for approximately 25 seconds while collecting a 20-second CPU interval inside it. Sum process CPU-time deltas for the isolated browser tree. Require an unchanged process set; otherwise report that browser CPU accounting can undercount. Normalize Edge CPU as `100 * delta_cpu_seconds / elapsed_seconds / logical_vcpus`. Sample `GetSystemTimes` at both boundaries and compute whole-guest busy fraction as `(delta_kernel + delta_user - delta_idle) / (delta_kernel + delta_user)`; kernel time includes idle.
4. Close only the test instance and relaunch that profile with `--disable-accelerated-video-decode`. Repeat the same clip, codec, resolution, frame rate, fragment and warmup. Require actual `Dav1dVideoDecoder` and platform-decoder `false`; the flag alone is not software-decoding proof. Abort the comparison if the requested media properties or decoder cannot be verified.
5. Collect browser frame/drop deltas near the CPU boundaries and identify their approximate alignment. Keep CPU measurement separate from physical-display recording. Restore the hardware launch flags, close the isolated test browser and verify restoration.

Hardware launch flags were restored after this comparison and the isolated browser was closed. Physical rendering glitches remain an independent correctness issue.
