# Bounded live Bridge output

The native Metal diagnostic produces new poses while the Bridge window is visible. It uses distinct immutable SDK textures and stops after eight updates. It is not indefinite streaming.

## Ordering and ownership

Request and finish a Godot quilt revision, freeze its source, commit/wait the producer fence, copy into a new SDK IOSurface and wait for the GPU copy. Then call `pump_latest_frame()` on the main thread. The source may change after its copy completes; every consumer texture stays alive and unchanged until SDK release/session teardown.

The adapter keeps its existing 16-texture/128-MiB payload limits. This diagnostic uses eight 704×684 RGBA8 quilts (about 14.7 MiB excluding driver allocations). Each pose is held approximately one second plus intervening rendering overhead; this is not measured FPS. Production output does not read pixels back to CPU. Fixture checks do.

## Continuous-streaming blocker

The inspected external `BridgeRuntime/bridge.h:374-380` exposes Metal create/copy/draw/release operations without a consumer-completion fence. Producer completion does not establish consumer completion. A successful draw return, three buffered slots or an arbitrary delay does not establish safe reuse.

The inspected [official native reference](https://lfdocs.lookingglassfactory.com/software/looking-glass-bridge-sdk/native-function-reference) and [SDK samples](https://github.com/Looking-Glass/bridge-sdk-samples) did not establish a Metal consumer-lifetime contract. An SDK-supported completion mechanism or documented synchronous consumption/release guarantee is needed before indefinite bounded-memory output is enabled. No support message has been sent.

## Implementation and validation

- `adapter.mm`: `pump_latest_immutable()` validates main thread, session and geometry; shows the window, pumps available SDK events and redraws the current immutable texture.
- `godot_diagnostic.mm`: exposes `pump_latest_frame()` to Godot.
- `tests/test_real_bridge_sequence.gd -- --live`: produces eight poses during presentation, retaining all copies until close.
- `--fixture --live`: tests the Godot lifecycle with the own SDK test double.
- `native/bridge_metal/test.mm`: checks exact pixels, 16 immutable targets, pumping, invalid states, budget rejection and teardown retry.

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT_LG_BIN" --path . --rendering-driver metal --script tests/test_real_bridge_sequence.gd -- --fixture --live
# Real output requires external BRIDGE_LIBRARY and BRIDGE_DISPLAY_INDEX:
GODOT_MTL_SYNC_MODE=none "$GODOT_LG_BIN" --path . --rendering-driver metal --script tests/test_real_bridge_sequence.gd -- --live
```

This small-resolution scene differs from accepted static 4K controls. It does not validate fine-edge quality, full-resolution motion or transparency. Recorded API results and user display observations remain separate.

## Executed results

On 2026-10-12, native adapter tests passed, the Godot fixture completed eight interleaved updates and clean teardown, and the real Bridge 2.6.3 run completed eight updates with successive source revisions 122 through 129. The known SDK initialization GL_INVALID_ENUM message persists. Physical user confirmation is pending. See [fixture result](../benchmarks/hardware/bounded-live-fixture.json) and [hardware result](../benchmarks/hardware/bounded-live-real.json).
