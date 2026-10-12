# Removing the intermediate HDR color copy

Optional addon path: `borrow_source_color=true` / demo `--borrow-color`. The compositor obtains the Godot-owned color RID through `RenderSceneBuffersRD.get_color_layer(0)` and passes it directly to synthesis. Compute capture stores only linear depth in its own R32F texture; HDR color is not copied into an additional RGBA16F texture.

The addon never frees Godot-owned RIDs. Capture retains the RenderSceneBuffersRD owner and refreshes the color RID on every callback; synthesis rebuilds its uniform cache when source RIDs change. Capture release is idempotent, frees only owned resources, and stops further callbacks. Copy remains the default; borrowed mode is experimental.

```sh
python3 /Users/roman/work/godot-looking-glass/benchmarks/borrow-color/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 /Users/roman/work/godot-looking-glass/benchmarks/borrow-color/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile=1024 --rendered --results-dir=/Users/roman/work/godot-looking-glass/benchmarks/borrow-color/rendered1024
```

Import the new shader in the official editor before running, as described in the main README. The runner creates an isolated project with symlinked addon/demo/tests sources. A runtime with the shared-shadow patch is required. Runs are sequential, with three repeats per mode, alternating copy/borrow order; 90 warmup + 240 samples. Avoid other GPU workloads. Rerunning overwrites the corresponding results.

512²: 48 output / 24 real views, 512 MultiMesh boxes plus a moving caster, four SpotLights; viewport timestamps disabled. Copy wall frame: 16.712 ± 0.079 ms; borrow: 16.643 ± 0.039 ms. The difference is too small to establish sustained FPS gain; scheduling near 16.7 ms limits this workload. PNGs match byte-for-byte: `9be0a98db198e7910cd51fde2af71d7dbbd51e66a7782e2e3eb81cdac5b443bf`. All six runs executed 330 quilt dispatches.

Removed 24 × 512 × 512 × 8 = 50,331,648 bytes = 48 MiB of owned color texture payload. This is calculated intermediate RGBA16F allocation savings, not measured total VRAM/residency. At 1024², the corresponding payload is 192 MiB. Reverse-Z linearization remains a separate compute pass; depth copying is not removed. Quilt GPU time excludes capture and includes its own two timestamps, equally in baseline and borrow. The current sampler includes startup samples, so this GPU time is not independent evidence of faster capture.

## Measurement validity

The first six runs were rejected: an array typing error in the new capture caused a GDScript runtime error hidden by minimal template_release; compute_dispatches=0. They remain in `discarded/` and are excluded from the summary. The error was fixed; the runner requires compute work and timestamp samples. The test now rejects two identical empty quilts.

The ordinary 1024² process-call benchmark was rejected (`tile1024/`): 330 process calls produced only 199 quilt dispatches and 195 timestamp samples. Logic steps are not rendered outputs. A stack sample did not establish a shader/GPU deadlock; the process finished and saved JSON/PNG. These data cannot support a copy/borrow FPS claim.

`--rendered-benchmark` samples only observed increases in successful quilt dispatches. Wall metric measures intervals between observed quilt updates, including scheduling/presentation; it is not the hardware GPU critical path. Runner `--rendered` also fixes the scene with --static so process-call counts do not change reference geometry. Thus 512² dynamic and 1024² static results are not a scaling curve. Insufficient samples or compute work cause failure.

The shared capture frame number now uses the RD slot index, stable within a render draw, rather than independent callback counters; this change applies equally to copy/borrow. A previous startup synchronization problem was not established: the first failure came from the new code's typing error.

## Tests and limitations

Executed GPU test `test_capture_lifetime.gd`: advancing dispatch_count, nonempty quilt, exact floating-point quilts at source sizes 64/48/80, buffer resize, double release, and Godot-owned texture survival after release. Tested on official Godot 4.5.1 and experimental 4.8-dev; final logs in lifetime-stock.log/lifetime.log and the overall test runner.

Equivalence with TAA, FSR2, MSAA, glow or additional post-transparent effects is not established at this stage. If color changes after POST_TRANSPARENT, borrowed input may differ from a snapshot copy. Default copy path retained; no automatic effect-based fallback yet. Borrowed mode requires renderer configuration control; do not enable it for those effects without a quality comparison. Native Metal, Compatibility and physical Looking Glass are untested with this path.

Source reference: Godot forward_clustered/render_forward_clustered.cpp:2541 invokes POST_TRANSPARENT; :2555 starts FSR2, :2623 TAA, :2632 tonemap. Accessing color does not produce a snapshot after those effects. This is a direct-reuse limitation; buffer lifetimes still need consideration.

## Heavy workload: executed result

1024², 48 output / 24 real views, static scene with 512 MultiMesh boxes and four SpotLights; three runs, each with 240 successful quilt-update samples after 90 warmup.

| Mode | Wall quilt-update interval, ms | Run stddev, ms | Owned HDR copy payload |
|---|---:|---:|---:|
| Copy | 52.205 | 0.057 | 192 MiB |
| Borrow | 49.656 | 0.121 | 0 |

Quilt update interval decreased 4.88%. This measures the whole configuration including scheduling, not isolated capture GPU time. Quilt compute itself did not improve: means 12.253 / 12.359 ms; savings occur outside that pass. Do not generalize this percentage to all scenes/GPUs or ordinary 128² tiles.

Copy/borrow PNGs match byte-for-byte: SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Raw JSON/log/PNG and mean/stddev: rendered1024/. Engine version and binary SHA256 are recorded in each JSON/summary.
