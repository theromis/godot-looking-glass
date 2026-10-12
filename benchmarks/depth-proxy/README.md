# Depth-only reconstruction-error proxy

Executed on Apple M4 with Vulkan Forward+, official Godot 4.5.1 and custom 4.8-dev. This is an offline diagnostic for evaluating whether depth-only signals can guide view selection. It does not enable a runtime adaptive controller or alter normal quilt rendering.

## Experiment

Three deterministic unshaded opaque fixtures: a smooth sphere in front of a background plane; thin foreground bars plus differently colored boxes; thirty boxes/spheres arranged at several depths. Each is sampled at three camera translations/yaw angles, with 48 outputs, 16 uniformly spaced real cameras, 256² tiles, borrowed raw reverse-Z depth, and ordinary eight-iteration synthesis. The all-real 48-camera reference is rendered alongside the 16-camera rig at the same pose. No MSAA, TAA, shadows, transparency, motion vectors or temporal synthesis are involved.

Each dataset contains 9 sampled poses and 288 synthesized-view observations. Multiple datasets repeat the same poses to test density, renderer version and camera updates; they are not additional independent scenes. At every pose all 16 real-camera output tiles must exactly match their all-real reference. The CPU analysis rejects any differing real tile or wrong quilt dimensions.

The separate compute shader samples only the two source depth buffers, repeats the current eight-step correspondence solve, and reduces four integer counters per workgroup:

- Both sources invalid: out-of-bounds or failed fixed-point residual validation. This is not a ground-truth disocclusion label.
- Exactly one source invalid.
- Horizontal inverse-depth change projected across the source baseline exceeds one output pixel, in either source. Sample spacing for the gradient is one output texel, regardless of probe density.
- Both correspondences valid, but their recovered inverse depths differ by more than one projected pixel across the source baseline.

Metric values are counts divided by sample count. A fifth baseline uses only camera indices: `(target-a)*(b-target)`. No weights are trained, no combined classifier is fitted, and no metric is selected as a production policy from these results.

## Result: moderate information, not a reliable adaptation policy

Raw pooled correlations are misleading here. At 64² sampling, exactly-one-source-invalid has Spearman 0.894 against RGB MSE over all views, but only 0.210 after removing each sampled pose's mean. The large pooled value primarily reflects differences between fixtures, and is not evidence that the metric can choose the best cameras within a given pose.

The following subtracts each pose's mean from both proxy and MSE, then computes pooled Spearman correlation. This controls mean differences, not all possible scene/variance confounders. Positive values indicate higher proxy tends to accompany higher reconstruction error; 1 is perfect rank agreement. Per-pose correlations and top-quartile recall, including explicit treatment of ties, are retained in `analysis.json`.

| Depth metric | Centered Spearman, 64² | 128² | 256² |
|---|---:|---:|---:|
| Both sources invalid | 0.406 | 0.483 | 0.449 |
| Exactly one source invalid | 0.210 | 0.245 | 0.204 |
| Horizontal depth edge | 0.029 | 0.316 | 0.467 |
| Valid depth disagreement | -0.056 | -0.121 | -0.072 |
| Anchor-distance baseline | 0.429 | 0.429 | 0.429 |

Dense sampling improves the edge metric substantially: 0.029 → 0.467. This is consistent with sparse sampling missing relevant one-pixel boundaries; the experiment does not isolate all sources of sampling error. However the dense result is only slightly above the geometric baseline's 0.429, and the advantage varies by pose. Dense per-pose edge Spearman ranges from approximately zero to 0.628; the geometric baseline is stronger at the center bars pose (0.663 versus edge 0.356). Both-invalid is a useful additional candidate signal, but does not consistently dominate the baseline either. Grid-density results are not monotonic, so 128² is not established as an optimal setting.

After controlling both pose means and a linear anchor-distance baseline, dense partial Pearson values are 0.313 for both-invalid and 0.309 for the edge metric. This remains descriptive, in-sample evidence. Neighboring views and poses are correlated observations; no independence assumption, statistical-significance claim, general quality guarantee or cross-validated camera policy is made.

## Camera motion and version checks

The initial captures use fixed poses. Additional runs update translation and yaw on 16 successive draws before each sampled pose, then allow two settling draws. On custom 4.8, the resulting 64² depth counters and decoded reference/synthesized quilts match the fixed-pose run exactly. This validates settled capture/probe consistency after camera updates; it does not measure flicker, temporal artifacts, hysteresis or adaptive camera switching during motion.

At 64² the GPU depth counters match official 4.5.1 exactly. Decoded RGB quilts differ between renderer versions; each version's real-camera tiles match its own reference, and the maximum difference in whole-quilt PSNR between versions is 0.0383 dB. Do not use a cross-version image as an exact reference. Detailed comparisons are in `official45/comparison.json` and `motion48/comparison.json`.

## Implementation and validation

`tests/depth_proxy.glsl` performs the depth-only solve and workgroup reduction. `tests/depth_probe.gd` dispatches it and reads reduced blocks; `tests/test_depth_proxy.gd` generates fixtures and captures. This diagnostic is deliberately separate from production shaders/addon APIs. At grids 64²/128²/256² it reads back 49,152 / 196,608 / 786,432 bytes per pose and sums blocks on CPU. Sampling 256² executes sixteen times as many probe invocations as 64²; this is a work-count comparison, not a measured runtime slowdown. Shader/pipeline setup, synchronous readback and all-real reference rendering are part of the diagnostic workflow. Runtime GPU cost and amortized adaptation benefit are **not measured**.

The analytical GPU test uses a constant-depth plane with known zero, opposite and same-direction camera shifts. It checks exact reduced counts, including 384 single-source failures and 192 double-source failures, and exclusion of real views. An invalid sample grid is rejected before GPU resource allocation. These tests passed on official 4.5.1 and custom 4.8. All 15 project regression checks passed on both versions; after adding configurable density, the analytical test was rerun on both and all nine dense/128² GPU fixture cases executed on custom 4.8. No engine rendering code changed.

`benchmarks/.gdignore` prevents Godot from importing benchmark screenshots and nested benchmark projects. Diagnostic scripts/shaders remain under `tests/`; Python and direct image/file access to benchmark results still work.

## Reproduce

Import the project shaders first using the Godot editor. From project root (image analysis requires Python with Pillow/NumPy):

```sh
python3 benchmarks/depth-proxy/run.py --godot path/to/godot --results-dir benchmarks/depth-proxy/new-results --grid=64 --motion
python3 benchmarks/depth-proxy/analyze.py benchmarks/depth-proxy/new-results
python3 benchmarks/depth-proxy/run.py --godot path/to/godot --results-dir benchmarks/depth-proxy/new-dense --grid=256 --motion
python3 benchmarks/depth-proxy/analyze.py benchmarks/depth-proxy/new-dense
/path/to/godot --path . --rendering-driver vulkan --script res://tests/test_depth_proxy_analytic.gd
```

`run.py` verifies actual submissions, case counts, depth counter bounds, sample density and capture presence. `analyze.py` verifies real-pixel/reference equivalence and computes per-view full-tile RGB error. `compare_runs.py BASELINE OTHER` compares counters and decoded images after both directories have `analysis.json`. Raw runs are retained in `custom48/`, `official45/`, `motion48/`, `grid128/`, `dense256/`, with logs, PNGs, raw counts, image hashes and binary provenance. The extra `official45-motion/` run validates the final wrapper and camera updates on the official engine.

## Next decision

Do not enable automatic camera selection from these correlations. First evaluate a depth-only interval cost directly: choose anchors with it on one fixture, then compare the resulting quilt with uniform placement and the reference-assisted oracle on different fixtures/poses. A proxy correlated with error can still pick a worse anchor layout. Runtime feedback would also need final GPU reduction to a few scalars, readback-free or amortized selection, overhead measurements and stable transitions. Another promising scope is scene-level view-budget selection, for which the strong between-scene signal may be useful; it is untested here.
