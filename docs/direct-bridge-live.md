# Live direct Bridge texture, without worker

On October 12, 2026, a short native-Metal Godot 4.8 test on Apple M4 updated a single persistent SDK RGBA8 texture directly. The physical Looking Glass user confirmed visible rotation and orange/cyan color changes. Forty updates completed, followed by successful imported-RID release and SDK teardown; process exit was 0.

The SDK creates its IOSurface-backed texture once. `import_direct_target()` imports it into Godot RenderingDevice. The rig's existing external quilt target routes compute synthesis into that same texture. `update_direct_target_experimental()` fences previously committed Godot GPU work, submits the persistent texture and shows/pumps Bridge on the main thread. No worker, mailbox, producer quilt blit or adapter blit is used in this path. Internal Bridge copies and processing are not observable from this code.

The fixture test checks every updated quilt byte against the SDK fixture and requires at least two distinct frame hashes. The first fixture run checked 40 updates; the strengthened regression uses 8. Physical output uses 4092×4092, 24 source views → 66 output views, 20-degree cone, focus 5.6, and an unshaded cube/spheres scene. Two explicit Godot draws commit capture and frame-post-draw synthesis before submission. This is conservative diagnostic scheduling, not a production frame loop.

## Limits

The experiment explicitly permits overwriting a previously submitted target. It does not establish an SDK consumer-completion guarantee. Producer completion only establishes that Godot finished writing; Bridge's successful draw return may not establish that all SDK reads finished. The 0.5-second delay is test pacing, not a correctness fence. Long-running reuse, resize, unexpected close, scene changes and uncapped performance remain untested. The selected TPS worker path remains unchanged.

The hardware run emitted an SDK `GL_INVALID_ENUM` diagnostic during startup, then delivered the expected updates and completed teardown. Its source and significance are unresolved. Do not describe this as a completely error-free SDK run or a production-ready path.

No throughput benchmark was performed. The test intentionally updates around twice a second plus rendering overhead. Removing two explicit copies does not prove higher cadence than the measured private-quilt overlap baseline.

## Run

After building the diagnostic extension, set `BRIDGE_LIBRARY` to the external runtime and `BRIDGE_DISPLAY_INDEX` to the detected numeric display index, then run:

```sh
"$GODOT_EDITOR" --path . --rendering-driver metal \
  --script tests/test_bridge_direct_target.gd -- \
  --live-direct --large --real-views=24 --display-aspect \
  --view-cone=20 --focus=5.6
```

Fixture regression requires the separately built own fixture library and uses `--fixture --live-direct` instead of hardware arguments. It performs diagnostic CPU readbacks only in fixture mode. Hardware mode performs no pixel readback.
