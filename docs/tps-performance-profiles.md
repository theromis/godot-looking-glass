# TPS integration performance profiles

The original TPS integration rendered 24 source views at 384×682 for a 4092×4092 66-view quilt. Rig motion also called `request_update()` each frame while the managed output independently scheduled captures after source-copy acknowledgment. This kept source viewports rendering even in frames where the output scheduler only needed to submit the completed quilt or wait for acknowledgment.

`Rig.auto_update_on_transform` now defaults to true for compatibility. Setting it false still updates camera transforms but delegates capture requests to the caller. Managed Metal output saves the prior policy, disables automatic transform requests for its session, and restores it on stop. Explicit rig requests and initial capture still work. The small transform-ownership test passed; the managed output lifecycle test passed with 119/119 frames, clean SDK teardown, restart/immediate-stop and policy restoration.

The own adapter at `examples/tps/game_output.gd` follows the game's current camera, exposes F4 Start/Stop and Shift+F4 profile selection, and uses a fast default. Copy it into the target project's `looking_glass/game_output.gd`, register an autoload named `LookingGlassGame`, install the addon and configure an external Bridge runtime. The local TPS copy has been updated; no game assets are redistributed here.

| Profile | Real views | Source size | Synthesis iterations | Positional shadow atlas | Extra camera effects |
| --- | --- | --- | --- | --- | --- |
| Quality | 24 | 384×682 | 8 | 2048 | Original |
| Balanced | 12 | 256×455 | 4 | 512 | Reduced |
| Fast | 8 | 192×341 | 4 | Disabled | Reduced |

All preserve the 4092×4092 11×6 output quilt, focus 2.4 and 10-degree cone. Reduced effects use a cloned per-camera environment with SSAO, SSIL, SSR, volumetric fog, glow and SDFGI disabled; the main window environment is untouched. Voxel GI remains part of the shared scene. Zero positional atlas does not disable directional shadows or remove light shading. Reduced source resolution, view count and iteration count trade sharpness/reconstruction quality for lower cost. Optical quality has not received new physical confirmation.

## Measurements, October 12, 2026

Apple M4, Godot 4.8 c61fc0118 editor/native Metal, `GODOT_MTL_SYNC_MODE=none`. Real TPS level; fixed first player spawn; camera yaw animated; game GI settings preserved; in-memory windowed mode, bilinear scaling and VSync disabled. Four-second warmup and eight-second sample per mode. One run per mode. These are wall process-frame intervals and SDK submission counts, not isolated GPU timings or physical panel FPS.

| Mode | Mean frame ms | p95 frame ms | Godot frame Hz | SDK submission Hz |
| --- | --- | --- | --- | --- |
| Desktop only | 19.79 | 20.50 | 50.52 | 0 |
| Original 24 views, automatic motion requests | 232.98 | 275.26 | 4.29 | 2.21 |
| Same quality, scheduler owns requests | 121.24 | 210.15 | 8.25 | 3.75 |
| Balanced | 54.53 | 96.28 | 18.34 | 7.36 |
| Fast | 38.68 | 61.87 | 25.86 | 10.24 |

The same-quality scheduling change improved this measured interval without changing source count/resolution/effects. Fast combined multiple quality reductions and measured roughly six times the original Godot frame rate. These results are limited to this scene and test configuration; dynamic actors and single-run sampling still introduce variation. Fast remains substantially more costly than desktop-only, and its physical content updates are about 10 Hz in this test.

All active modes received every submitted frame and passed SDK teardown. Every run, including desktop-only, reported one leaked MaterialStorage shader RID and one unfreed ParticlesShaderRD at engine shutdown. Thus the records report successful feature checks separately from complete-test failures. Extending cleanup to 60 frames did not remove that issue; its root cause remains unresolved. No leak-free or production-ready claim is made.

Records: [profiles](../benchmarks/hardware/tps-profiles.json), [desktop baseline](../benchmarks/hardware/tps-desktop.json). The first exploratory series was excluded because fixed-spawn control was added during that series. Shared shadow optimization is not enabled. Further improvements require measurements rather than assuming multiview or another transport is faster.
