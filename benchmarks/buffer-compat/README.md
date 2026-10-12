# Borrowed-buffer compatibility and snapshot fallback

The test checks POST_TRANSPARENT snapshot equivalence, not final viewport output after TAA/upscaling/glow/tonemapping. Quilt still uses pre-postprocessing HDR with simple gamma. These tests establish neither TAA/FSR2 on the quilt nor temporal reprojection quality.

## Executed matrix

Apple M4 / Forward+ Vulkan-MoltenVK; official 4.5.1 and custom 4.8-dev. Three rigs sharing World3D, 5 output / 2 real views, 256², spheres and boxes at multiple depths. Compare raw RGBAH quilts rather than PNG alone. All 15 configurations switch on existing viewports, including same-size reconfiguration and render scale 0.5/1.25.

| Configuration | Direct access without policy | With automatic policy |
|---|---|---|
| Baseline | Exact | Borrowed, exact |
| MSAA 2/4/8 | Exact | Borrowed, exact |
| TAA | Differs | Copied snapshot, exact |
| FXAA | Exact | Borrowed, exact |
| FSR1, scale 0.5 | Exact | Borrowed, exact |
| FSR2, scale 0.5 | Exact | Borrowed, exact |
| FSR2, scale 1.0 | Not in initial probe | Borrowed, exact |
| Bilinear scale 0.5/1.25 | Exact | Borrowed, exact |
| Glow, filmic tonemapping | Exact | Borrowed, exact |
| Extra POST_TRANSPARENT color modifier after capture | Differs | Copied snapshot, exact |
| Reset | Exact | Returns to borrowed, exact |

The final matrix tests default copy, borrowed color + linear-depth copy, and borrowed color/depth. Checks cover nonempty output, advancing dispatches, exact equality, effective borrow flags, fallback reasons, dimensions, RID changes and actual FSR2 mode via RenderSceneBuffersRD. Initial probes compared default copy and raw-depth borrowing. All 9 regressions passed on both versions. Files: validated-4.5/4.8.json/.log, checks-4.5/4.8.log; initial probe-4.5.json/.log and probe-4.8.json/probe-4.8-manual.log.

## Implementation

Capture separates requested and effective borrow modes. Callback `get_use_taa()` blocks direct access; any other enabled camera compositor effect also triggers conservative fallback, even if potentially safe. WeakRef avoids a compositor ownership cycle. Switching frees only owned textures, refreshes RIDs and rebuilds cached synthesis descriptors. Direct mode returns automatically when blockers are removed.

When synthesis expects raw reverse-Z, fallback writes raw depth to owned R32F through capture_raw_depth.glsl, preserving interpretation across mode changes. Linear-depth mode uses the previous capture shader. Fallback pipelines are prepared beforehand; color/depth textures are allocated only when needed. Capture.release remains idempotent and never frees borrowed RIDs.

Demo JSON separates requested borrow_source_color/depth, effective_borrowed_color/depth_views, capture_fallback_reasons and calculated owned payload using actual dimensions. This is not total VRAM. Speed after this policy was not measured separately; earlier benchmark numbers were not reinterpreted.

## Reproduction

```sh
python3 tests/run_checks.py --godot /path/to/godot --driver vulkan
/path/to/godot --path . --rendering-driver vulkan --quit-after 3000 --script res://tests/test_buffer_compat.gd -- --output=res://benchmarks/buffer-compat/manual.json
/path/to/godot --path . --rendering-driver vulkan --quit-after 3000 --script res://tests/test_buffer_compat.gd -- --probe --output=res://benchmarks/buffer-compat/probe.json
```

`--probe` disables policy only in test Capture instances and records differences; it does not validate production fallback. Matrix tests disable the ordinary render loop and use force_draw(false, 1/60) + force_sync for stability outside the foreground macOS window. Synchronization and GPU readbacks are test-only; matrix runtime is not a benchmark.

## Limitations and rejected probes

Initial 4.5 test at viewport 96² / internal FSR2 48² produced execute_gpu_job_compute_rd errors (uavMip >= mip_slice_rids.size()). That probe's FSR2 result was rejected. Repeated at 256² / internal 128² without errors; minimum safe FSR2 size remains unknown and the engine bug was not fixed. probe-small.json retained.

Initial 4.8 run did not finish; its main-loop/nanosleep stack sample does not establish a GPU deadlock. After fixing typed-array setup, a bounded retry reached FSR1 and stopped at quit-after while awaiting another draw. These logs are not a passed matrix; final manual-draw tests completed without RID leak warnings.

One static matrix on one GPU does not guarantee lifetime across all renderer configurations. Moving objects, temporal jitter compensation, particles/transparency, other callback combinations, native Metal, other GPUs and physical Looking Glass remain untested. Engine-owned sources are still not snapshots; policy covers verified hazards without providing an official lifetime guarantee. Discussion: https://github.com/godotengine/godot-proposals/discussions/15633.
