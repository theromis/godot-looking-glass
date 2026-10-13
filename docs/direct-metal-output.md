# Experimental managed direct Metal output

`addons/looking_glass/direct_metal_output.gd` inherits display discovery and rig configuration from `MetalOutput`, but replaces the streaming worker with an in-process Bridge session and persistent SDK texture. Discovery currently invokes the existing one-shot helper; no helper remains alive to carry frames.

Use the same external runtime, detected numeric index and RGBA8 on-demand capture-stage rig. The component imports the SDK texture on the render thread, switches synthesis uniforms/output to it, and restores the previous owned quilt on Stop. Source transform-triggered requests are disabled while running. Each completed requested quilt is fenced and submitted on the main thread. No pixel readback or quilt blit is used. The original quilt allocation is retained for restoration, so no VRAM reduction is claimed.

Signals and start/stop methods match `MetalOutput`. Always call `stop_output()` and await `stopped` before removing the output node or rig. Active output-node removal is not supported and emits an error. Native extension APIs remain experimental. Resize and external target sharing are unsupported. Only native Metal on macOS is accepted.

`received_frames` counts successful SDK update calls in direct mode. It does not mean worker receipt or panel presentation. Legacy `copy_*` counters measure API wall time even though direct mode performs no copy. There is no SDK consumer-completion proof; the producer fence guarantees only completion of Godot writes. The TPS adapter selects this experimental path by default at the user’s request; other integrations choose their output component explicitly.

The managed test completed 196 updates over a six-second window including startup, restored the rig policy, then restarted and immediately stopped successfully. All SDK lifecycle calls passed and Godot exited 0 without script/render errors. A separate two-minute manual diagnostic previously completed 6640 calls and received stable physical-display confirmation. SDK startup GL_INVALID_ENUM diagnostics remain unresolved.

## TPS integration

The adapter accepts `output_mode="direct"` or `"worker"` before `start_output()`. Direct is the TPS default at the user’s request; set `output_mode="worker"` for the alternative path. Both paths use the same profiles and disable extra desktop 3D during output, restoring it on stop. The direct component owns request scheduling; neither async-copy nor private-quilt overlap changes its direct behavior.

Copy `examples/tps/tests/run_output_modes.py` and the updated `benchmark_profiles.gd` into the target integration's test directory, then run:

```sh
python3 looking_glass/tests/run_output_modes.py \
  --godot "$GODOT_EDITOR" --runtime "$BRIDGE_LIBRARY"
```

The protocol alternates two worker/direct pairs, fixed spawn, fast preset, 4-second warmup and 8-second measurement. Publication counters are stream proxies, not panel FPS. Existing TPS particle-shader shutdown errors still make full tests fail even if output feature checks pass. See the recorded comparison for actual measurements; do not infer a universal improvement from copy elimination.

## Same-scene comparison — October 12, 2026

| Path | Run 1 quilts/s | Run 2 quilts/s | p95 gaps, ms |
| --- | --- | --- | --- |
| Worker with private overlap | 27.98 | 29.73 | 42.08 / 37.26 |
| Direct persistent SDK texture | 27.40 | 29.63 | 50.01 / 33.59 |

No demonstrated throughput improvement: averages are about 28.85 vs 28.51 calls/s, within run variation. All output feature checks and SDK teardown passed; both paths retained the known TPS MaterialStorage/ParticlesShaderRD shutdown errors, so full tests fail. Direct is the TPS default at the user’s request; set `output_mode="worker"` for the alternative path. Results: [TPS output modes](../benchmarks/hardware/tps-output-modes.json).

A 20-second direct TPS repeat produced 561 measured updates (28.01 calls/s), p95 gap 50.015 ms, 671 total successful calls including warmup and clean SDK teardown. The user confirmed correct image updates without freezes or new artifacts. Known particle-shader exit errors remained. [Repeat record](../benchmarks/hardware/tps-direct-repeat.json).

Both experimental ZIPs were rebuilt and verified in clean projects. Native package import, preview and existing worker demo passed (114/114 frames); preview-only import and preview passed. This does not add production guarantees to the direct component.
