# Native Metal barrier investigation

These are controlled correctness experiments on Apple M4 / Godot 4.8-dev, based on engine commit `c61fc0118854f38d75474346a417db55e52d0ffd`. They are **not accepted engine patches**. Engine sources, the normal native Metal executable, and the production addon were restored. The previously validated `GODOT_MTL_SYNC_MODE=none` remains the opt-in workaround.

## Executed results

| Experiment | On-demand | Resize/capture | Buffer compatibility |
| --- | --- | --- | --- |
| Wait on the current level after an encoder closes | Fail | Pass | Fail |
| Single encoder fence chain across levels | Fail | Pass | Fail |
| CPU allocation type bypasses heap suballocation | Fail | Pass | Fail |
| Camera/implementation UBO pool resets per frame rather than per scene | Fail | Pass | Pass |
| Explicit indirect-resource declarations alongside heap residency | Fail | Pass | Fail |
| Producer-graph color/depth read marker, original engine | Fail | Pass | Pass |
| Per-frame UBO pool plus producer read marker | Fail | Pass | Pass |

These are selected checks, not seven full regression suites. A pass in a single run does not establish causation. No timing comparison was made; stronger serialization, more buffers and extra dispatches may cost performance. Experimental patches must not be applied as an upstream fix merely because one check passed.

The per-frame UBO variant independently matched all **80/80** source/viewport/quilt comparisons in the nine-rig diagnostic. Its on-demand failure remains with an explicit settled-startup refresh. This improves the reproduction without proving the precise Metal driver defect.

The new standalone `tests/test_buffer_ordering.gd` compiles its compute shader at runtime and interleaves 64 updates to one uniform buffer with 64 dependent GPU reads before one submission. All expected integer values match with native Metal barriers, native hazard tracking, and Vulkan/MoltenVK on the latest local 4.8 engines. Thus this narrower buffer/compute test does not reproduce the viewport failure. It is not a raster or main-RenderingDevice test and must not rule those paths out.

See [structured results with patch/binary hashes](results.json) and [per-frame UBO snapshot manifest](unique-ubo-equivalence.json). Full pixel captures remain local under the existing ignored diagnostic directory. All variants were tested without `GODOT_MTL_SYNC_MODE=none`; only the separately labeled hazard-tracking control enables that switch.

## Source investigation points

Paths and line numbers refer to the unmodified engine base above:

- `drivers/metal/metal_objects_shared.cpp:440`, `MDCommandBufferBase::_fence_to_wait()`, chooses alternating level fences; `:452`, `_fence_to_update()`, records updates. Experiments in stronger ordering did not satisfy all three checks.
- `drivers/metal/rendering_device_driver_metal.cpp:112`, `buffer_create()`, routes allocations through the Metal allocator; `:3023` couples barriers with heaps. Changing only CPU buffer placement was insufficient.
- `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:709`, `_setup_environment()`, assigns a camera UBO; `:1783`, `_render_scene()`, resets its pool counter per scene. The partial variant resets the pool at the first setup of each rendering-device frame instead, including shadow setup, and uses more distinct buffers.
- `drivers/metal/rendering_device_driver_metal.cpp:1395`, `uniform_set_create()`, builds indirect resource declarations only for hazard tracking; `drivers/metal/metal3_objects.cpp:1095`, `_render_set_dirty_state()`, encodes these declarations in that mode. Adding declarations in barriers mode was insufficient.
- `servers/rendering/rendering_device_graph.cpp:346`, `_check_discardable_attachment_dependency()`, changes discardable attachment store operations when a later command depends on them. The addon marker experiment records sampled reads inside the producer callback before later quilt synthesis. It did not fix on-demand, so no stronger lifetime guarantee is claimed.

Apple documents that a consuming fence wait covers updates in relevant producing passes, and allows waiting before updating the same fence. This informed the experiments; it does not prove the engine's graph or fence implementation correct. See [Apple fence synchronization](https://developer.apple.com/documentation/metal/synchronizing-passes-with-a-fence) and [heap/fence programming guide](https://developer-mdn.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/ResourceHeaps/ResourceHeaps.html).

Engine patch excerpts retain the [Godot MIT license](../../engine-patches/GODOT-LICENSE.txt). The addon marker excerpt is repository-owned MIT code. These experiments contain no proprietary SDK implementation.

## Reproduction

For the narrow control, set `GODOT` to the latest local 4.8 executable and run from the repository root:

```sh
"$GODOT" --path . --rendering-driver metal --script tests/test_buffer_ordering.gd
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal \
  --script tests/test_buffer_ordering.gd
```

Use the Vulkan 4.8 executable with `--rendering-driver vulkan` for its control. Engine variants were built incrementally with the same native Metal build configuration recorded in [previous build provenance](../native-bridge/godot-integration-results.json), with only their recorded patch applied. The optional producer-read patch was applied only for its two named rows. Build logs and selected-check logs are stored next to this README; machine-specific paths are normalized. Local experimental binaries are outside the addon repository and are not shipped.

The next investigation must isolate the on-demand failure's source color/depth and frame lifetime, distinguish scene startup effects from persistent divergence, and exercise raster/main-device buffer reuse before a production engine change is proposed.
