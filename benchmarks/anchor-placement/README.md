# Nonuniform real-camera placement: negative result

Apple M4, custom Godot 4.8 Vulkan/MoltenVK, 48 outputs, 24 real cameras, 1024² tiles, 512 MultiMesh boxes and foreground bars, four shared-shadow SpotLights. Static opaque scene; borrowed raw depth/color, 8 iterations, 8×8 workgroups, rescue off. Viewport timestamps off, quilt timestamps on. Three sequential repeats per layout, alternating order; 90 warmup dispatch updates and 240 measured observed update intervals. These wall intervals include presentation and scheduling, not isolated GPU time.

Selection preserves the 16 uniform anchors from the preceding view-budget test, adding the eight non-real views with largest RGB squared error against its all-real reference. This is an offline ground-truth-assisted, in-sample experiment. It is not a runtime adaptive controller. There is no claim that this heuristic optimizes the joint error of all views.

| Layout | Observed update interval, mean ± run SD | Quilt compute GPU, mean ± run SD | Whole-quilt RGB PSNR | RGB MAE (8 bit) |
|---|---:|---:|---:|---:|
| Uniform 24 | 48.317 ± 0.425 ms | 11.106 ± 0.115 ms | 25.768 dB | 1.166 |
| Selected 24 | 48.204 ± 0.090 ms | 11.132 ± 0.017 ms | 24.088 dB | 1.666 |

No speed improvement is established. Total squared RGB error increases 47.21%. Ten output views improve and twenty worsen; all 24 real anchors in each layout match the all-real reference exactly. The selected layout has eleven gaps of three view indices, versus one in the uniform layout. Wider local baselines are a plausible explanation for degraded synthesized views, not a proven isolated cause. Simply selecting high-error views without evaluating neighboring reconstructions fails in this scene. Uniform remains the default.

Raw runs, logs, images and timestamp sample counts: `rendered1024/`. The uniform PNG SHA256 matches the earlier 24-real baseline; the reference SHA256 is recorded in `quality.json`. All runs have 331 compute submissions, 240 measured intervals, and no wall/engine ratio above 1.5. Submission counters are not individual GPU fences.

## Reproduce

From project root, with the optional shared-shadow engine patch and Python Pillow/NumPy for image analysis:

```sh
python3 benchmarks/anchor-placement/run.py --godot /absolute/path/to/godot --rendered --results-dir benchmarks/anchor-placement/new-results
python3 benchmarks/anchor-placement/quality.py benchmarks/anchor-placement/new-results --reference benchmarks/view-budget/rendered1024/reference.png
```

The reference must use identical scene, renderer and preview transfer; the quality script rejects mismatched dimensions and any differing real-anchor pixels. The supplied selection is scene-specific. The run does not generate a new all-real reference.

## Addon API and validation

Set `custom_anchor_indices: PackedInt32Array` before adding the rig to the scene. It must contain exactly `real_views` strictly increasing indices, starting at zero and ending at `total_views - 1`. Empty means uniform. Invalid addon values warn and fall back to uniform; the demo CLI rejects invalid input with exit code 1. Raster/unsupported-compute fallback uses all real views. Change camera configuration by replacing the rig.

Demo: `--views=48 --real=4 --anchors=0,3,35,47` (other scene options as required). This example demonstrates the API, not a quality recommendation. Benchmark JSON records effective `anchor_indices`.

Tests verify invalid-set rejection, source bracketing, focus registration, nonuniform GPU quilts across capture modes/workgroups, resizing and borrowed-resource ownership. All 14 project checks passed on official Godot 4.5.1 and custom 4.8 after this change.

Next research: evaluate the change in error over a whole anchor interval, constrain baseline gaps, then test an inexpensive depth/visibility proxy on different scenes and motion. Ground-truth selection cost and temporal camera changes would need separate measurements before a production adaptation policy.
