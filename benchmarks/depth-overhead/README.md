# Depth-probe cost on latest Godot 4.8-dev

Measured only on the user's newest local custom 4.8-dev build, Apple M4, Vulkan/MoltenVK. Executable SHA256: `e3f0117c1da12d25f8ed25fe28ebae6595db1efff1960ee01360ed745e594ced`. No old Godot executable was run in this step.

Scene: 48 output views, 24 uniformly spaced real cameras, 1024² tiles, 512 MultiMesh boxes plus foreground occluders, four shared-shadow SpotLights, static opaque geometry. Raw depth/color borrowing, eight-step synthesis, 8×8 workgroups; viewport timestamps disabled, quilt timestamps enabled. Probe operates on all 48 output slots, including zero-counter real-view slots. Initialization, shader compilation and uniform creation are outside measured steady-state intervals. Exact quilts match every tested mode, including isolated timer controls, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`.

## Calibrated GPU scope

Simple begin/end timestamps around a second compute list gave implausible 0.005–0.010 ms and did not scale with work. They are not reported as shader timings. Godot's `RenderingDevice::capture_timestamp` records graph queries (local engine `servers/rendering/rendering_device.cpp:8955`); the Vulkan driver writes them at BOTTOM_OF_PIPE (`drivers/vulkan/rendering_device_driver_vulkan.cpp:6894`). The query values do not prove isolated pass boundaries on this backend.

On the stage-counter path, MoltenVK defers queries to the end of an encoder batch rather than sampling individual dispatches: see `markTimestamp` / `encodeTimestampStageCounterSamples` in the [official MoltenVK v1.4.1 source](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.1/MoltenVK/MoltenVK/Commands/MVKCommandBuffer.mm). The installed library link used by the SDK points to Homebrew 1.4.1; the executable hash is the precise build identity. A deferred batch can place logically separate queries together; a neighboring pass's marker interval can also include later work. This explains the observed anomaly, but is not a general diagnosis of every historical timestamp measurement.

The experimental isolated timer adds a four-byte GPU buffer copy after the start marker and another after the end marker to create blit/compute encoder boundaries. An empty control measures the same timer/copy sequence without a kernel. Three sequential repeats per configuration, rotated order, 30 actual quilt-update warmup submissions, 60 measured intervals per repeat. All 60 expected timestamp pairs were delivered in each run. Counts and quilts remain correct.

| Probe grid | Isolated GPU scope, mean ± run SD | Scope minus mean empty control |
|---|---:|---:|
| Empty timer | 0.00330 ± 0.00042 ms | — |
| 64×64 | 0.52263 ± 0.00828 ms | **0.51933 ms** |
| 128×128 | 0.81217 ± 0.01480 ms | **0.80887 ms** |
| 256×256 | 1.37975 ± 0.02476 ms | **1.37645 ms** |

These are per probe of the whole 48-slot quilt, not per camera. They include compute/dispatch and forced encoder-boundary effects, not pure arithmetic instruction time. Calibration removes the empty timer's measured scope; it cannot prove removal of all serialization effects introduced by profiling. The GPU-isolation experiment is separate from normal runtime overhead testing. Its frame-time averages must not be used as production FPS effects.

## Runtime feedback costs

A second series uses the ordinary callback path without artificial encoder boundaries: seven modes, three sequential repeats, rotated order, 90 warmup and 240 observed quilt-update intervals per run. Every-frame GPU-only grids 64/128/256 and rare 256² probing are compared with disabled probing. Rare feedback runs every 16 quilt submissions; there are 15 measured requests/callbacks per repeat.

| Feedback path at 256², every 16 updates | CPU work/blocking per request, mean ± run SD |
|---|---:|
| Synchronous `buffer_get_data` plus CPU block summation | **87.39 ± 7.83 ms** |
| Asynchronously delivered buffer: CPU block summation | **19.94 ± 1.42 ms** |

Async delivery latency before CPU summation is **110.92 ± 12.36 ms**. It is delayed feedback, not instantaneous scene information. Async enqueue/transfer work is not included in the decode timer; latency includes frame scheduling and queued work. Both variants read 786,432 bytes per probe, then reduce workgroup blocks on CPU. This prototype performs substantial GDScript work; the data do not establish that transferring those bytes intrinsically costs 20 ms.

Godot's synchronous path explicitly calls `_flush_and_stall_for_all_frames` before mapping the temporary buffer (`RenderingDevice::buffer_get_data`, local engine `servers/rendering/rendering_device.cpp:1360`, stall at `:1384`). `buffer_get_data_async` (`:1403`) instead queues a staged download/callback. A diagnostic native stack contained `vkWaitForFences`; a smaller 256-tile debug run continued processing requests, so there is no proven deadlock. The initial full-rate synchronous 1024-tile run timed out after 240 seconds and produced no complete timing result. It is excluded, not assigned a fabricated mean.

## Frame impact is inconclusive

Ordinary runtime observed update intervals, mean ± run SD:

| Mode | Update interval |
|---|---:|
| Probe off | 51.55 ± 4.96 ms |
| GPU 64² every update | 54.53 ± 10.35 ms |
| GPU 128² every update | 58.67 ± 9.69 ms |
| GPU 256² every update | 60.54 ± 8.97 ms |
| GPU 256² + sync feedback every 16 | 55.79 ± 6.86 ms |
| GPU 256² + async feedback every 16 | 54.99 ± 6.13 ms |

These are measured observed submission-update intervals, including presentation/scheduling, not isolated GPU completion times or physical display FPS. Between-run variation is too large to assign reliable FPS penalties to each grid or establish an async FPS improvement.

GPU-only sparse runs 1/3 gave wall intervals 126.92 / 815.99 ms while corresponding engine deltas were 56.60 / 60.01 ms. They fail the pre-existing wall/engine ratio >1.5 guard and are excluded from frame-impact claims. The remaining sparse run is insufficient for a three-repeat summary. The cause of this scheduling/observation disagreement is not established. Raw anomalous values are retained; the invalid aggregate in `runtime1024/summary.json` must not be interpreted as a kernel slowdown. `verified-results.json` records these qualifications explicitly.

## Code and tests

- `tests/depth_probe.gd:16` configures persistent resources; `:72` dispatches cached constants/sets; `:82` synchronously reads; `:86` separately decodes data; `:96` releases resources. It rebuilds bindings when source depth RIDs change and supports reconfiguration.
- `tests/benchmark_depth_overhead.gd` separates measured CPU submission, scoped timestamps, feedback duration and async delivery latency. It drains queued callbacks before release. The isolated copies belong to the benchmark, not normal addon rendering.
- `tests/test_depth_proxy_analytic.gd` checks analytic counters, repeated dispatch without shader recreation, replacement depth RID, grid reconfiguration and idempotent release. All passed on 4.8-dev.
- All 15 project regression checks passed on the same latest build. No older-version comparison was performed.

The normal addon has no enabled depth-analysis controller and still produces its quilt without CPU readback. These changes are diagnostic infrastructure; they do not rescue the earlier depth-guided placement's negative quality result.

## Reproduce

Import project shaders first. Run tests/benchmarks sequentially, with no concurrent GPU workload or CPU image analysis:

```sh
python3 benchmarks/depth-overhead/run.py --godot path/to/current-4.8 --results-dir benchmarks/depth-overhead/new-isolation --isolate
python3 benchmarks/depth-overhead/run.py --godot path/to/current-4.8 --results-dir benchmarks/depth-overhead/new-runtime
python3 tests/run_checks.py --godot path/to/current-4.8 --driver vulkan
```

The runner rejects older engine versions, missing compute work, missing isolated timestamp samples, incorrect counter bounds, pending async callbacks and changed quilts. `isolation1024/` and `runtime1024/` retain JSON, logs, PNGs and summaries; `source-snapshot/` and `source-sha256.json` preserve measured implementation. `rendered1024/` contains the preliminary partial series that stopped at the synchronous timeout; it is not the accepted matrix. The debug stack/log and smoke results are diagnostic evidence, not substitutes for the accepted scenes.

## Practical next step

The largest measured avoidable CPU work is summing all workgroup counters after feedback. A final GPU reduction could return 48×4 uints = 768 bytes instead of 786,432 bytes; skipping real-view probe dispatches is another candidate. Benchmark both changes rather than assuming a net gain. Keep feedback asynchronous and amortized if it is needed. A useful controller still needs a quality objective and an acquisition strategy whose total cost is outweighed by fewer rendered views; neither is demonstrated here.
