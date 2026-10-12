# Actual Godot quilt synthesis: direct SDK target versus RD copy

Executed on 2026-10-12 with Godot 4.8 `c61fc0118`, native Metal Forward+, Apple M4, real Bridge 2.6.3 and `GODOT_MTL_SYNC_MODE=none`. This benchmark uses the actual addon synthesis shader and Godot capture textures rather than the prior native constant-color fill.

## Workload

The scene contains an unshaded orange box and RGB spheres at multiple depths against a blue background. Twenty-four real off-axis cameras supply sixty-six output views. The selected raw reverse-Z synthesis variant uses eight reprojection iterations, two neighboring sources and 8×8 workgroups; optional rescue is disabled. The output is gamma-encoded RGBA8, with no added tonemapping. The scene/cameras are warmed with 120 requests, then frozen. Capture counters must stay unchanged throughout timing. Camera rendering is excluded; it is not measured as part of these figures.

Each process makes twenty warmup samples and one hundred measured samples, fifty per mode. Within each pair, direct/copy order alternates. The same shader, pipeline and source textures are reused. Uniform sets are rebound outside the timed intervals when changing output. In direct mode the shader writes into an imported real SDK IOSurface. In copy mode it writes into an owned RD RGBA8 texture, then `RenderingDevice.texture_copy()` copies the quilt into the SDK allocation. This compares the Godot RD copy path; the older adapter's separate-queue native blit is not timed here.

## Timing boundary and validation

Two intervals are recorded separately: render-thread command recording and main-thread `force_draw(false)` / `force_sync()` plus an already-committed native Metal queue fence. The table uses the latter **submit/wait elapsed wall time**, including Godot root draw/submission and CPU waits. It is not isolated GPU kernel time, camera frame time, Bridge optical processing, display latency or interactive FPS.

Pilot instrumentation using RD GPU timestamps was rejected: named queries arrived with zero GPU values in this native Metal build. Manual draws also do not provide a useful changing Engine frame ID for deduplication. None of those zero-value pilots is included in results. Completed native command-buffer fencing provides a synchronous execution baseline, but cannot isolate GPU duration from CPU costs.

No SDK quilt draw is submitted during these tests, so no Bridge consumer sees repeated writes. These runs do not establish an animated texture-reuse contract. After all samples, diagnostic CPU readbacks compare entire direct and intermediate quilts byte-for-byte and check nonempty RGB content. Readback is outside timing. All six runs passed, each with exactly fifty measured samples per mode and unchanged camera capture counters.

| Quilt | Run | Direct submit/wait median ms | Synthesis + RD copy submit/wait median ms | Difference ms |
| --- | --- | ---: | ---: | ---: |
| 704×684 | 1 | 0.6275 | 0.6440 | 0.0165 |
| 4092×4092 | 1 | 2.6440 | 3.8945 | 1.2505 |
| 704×684 | 2 | 1.0220 | 1.0685 | 0.0465 |
| 4092×4092 | 2 | 7.5545 | 9.5255 | 1.9710 |
| 704×684 | 3 | 1.2105 | 1.3005 | 0.0900 |
| 4092×4092 | 3 | 7.4360 | 9.5575 | 2.1215 |

At 4092² all three paired medians favored direct output by 1.25–2.12 ms. Absolute times varied substantially across processes (including command-recording CPU time), and the cause was not isolated. Do not present a stable percentage speedup or transfer these figures to complete scene FPS. The 704×684 case showed only 0.02–0.09 ms median difference; distributions overlap and its practical benefit is small/unconfirmed. The direct path also avoids an intermediate RGBA8 allocation of 66,977,856 bytes at 4092², excluding allocation/padding overhead.

[Raw samples and p10/p90 statistics](sdk-synthesis-results.json) preserve all measurements.

## Reproduction

Build the optional native extension and set external `BRIDGE_LIBRARY`, explicit calibrated `BRIDGE_DISPLAY_INDEX`, and your latest native Metal engine as `GODOT`. Run serially without concurrent GPU benchmarks:

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal --script tests/benchmark_sdk_synthesis.gd
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal --script tests/benchmark_sdk_synthesis.gd -- --large
```

The large quilt uses 372×682 tiles in an 11×6 grid, exactly 4092². This does not validate optical aspect/view-order quality for that preset. Each process emits a `RESULT` JSON record and a `PASS synthesis benchmark` marker. SDK logs can contain private calibration identifiers; retain only structured results or sanitize logs before publication. Require exit zero, the PASS marker and no script/engine errors.
