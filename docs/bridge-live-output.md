# Bounded live Bridge output

The failure discussed below is specific to the tested distinct-texture Metal path. Working GL video/game examples update a persistent texture in an isolated process. See the [source audit and revised output plan](bridge-working-stream-reference.md); Bridge streaming in general is not blocked by this result.

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

On 2026-10-12, native adapter tests passed, the Godot fixture completed eight interleaved updates and clean teardown, and the real Bridge 2.6.3 run completed eight updates with successive source revisions 122 through 129. The known SDK initialization GL_INVALID_ENUM message persists. The requested repeat passed API checks, but the user answered no to the combined image/update question. Physical validation failed; whether image appearance or updates failed remains to be clarified. The nonblocking SDK pump is therefore not a working physical live-output feature. See [fixture result](../benchmarks/hardware/bounded-live-fixture.json) and [hardware result](../benchmarks/hardware/bounded-live-real.json).

## Event-path comparison

The --two-frame control captures two immutable quilts with orange/cyan cube materials, then presents them for 20 seconds at one change per second through the existing NSRunLoop playback path. The new play_sequence_at_rate API validates finite positive rate up to 60 Hz; existing playback defaults remain 5 Hz. Compare this with the failed nonblocking pump before assigning the failure to texture delivery or event processing. This is prerecorded playback, not live streaming. See benchmarks/hardware/two-frame-runloop.json.

The two-frame NSRunLoop comparison passed API checks but the user answered no to visible image/color changes. Therefore the new nonblocking event pump alone is not established as the cause. A separate native solid-blue probe, which selects the device via SDK enumeration and excludes Godot, is being used to distinguish current output/window availability from Godot texture delivery.

The native solid-blue probe was user-confirmed visible, and selected the same device index 1. The direct imported 4K Godot static quilt was also user-confirmed visible. The copied two-frame sequence remained unconfirmed/failed even with ShaderWrite added to output usage; that descriptor change was reverted. These controls narrow the issue to differences in copied sequence delivery/window setup rather than complete device unavailability. A native adapter copy probe verifies the copied blue pixels diagnostically and tests visibility independently of Godot.

Native adapter GPU-copy blue output was user-confirmed visible, with exact pixel readback. The two Godot source quilts were inspected: orange/cyan cube changes are present, and each source matches the real copied SDK target byte-for-byte. Diagnostic PNG readback is opt-in via --inspect-only and is not part of normal presentation. SDK session/window creation was then moved before rig creation/warmup, matching the ordering of the successful direct-target test; physical confirmation of this order control is recorded separately.

Early-window two-frame control also did not obtain user confirmation of switching. The user noted not seeing a cyan cube in the static control; that static control intentionally contains only an orange cube. A follow-up distinguishes a visible but unchanging new scene from no new scene at all. The order change is an experiment, not a verified fix. Native adapter and final two-frame live fixture tests passed.

The user clarified that the new orange-cube scene was visible in the two-frame tests, but its color did not change. Earlier combined no responses must therefore be read as a switching failure, not proof of an invisible window. A native two-color test alternates separate immutable blue/red targets to isolate SDK texture switching from Godot content production.

The native two-color probe completed exact blue/red copies and successful calls/teardown, but the user reported one constant color. This reproduces the switching symptom without Godot. It does not prove a particular internal SDK cache or defect; the supported switching/context protocol and consumer completion guarantees remain unresolved. A [support report draft](bridge-sdk-texture-switch-report.md) records the minimal reproduction and questions; it has not been sent.
