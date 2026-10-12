# Experiment: shared positional shadow atlas

Patch to MIT Godot sources, base `232e6b14abf6e590b41d60f11704e42de22bff72` (4.8-dev). No Looking Glass/Unity code used. Original checkout `/Users/roman/work/godot`; separate patch for review/porting.

Added `RenderingServer.viewport_set_positional_shadow_atlas_shared_from(viewport, source)`, default off. Empty RID disables sharing. Each viewport retains its own atlas ownership; source always uses its own. Chains/cycles disallowed; removed source RID automatically falls back.

Sharing eligibility checked every render:

- Same valid scenario;
- Both cameras use `cull_mask == 0xFFFFF` (all 20 layers);
- Both viewports use `mesh_lod_threshold == 0`;
- Equal atlas size and depth precision;
- Tighter caster culling disabled **at renderer startup**: `rendering/lights_and_shadows/tighter_shadow_caster_culling=false`.

Does not share directional shadows, primary geometry culling, Forward+ clusters or main-view draws. Atlas allocation depends on source camera coverage/subdivisions; compare quality/resolution. Independent fallback atlases remain allocated. No universal equal-resolution guarantee or production API for arbitrary SubViewports.

Sources: `RendererViewport::_draw_3d`, `servers/rendering/renderer_viewport.cpp:334–350`, setter `:1391`; eligibility `RendererSceneCull::camera_can_share_positional_shadows`, `servers/rendering/renderer_scene_cull.cpp:157`; read-only `RenderingLightCuller::uses_full_shadow_casters`, `servers/rendering/rendering_light_culler.h:164`. Existing `shadow_atlas_update_light` / `InstanceLightData::last_version` avoid unchanged-map redraws in the shared atlas; new cameras can still allocate/reallocate.

## Build in this environment

SCons in `/Users/roman/work/tools/godot-build-venv`; Homebrew `/opt/homebrew/lib/libMoltenVK.a` linked through SDK layout `/Users/roman/work/tools/mvk-sdk/macos-arm64/libMoltenVK.a`.

```sh
cd /Users/roman/work/godot
/Users/roman/work/tools/godot-build-venv/bin/scons \
  platform=macos target=template_release arch=arm64 disable_path_overrides=no \
  vulkan_sdk_path=/Users/roman/work/tools/mvk-sdk accesskit=no metal=no \
  modules_enabled_by_default=no module_gdscript_enabled=yes \
  module_text_server_fb_enabled=yes module_freetype_enabled=yes \
  module_godot_physics_3d_enabled=yes module_glslang_enabled=yes -j8
```

Minimal runtime, not editor. Shaders were pre-imported with official 4.5.1. Native Metal excluded; Vulkan/MoltenVK tested.

## Comparison

```sh
cd /Users/roman/work/godot-looking-glass
python3 benchmarks/engine-shadows/run.py /Users/roman/work/godot/bin/godot.macos.template_release.arm64
python3 benchmarks/engine-shadows/summarize.py
/Users/roman/work/godot/bin/godot.macos.template_release.arm64 \
  --path benchmarks/engine-shadows/project --rendering-driver vulkan \
  --script res://tests/test_shared_shadows.gd
```

Runner isolates project.godot with full caster culling, linked addon/demo/tests and copied imports. Three alternating baseline/shared pairs on one binary, matched lights/LOD/motion. Metrics: wall delta, viewport GPU sum, shadow draws; GPU sum is not critical path. PNG readback after timing. Normal addon retains separate atlases/tighter culling. Enable `rig.shared_positional_shadows=true` before `_ready()` plus the startup setting above.


## Execution result

Build succeeded (`benchmarks/optimization/engine-build-path.log`). 48 real: 32.964 → 21.983 ms/frame (−33.3%); viewport GPU sum 31.890 → 18.913 (−40.7%); shadows 2112 → 44. Three M4 pairs, exact PNGs. No 12-view frame gain. Method/limits: `docs/performance-optimization.md`; JSON: `benchmarks/engine-shadows/v48-summary.json`.

Omni/Spot, LOD/mask/chain/owner-release tests passed; projection/GPU/Bridge on stock 4.5.1 and patched 4.8 passed. For the 48-view comparison, runner accepts `48` and summarize accepts `48`. Release templates omit GDScript assert; explicit checks exit nonzero.

Stock 4.5.1 separately tested with `--shared-shadows`: unavailable-API warning, correct independent-atlas fallback, successful benchmark (`stock-fallback.log/json`).

Godot source license and copyright notice: [GODOT-LICENSE.txt](GODOT-LICENSE.txt).
