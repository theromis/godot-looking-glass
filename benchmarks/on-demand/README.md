# On-demand quilts for static scenes

Set `Rig.update_on_demand = true` **before adding the rig to the scene tree**. The initial frame renders automatically. SubViewports then move from `UPDATE_ONCE` to disabled, retaining the GPU quilt texture. No repeated source captures or compute assembly occur until another request. The main window continues showing the cached texture; VRAM stays allocated.

```gdscript
var rig = preload("res://addons/looking_glass/rig.gd").new()
rig.total_views = 48
rig.real_views = 24
rig.synthesis = true
rig.update_on_demand = true
add_child(rig)
# After changing objects, materials, lights or environment:
rig.request_update()
```

Rig motion automatically updates cameras and requests a quilt. Individual Camera3D, viewport size, projection, geometry, material, light, particle, shader TIME and environment changes need explicit requests. Requests before the next render coalesce. Code waits for a fresh successful capture of **every** source, then assembles once. Capture versions and assembly state belong to the rendering thread; deferred callbacks notify the main thread. Completion counts command submission, not a GPU fence; RenderingDevice ordering makes the result available to subsequent preview.

This is explicit update control, not automatic World3D change detection. Keep `update_on_demand=false` (default) for continuous animation. Compute synthesis is required; raster fallback stays continuous. Switching after `_ready` is unsupported: recreate the rig. Parameters normally requiring recreation still do; `request_update()` does not rebuild camera configuration or push constants.

Accumulating TAA/FSR2, temporal GI, shader TIME and particles are untested. One request does not warm their histories. The application must issue sufficient sequential updates or use continuous mode. Physical Looking Glass and power consumption were not measured.

## Validation

`tests/test_on_demand.gd` compares raw GPU quilts with continuous rendering for copy, borrowed color and borrowed color+depth. Tests cover initial output, no idle captures/compute, request coalescing, object/material/light changes, rig motion, source-buffer resize and release. Odd tile size 65×67; exact pixel equality required throughout.

```sh
python3 tests/run_checks.py --godot /absolute/path/to/latest/godot
python3 benchmarks/on-demand/run.py --godot /absolute/path/to/latest/godot --results-dir benchmarks/on-demand/static1024
```

Demo: `--views=48 --real=24 --tile=1024 --borrow-depth --static --opaque --on-demand`. Animation and `--rendered-benchmark` are rejected with on-demand: idle quilt updates do not advance, so that benchmark would never finish.

Three sequential alternating pairs, 90 warmup and 240 measured **process/presentation frames**, 48 output / 24 real views, 1024² tiles, 512 static MultiMesh objects, four shared-atlas SpotLights. Both modes disable viewport/quilt timestamps. First captures compared by SHA-256. Actual work checks require two captures/dispatches for on-demand (initial plus explicit refresh at process frame 86, before measured idle) and at least 300 for continuous. Startup process calls can precede capture; the initial minimum of 330 incorrectly rejected 326 valid captures. That run remains in `rejected-startup-check/`, excluded from accepted results.

Faster idle preview does not mean faster generation of new views for moving scenes. GPU kernel time and watt-hours are not measured here.

## Initial frame and warmup

The first full series (`initial-frame1024/`) failed strict image equality: 76 of 201,326,592 RGBA components differed by one level out of 255 between the first cached quilt and late continuous reference. Cause unknown. It is not described as bit-identical or included in accepted results. The main benchmark **explicitly** calls `request_update()` at process frame 86, before 90-frame warmup ends. This compares cached settled output, not a guarantee that one initial render suffices for every effect. The production API does not automatically warm the scene.

## Accepted series: Apple M4, Godot 4.8-dev

| Metric | Continuous | On-demand after warmup |
|---|---:|---:|
| Process/presentation interval, mean ± standard deviation of three run means | 47.408 ± 0.296 ms | 16.535 ± 0.121 ms |
| Compute dispatches per run | 330 / 330 / 328 | 2 / 2 / 2 |
| Captures per source viewport per run | 330 / 330 / 328 | 2 / 2 / 2 |
| Repeated renders during measured idle | Every frame | 0 |

After the explicit pre-idle refresh, PNGs match bit-for-bit: SHA-256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. This is ~65.1% lower update interval for **a window displaying a cached image**, not higher new-light-field-frame throughput. Idle image is unchanged and memory remains allocated. No power, physical-display or other-GPU measurements.

Accepted data: `static1024/summary.json` and individual JSON/logs; combined results/limitations: `verified-results.json`. Experiment/API snapshot: `source-snapshot/`. All tests used only the latest local Godot 4.8-dev.

All **16 regression checks** passed: `regression48.log`, including on-demand scene/light changes, rig motion and resize.
