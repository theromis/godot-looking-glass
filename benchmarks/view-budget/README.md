# Real-view budget: speed and quality

```sh
python3 benchmarks/view-budget/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/view-budget/rendered1024
python3 benchmarks/view-budget/quality.py benchmarks/view-budget/rendered1024
```

Quality.py requires NumPy/Pillow; local bundled Python `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. Main runner uses the standard library.

Apple M4 / 4.8-dev / Vulkan-MoltenVK. Uniform real budgets 12/16/24/32, identical 48 outputs, 1024². Opaque static scene: 512 MultiMesh boxes, foreground bars/multiple depths, four shared-atlas SpotLights. Borrowed raw color/depth with production snapshot policy, ordinary depth math, 8 iterations, 8×8, rescue off. Viewport timestamps off, quilt profiling on. Three cyclic orders: 12/16/24/32, 16/24/32/12, 24/32/12/16; 90 warmup + 240 observed intervals. GPU quilt means include startup, not whole-frame GPU time.

Separate 48-real reference uses identical HDR→gamma transfer. Whole-quilt RGB MAE/PSNR compares the same 48 outputs. Synthesized subsets change with budget; their PSNR alone is not comparable. Real anchors must match reference or quality comparison fails. Per-view SSE/SAE/changed counts retained for placement analysis. Round(i*47/(real_count-1)) reproduces rig uniform selection.

Wall/engine ratio>1.5 flags anomalies without silently removing them. Do not claim speedup from anomalous means. Remeasurement retains original records and identifies replacements/provenance. Shader, geometry and output resolution remain fixed across modes.

These are exploratory presets, not an adaptive controller. Addon/CLI already supports real count (`--real=N`). One static scene/GPU curve is not a universal preset or perceptual/temporal/physical-display equivalence. Curved geometry, transparency/particles, motion, other GPUs and native Metal not compared. No new engine patch.


## Measured curve

Apple M4, 48 outputs, 1024², three timing records per budget:

| Real cameras | Update interval ms ± run stddev | Whole-quilt PSNR vs 48 real | RGB MAE (8-bit units) |
|---|---:|---:|---:|
| 12 | 33.310 ± 3.490 | 18.521 dB | 5.570 |
| 16 | 37.999 ± 1.765 | 21.782 dB | 2.742 |
| 24 | 47.782 ± 0.128 | 25.768 dB | 1.166 |
| 32 | 58.813 ± 0.207 | 27.778 dB | 0.740 |

Here `--real=16` reduces mean interval ~20.47% versus 24 but loses 3.99 dB whole-quilt PSNR. `--real=12` averages 30.29% faster, losing 7.25 dB with wider timing spread. `--real=32` gains 2.01 dB with +23.09% interval. A controlled tradeoff, not free speedup; choose presets using content/physical-display evaluation. Defaults unchanged.

Table PSNR covers all 48 identical outputs, including exact real anchors. Earlier 22.757 dB for 24 covered only 24 synthesized tiles; whole-quilt value is 25.768 dB. These are consistent measures.

summary.json retains initial 12-1 wall 131.544 ms versus engine delta 31.416 ms; excluded only from accepted timing mean. Budget 12 uses 12-2,12-3 and 12-controlled after quality computation. 12-recheck.json/PNG retained but excluded because concurrent CPU image analysis ran. Other budgets use original three runs. Provenance: accepted-summary.json. 12-1 image is quality-only; all anchors match fresh 48-real reference.

Initial GPU quilt means ~12.6/12.4/11.0/10.1 ms for 12/16/24/32: fewer cameras mean more synthesis but less rendering. CPU/GPU causes of total savings are not isolated. Output dimensions and shader-quality settings stay fixed.

Artifacts: per-run JSON/log/PNG, summary.json, accepted-summary.json, quality.json with per-view errors, reference JSON/PNG. Benchmark/native APIs predate this step; no new controller or shader algorithm.
