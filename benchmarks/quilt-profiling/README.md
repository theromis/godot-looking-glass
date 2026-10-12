# Optional quilt profiling

`rig.profile_synthesis=false` by default. Ordinary preview submits no LG quilt GPU timestamps, reads no results and invokes no deferred sample recorders. `dispatch_count` remains for synchronization/benchmark progress. Capture reads the RD slot index for source coherence; that getter does not submit a GPU query.

Demo enables profiling for benchmarks and `--profile-passes`/`--profile-quilt`. `--no-quilt-timing` disables it while retaining wall-update measurement. `--no-viewport-timing` separately disables engine viewport timestamps; use both for an uninstrumented control. Native `--gpu-profile` is separate engine instrumentation, unused here.

GPU/CPU arrays are bounded by `profiling_sample_limit` (default 480, range 1..4096), then overwritten as rings without pop_front or array shifts. Full-buffer order is not chronological; demo aggregates means. CPU samples start after 90 dispatches; GPU samples include startup. Disabled arrays are empty, durations null (not 0), timestamp_pairs=0.

```sh
python3 benchmarks/quilt-profiling/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/quilt-profiling/rendered1024
python3 tests/run_checks.py --godot /path/to/godot --driver vulkan
```

A/B: identical opaque static scene, 512 MultiMesh objects, four shared-atlas SpotLights, 24 real → 48 output, 1024², borrowed color/depth with new snapshot policy, 8 iterations, 8×8, rescue off. Three alternating on/off pairs; 90 warmup + 240 observed intervals, not isolated GPU time. Compare wall mean and PNG SHA256. Off-mode intentionally has no GPU measurement; missing timestamps cannot establish GPU acceleration. Settings/sample counts checked; wall/engine ratio>1.5 anomalies retained.

Profiling test compares two quilts with a moving object after >100 updates: disabled counters/arrays empty, enabled rings contain exactly four GPU/CPU samples, raw output exact/nonempty. Uses the ordinary loop for timestamp delivery. Initial manual-draw setup submitted pairs without GPU samples; this setup limitation is not an accepted profiling result. Buffer compatibility separately uses manual draws for snapshot equality.

Limitations: one scene/GPU; fullscreen/hardware/native Metal untested. Removing two timestamps is not assumed faster; exact output and bounded memory matter even without frame gain. Default preview is profiling-off; earlier benchmarks remain profiling-on through explicit demo settings.


## Measured result

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, 24 real → 48 output, 1024², three pairs:

| Quilt profiling | Observed update interval ms | Run stddev ms | Recorded GPU/CPU samples |
|---|---:|---:|---|
| on | 47.6166 | 0.0835 | 327 GPU / 240 CPU per run |
| off | 47.6215 | 0.0460 | 0 / 0 |

No update-time gain established: +0.0049 ms is below variation. Each run has 240 samples and 331 dispatches. On submits 331 marker pairs; off 0. Off GPU/CPU submission durations are null, not zero work. First-pair PNG exact, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. No wall/engine ratio>1.5 anomalies.

Default profiling-off avoids instrumentation and growing sample arrays, without an established FPS gain here. Limit=4 ring test retained exactly four GPU/CPU samples after at least 140 actual updates and exact moving-object output.

Data: rendered1024/summary.json, per-run JSON/log/PNG, checks-4.5/4.8.log. Earlier viewport timestamp measurements (+1719 native markers) concern a different workload and cannot be added to this result.
