# TPS capture pacing experiment

`MetalOutput.max_capture_hz` limits the start rate of new rig capture requests. Zero preserves acknowledgment-driven pacing. The deadline is checked in the ordinary process loop; it does not sleep or block the game. A late capture starts a new interval rather than accumulating catch-up requests. Source readiness and the existing GPU/worker acknowledgment protocol still apply. Session startup resets the deadline; stopping is not delayed by the timer.

On Apple M4 with Godot 4.8 c61fc0118 native Metal, the same fast TPS preset (8 views at 192×341, 4K quilt) was tested at 0/15/10/5 Hz limits. The test used a fixed first player spawn, camera yaw motion, preserved game GI settings and in-memory windowed/bilinear/VSync-off settings. Four-second warmup, eight-second measurement, one run per cap. Process-frame wall intervals are not isolated GPU times or physical panel FPS.

| Capture limit | Godot frame Hz | Mean frame ms | p95 frame ms | SDK submission Hz |
| --- | --- | --- | --- | --- |
| None, repeated control | 25.65 | 38.99 | 61.40 | 10.71 |
| 15 Hz | 26.70 | 37.45 | 59.64 | 10.98 |
| 10 Hz | 27.61 | 36.21 | 61.01 | 9.12 |
| 5 Hz | 33.09 | 30.22 | 61.85 | 4.75 |

The 15 Hz cap did not meaningfully constrain a path already delivering approximately 11 new quilts per second. A 10 Hz cap yielded a small average-rate change with fewer content updates and no demonstrated p95 improvement. A 5 Hz cap increased average game frame rate while cutting content updates by more than half; long frames remained. Single-run variation limits small comparisons. No new physical visual confirmation was collected.

The default therefore remains zero. A desktop-priority application may explicitly choose 5 Hz, accepting visibly infrequent display updates. This is not a recommended default for animated light-field gameplay. The experiment suggests that limiting capture frequency alone does not remove individual expensive capture frames; further work should measure their render and synchronization cost.

All caps delivered every submitted frame and passed SDK teardown. Known MaterialStorage/ParticlesShaderRD errors still appeared at game shutdown, so full TPS tests are not clean passes. The initial uncapped test also falsely failed final pose equality because it sampled before the camera-following process callback; the repeated control compares after `frame_post_draw` and passed the feature checks. That harness repair does not alter the timing window.

The isolated six-second managed-node test at 5 Hz delivered 28/28 frames (upper bound 31), with clean SDK teardown, policy restoration and immediate-stop restart. It verifies that submission count stays within the configured bound and that stop/restart and policy restoration still work. See [raw TPS record](../benchmarks/hardware/tps-capture-pacing.json).

For reproduction, copy the own benchmark helpers from `examples/tps/tests/` into the target TPS project's `looking_glass/tests/`, install the adapter/addon, and run:

```sh
python3 looking_glass/tests/run_pacing.py \
  --godot "$GODOT_EDITOR" --runtime "$BRIDGE_LIBRARY"
```

Set the adapter's `max_capture_hz` before starting output to try an optional cap. GPU source-copy acknowledgment is not a Bridge texture-consumption or presentation fence; the experimental synchronization limits are unchanged.
