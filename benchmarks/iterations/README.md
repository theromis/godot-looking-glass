# Fixed reprojection iteration limits

```sh
python3 benchmarks/iterations/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/iterations/rendered1024
python3 benchmarks/iterations/quality.py benchmarks/iterations/rendered1024
```

quality.py requires NumPy/Pillow; locally used bundled Python `../../.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. Benchmark runner uses the standard library.

Variants change only gather-loop limits 2/4/8; exact fixed-point early exit, residual threshold and hole fallback are unchanged. Canonical 8 shader retained. Selector `--iterations=2|4|8`, addon `reprojection_iterations`. Default 8; export enum/CLI accept 2/4/8, and invalid programmatic values fall back to 8. `shaders/generate_workgroups.py` generates group/iteration variants for advance Godot import.

Timing scene: Apple M4/Vulkan-MoltenVK, 4.8-dev, 24 real → 48 output, 1024², 512 static MultiMesh boxes, foreground bars/multiple depths, four shared-atlas SpotLights, borrowed color/depth, 8×8. Three repeats in 8/4/2, 4/2/8, 2/8/4 order; 90 warmup + 240 observed intervals. GPU quilt scope includes two markers and startup, not full-frame GPU time. Wall/engine mismatches are retained and flagged, not silently filtered.

Quality: first three PNGs compared with 8 iterations and separate 48-real output, all using identical linear-HDR→simple-gamma transfer without native tonemap mismatch. RGB MAE in 8-bit units, PSNR and changed fractions separately cover 24 synthesized tiles/24 anchors. Uniform round(i*47/23), 4 columns, inverted rows. PNG compression/alpha are excluded from RGB metrics. Exact matches yield null PSNR (infinite).

Not a perceptual/temporal score: opaque/static scene only; curved geometry, particles, motion, TAA/FSR2/MSAA and other scenes untested. Aggregate PSNR can hide small boundary defects. Default 8 is not changed from one scene.

All six checks passed on 4.5.1 and 4.8: projection, analytic GPU 8/2/4, capture/workgroup lifetime, Bridge fixture. Planar zero/positive/negative disparity should need few iterations; it does not validate complex occlusions.


## Measured result

Apple M4, three repeats:

| Iterations | GPU quilt ms (mean ± run stddev) | Update interval ms | Changed synthesized pixels vs 8 | PSNR vs 48 real views |
|---|---:|---:|---:|---:|
| 8 | 11.005 ± 0.053 | 48.029 | baseline | 22.757 dB |
| 4 | 10.775 ± 0.069 | 47.770 | 0.01197% | 22.757 dB |
| 2 | 10.726 ± 0.032 | 47.723 | 0.34439% | 22.619 dB |

4 reduces GPU interval 2.09% and update interval 0.54%; 2 reduces them 2.54% and 0.64%. Small scene-specific savings, not a substantial universal FPS gain. 4 is not exact: PNGs differ despite low aggregate error. PSNR versus 8: 52.920 dB for 4, 36.971 dB for 2. Real anchors exactly match across variants and independent 48-real reference. No wall/engine ratio>1.5 anomalies.

8 also differs from all-real: synthesized PSNR 22.757 dB. Quality improvements should address visibility/disocclusions rather than treat 8-loop output as ground truth. Individual error causes were not fully localized.

Default 8 retained. `--iterations=4` is an optional quality/performance tradeoff; `--iterations=2` a more aggressive experiment. Other-scene speed, temporal stability and curved geometry not measured. Data: rendered1024/summary.json, quality.json, reference JSON/PNG. Nothing was pushed at this stage; engine code unchanged.
