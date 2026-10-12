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
