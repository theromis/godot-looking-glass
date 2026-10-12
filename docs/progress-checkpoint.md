# Progress checkpoint — 2026-10-11

Standalone Godot project, MIT addon, demo/tests, research documentation, optional shared-shadow patch and measured experiments. Proprietary Unity Plugin used only as research reference; its sources/native libraries are not included.

Latest completed steps:

- Depth-diagnostic GPU reduction: feedback 786432 → 768 bytes; CPU decoding 20.499 → 0.306 ms on M4. No confirmed FPS gain. See `benchmarks/depth-reduction/`.
- On-demand quilt: static process/presentation 47.408 → 16.535 ms after warmup, no repeated idle captures/compute. Cached-image presentation, not faster new animated frames. See `benchmarks/on-demand/`.
- All 16 regressions passed latest local 4.8-dev. Log: `benchmarks/on-demand/regression48.log`.
- Depth-only selection did not improve quality; uniform anchors remain default. See `benchmarks/depth-selection/`.

Code/protocols/raw JSON/logs/aggregates/snapshots/hashes are in Git. Large PNGs, Godot caches and temporary projects remain local, excluded from Git. Paths/sizes/SHA-256 in `benchmarks/local-artifacts-manifest.json`. Reproduction needs editor shader import and benchmark scripts; excluded captures are absent after clone. Image analysis may require rerendering first.

Remaining: physical Looking Glass/Bridge GPU interop, other GPUs, dynamic/transparency/temporal quality. On-demand needs explicit scene invalidation; initial large-scene differences are documented. Results are not universal acceleration.

History/tasks: `docs/implementation-roadmap.md`; upstream patch/provenance: `engine-patches/`. Engine fork changes remain in its separate branch; no engine checkout/binary included here.


## Native Metal boundary prototype

A standalone Objective-C++ Metal boundary now dynamically loads Bridge, verifies SDK symbols/version and performs a one-shot GPU copy into an SDK-created texture before submission. Real Metal/IOSurface fixture tests and installed SDK 2.6.3 probing passed on Apple M4, including failure/retry and ownership checks. This is not a Godot GDExtension: the current 4.8 runtime is Vulkan-only, no real SDK draw/hardware output was executed, and consumer completion/streaming remain unverified. Blocking producer/copy waits are a correctness baseline; no speedup is claimed. See [component and next integration steps](../native/bridge_metal/README.md) and [executed scope](../benchmarks/native-bridge/README.md).


## Executed Godot native Metal diagnostic

A new 4.8-dev native Metal runtime and optional test-fixture-only GDExtension now execute Godot quilt → Metal blit → SDK-fixture IOSurface copying. Three final 64×64 repeats matched every half-float component after explicit 120-update warmup and a verified frozen interval. Vulkan handles are rejected before native access. The same-queue sentinel requires already committed producer work; no streaming or real SDK display output is validated. Full native Metal QA passed 13/16, failing on-demand, resize/capture equivalence and borrowed-buffer policy; a settled refresh did not guarantee equality. Vulkan 4.8 still passes all 16. All failures are retained, and general native Metal support remains experimental. See [Godot diagnostic contract](../native/bridge_metal/README.md) and [results](../benchmarks/native-bridge/README.md).


## Native Metal correctness gate: optional hazard tracking

The latest native Metal 4.8-dev addon suite passes 16/16 with `GODOT_MTL_SYNC_MODE=none`; the static Godot-to-fixture copy also passes. Repeating default barriers still fails the three prior image-equivalence checks. Diagnostics isolate source/final-viewport mismatches and an opposite-camera image substitution; the exact driver cause remains open. The smaller standalone reproduction is intermittent. No production rendering code was changed and no performance gain is claimed. Default-barrier engine correctness, other GPUs/versions, real Bridge output and safe consumer-side texture reuse remain open. See [findings and launch instructions](../native/bridge_metal/README.md#native-metal-synchronization-diagnosis) and [unpublished engine issue draft](native-metal-issue-draft.md).


## Controlled Metal engine experiments

Seven selected-check variants tested stronger encoder ordering, CPU staging allocation, per-frame camera UBO allocation, explicit resource declarations, producer attachment reads, and a combined variant. None passed all three previously failing checks. The per-frame UBO variant matched 80/80 source/viewport/quilt comparisons and passed resize/capture plus buffer compatibility, but still failed on-demand after an explicit settled refresh. A separate 64-update uniform-buffer compute control passed on both Metal modes and Vulkan, so it does not reproduce the raster failure. Production engine/addon changes were restored; no upstream-ready fix or speedup is claimed. See [experiment matrix, patches and provenance](../benchmarks/metal-barriers/README.md).


## Connected hardware checkpoint

A connected 1440×2560 / 60 Hz Looking Glass is now detected by native Bridge 2.6.3 and the corrected HTTP client. The SDK preset is 4092², 11×6 / 66 views, aspect 0.5625, cone 54°. Serialized calibration required a second recursive unwrap after JSON parsing; fixture and real detection pass. Real SDK RGBA8 allocation/draw succeeds, and the user confirmed a solid blue image after explicit window visibility plus an event-loop/repeated immutable-submission test. Both tested RGBA16Float allocation descriptors fail. SDK initialization logs an OpenGL error even in the visually successful test. Godot scene conversion/delivery, the current 48-view cap, optical validation and animated consumer lifetime remain open. See [hardware evidence](../benchmarks/hardware/README.md).
