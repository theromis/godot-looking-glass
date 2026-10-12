# 66-view quality comparison

Executed on 2026-10-12, Apple M4, Godot 4.8 c61fc0118, native Metal Forward+ with `GODOT_MTL_SYNC_MODE=none`. The same static opaque box/RGB-sphere scene and 54-degree cone are rendered into 1408×1368 RGBA8 quilts (11×6 views, 128×228 tiles). All variants use the same shader output path: borrowed reverse-Z depth, eight iterations and uniform anchor placement. The reference has 66 real cameras; candidates have 12, 24 and 36.

| Real cameras | Synthesized views | Synthetic-view PSNR dB | MAE [0,1] | Pixels with any RGB error >0.1 |
| --- | --- | ---: | ---: | ---: |
| 12 | 54 | 27.82 | 0.002609 | 0.548% |
| 24 | 42 | 29.81 | 0.001561 | 0.322% |
| 36 | 30 | 29.74 | 0.001564 | 0.326% |

Each row excludes its real anchors. Because these masks differ, `quality.json` also compares the same common synthesized views across all budgets: 27.81 / 29.81 / 29.82 dB for 12 / 24 / 36. Every real anchor tile matched its all-real reference exactly. Thus the similar aggregate quality for 24 and 36 is also seen on the common mask, rather than being solely a consequence of comparing different views.

Reference color-gradient boundaries had mean RGB errors 0.0723 / 0.0429 / 0.0387. This is a color-edge proxy, not a disocclusion detector. Large blue background regions dilute whole-image metrics. Artifacts remain at object boundaries; PSNR alone does not establish acceptable autostereoscopic appearance.

Twenty-four cameras are a candidate balanced preset for this scene, not a new automatic default. No FPS or timing comparison is made here. Transparent objects, particles, moving objects, complex materials, fine geometry and physical optical quality remain to be tested. The physical display was not driven by this capture test. The prior user-confirmed hardware baseline uses 66 real cameras.

## Reproduction

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal --script tests/capture_quality66.gd
python3 benchmarks/view-budget66/analyze.py
```

The analyzer requires NumPy and Pillow. Generated PNGs remain local/ignored; hashes, configuration, full per-view errors and common-mask statistics are saved in `quality.json`. Require the capture PASS marker, exit zero and no script errors before analyzing. All metrics use RGB bytes normalized to [0,1], with alpha excluded and no extra gamma conversion.
