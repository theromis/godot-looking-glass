# GPU pass intervals and timestamp overhead

Godot RenderingDevice diagnostic profiler; no new engine patch. Scene: 48 real off-axis 128² views, 512 identical MultiMesh objects plus the original moving caster, four SpotLights, shared World3D; Apple M4, Vulkan/MoltenVK, patched 4.8-dev.

```sh
python3 benchmarks/gpu-passes/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 benchmarks/gpu-passes/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --suite overhead
```

Each mode runs three times, 90 warmup + 240 samples, sequentially without unrelated GPU load. Requires imported project shaders and the experimental shared-shadow runtime. Runner creates an isolated full-caster-culling project and a 4096-marker query pool. Reruns overwrite the selected suite's results.

Main suite:

- `control`: standard viewport begin/end timestamps, no detailed pass markers.
- `profile`: `--gpu-profile` before `--` and `--profile-passes` after; all pass markers plus RenderingDevice reads on the render thread.
- `profile-half-resolution`: same profiler, 64² tiles.

Overhead suite:

- `timing-off`: shared shadows, begin/end timestamps disabled through `--no-viewport-timing`.
- `timing-off-independent`: independent atlases, timestamps disabled.
- `markers-only`: detailed engine markers without the GDScript profiler; separates GPU capture cost from result reading.

Frame time is measured independently with `Time.get_ticks_usec` between `_process` calls. It includes scheduling/presentation, not isolated GPU critical-path time. Engine delta remains separately available. Zero viewport GPU values with timestamps disabled do not mean zero GPU workload.

Profiler sums adjacent GPU marker intervals by viewport role (`anchors`, `quilt`, `main`, `outside_viewports`). Full viewport spans overlap pass intervals and must not be added to them. Scope boundaries are retained. Each profile JSON stores one raw marker frame. The observed run had 1719 markers/frame and 240 unique timestamp frames; interval sum matched total marker span.

## What is actually measured

Opaque/transparent/depth/tonemap intervals may include transitions, barriers and idle time, not just a shader or draw work. Timestamps change the command graph and cost substantially on this backend. Without vendor GPU capture, the profiled breakdown is not an ordinary-frame breakdown.

Verified source references, Godot base `232e6b14abf6e590b41d60f11704e42de22bff72`:

- `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:2210`, `:2273`, `:2495`, `:2632`: depth, opaque, transparent and tonemap markers.
- `servers/rendering/renderer_viewport.cpp:357`, `:780`: viewport begin/end capture.
- `servers/rendering/storage/utilities.h:167`: RENDER_TIMESTAMP enabled by capturing_timestamps.
- `main/main.cpp:1955`, `:3597`: CLI --gpu-profile enables GPU profile printing.
- `servers/rendering/rendering_device.cpp:8955`: timestamp capture and query-pool limit; `:9086` onward reads results.
- `servers/rendering/rendering_device_graph.cpp:395–406`: timestamp commands add adjacency constraints to GPU commands.
- `drivers/vulkan/rendering_device_driver_vulkan.cpp:6894–6896`: vkCmdWriteTimestamp with VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.

These paths establish additional commands and ordering constraints. The overhead shares attributable to queries, MoltenVK, queues or restricted reordering remain unknown.

Addon `measure_render_time` now defaults to false; demo enables it only for benchmarks without --no-viewport-timing. This disables ordinary-preview diagnostics without changing rendering or the shared-shadow patch. Only the detailed profiler measures quilt/main viewports. Native Metal, other GPUs and physical LKG untested.

Final numerical results: `summary.json` and `overhead-summary.json`; raw JSON/log/PNG retained nearby. The first suite cannot directly establish uninstrumented shared-shadow savings; use timing-off/timing-off-independent for that comparison.

## Executed results

Three runs per mode. Independent wall-frame mean; ± is sample standard deviation across runs, not a confidence interval.

| Mode | Wall frame ms |
|---|---:|
| Shared, viewport timestamps | 22.533 ± 0.152 |
| Shared, no viewport timestamps | 20.145 ± 0.127 |
| Independent shadows, no timestamps | 28.795 ± 0.224 |
| All engine markers, no GDScript profiler | 64.161 ± 0.141 |
| All markers + GDScript profiler | 65.019 ± 1.703 |
| All markers + profiler, 64² tiles | 64.429 ± 1.166 |

Disabling begin/end timestamps reduces frame time 10.6% here. Shared shadows without those measurements reduce frame time 30.0% versus independent atlases. This new stress scene does not replace the earlier 32.96 → 21.98 ms result from another scene.

Control/profile/timing-off/timing-off-independent/markers-only PNGs match byte-for-byte: SHA256 `5c6e10f50008008b5e3c28d9ad17747a2227a5980335166a5aad6b7e552f07ba`. Equality holds for this workload, not all scenes.

Full profiled marker span ~65 ms; anchors ~60 ms, quilt ~0.25 ms, main ~0.38 ms. These describe a workload heavily altered by profiling. No specific unprofiled shader bottleneck is established. The useful verified result is removing continuous diagnostics from ordinary rendering.

Projection/GPU synthesis/Bridge regressions passed after default changes. Capture-only preview separately confirmed: no --benchmark statistics and no viewport timestamps.
