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
