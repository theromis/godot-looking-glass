# Experimental managed Metal output node

`addons/looking_glass/metal_output.gd` runs the isolated worker directly from a Godot scene. It uses the normal engine render loop, requests new on-demand quilt revisions, copies completed output into private IOSurface transport, and waits for source-copy acknowledgment before reuse. No manual force_draw, diagnostic readback, Python supervisor or pixel files are needed for this path.

This is a bounded macOS native Metal prototype, not production-qualified Bridge synchronization. Current worker presets are fixed 66-view 11×6, 704×684 or 4092×4092, with presentation aspect queried from the selected device. Other grids and Vulkan/MoltenVK are not supported by this component yet. Full calibration remains internal to Bridge. It requires separately built native artifacts and an external Bridge runtime; no SDK runtime is included.

## Setup and API

Build the worker and extension using the native README. The rig must already be in the scene with `synthesis`, `quilt_rgba8`, `update_on_demand` and `compose_in_capture_callback` enabled before ready. Use 66 total views and 11 columns; the number of actual source cameras remains configurable. Native Metal tests use the documented `GODOT_MTL_SYNC_MODE=none` hazard-tracking workaround.

```gdscript
const MetalOutput = preload("res://addons/looking_glass/metal_output.gd")
var output = MetalOutput.new()

func start_display(rig: Node3D) -> void:
    add_child(output)
    # Set externally; an empty value falls back to BRIDGE_LIBRARY.
    output.bridge_library = OS.get_environment("BRIDGE_LIBRARY")
    output.display_index = -1 # Automatically select the first available device.
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

The worker now rejects missing/invalid indices before SDK window creation and reports a sanitized device-unavailable status. `tests/test_metal_output_unavailable.gd` deliberately selects an invalid index and verified a controlled worker exit code 1, a failure signal, an inactive node and no SIGSEGV. The zero-device state blocked that earlier verification. On October 12, a later enumeration returned one device again; the updated worker passed a 99-frame normal-loop test and restart/immediate-stop with clean SDK teardown. This latest test has no new user visual confirmation; earlier visible successes remain recorded separately. This does not establish hot-unplug safety during an active SDK call or automatic reconnect support.

## Device settings discovery

`output.discover_displays()` returns only numeric index, quilt width/height, columns/rows, display aspect and nominal view cone. It initializes the SDK in a separate process without creating a display window; call it during setup, since this explicit query blocks. SDK diagnostics are captured and discarded rather than exposed to application logs. There is no query timeout or automatic reconnect in this API yet.

Before adding a rig to the tree, call `output.configure_rig_for_display(rig, device)`. It accepts the currently supported 4092×4092 11×6 preset, configures RGBA8/on-demand/capture composition and camera source dimensions using the reported display aspect. Real-view count and focus remain application choices. Nominal cone application is opt-in via the third argument, because wider cones increased optical ghosting in earlier tests. Replacing an existing rig is required to change its resources.

The worker independently enumerates devices at startup, selects the first available index when configured as -1, validates the 11×6 grid and queries presentation aspect. This does not imply safe hot-unplug during SDK calls or support for arbitrary presets. Small quilts remain a diagnostic override.

Executed on October 12 with Godot 4.8 native Metal: discovery returned index 1, 4092×4092, 11×6, aspect 0.5625, cone 54; `test_metal_discovery.gd` passed configuration checks; invalid-device lifecycle passed; `test_metal_output_node.gd --show-seconds=6` submitted/received 99 frames, passed cleanup and restart/immediate-stop. These are functional tests, not new throughput or optical measurements.

## Interactive demo

Open `demo/metal_output.tscn` in Godot 4.8 with native Metal, or run:

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT_BINARY" --path . --rendering-driver metal res://demo/metal_output.tscn
```

Set `GODOT_BINARY` and `BRIDGE_LIBRARY` externally. The library can also be entered in the demo UI. Native worker/extension builds are still required for physical output, but the desktop preview needs neither Bridge nor a connected display.

1. Click **Discover displays**. This explicit SDK startup query may briefly block the UI.
2. Select a supported device and click **Start (60 seconds)**. The demo creates a fresh 24-source/66-view 4K rig using the queried aspect, with focus 6 and a conservative 30-degree cone.
3. Click **Stop** to release output resources while retaining the animated desktop preview. Closing the window also requests worker shutdown before exiting.

Controls are locked while output runs. Errors leave the desktop preview available. There is no automatic reconnect or hot-unplug guarantee. Submitted/worker-copy counters are not physical panel FPS. This preview is a conventional center camera, not an optical simulation of the display.

Executed on October 12: `--preview-smoke` passed without Bridge; the captured UI image was inspected for layout; `--output-smoke` performed discovery, configured a real-device rig, submitted/received 109 frames and passed SDK cleanup. No new user visual confirmation was collected for this demo run. Test commands append the selected flag after `--` in the command above.

## Repeated lifecycle and sustained validation

Five Start/Stop sessions followed by a 120-second session passed on the managed node: all 2331 frames of the sustained session were received, every worker exited 0 and SDK cleanup passed. Steady process RSS increased 464 KiB for Godot and 304 KiB for the worker. See [method, limitations and full measurements](managed-metal-stress.md).

The demo also passed four fresh-rig Start/Stop cycles, including expired rig/publisher references, invalidated quilt texture RIDs and exited worker processes. An injected active window-close notification passed with 68/68 frames and clean SDK teardown. See [test scope and records](managed-metal-stress.md#rig-recreation-and-active-close--october-12-2026).

## Capture ownership during camera motion

Managed output temporarily disables `Rig.auto_update_on_transform`, while retaining camera transform updates and explicit scheduled captures. It restores the caller's policy after stop. This prevents camera-following rigs from launching additional source captures while the output waits for copy acknowledgment. The transform-ownership test and a 119-frame managed lifecycle/restart test passed. See [TPS measurements and limits](tps-performance-profiles.md).

## Optional capture pacing

`max_capture_hz=0` preserves natural source-copy acknowledgment pacing. A positive value limits new capture starts without blocking the process loop; late captures do not create catch-up bursts, and the deadline resets at each start. The TPS experiment improved average desktop FPS only by reducing content updates and did not eliminate slow capture frames, so the default remains zero. See [measurements and tradeoffs](tps-capture-pacing.md).
