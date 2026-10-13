# Experimental managed Metal output node

`addons/looking_glass/metal_output.gd` runs the isolated worker directly from a Godot scene. It uses the normal engine render loop, requests new on-demand quilt revisions, copies completed output into private IOSurface transport, and waits for source-copy acknowledgment before reuse. No manual force_draw, diagnostic readback, Python supervisor or pixel files are needed for this path.

This is a bounded macOS native Metal prototype, not production-qualified Bridge synchronization. Current worker presets are fixed 66-view 11×6, 704×684 or 4092×4092, with aspect 0.5625. Other devices/grids, automatic calibration and Vulkan/MoltenVK are not supported by this component yet. It requires separately built native artifacts and an external Bridge runtime; no SDK runtime is included.

## Setup and API

Build the worker and extension using the native README. The rig must already be in the scene with `synthesis`, `quilt_rgba8`, `update_on_demand` and `compose_in_capture_callback` enabled before ready. Use 66 total views and 11 columns; the number of actual source cameras remains configurable. Native Metal tests use the documented `GODOT_MTL_SYNC_MODE=none` hazard-tracking workaround.

```gdscript
const MetalOutput = preload("res://addons/looking_glass/metal_output.gd")
var output = MetalOutput.new()

func start_display(rig: Node3D) -> void:
    add_child(output)
    # Set externally; an empty value falls back to BRIDGE_LIBRARY.
    output.bridge_library = OS.get_environment("BRIDGE_LIBRARY")
    output.display_index = 1 # Select the actual target device.
    output.duration_seconds = 60 # Bounded 20–600 second worker lifetime.
    output.failed.connect(func(reason): push_warning(reason))
    output.stopped.connect(func(graceful): print("Display stopped: ", graceful))
    output.start_output(rig)

func stop_display() -> void:
    if output.is_output_active():
        output.stop_output()
        await output.stopped
    output.queue_free()
```

`start_output()` reports whether launch was accepted; `started` is emitted after the worker SDK and GPU publisher are ready. `submitted_frames`, `received_frames` and `sdk_cleanup_passed` expose protocol diagnostics, not panel FPS or display completion. `stop_output()` stops requesting new revisions, waits for the outstanding source copy, then writes a quit command to the worker. The worker releases its SDK texture and calls SDK shutdown. Prefer awaiting `stopped` before freeing the node. Tree exit uses a forced fallback and cannot promise graceful SDK shutdown.

The native helper reserves a cryptographically random private IPC name and can clean up only that reserved namespace. Startup failure, normal worker exit and forced cleanup release producer resources. The GPU publisher is opened only after both IPC and SDK readiness. Before creating an SDK window, the worker checks that its configured index appears in the current display list and that a Metal device/queue exists. The node continuously drains nonblocking stdout/stderr and consumes only protocol lines; SDK serial/calibration diagnostics are not published. Runtime and binary locations are configured, not hardcoded installation paths.

The node requires exclusive control of rig revision requests while streaming. External render effects, rig replacement, device disconnect/reconnect, packaging and process crashes require further tests. Shared-shadow behavior remains the separate optional engine prototype; this node does not change global caster-culling settings.

## Executed tests

On the current Apple M4 native Metal Godot 4.8 build:

- Initial normal-render-loop test: 191 submitted/received frames, SDK cleanup passed.
- User-requested 20-second repeat: 391 submitted/received frames; the user confirmed a visible rotating orange cube.
- Restart followed by immediate stop: SDK cleanup passed before any scene frame was required.
- No SCRIPT ERROR or ERROR occurred; the native build retains the documented deprecated Mach bootstrap warning.

```sh
BRIDGE_LIBRARY="$BRIDGE_LIBRARY" GODOT_MTL_SYNC_MODE=none "$GODOT_LG_BIN" --path . --rendering-driver metal --script tests/test_metal_output_node.gd -- --show-seconds=20
```

These are functional lifecycle tests, not throughput benchmarks or indefinite-operation proof. See [record](../benchmarks/hardware/managed-metal-output.json). The existing main-device rendering and source-copy completion distinction still applies; acknowledgment does not assert that the physical display has consumed a frame.

## Unavailable-device finding and final verification limit

After the user-confirmed 391-frame repeat, later attempts found no devices in a separate SDK enumeration probe, while the Bridge application process remained running. Unguarded calls to `instance_window_metal` for index 1 crashed with SIGSEGV/null access; the local crash reports identify that SDK function as the top frame. Deferring IOSurface creation did not prevent this failure. No specific physical cause of the enumeration loss is established.

The worker now rejects missing/invalid indices before SDK window creation and reports a sanitized device-unavailable status. `tests/test_metal_output_unavailable.gd` deliberately selects an invalid index and verified a controlled worker exit code 1, a failure signal, an inactive node and no SIGSEGV. Final positive hardware revalidation is blocked by the current zero-device SDK state; earlier visible normal/early-stop successes remain recorded separately. This does not establish hot-unplug safety during an active SDK call or automatic reconnect support.
