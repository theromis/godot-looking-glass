# Performance: measurements and testable hypotheses

## Executed measurements

Apple M4, 10 GPU cores, macOS, official 4.5.1, Forward+, Vulkan 1.2.283/MoltenVK; Compatibility/OpenGL also tested. Window 1152×720, 128×128 tiles, 4 columns, static boxes/thin occluders/shadows, alpha panel as specified. 90 warmup + 240 CPU samples. JSON records engine/GPU/driver/resolution/transparency/view count; logs/PNGs in [benchmarks](../benchmarks).

| Run | Driver | Total/real | Alpha | Mean frame ms | p95 ms | Σ viewport GPU ms | Quilt compute GPU ms |
|---|---|---|---|---|---|---|---|
| real12 | vulkan | 12/12 | yes | 16.573 | 16.667 | 10.891 | — |
| synth12 | vulkan | 12/4 | yes | 16.476 | 16.667 | 5.462 | 0.364 |
| real48 | vulkan | 48/48 | no | 35.817 | 36.310 | 34.759 | — |
| synth48 | vulkan | 48/12 | no | 16.420 | 16.987 | 10.254 | 0.631 |
| compatibility12 | opengl3 | 12/12 | yes | 4.190 | 4.846 | 0.000 | — |

`frame_*` is `_process` wall delta including scheduling/engine/preview. `Σ viewport GPU` sums engine durations, not critical path, and cannot freely be added to other times; includes capture. Quilt compute RD markers cover synthesis/composition, not the whole frame. Compute means include startup/warmup; CPU/viewport means are post-warmup. Compatibility 0 means unavailable timer, not free rendering.

Matched opaque/static 48/48 and 48/12: 35.817/16.420 ms (~2.18× wall ratio), single sequential runs, not robust universal or Unity comparison. ~16.7 ms pacing plateau despite disabled VSync may reflect platform scheduling. 12/12 versus 12/4 does not prove speedup; both near plateau. synth12 predates redundant-raster removal, synth48 disables it, so the 12/12 versus 12/4 pair is not strictly controlled.

Substantial loss: [quality48.json](../benchmarks/quality48.json), 36 synthesized tiles versus static all-real, normalized MAE 0.04330 (range 0–1), PSNR 16.94 dB. Includes gamma/HDR transfer difference; diagnostic RGB, not optical quality. Visible thin-occlusion/disocclusion errors prevent FPS-only recommendations.

Native Metal 3.2/Forward+ initialized but compute demo exceeded 60 seconds and was stopped; unverified. `metal-synth12.log` retained without result JSON/PNG. SDK API declarations do not prove a working backend. Verified Apple path: Vulkan/MoltenVK. Compatibility selected all 12 real views successfully; different cost/quality, not proof OpenGL is better for production.

## Reproduction

```sh
GODOT_LG_BIN="../tools/Godot.app/Contents/MacOS/Godot"
"$GODOT_LG_BIN" --headless --path . --editor --import --quit
"$GODOT_LG_BIN" --path . --rendering-driver vulkan -- --views=48 --tile=128 --static --opaque --benchmark=res://benchmarks/real48.json --capture=res://benchmarks/real48.png
"$GODOT_LG_BIN" --path . --rendering-driver vulkan -- --views=48 --real=12 --tile=128 --static --opaque --benchmark=res://benchmarks/synth48.json --capture=res://benchmarks/synth48.png
"$GODOT_LG_BIN" --headless --path . --script res://tests/compare_quilts.gd
```

Run sequentially with visible active window; PNG readback occurs after measurements. Robust claims need at least 5 shuffled repeats, matched thermal/power/resolution/shadow/GI/MSAA state and uncapped pacing/separate GPU capture. Exclude GPU warmup throughout. That full campaign has not been completed here.

## Experiment matrix

| Optimization | Potential gain | Cost/risk | Validation |
|---|---|---|---|
| VK_KHR_multiview / Vulkan 1.1 groups 2/4/8 | Less CPU submission/preparation | Raster/vertex work remains; caps, 32-bit masks, union overdraw | Matched scene/count/pixels; render-thread CPU, vertex/fragment work, GPU critical path |
| Shared shadow atlas and union culling | Less repeated viewport work | Wider coverage, cascade-resolution loss, edge-visibility errors | Directional/spot/point scenes, shadow/cone edges |
| Texture arrays | Simple addressing/layer rendering | Memory/layer limits, lifetime/barriers, geometry changes | Peak VRAM, bandwidth, copies, group timing |
| Compute reprojection | Fewer real scene draws | Holes, BRDF/reflection mismatch, bandwidth, quality loss | Matched all-real, MAE/PSNR/edges/invalid ratio; separate opaque/alpha |
| Adaptive anchors | Real views concentrated on difficult intervals | Reduction/feedback delay, popping, variable cost | Thin fences, depth range, rotating foreground; mean/p95 and quality budget |
| Temporal reuse | Less real rendering in static regions | Vectors/history VRAM, ghosting, cuts | Moving objects/particles/disocclusions/teleports; rejection/history metrics |
| Depth-aware hole filling | Better local disocclusions | Extra pass, background smearing | Bounded radius, invalid counts, foreground/background errors |
| Direct GPU Bridge handoff | No readbacks | Exportability, fence/queue stalls, formats | End-to-end latency, copies/idle/native capture; no CPU image transfer |
| Native Metal/IOSurface | Direct Apple interop | Ownership/storage/synchronization; current run unverified | Matched MoltenVK scene, timers, output/reconnect |

Availability alone does not justify a feature. Pixel-bound scenes may gain nothing from multiview; CPU-bound draw-heavy scenes are more promising. Smaller groups can reduce overdraw while increasing submissions.

## Memory and copies

Capture owns 12 bytes/pixel/anchor (RGBA16F+R32F), quilt 8 bytes/pixel/target. 24×640×800 sources/48 targets: 344064000 bytes (~328 MiB) in addon textures alone, excluding engine attachments/shadows/history. MVP defaults smaller. Production needs VRAM budgets, smaller depth, packed formats/pools; tile-GPU MSAA/store-load may dominate.

Source copies deliberately provide a safe lifetime baseline. Remove only with verified transient RID access and dependencies before frame end. Main RD resources freed on render thread; no main-RD submit/sync. Local submit/sync only in GPU fixture. Dispatch/CPU `_process` duration is not GPU time.

## Presets

`quality`: all-real, better transparency/view shading, expensive. `balanced`: uniform sparse anchors, hole diagnostics, moderate tiles, experimental. `performance`: fewer anchors/lower resolution, more occlusion errors. These describe manual CLI settings, not implemented named automatic profiles/adaptation. Production presets need hardware/quality tests; default demo all-real 12.

## Addon CPU optimization (October 11, 2026)

Cached neighbors/constants/uniforms remove 240 per-frame RDUniform creations for 48 outputs. Source RID changes invalidate sets. Eye offsets cached; transform setters only on rig motion. GPU algorithm/shader unchanged at this stage.

Three before/after sequential runs, 48/12, static opaque 128×128, M4/Vulkan. Submission after 90 warmup: 0.32686 → 0.02250 ms (−93.1%, ~0.304 ms saved), not 14.5× whole-render speedup. Frame 16.671 → 16.590, quilt GPU 0.645 → 0.623 ms; near variation, no sustained FPS evidence.

Before/after PNG exact, SHA-256 `10e8a4445bdb63d80fc6ee6989a237c3e668e404323496885100f8e9a4afc155`. Regressions including rig motion passed. Data: `benchmarks/optimization/before-*`, `after-*`, [summary.json](../benchmarks/optimization/summary.json). Runner: `python3 benchmarks/optimization/run.py STAGE [TILE_SIZE]`.

## Exact-convergence GPU optimization

`synthesize.glsl` gains exact fixed-point exit: if reread depth equals the depth used for UV, subsequent UV/iterations are identical. Otherwise continue up to 8 steps. Bounds/residual/source resolution/fallback unchanged; no approximate threshold added.

Three before/final-after runs, 48 output/12 real, opaque static **512×512**, M4/Vulkan. GPU mean **4.058 → 3.189 ms** (−21.4%, ~0.868 ms); between-run standard deviation 0.046/0.146. Pass-specific, not application speedup. Intermediate `gpu-after-*` retained; summary uses `gpu-after-clean-*` without concurrent regressions.

Unstable frame means: before 16.678/16.676/8.153 ms, final after 16.232/16.666/15.208 ms. **FPS gain unconfirmed**; platform/window pacing affects wall. Offscreen/uncapped benchmark needed for critical path. Here timestamp scopes support pass savings.

PNG exact, SHA-256 `fab878ac240682fab0a54913e8306e371de65a573c657bd93892713d73802722`. [summary-gpu.json](../benchmarks/optimization/summary-gpu.json); old shader `benchmarks/optimization/baseline-synthesize.glsl.txt` enables manual A/B substitution/reimport. Final shader/projection/motion/analytic GPU/Bridge regressions passed.


## Godot engine experiment: shared positional shadows

Separate **4.8-dev** runtime built/executed from `232e6b14abf6e590b41d60f11704e42de22bff72` plus opt-in patch. M4/Forward+/Vulkan **1.2.334**, Homebrew MoltenVK. Different binary/driver; comparisons remain within it, not earlier 4.5.1 numbers.

Three alternating baseline/shared pairs per count: opaque, four shadowed SpotLights, deterministic frame-index caster rotation, 128×128, 90 warmup + 240 measured frames. Tighter culling disabled/LOD=0 in **both**. Ordinary addon defaults retained; isolation runner creates separate project.godot.

| Metric: mean of three runs | 12 baseline | 12 shared | 48 baseline | 48 shared |
|---|---:|---:|---:|---:|
| Wall frame mean, ms | 16.581 | 16.675 | 32.964 | 21.983 |
| Summed viewport GPU durations, ms | 10.658 | 6.460 | 31.890 | 18.913 |
| Summed shadow draw calls/frame | 528 | 44 | 2112 | 44 |

**48 real views**: wall −**33.3%**, GPU sum −**40.7%**, shadow draws −**97.9%**. Run-mean stdev wall 0.187/0.279 ms, GPU sum 0.145/0.118. Scene-specific M4 gain, not universal/Unity comparison. At 12 views, wall unchanged despite ~39.4% GPU savings near 16.7 ms plateau. Wall includes instrumentation/preview; viewport sum is not critical path.

Both counts' baseline/shared PNGs exact; 48 SHA-256 `9df4ac0e3a7ef7a49371d34f1a5b132e08eb4d7a750e8f27b5b729b9dee4ecbf`. Disabling positional shadows yielded 0 shadow draws and **629453 changed RGB channels**, MAE 0.002660, PSNR 44.085 dB, confirming actual shadow sensitivity. Not exhaustive coverage/allocation/subdivision testing.

Runtime **OmniLight + SpotLight**, three viewports/moving caster: shadow draws 12 → 4; incompatible LOD 8, partial mask 8, chain/cycle 12, owner deletion 8. No render errors. Release-safe checks return exit 1; tighter-culling negative control correctly exited 1. Projection/GPU/Bridge regressions passed patched 4.8 and official 4.5.1.

Data: `benchmarks/engine-shadows/summary.json`, `v48-summary.json`, per-run JSON/log/PNG, `test-shared-shadows.log`, `shadow-visibility.log`, `regression-4.8.log`, `regression-4.5.log`. Reproduction/limits: `engine-patches/README.md`. No directional, union culling or native multiview sharing. Viewports retain fallback atlases; VRAM savings unmeasured.

## Scene preparation after shared shadows

New M4/patched-4.8/Vulkan-MoltenVK test: 48 real 128×128 views, four SpotLights, 512 extra static BoxMeshes plus moving caster. Shared geometry/material both paths; separate MeshInstance3D versus one MultiMeshInstance3D. Shared shadows, full culling, LOD=0. Three alternating repeats, 90 warmup + exactly 240 samples.

| Mode | Frame mean ms | CPU viewport sum ms | GPU viewport sum ms | Scene draws | Shadow draws |
|---|---:|---:|---:|---:|---:|
| Separate instances, 128² | 22.447 | 2.480 | 19.767 | 586 | 78 |
| MultiMesh, 128² | 22.594 | 1.332 | 19.916 | 490 | 48 |
| Separate instances, 64² | 22.468 | 2.472 | 19.879 | 586 | 78 |

MultiMesh reduces measured CPU preparation 46.3% without whole-frame gain; fourfold tile-area reduction also gives none. These observations do not isolate a GPU bottleneck: pass scopes/capture needed. Shared culling remains unimplemented with no verified FPS gain.

512 objects do not require 512 draws/view: Forward+ instances compatible surfaces. `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:898–900` counts equal sort keys, `:608` uses repeat as instance_count, `:627` skips repeated entries. MultiMesh mainly lowers preparation object count here. It loses per-instance frustum culling; large scenes need spatial groups.

Separate/MultiMesh PNG exact, SHA256 `5c6e10f50008008b5e3c28d9ad17747a2227a5980335166a5aad6b7e552f07ba`. CPU sums include only anchors; global setup separate, main/quilt excluded. Frame is engine `_process(delta)`, not independent OS timing. Counters add overhead to both modes.

Fixed capture-time benchmark bug: `_finish()` disables `_process` before `frame_post_draw`, preventing extra samples/caster motion. Initial runs overlapped GPU regressions, remain in `benchmarks/scene-preparation/discarded` and are excluded.

Data/reproduction: `benchmarks/scene-preparation/summary.json`, per-run JSON/log/PNG, `run.py`.

Same-scene MultiMesh 12/24→48 synthesis: three alternating runs, frame 16.173/16.554 versus 22.594 ms all-real, anchor CPU 0.750/1.060, GPU 6.252/9.195 ms. Full-quilt PSNR 16.902/21.268 dB, MAE 0.04414/0.02477, including gamma/tonemap mismatch. 24 anchors offers better quality at close frame cost here; adaptive placement absent. Synthesis ran after instances suite without concurrent GPU tests.

Ordinary preview no longer gathers benchmark samples, avoiding continuous queries/unbounded arrays. Separate FPS gain unmeasured.

## GPU timestamp impact on the workload

Separate built-in-marker/RD diagnostic, no new patch: M4/Vulkan/MoltenVK, 48 real 128², 512 MultiMesh boxes/moving caster, four SpotLights, three repeats/mode. Independent Time.get_ticks_usec wall timer added alongside engine delta.

Shared with viewport queries 22.533 ms; without 20.145 (−10.6%); independent without 28.795. Shared gain ~30.0% remains without queries. Full-resolution PNGs exact. Different stress scene, not a revision of initial engine-shadow measurements.

Detailed markers cost 64.161 ms without GDScript collector, 65.019 with it; 1719 markers/frame are not a normal 20 ms breakdown. Graph adjacency at RenderingDeviceGraph::_add_command_to_graph, rendering_device_graph.cpp:395–406; Vulkan command_timestamp_write at rendering_device_driver_vulkan.cpp:6894–6896 uses BOTTOM_OF_PIPE. Query/driver/MoltenVK/reorder overhead shares unknown.

Default rig `measure_render_time=false`; demo enables it for benchmarks unless --no-viewport-timing. Detailed diagnostic needs --gpu-profile before -- and --profile-passes after, pool 4096. Only this diagnostic separately measures main/quilt. Scopes may contain barriers/transitions/idle; disabled timing 0 means unmeasured.

Raw JSON/log/PNG/markers, means/stddev/commands: benchmarks/gpu-passes/README.md, summary.json, overhead-summary.json. Regressions passed after disabling ordinary queries. Further analysis needs low-intrusion GPU capture; normal shader-pass cost remains unproven.

## Removing the owned HDR color copy

Opt-in borrow_source_color / --borrow-color directly uses POST_TRANSPARENT Godot HDR RID. capture_depth.glsl owns only linear R32F depth; no extra RGBA16F, capture color imageStore/texelFetch. Depth compute remains; fewer copies/traffic, not zero capture dispatches. Default copy.

M4/Vulkan/patched 4.8, shared shadows both modes, viewport queries off. Dynamic 512², 48/24, three copy/borrow runs, 90 warmup + 240 process samples, 330 dispatches each. Wall 16.712/16.643 ms, no confirmed FPS gain; exact PNG, 48 MiB payload removed.

Static 1024² successful-update sampling, three runs, 90 warmup + 240: wall 52.205±0.057 → 49.656±0.121 ms, −4.88%, including scheduling/presentation. Exact PNG, 192 MiB payload removed (24×1024²×8 bytes), total residency unmeasured. Quilt compute 12.253/12.359 ms does not accelerate; configuration savings outside synthesis.

Dynamic/static scenes and sampling differ; not one scaling curve. Rejected 1024² process run retained: 330 calls/199 dispatches, no performance conclusion. Zero-dispatch initial runs retained after fixing array typing. Runner rejects absent work/GPU samples/incomplete counts.

Copy/borrow tests require advancing/nonempty quilts, exact float output at 64/48/80, double release and engine-color survival. Four regressions passed official 4.5.1/patched 4.8. Capture retains owner, refreshes RIDs and frees no borrowed resources. TAA/FSR2/MSAA/glow/other later effects untested at this stage; default copy retained.

Code: addons/looking_glass/capture.gd, shaders/capture_depth.glsl, rig.gd; tests/test_capture_lifetime.gd. Data/commands: benchmarks/borrow-color/README.md, summary.json, rendered1024/summary.json. No engine change.


## Removing the intermediate depth copy

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, repeated series `recheck1024/summary.json`: three pairs, each with 240 observed intervals after 90 warmup. Linear-depth copy: 50.903 ± 0.997 ms; direct depth: 48.688 ± 0.934 ms (standard deviation of run means), −4.35%. Synthesis+quilt GPU time: 12.539 → 11.094 ms (−11.52%). GPU means include startup, not isolated capture. CPU submission ~0.070 ms in both modes. All six records contain at least 330 dispatches; first-pair PNGs match byte-for-byte, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`.

Initial series `rendered1024/` retained for audit: linear-3 reported wall 155.75 ms against engine delta 51.70 ms. Cause unknown; that series' wall mean is not used for speedup claims. The repeat used unchanged code/settings. Do not add this gain to the color-copy gain from another series. The new depth path has not yet been measured at 512².

Implementation: capture.gd, synthesize_raw_depth.glsl, synthesizer.gd; opt-in `--borrow-depth` also borrows color. Eliminates calculated 96 MiB R32F payload, not measured total VRAM. Lifetime/resize/equality tests passed 4.5.1/4.8. Temporal/MSAA/post effects and physical hardware untested at this stage. Method: benchmarks/borrow-depth/README.md.


## Compute workgroup size validation


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

Method: benchmarks/workgroups/README.md.


## Reprojection iteration limits


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

Method: benchmarks/iterations/README.md.


## Measured results

Apple M4, Godot 4.8-dev/Vulkan-MoltenVK, 24 → 48, 1024², three pairs:

- Synthesis+quilt GPU time: baseline 10.997 ± 0.033 ms → rescue 11.364 ± 0.021 ms, +3.34%. Standard deviation of three run means.
- Observed update interval: 48.019 ± 0.184 → 48.188 ± 0.057 ms, +0.35%. No speedup.
- Invalid two-source correspondences: 681614 → 667752 of 25165824 synthesized pixels. Recovered 13862 (2.03% of the initial invalid mask), with no new holes.
- Recovered-mask PSNR against all-real: 6.928 → 18.624 dB. Overall synthesized PSNR: 22.757 → 22.843 dB; RGB MAE 2.332 → 2.292 in 8-bit units.
- Real anchors exact; changed pixels outside the baseline hole mask = 0. Baseline PNG SHA matches the earlier 8-iteration benchmark.

Conclusion: small measured quality improvement at additional GPU cost. Opt-in `--rescue`, default false. Limited correspondence search does not eliminate all disocclusions. This static test cannot establish freedom from temporal flicker/foreground bleeding elsewhere. Raw JSON/log/PNG retained; no wall anomalies at ratio>1.5.

Eight regressions passed on 4.5.1 and 4.8: projection, planar 8/2/4, synthetic recoverable layers on linear/reverse-Z depth, capture/workgroup lifetime, Bridge fixture. Synthetic source depths 2/3/6 occupy neighboring strips: baseline oscillates 2↔6, while hypothesis 3 recovers the analytically known source pixel. Not every generated rescue/group/iteration combination was executed; performance/quality measured at 8×8/8.

Method: benchmarks/disocclusion/README.md.


## Borrowed-buffer compatibility fallback

15 renderer configurations tested on Apple M4/Vulkan, 4.5.1/4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, additional compositor, reset. Final raw RGBAH matrix compares default copy, borrowed color, borrowed color+depth. Production policy yields exact results; all nine regressions passed on both versions.

Direct color without fallback differs with TAA or a later color-modifying POST_TRANSPARENT effect. Capture snapshots color/depth for TAA or any additional enabled compositor, then returns to direct access when removed. Raw fallback preserves reverse-Z in R32F and synthesis interpretation. RID changes refresh descriptors; only owned textures freed. Compositor WeakRef avoids cycles.

MSAA/FXAA/FSR1/FSR2/scaling/glow/tonemap retained tested equivalence, specifically to POST_TRANSPARENT snapshots. Final temporal/postprocessing output is not in quilts; jitter/dynamic quality untested. Manual draw/sync are correctness tools, not timing benchmarks. New policy speed unmeasured; reports expose effective borrowing, fallback reasons and actual-dimension payload.

Initial internal-48² FSR2 probe produced uavMip errors and was rejected; internal 128² repeat passed. Engine bug/minimum size unresolved. Native Metal, other GPUs, physical Looking Glass, motion/particles/transparency untested. Commands/JSON/log: benchmarks/buffer-compat/README.md.


## Optional bounded quilt profiling


## Measured result

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, 24 real → 48 output, 1024², three pairs:

| Quilt profiling | Observed update interval ms | Run stddev ms | Recorded GPU/CPU samples |
|---|---:|---:|---|
| on | 47.6166 | 0.0835 | 327 GPU / 240 CPU per run |
| off | 47.6215 | 0.0460 | 0 / 0 |

No update-time gain established: +0.0049 ms is below variation. Each run has 240 samples and 331 dispatches. On submits 331 marker pairs; off 0. Off GPU/CPU submission durations are null, not zero work. First-pair PNG exact, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. No wall/engine ratio>1.5 anomalies.

Default profiling-off avoids instrumentation and growing sample arrays, without an established FPS gain here. Limit=4 ring test retained exactly four GPU/CPU samples after at least 140 actual updates and exact moving-object output.

Data: rendered1024/summary.json, per-run JSON/log/PNG, checks-4.5/4.8.log. Earlier viewport timestamp measurements (+1719 native markers) concern a different workload and cannot be added to this result.

Method: benchmarks/quilt-profiling/README.md.


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


## Real-view budget curve


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

Method: benchmarks/view-budget/README.md.


## Nonuniform anchors: measured negative result

Added optional strictly increasing `custom_anchor_indices` (demo `--anchors=`), with validation and effective anchor telemetry. An offline selection of 24 cameras from the previous 16-view RGB errors worsened whole-quilt PSNR from 25.768 to 24.088 dB and increased squared error 47.21%; observed quilt-update intervals 48.317±0.425 versus 48.204±0.090 ms do not establish acceleration. Uniform remains the default; no runtime adaptive controller is implemented. See [benchmark details](../benchmarks/anchor-placement/README.md).


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](../benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](../benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](../benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](../benchmarks/depth-overhead/README.md).


## Compact GPU depth feedback

GPU reduction of the optional depth diagnostic now returns 768 bytes instead of 786,432 bytes for 48 views at 256². On current Godot 4.8-dev / Apple M4, three repeated async experiments reduced CPU decoding from 20.499±1.021 to 0.306±0.009 ms per callback (about 67×). Isolated GPU scopes 1.371±0.021 versus 1.365±0.043 ms show no measurable extra GPU cost; quilt update intervals remain 48.27 ms and callback latency about 97 ms. GPU totals match CPU sums exactly, all output PNGs match byte-for-byte, and all 15 regression checks pass. This reduces diagnostic CPU work, with no established FPS gain. Uniform view selection and addon defaults remain unchanged. See [implementation, measurements and reproduction](../benchmarks/depth-reduction/README.md).


## Static quilt updates on demand

Optional `update_on_demand` renders source views and assembles the compute quilt only when `request_update()` is called. Rig motion requests updates automatically; the application explicitly reports object, light, material and environment changes. On current Godot 4.8-dev / Apple M4, three pairs of the static 24→48 scene with 1024² tiles reduced process/presentation interval from 47.408±0.296 to 16.535±0.121 ms. After warmup, the cached quilt matches the continuous reference bit-for-bit. Idle performs no repeated source captures or compute dispatches; the window keeps presenting the cached texture. This saves static-scene work rather than accelerating new animated views. The first large-scene frame differed in 76 RGBA components by at most 1/255, so the benchmark explicitly refreshes the quilt before measured idle. The startup difference has no established cause; no automatic warmup is implemented. Mode is off by default and does not modify the engine fork. See [API, limitations and measurements](../benchmarks/on-demand/README.md).


## Metal correctness before timing

Native Metal default barriers fail three image-equivalence regressions on the current Apple M4 / 4.8-dev setup. Native hazard tracking (`GODOT_MTL_SYNC_MODE=none`) passes all 16 checks; both default-barrier diagnostic runs reproduce source/viewport mismatches. This is a correctness workaround, not a measured optimization. The switch also changes heap/allocation policy, so future mode comparisons must record it and independently verify camera images. Do not compare frame times from an incorrect multi-camera baseline as equivalent work. See [evidence and limitations](../benchmarks/native-bridge/metal-sync-results.json).

## Native Metal direct SDK output checkpoint

The frozen-quilt experimental path imports a Bridge RGBA8 IOSurface through public RenderingDevice API and writes the quilt directly into it. A three-run output-boundary microbenchmark at 4092² measured direct constant-fill GPU time of 0.64–0.73 ms versus 1.96–2.20 ms for private output plus blit. The same shader, alternating mode order and completed command-buffer timing were used; all final target bytes were verified after timing. This is a synthetic output-boundary result. Actual depth synthesis, scene FPS, optical processing, presentation latency and live texture reuse remain unmeasured. See [complete protocol and limitations](../benchmarks/hardware/direct-target-microbenchmark.md).
