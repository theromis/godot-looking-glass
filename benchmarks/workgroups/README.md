# Compute workgroups A/B/C

```sh
python3 benchmarks/workgroups/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/workgroups/rendered1024
```

Compare 8×8 (64 invocations), 16×8 (128), 16×16 (256). Only local size/dispatch grid change; algorithm/capture/scene fixed. Selector `--workgroup=8x8|16x8|16x16`, export `synthesis_workgroup`. Default 8×8 until other-GPU testing. Shaders imported beforehand; compilation excluded. After canonical changes, run `python3 addons/looking_glass/shaders/generate_workgroups.py` and editor import.

Scene: Apple M4, 4.8-dev, Vulkan/MoltenVK, 24 real → 48 output, 1024², 512 static MultiMesh boxes, 4 SpotLights, shared atlas, borrowed color/depth. Three cyclic A/B/C, B/C/A, C/A/B repeats; 90 warmup + 240 observed updates. Two equal GPU markers; mean includes startup, not whole-frame GPU time. First-three PNG SHA256 compared; JSON/log/PNG retained. Wall anomalies require analysis, not concealment.

All four regressions passed on official 4.5.1/experimental 4.8. Lifetime test covers 9 capture/group combinations, exact raw quilts, 65×67 tiles, 64/49/81 source resize and borrowed resources surviving release. Checks partial-group coverage and tile bounds.

One scene/GPU only. Larger groups may change occupancy, active-group count, register pressure and locality; no assumed speedup. TAA/FSR2/MSAA/post effects and physical Looking Glass untested.


## Apple M4 results

Three repeats per variant, 24 → 48 views, 1024². Synthesis+quilt GPU time (mean ± standard deviation of run means):

| Local size | GPU ms | Change versus 8×8 |
|---|---:|---:|
| 8×8 | 11.179 ± 0.127 | baseline |
| 16×8 | 11.470 ± 0.043 | +2.61% |
| 16×16 | 11.270 ± 0.257 | +0.82% |

Larger groups show no confirmed acceleration; default 8×8 retained. 16×16 is close to baseline with overlapping variation. Do not generalize to other scenes/GPUs.

Wall mean: 8×8 49.152 ms, 16×8 49.331 ms. 16×16-1 wall 96.796 ms versus engine delta 47.351 ms, unknown cause; retained/flagged in summary.json. Mean wall 16×16 cannot establish kernel slowdown. No need to repeat searching for a winning result: GPU scope does not show expected speedup.

All nine runs valid by dispatch/sample count; first-three PNGs match SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Data: rendered1024/summary.json and per-run JSON/log/PNG. Default unchanged; selector retained for other GPUs.
