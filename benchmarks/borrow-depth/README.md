# Direct depth access: A/B benchmark

Experimental `--borrow-depth` also enables `--borrow-color`. Capture retains RenderSceneBuffersRD and source color/depth RIDs, refreshes them each callback, and never frees engine-owned textures. There is no separate capture compute pass. Synthesis converts reverse-Z to linear depth on each read; the ordinary shader and default copy path are retained.

```sh
python3 benchmarks/borrow-depth/run.py --godot ../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/borrow-depth/rendered1024
```

Both modes read borrowed HDR color. `linear` copies depth into an owned R32F texture; `raw` reads source depth. Static scene: 512 MultiMesh boxes, four SpotLights, shared shadow atlas, 24 real → 48 output. Three pairs with alternating order. 90 warmup + 240 observed quilt-update intervals. Dispatch counts, timestamp samples, runtime errors and PNG SHA256 are checked.

24 sources at 1024² avoid 96 MiB of owned R32F payload; this is calculated allocation, not measured total VRAM. The cost is repeated depth conversion in iterative gather. Quilt GPU time excludes capture and cannot independently establish overall speed.

Limitations: Forward+ Vulkan/MoltenVK; TAA/FSR2/MSAA/post effects and physical hardware untested at this stage. Lifetime tests check exact raw quilts at source sizes 64/48/80, continuing dispatches, nonempty output and survival of both borrowed RIDs after double release. Direct depth has the same open lifetime and subsequent-buffer-modification questions as direct color (#15633).


## Measured results

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, repeated series `recheck1024/summary.json`: three pairs, each with 240 observed intervals after 90 warmup. Linear-depth copy: 50.903 ± 0.997 ms; direct depth: 48.688 ± 0.934 ms (standard deviation of run means), −4.35%. Synthesis+quilt GPU time: 12.539 → 11.094 ms (−11.52%). GPU means include startup, not isolated capture. CPU submission ~0.070 ms in both modes. All six records contain at least 330 dispatches; first-pair PNGs match byte-for-byte, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`.

Initial series `rendered1024/` retained for audit: linear-3 reported wall 155.75 ms against engine delta 51.70 ms. Cause unknown; that series' wall mean is not used for speedup claims. The repeat used unchanged code/settings. Do not add this gain to the color-copy gain from another series. The new depth path has not yet been measured at 512².
