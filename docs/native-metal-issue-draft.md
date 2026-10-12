# Draft: native Metal camera equivalence with multiple SubViewports

This is a technical issue draft, not a posted upstream report. The engine-side cause is not established.

## Observed behavior

On Apple M4, Godot 4.8-dev `c61fc0118`, Forward+ native Metal, identical off-axis cameras in multiple SubViewports sharing World3D can produce different images. In the nine-rig diagnostic, the first left source color matches the opposite/right source byte-for-byte despite matching left camera transforms and projections across rigs. The final viewport image also differs, so this is not limited to quilt synthesis. Differences persist after 120 explicit draws and 12 draws with source cameras disabled.

The addon regressions fail for continuous/on-demand equality, resized copy/borrow/workgroup equality, and borrowed-buffer compatibility. A later control rerun with default barriers reproduces all three failures.

With the existing environment switch `GODOT_MTL_SYNC_MODE=none`, the same engine uses native hazard tracking and all 16 addon checks pass. All 80 snapshot comparisons in the nine-rig diagnostic match exactly. The switch changes resource allocation policy as well as synchronization, so this does not isolate an exact faulty fence or prove a particular race.

## Reproduction and controls

Set `GODOT` to the latest local native Metal executable. These commands run from the repository root:

```sh
"$GODOT" --path . --rendering-driver metal --script tests/diagnose_native_equivalence.gd
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal \
  --script tests/diagnose_native_equivalence.gd \
  -- --output=res://benchmarks/native-bridge/equivalence-hazard-local
python3 benchmarks/native-bridge/analyze_equivalence.py \
  --input benchmarks/native-bridge/equivalence-local --output barriers.json
python3 benchmarks/native-bridge/analyze_equivalence.py \
  --input benchmarks/native-bridge/equivalence-hazard-local --output hazard.json
```

This diagnostic uses the addon and reads GPU snapshots; it is not a performance benchmark. Source color/depth are sampled into owned readable textures because borrowed resources do not necessarily support direct CPU readback.

A smaller script uses only core Godot classes when invoked with `--frustum`:

```sh
"$GODOT" --path . --rendering-driver metal \
  --script tests/test_plain_viewport_equivalence.gd -- --frustum
```

It builds six alternating left/right cameras, compares same-side outputs and requires opposite-side images to differ. It needs no addon, compositor, imported shaders or assets with this argument alone; it can be copied into an empty Forward+ project. The initial off-axis run failed with the first image equal to the opposite camera. A later repeat passed, and six subsequent runs each with default barriers and hazard tracking passed. **This smaller reproduction is intermittent and should not be presented as deterministic.** The Vulkan/MoltenVK 4.8 control passes. A clean repeat in an isolated empty Forward+ project also passed with both Metal modes; the template runtime was supplied an empty `list=[]` global script cache. Optional `--capture` and `--compute-tail` controls require addon files and are not the standalone reproduction.

## Inspected source locations

Paths refer to engine commit `c61fc0118854f38d75474346a417db55e52d0ffd`:

- `drivers/metal/rendering_device_driver_metal.cpp:2873`: constructor selects native hazard tracking for `GODOT_MTL_SYNC_MODE=none`; otherwise barriers are default.
- `drivers/metal/metal3_objects.cpp:273`: `MDCommandBuffer::pipeline_barrier()` relies on command-group level fences instead of implementing individual barriers.
- `drivers/metal/metal3_objects.cpp:103`: render encoder fence waits; `:124` updates. These are investigation points, not established defective lines.
- `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:1783`: `_render_scene()` resets camera uniform buffer allocation count per scene; `:709` selects the buffer and `:722` updates it. Buffer reuse is a hypothesis worth examining, not a proven cause.
- `servers/rendering/renderer_rd/storage_rd/render_scene_data_rd.cpp:307`: `update_ubo()` updates the selected buffer.

No engine patch is proposed here. No performance benefit, other hardware compatibility or physical Looking Glass output is established. See [structured outcomes](../benchmarks/native-bridge/metal-sync-results.json), [snapshot analysis](../benchmarks/native-bridge/equivalence-metal.json), and [hazard-tracking regression log](../benchmarks/native-bridge/regression-metal-hazard.log).
