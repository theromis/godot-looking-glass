# Whole-interval camera selection

This offline experiment chooses 24 real cameras for 48 output views by minimizing measured RGB squared error over all synthesized views between adjacent cameras. It uses a static all-real reference. It is not a runtime adaptive controller or a speed optimization.

## Measured result

Apple M4, custom Godot 4.8-dev Vulkan/MoltenVK, 1024² tiles, 512 MultiMesh boxes plus foreground occluders, four SpotLights with the optional shared-shadow engine patch. Static opaque scene; borrowed raw depth/color, 8 reprojection iterations, 8×8 workgroups, rescue off. Performance stage uses three sequential repeats per layout, alternating order, 90 warmup updates and 240 observed quilt-dispatch update intervals. Viewport timestamps are disabled, two quilt timestamps enabled. Counters represent submissions, not per-update GPU completion fences. Wall intervals include scheduling/presentation.

| Layout | Whole-quilt RGB PSNR ↑ | Whole-quilt RGB MAE ↓ | Update interval, mean ± run SD | Quilt GPU, mean ± run SD |
|---|---:|---:|---:|---:|
| Uniform 24 | 25.768 dB | 1.166 | 48.221 ± 1.813 ms | 11.006 ± 0.354 ms |
| Interval-selected 24 | 26.046 dB | 1.119 | 47.309 ± 0.324 ms | 10.844 ± 0.108 ms |

Total RGB squared error decreases **6.209%**; RGB MAE decreases **4.035%**. This is a modest in-sample improvement in one static scene. There is no established timing gain: differences are below the observed run variation, and the first uniform repeat is slower than the other two. No runs were discarded; no wall/engine ratio exceeded 1.5. All runs submitted 331 quilts and recorded 240 intervals.

Every real-camera tile exactly matches the all-real reference in the five cost captures and final selected/uniform quilts. Actual total squared error in the independently rendered selected quilt equals the interval model prediction exactly: 24,403,568,184 versus uniform 26,019,076,952. The final uniform PNG hash also matches the prior 24-camera baseline.

## Algorithm and scope

For neighboring real-camera indices `a,b`, measure the sum of RGB squared error in output views `a+1 ... b-1`. Real views contribute zero error. The current synthesis shader uses only the two bracketing cameras, so these interval costs can be summed. This separability is verified for the selected layout in this test; effects whose output depends on other cameras could invalidate it.

Five interleaved camera grids cover every possible interval of length two or three: two phase offsets at stride two, three at stride three, always including both end views. Adjacent real views have no synthesized outputs and cost zero. Duplicate interval measurements must match exactly; missing interval costs and differing real anchors abort the solver.

Dynamic programming finds the minimum sum for 24 anchors, endpoints 0/47 and **maximum index gap three**, matching the uniform layout's maximum gap. The cost table contains 138 possible intervals (47 adjacent, 46 of length two, 45 of length three). Selection is exact for this additive model and constrained candidate set; it is not the unconstrained optimum or a perceptual optimum. Unlike the earlier high-error-view heuristic, it accounts for all intermediate views that change when an anchor moves.

Selected indices:

```text
0,2,4,6,7,9,11,13,15,17,19,21,23,25,27,29,31,34,36,38,40,42,44,47
```

Uniform remains the addon default. Use `--anchors=` or `custom_anchor_indices` only when an application has a suitable selection policy. Computing these costs requires reference images and expensive extra renders; CPU image readbacks here are offline analysis, outside the normal GPU quilt path. Selection and evaluation use the same scene, so there is no demonstrated generalization to motion, transparency, other scenes, resolutions, or physical Looking Glass image quality.

## Reproduce

From project root, use the custom shared-shadow engine binary and Python with Pillow/NumPy for analysis. GPU stages run sequentially; do not run CPU image analysis alongside performance sampling.

```sh
python3 benchmarks/interval-placement/capture_costs.py --godot /absolute/path/to/godot --results-dir benchmarks/interval-placement/costs1024
python3 benchmarks/interval-placement/solve.py benchmarks/interval-placement/costs1024 --reference benchmarks/view-budget/rendered1024/reference.png --output benchmarks/interval-placement/selection.json
python3 benchmarks/anchor-placement/run.py --godot /absolute/path/to/godot --rendered --selection benchmarks/interval-placement/selection.json --results-dir benchmarks/interval-placement/new-results
python3 benchmarks/anchor-placement/quality.py benchmarks/interval-placement/new-results --reference benchmarks/view-budget/rendered1024/reference.png
python3 benchmarks/interval-placement/test_optimize.py
```

The supplied all-real reference was rendered with identical scene/renderer/preview transfer. Quality validation checks dimensions, exact real-camera pixels, reference hash, and exact agreement with predicted selected and uniform error. Raw cost captures, cost table, logs, JSON, images and binary hash are retained in `costs1024/`; independent performance/quality runs are in `rendered1024/`. Cost-capture timing is not used for performance claims.

Two solver tests passed: comparison against exhaustive search across small view counts/budgets, including infeasible layouts, plus rejection of missing costs. Addon and engine rendering code did not change in this step; the preceding 14 checks on Godot 4.5.1/custom 4.8 remain the rendering regression evidence. This new whole-interval GPU experiment was executed on custom 4.8 only.

A runtime policy would need a cheap depth/visibility proxy that predicts interval reconstruction error without a full reference. Its correlation, update overhead, stability during motion and amortized benefit need separate experiments. Existing measurements justify the offline tool, not enabling automatic adaptation.
