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

## Extended animation test

Add `--duration 120` to the GPU-only command to keep the worker alive for two minutes and generate fresh Godot revisions for approximately 105 seconds. The remaining time allows startup/final acknowledgment and holds the last frame. The duration is bounded to 20–600 seconds; the default 20-second eight-frame 4K test remains unchanged. Longer runs write distinct `-duration-120` result files.

The worker still checks for updates at approximately 2 Hz, and the producer intentionally waits 0.4 seconds after each synchronously flushed revision. This tests sustained ownership and visual updates, not maximum throughput. `worker_update_rate_hz` counts new-frame SDK submissions between the first and last update, not physical display refresh. Process RSS is sampled once per second with `ps`; it excludes GPU allocation accounting and is not a leak proof. Producer publication timing excludes rendering, previous-copy acknowledgment wait and worker/display work.

### Two-minute result (2026-10-12)

The 4092×4092 run produced and received all 212 frames in order during 105.086 seconds of animation, then held the last frame until worker shutdown. The user confirmed ongoing visible updates. The SDK-submission rate between first and last new frame was 2.009 Hz under the approximately 2 Hz cap. Mean producer publication/copy-wait elapsed time was 3.329 ms. No diagnostic pixel readback was performed. Both processes exited successfully and SDK release/shutdown passed.

After ten seconds of warmup, producer RSS was 242,128 KiB initially and 189,008 KiB at its final sample; worker RSS was 91,440 KiB initially and 90,752 KiB at its final sample. Memory samples are recorded below; these values do not establish absence of GPU leaks. The known SDK initialization GL_INVALID_ENUM was still logged despite successful visible output. See the [full measurements](../benchmarks/hardware/live-surface-4k-gpu-duration-120.json) and [sanitized log](../benchmarks/hardware/live-surface-4k-gpu-duration-120.log). SDK consumer-completion guarantees and higher-rate stability remain unresolved.

## Uncapped diagnostic mode

Use `--large --duration 60 --uncapped` with the launcher to remove the producer's 0.4-second delay and the worker's 2 Hz admission cap. The event loop still yields for approximately 1 ms and each Godot revision still uses eight explicit frame flushes. One outstanding source frame and copy acknowledgment are retained. This is the throughput of this synchronous diagnostic harness, not the maximum native renderer throughput.

Additional stage means are CPU wall-clock measurements: `mean_revision_flush_ms` includes eight Godot process-frame waits and forced draws/synchronization; `mean_ack_wait_ms` covers waiting for the previous source-copy acknowledgment; `mean_surface_publish_elapsed_ms` includes producer copy/publication; worker `worker_mean_finish_ms` covers the experimental observed-context `glFinish`, `worker_mean_copy_wait_ms` covers encoding/submission/completion of the worker GPU copy, and `worker_mean_new_frame_draw_ms` covers the new-frame SDK call. Repeated event-loop redraws and display completion are outside the last metric. Stages overlap across processes and must not be added as end-to-end latency. No Metal GPU timestamps or physical refresh measurement are implied.

### Uncapped 4K result (2026-10-12)

The 60-second worker run received all 1,238 frames in order over 44.884 seconds between first/last submissions, averaging 27.560 new SDK frame submissions per second. The user confirmed normal visible updates. There was no producer/worker pixel readback and SDK release/shutdown passed. This is a simple unshaded cube scene with 66 actual cameras and a synchronous eight-flush harness, not a general game benchmark or measured panel FPS. The initial run advanced rotation/color per frame; uncapped animation now advances by elapsed time.

| CPU wall-time stage | Mean ms |
| --- | ---: |
| Godot revision preparation (eight flushes, waits/draw/sync included) | 34.269 |
| Previous source acknowledgment wait | 0.147 |
| Producer GPU copy and publication | 1.922 |
| Worker observed-context finish | 0.006 |
| Worker GPU encoding/copy/completion wait | 3.401 |
| Worker new-frame SDK draw call | 11.624 |

The longest measured producer stage is revision preparation; its eight forced flushes are diagnostic overhead mixed with actual rendering, so this does not isolate GPU scene cost. Worker stages execute concurrently with producer work. The next useful experiment is reducing flushes while validating that each received quilt contains the intended revision; it should precede speculative buffering changes. See [measurements](../benchmarks/hardware/live-surface-4k-gpu-duration-60-uncapped.json).

The subsequent elapsed-time animation code passed a 30-second API run: all 432 frames were received, new-frame submissions averaged 28.744 Hz and SDK cleanup passed. A separate physical assessment was not requested for that repeat; the user observation above belongs to the initial 60-second run. See the [repeat record](../benchmarks/hardware/live-surface-4k-gpu-duration-30-uncapped.json).
