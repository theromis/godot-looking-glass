# GPU reduction of depth diagnostics

This optional diagnostic path reduces four unsigned counters per workgroup to four counters per output view. It does not alter source-view selection or quilt rendering. Uniform anchors remain the production default: the earlier depth-only selection experiments did not improve image quality.

`tests/depth_reduce.glsl` dispatches one 64-thread workgroup per view. Each thread sums strided blocks, followed by shared-memory tree reduction. Two separate RenderingDevice compute lists expose the storage-buffer write/read dependency to Godot's resource tracking. At grid 256 and 48 views, feedback shrinks from 786,432 to 768 bytes (1024 times smaller). The intermediate GPU buffer is retained. Shader compilation and resource allocation occur once at configuration, outside timing.

`DepthProbe.configure(..., gpu_reduction=true)` enables the path. `feedback_buffer()` chooses the correct async readback RID. `read_block_counts()` remains available for an untimed exact comparison. The benchmark option is `--probe-reduce-gpu`; each reduced run compares current GPU totals against CPU sums from the same intermediate buffer after measurement. Analytic tests cover persistent dispatches, grid changes and exact reduced counts at 64/128/256.

Run only the latest local Godot build:

```sh
python3 benchmarks/depth-reduction/run.py --godot /absolute/path/to/godot --results-dir benchmarks/depth-reduction/isolation1024 --isolate
python3 benchmarks/depth-reduction/run.py --godot /absolute/path/to/godot --results-dir benchmarks/depth-reduction/runtime1024
python3 tests/run_checks.py --godot /absolute/path/to/godot
```

The GPU series uses three rotated repeats per mode, 30 warmup and 60 measured updates. Explicit 4-byte buffer copies establish encoder boundaries around the probe on MoltenVK; an empty scope provides calibration. These are scoped GPU measurements including encoder transitions, not isolated shader instruction timing. The runtime series uses three rotated repeats, 90 warmup and 240 measured updates, with asynchronous feedback every 16 updates. It measures CPU decoding separately from callback arrival latency. Runtime timestamp deltas without encoder isolation are not valid standalone GPU timings on this driver.

Both series use 48 output views, 24 real views, 1024² tiles, 512 static batched opaque objects, four shared SpotLights, borrowed depth, eight inverse-warp iterations and disabled viewport timing. Runs are sequential. Strict checks require actual dispatches, callbacks, counter bounds, exact reduction, expected feedback size and identical output PNGs. Full-frame scheduling effects can be noisy; a smaller feedback buffer alone does not prove higher FPS. No physical Looking Glass hardware is involved.

## Executed results: Apple M4, current custom Godot 4.8-dev

Three repeats per mode; ± is standard deviation of run means, not a confidence interval.

| Metric | Per-workgroup feedback | GPU-reduced feedback |
|---|---:|---:|
| Feedback bytes at 256² / 48 views | 786,432 | 768 |
| Isolated GPU scope, before empty calibration | 1.371 ± 0.021 ms | 1.365 ± 0.043 ms |
| Async CPU decoding / callback | 20.499 ± 1.021 ms | 0.306 ± 0.009 ms |
| Async delivery latency before decoding | 97.107 ± 0.919 ms | 96.994 ± 0.437 ms |
| Observed quilt update interval | 48.269 ± 0.305 ms | 48.271 ± 0.179 ms |

Empty GPU scope: 0.003170 ± 0.000177 ms. The -0.0061 ms difference between GPU paths is below run variation; no measurable extra GPU cost or GPU acceleration is established. CPU decoding falls approximately 67.05 times. Delivery latency and full-frame intervals remain effectively unchanged. Readback enqueue/transfer costs are not included in CPU decoding; asynchronous delivery is not instantaneous. No wall/engine anomalies occurred in this series.

All reduced runs passed exact GPU-versus-CPU counter comparison; the rendered scene exercises all four counters (nonzero aggregate values). Captures across all modes are byte-identical (SHA-256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`). Fifteen regression checks passed on the same latest 4.8-dev build. Shader stage annotation was added after timing for editor import compatibility; the runtime compiler strips it, leaving the measured GLSL unchanged.

Raw logs and JSON: `isolation1024/`, `runtime1024/`, `regression48.log`. Aggregates and binary hash: `verified-results.json`. The benchmark uses optional diagnostic code only; no engine changes or upstream push were made.
