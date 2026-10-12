# Scene preparation and view-budget measurements

Apple M4, patched 4.8-dev, Vulkan/MoltenVK. 512 additional static cubes, one shared BoxMesh/material, identical transforms; original moving caster and four SpotLights. Shared positional shadows enabled throughout. Native Metal, other GPUs and physical Looking Glass untested.

```sh
python3 benchmarks/scene-preparation/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 benchmarks/scene-preparation/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --suite synthesis
```

Runner creates an isolated project with tighter caster culling disabled and requires experimental shared-shadow API. Import the main project first as documented in README. No concurrent GPU load. Three repeats per mode, 90 warmup + 240 samples; reruns overwrite that suite.

| Mode | Frame mean, ms | CPU anchor sum, ms | GPU anchor sum, ms |
|---|---:|---:|---:|
| 48 real, separate objects, 128² | 22.447 | 2.480 | 19.767 |
| 48 real, MultiMesh, 128² | 22.594 | 1.332 | 19.916 |
| 48 real, separate objects, 64² | 22.468 | 2.472 | 19.879 |
| 12 real → 48, MultiMesh, 128² | 16.173 | 0.750 | 6.252 |
| 24 real → 48, MultiMesh, 128² | 16.554 | 1.060 | 9.195 |

MultiMesh reduces CPU preparation 46.3% without confirmed FPS gain. Fourfold tile-area reduction also yields no speedup. Forward+ already automatically instances compatible surfaces. A single large MultiMesh can weaken frustum culling; arbitrary scenes need spatial groups.

48-real separate/MultiMesh PNGs match byte-for-byte. Synthesis intentionally changes output: all-real MultiMesh PSNR 16.902 dB with 12 anchors, 21.268 dB with 24; normalized RGB MAE 0.04414/0.02477. Full-quilt comparison includes compute-gamma versus Godot-tonemap differences and does not prove optical display quality.

The practical candidate here is 24 real views with synthesis: ~16.55 versus 22.59 ms (−26.7%), better quality than 12 anchors. This configures existing compute, not a new algorithm. The 12/24 speed difference is not necessarily sustained; scheduling/frame pacing can limit it.

Viewport CPU/GPU sums are not full-frame critical-path time. Global CPU setup is separate; anchor sums exclude main/quilt. Frame metric is engine process delta, not independent OS wall-clock timing. Compute data appear in individual synthesis JSON and synthesis-summary.json. Instrumented modes query identical counter types, but total query cost depends on view count.

`summary.json` and `synthesis-summary.json` store means and between-run sample standard deviations. Individual JSON/log/PNG retained nearby. `quality-12.log` and `quality-24.log` are executed image comparisons. `discarded/` retains rejected initial runs with concurrent GPU tests or extra samples while awaiting frame_post_draw; excluded from final summaries.

Benchmark fixes: `_finish()` disables `_process` before waiting for GPU draw; collection is bounded to 240 samples and enabled only with `--benchmark`. Ordinary preview no longer accumulates statistics arrays.
