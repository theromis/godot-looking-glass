# Private IOSurface GPU frame transport

The macOS native Metal diagnostic can pass Godot quilts to the isolated worker without CPU pixel transfer. It is still a bounded prototype; Bridge consumer synchronization remains experimental.

```sh
# Diagnostic checksums: intentional source/output readbacks, not a benchmark.
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1 --large --verify
# GPU pixel transport, no diagnostic pixel readback:
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1 --large
```

## Resource and ordering contract

1. The worker creates a 32-byte descriptor/ack mailbox and a temporary Mach endpoint, then reports readiness.
2. The Godot GDExtension creates one private RGBA8 IOSurface on the actual Godot Metal device. It sends an IOSurface Mach-port right to the worker. The surface is not made globally accessible.
3. After flushing/finalizing the requested frozen Godot revision, the producer copies the quilt into that surface on the producer Metal queue and waits for GPU completion before publishing its sequence.
4. The worker imports the surface using the received right, copies into its persistent SDK texture on the worker queue, and waits for completion.
5. The worker acknowledges that source copy. Only then may Godot overwrite the shared source. The acknowledgment does not mean display completion.
6. The SDK output is a separate texture. Rewriting it still uses the experimental observed-context GL completion check; the public all-consumer lifetime guarantee is unresolved.
7. Godot waits for the final source acknowledgment before releasing its publisher. The worker retains its imported surface independently until cleanup.

There are two GPU copies: Godot quilt to shared source, then shared source to SDK output. This is GPU-only pixel transport in non-verify mode, not zero-copy rendering. CPU orchestration, semaphore waits and blocking producer/copy completion waits remain.

The initial numeric `IOSurfaceLookup` attempt failed for a private cross-process surface. The corrected route follows Apple's [IOSurfaceCreateMachPort/lookup-from-port API](https://developer.apple.com/documentation/iosurface/iosurfacelookupfrommachport%28_%3A%29), with [Metal IOSurface-backed texture creation](https://developer.apple.com/documentation/metal/mtldevice/maketexture%28descriptor%3Aiosurface%3Aplane%3A%29?language=objc). Numeric IDs only validate identity after rights-based import; they are not used to obtain access.

## Executed tests and measurement scope

- Cross-process control test completed 32 acknowledgments, rejected outstanding-frame overwrite, wrong acknowledgment and stale sequence.
- Mach endpoint close/re-register test passed. An initial unsupported null-port unregister call returned NAME_IN_USE; cleanup now releases owned port rights, and same-name reuse was verified.
- The 4K diagnostic run copied eight frames and matched per-frame FNV-1a checksums between producer IOSurface and worker SDK output. These are diagnostic checksums, not an exhaustive byte-by-byte identity proof or performance measurement.
- The non-verify 4K run copied eight frames without producer or worker pixel readback. Initial average producer publication/copy-wait elapsed time was 2.678 ms; the final repeat after endpoint cleanup correction was 2.195 ms. This excludes prior rendering, waiting for the previous acknowledgment, worker copy/draw and display latency. `get_image()` is not called in this mode; its zero counter does not claim a free readback operation.

See [diagnostic record](../benchmarks/hardware/live-surface-4k-verify.json), [GPU-only record](../benchmarks/hardware/live-surface-4k-gpu.json) and [retained failed ID-lookup attempt](../benchmarks/hardware/live-surface-id-lookup-failed.json). Physical observations are separate from API completion.

## Remaining limitations

The temporary standalone rendezvous uses deprecated `bootstrap_register`; modern XPC packaging and hardened peer authorization are still future work. Current support is the tested unsandboxed macOS desktop native Metal setup, with fixed small/4K quilt presets. Vulkan/MoltenVK import, indefinite operation, full-rate animation and scene-quality/transparency validation are not covered. No SDK source or runtime is vendored.

## Hardware-confirmed repeat

On 2026-10-12, the 20-second 4092×4092 repeat delivered all eight sequences without producer/worker pixel readback, completed SDK release/shutdown, and the user confirmed that it works on the physical display. Mean producer publication/copy-wait elapsed time was 2.361 ms with the exclusions above. See the [repeat record](../benchmarks/hardware/live-surface-4k-gpu-repeat.json). This confirms the bounded visual update test; continuous full-rate operation and the SDK consumer-completion contract remain unverified.
