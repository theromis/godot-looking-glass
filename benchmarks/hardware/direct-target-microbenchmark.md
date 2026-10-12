# Direct SDK target versus intermediate GPU blit

Measured on 2026-10-12, Apple M4, native Metal, real Bridge 2.6.3 RGBA8 IOSurface. This is a synthetic constant-color compute microbenchmark, not Godot scene rendering or end-to-end display latency.

The same 8×8 compute kernel writes either directly to the SDK shared IOSurface or to a private RGBA8 texture followed by a GPU blit into that IOSurface. Each run has ten warmup pairs and fifty measured samples per mode; the first mode alternates every pair. Modes share one command queue and wait for command-buffer completion after each sample. GPU time comes from completed `MTLCommandBuffer.GPUStartTime/GPUEndTime`, covering the whole command buffer.

No SDK quilt draw is submitted, so Bridge does not consume this target while producers overwrite it. These timings cannot resolve the live consumer lifetime problem. A diagnostic CPU readback after the timed series verified all final RGBA8 components; it is excluded from GPU timings. All six processes exited zero and SDK teardown succeeded.

| Texture | Repeat | Direct median GPU ms | Compute + blit median GPU ms | Difference ms |
| --- | --- | ---: | ---: | ---: |
| 704×684 | 1 | 0.042167 | 0.076875 | 0.034708 |
| 4092×4092 | 1 | 0.641458 | 1.963210 | 1.321752 |
| 704×684 | 2 | 0.023458 | 0.058208 | 0.034750 |
| 4092×4092 | 2 | 0.729458 | 2.160500 | 1.431042 |
| 704×684 | 3 | 0.042583 | 0.096375 | 0.053792 |
| 4092×4092 | 3 | 0.725583 | 2.201580 | 1.475997 |

At 4092² the removed intermediate allocation has 66,977,856 bytes (about 63.88 MiB) of RGBA8 texture payload, excluding allocation overhead and padding. The measured reduction in this workload is 1.32–1.48 ms. It does not establish a corresponding Godot frame-time reduction: the real synthesis kernel reads color/depth sources and performs reprojection, and rendering/Bridge/CPU overheads may dominate. The private-intermediate versus shared-IOSurface storage choice is part of the comparison, not a controlled equal-storage blit-only timing.

See [raw per-run statistics](direct-target-microbenchmark.json), including p10/p90 ranges. The short 704×684 case shows substantial relative timing variation, so avoid extrapolating a stable percentage gain.

## Reproduction

```sh
python3 native/bridge_metal/build.py --sdk-headers "$BRIDGE_HEADERS"
native/bridge_metal/build/benchmark-target "$BRIDGE_LIBRARY" "$BRIDGE_DISPLAY_INDEX" 704 684
native/bridge_metal/build/benchmark-target "$BRIDGE_LIBRARY" "$BRIDGE_DISPLAY_INDEX" 4092 4092
```

Use an explicit calibrated device index, run serially without concurrent GPU benchmarks, and do not reuse this test's repeated writes in a live SDK consumer path. The command does not show a scene on the physical display. The executable emits one `RESULT` JSON record plus SDK logs; discard or redact raw calibration and serial messages before publishing results.
