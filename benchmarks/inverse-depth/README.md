# Direct inverse-depth reprojection

For raw reverse-Z perspective input `d`, near `n`, far `f`:

`z = n*f / (n + d*(f-n))`

`1/z = 1/f + d*(1/n - 1/f)`

Optional `--inverse-depth`, default `rig.inverse_depth_reprojection=false`, selects a separate shader and requests borrowed raw depth/color. Inverse-far and inverse-near-minus-far coefficients are configured once in existing 64-byte push constants. Synthesis keeps inverse depth rather than reconstructing z per lookup, substitutes min(inverse_z,1000) for 1/max(z,0.001), and compares >= for the nearest surface. Rescue is supported. Iterations, residual thresholds, sampling, gamma and hole fallback are unchanged.

Algebraically equivalent for positive finite perspective depth, but not necessarily floating-point equivalent: coefficient/product rounding affects UVs and early-exit equality, especially at sampling boundaries. Ordinary shaders remain canonical; inverse mode is opt-in. TAA/additional-effect snapshot fallback copies raw depth, preserving interpretation.

```sh
python3 benchmarks/inverse-depth/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/inverse-depth/rendered1024
python3 benchmarks/inverse-depth/quality.py benchmarks/inverse-depth/rendered1024
```

Quality.py needs NumPy/Pillow; local bundled Python `../../.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. generate_workgroups.py generates shader variants for import in Godot before running.

A/B: Apple M4, Godot 4.8-dev, Vulkan/MoltenVK, 24 real → 48 output, 1024², 512 static MultiMesh boxes, foreground bars/multiple depths, four shared-atlas SpotLights. Borrowed color/raw depth, current safety policy, profiling on, 8×8, 8 iterations, rescue off. Three alternating pairs; 90 warmup + 240 observed intervals. Equal quilt markers; GPU mean includes startup, not whole-frame GPU time. First-pair PNGs compared numerically by synthesized tiles/anchors; fresh 48-real reference uses the same HDR→simple-gamma transfer.

Analytic tests: zero/positive/negative inverse-depth planar disparity, recoverable rescue layers, near/far 0.01/5000. They do not establish universal FP identity. Benchmark checks changed fraction, MAE, PSNR and real-anchor equivalence.

Limitations: one static opaque scene/GPU; curved/moving/transparency, extreme clipping in actual scenes, native Metal/other GPUs/physical Looking Glass not measured. Not all group/iteration/rescue combinations executed. Compiler may already optimize divisions; speedup is not assumed.


## Result

Repeat series: three Apple M4 pairs, 24 real → 48 output, 1024²:

| Arithmetic | GPU quilt ms, mean ± run stddev | Observed update interval ms, mean ± run stddev |
|---|---:|---:|
| Ordinary | 11.346 ± 0.238 | 49.646 ± 1.131 |
| Inverse depth | 11.316 ± 0.290 | 49.173 ± 1.002 |

GPU/update-interval differences are below between-run variation; no sustained speedup. Fewer source-level divisions do not prove lower GPU cost; actual compiler output/cause was not investigated. Ordinary shader remains default; inverse mode opt-in.

Quality: 0.017019% of synthesized pixels differ; RGB MAE 0.0000831 in 8-bit units, baseline PSNR 88.875 dB. Fresh 48-real PSNR: ordinary 22.75720885 / inverse 22.75720883 dB. Real anchors exact. These PNG RGB measures establish neither HDR identity nor perceptual/temporal quality.

Initial `rendered1024/` baseline timed out after 180 s without valid JSON/PNG and was excluded; cause unknown. Ordinary 4.5.1 and inverse custom-4.8 smoke tests each executed 331 dispatches. Fresh `recheck1024/` finished without wall/engine ratio>1.5 anomalies; all six records have 240 samples and >=330 dispatches.

All 13 regressions passed on 4.5.1 and 4.8. Other group/iteration variants and dynamic inverse-depth quality remain partly untested; default unchanged. Data: recheck1024/summary.json, quality.json, reference JSON/PNG, per-run JSON/log/PNG, checks-4.5/4.8.log.

Method: benchmarks/inverse-depth/README.md.
