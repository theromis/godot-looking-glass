# Prioritize smooth Looking Glass content updates

The optimization target is new content delivered to Looking Glass, not the desktop window's frame rate. Capture limiting is disabled. The same fast visual preset remains: 8 source views, 192×341 source images, 4092×4092 quilt, 4 synthesis iterations, conservative cone/focus and reduced extra-view effects.

## Changes and ownership

The TPS adapter now defaults to `render_desktop_3d=false` while output runs and restores the prior root viewport flag on stop. The game's camera, world simulation and input remain active; only the extra desktop 3D drawing is suppressed. Desktop 2D HUD remains visible and is still not part of the quilt. There is no new desktop preview camera or CPU pixel readback.

`MetalOutput.overlap_capture` permits preparing the next **private Godot quilt** after the previous producer blit has completed, while the worker copies the shared IOSurface. Publication into the shared surface still waits for worker ACK. This separates private rendering from shared-buffer reuse without weakening the source-copy barrier. The TPS adapter enables overlap; the generic node keeps it opt-in. One unpublished prepared frame may be dropped on Stop.

The experimental `async_gpu_copy` option retains its Metal command buffer and source texture, polls completion on the main thread, then publishes the mailbox sequence. It does not publish or declare ready while the GPU copy is pending. Forced cleanup waits before releasing copy resources. It remains disabled by default: removing CPU wait improved desktop frame rates but reduced actual delivery cadence in this test. No callback accesses Godot from another thread.

## Measurements — October 12, 2026

Apple M4, Godot 4.8 c61fc0118 native Metal editor, same fixed-spawn TPS level with camera yaw animation. Four-second warmup, eight-second sample, one run per mode. The game GI settings were preserved; windowed/bilinear/VSync-off test overrides were unsaved.

| Mode | New quilt submissions/s | p95 publication gap ms | CPU publication call ms |
| --- | --- | --- | --- |
| Blocking copy, desktop 3D, no overlap | 10.47 | 110.81 | 49.36 |
| Async copy, desktop 3D, no overlap | 9.71 | 124.62 | 0.039 |
| Blocking copy, no desktop 3D | 16.25 | 68.36 | 26.60 |
| Blocking copy, no desktop 3D, overlap | 27.04 | 41.07 | 18.41 |
| Async copy, no desktop 3D, overlap | 21.73 | 50.70 | 0.037 |

The blocking publication time includes waiting for earlier GPU rendering on Godot's queue; it is not the isolated blit's GPU execution duration. Async completion wall latency additionally includes frame polling. Two GPU copies still exist; no zero-copy claim is made.

A 20-second repeat of the selected blocking/no-desktop/overlap mode produced 30.02 new quilt submissions/s, p95 publication gap 42.52 ms, and received all 713 submitted frames including warmup. The user confirmed noticeably smoother motion on the physical Looking Glass without new artifacts. Root desktop 3D was restored after stop. These cadence counters remain stream proxies, not panel presentation-fence measurements or proof of 30 distinct physically presented frames every second.

Every active mode delivered all submitted frames and passed SDK cleanup. The existing MaterialStorage/ParticlesShaderRD shutdown errors still occurred, so complete TPS tests remain failures even when feature checks pass. The underlying SDK consumer-completion contract remains unknown; this change does not establish safe indefinite reuse across SDK contexts.

## Verification and reproduction

`test-surface-async` compared three complete small-surface GPU copies byte-for-byte, tested retained-source lifetime, rejected concurrent publication and premature reuse, and closed with a copy in flight. The managed async test delivered 87/87 frames, clean SDK teardown and restart/immediate-stop. Async throughput was then compared against blocking rather than assumed faster.

Copy the own helpers under `examples/tps/tests/` into the target TPS project's `looking_glass/tests/` and run:

```sh
python3 looking_glass/tests/run_copy_modes.py \
  --godot "$GODOT_EDITOR" --runtime "$BRIDGE_LIBRARY"
```

Records: [mode comparison](../benchmarks/hardware/tps-copy-modes.json), [physical repeat](../benchmarks/hardware/tps-display-priority-repeat.json), [async functional tests](../benchmarks/hardware/async-surface-functional.json). The game assets are not redistributed. A richer HUD on the display, presentation timing and broader motion/transparency validation remain separate work.
