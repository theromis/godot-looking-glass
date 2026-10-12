# Experimental Metal-to-Bridge boundary

Own MIT-licensed Objective-C++ code, separate from the Godot addon. The adapter is a **one-shot native diagnostic**; an optional test-fixture-only GDExtension is described below. This is not working physical Godot display output. It accepts an actual `id<MTLTexture>` and its committed producer `id<MTLCommandBuffer>`, copies the quilt on GPU into an SDK-created texture, then calls the documented Metal quilt function. Do not pass Vulkan handles to this interface.

## Build and run

Run from the repository root on macOS with the Apple compiler and Metal frameworks. Supply legally available SDK headers yourself; headers and runtime binaries are neither vendored nor redistributed.

```sh
python3 native/bridge_metal/build.py --sdk-headers ../looking-glass-reference/bridge-sdk-samples/BridgeRuntime
native/bridge_metal/build/test-adapter native/bridge_metal/build/fixture.dylib
native/bridge_metal/build/test-adapter --probe-sdk "path/to/Bridge.app/Contents/MacOS/libbridge_inproc.dylib"
```

Build artifacts stay in the ignored `native/bridge_metal/build/` directory. `--probe-sdk` loads the installed library, resolves required entry points and queries its version. It does not initialize an SDK session, select a monitor, create a window or submit an image. Missing libraries/symbols and unsupported major versions fail closed. The supported check is major 2, minor >=6, with all required symbols available; future binary compatibility is not guaranteed by this check.

## Implemented contract

- `load(path)` dynamically resolves APIs using types from the external header; no link-time SDK binary dependency.
- `open(device, calibrated_display_index)` requires an explicit index supplied by the caller after calibration validation. It rejects automatic/offscreen sentinels. Only one adapter instance may own the native SDK session in this process; other native SDK clients must coordinate lifecycle separately.
- `submit_once(source, producer, columns, rows, aspect, zoom)` validates device, 2D RGBA16Float/single-sample format, quilt dimensions and finite positive geometry. It rejects uncommitted producers, waits for producer completion, allocates an SDK texture, validates its format/size/device, blits on GPU and waits for copy completion before the SDK draw call.
- No pixel readback occurs in the adapter. The two blocking waits are a correctness baseline, not a performance optimization or an asynchronous streaming design.
- After allocation begins, the one-shot guard prevents replacement/reuse even on errors. Output remains retained until SDK release/session shutdown. Successful close is idempotent. Failed release/shutdown keeps the session/library/resources pinned and prevents another adapter taking ownership; callers can retry close. If destruction still fails, resources are intentionally retained until process exit rather than unloading live SDK code.

SDK draw return is **not** established as a consumer GPU fence. Therefore this component does not reuse output slots or claim safe multi-frame streaming. Real SDK consumption/teardown semantics, format/transfer function, view orientation and optical correctness require hardware validation. The adapter must be called serially; this prototype provides no cross-thread Godot window/render-thread integration.

## Executed tests

Apple M4, Apple clang 21.0.0:

- Built without compiler diagnostics using the external sample header (declared Bridge version 2.6.2).
- Real Metal command buffers generated an 8×4 RGBA16Float input, then copied it to a **real IOSurface-backed** texture allocated by the SDK test double. All 128 half-float components matched exactly. The fixture's CPU readback is validation-only.
- Tested missing library, unsupported SDK version, explicit-index validation, uncommitted producer, invalid grid, exclusive adapter session, repeated submission, initialization/window/allocation/draw failures, release/shutdown failures and retry, and double close.
- Loaded the installed Bridge 2.6.3 library and verified required symbols/version; no real SDK window/texture/draw was attempted.

Logs and provenance: [native-bridge results](../../benchmarks/native-bridge/README.md).

## Godot integration still required

The original Godot 4.8-dev runtime is Vulkan/MoltenVK-only; a separate native Metal build of the same engine generation has now been tested below. Its texture handle is not a native Metal handle. The inspected SDK header exposes Metal APIs but no direct Vulkan image submission. A MoltenVK texture accessor alone would not establish when Godot's producer commands have been submitted/completed or when Bridge has finished consuming the texture.

The fixture diagnostic below now provides tested Godot Metal handle access for a frozen post-frame source. Production integration still needs a real calibrated SDK window, SDK formats/color transfer, session/window threading, consumer completion and bounded output slots. Vulkan/Metal interop is a separate unvalidated path.

Source evidence: external `bridge.h:108–118` (version query), `:373–380` (Metal APIs); Godot `drivers/metal/rendering_device_driver_metal.cpp:2545–2568` (device/queue/texture handles), base `232e6b14abf6e590b41d60f11704e42de22bff72`. No proprietary implementation source was copied.

## Optional Godot diagnostic GDExtension (executed)

The component now includes `LookingGlassMetalDiagnostic.copy_static_quilt()`, a **test-fixture-only** GDExtension. It resolves Godot's native Metal device, queue and texture handles on the rendering thread, commits a sentinel on the same queue and feeds the frozen texture to the adapter. It refuses Vulkan and libraries without the fixture exports before native texture submission. Readback is explicitly limited to 16 MiB and exists only to compare test output; no production streaming API is provided.

```sh
# External MIT bindings, pinned revision e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77.
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git ../godot-looking-glass-deps/godot-cpp
(cd ../godot-looking-glass-deps/godot-cpp
scons platform=macos target=template_release arch=arm64 build_profile=../../godot-looking-glass/native/bridge_metal/bindings-profile.json -j4)
python3 native/bridge_metal/build.py --sdk-headers ../looking-glass-reference/bridge-sdk-samples/BridgeRuntime
python3 native/bridge_metal/build_extension.py --godot-cpp ../godot-looking-glass-deps/godot-cpp --sdk-headers ../looking-glass-reference/bridge-sdk-samples/BridgeRuntime
GODOT_METAL_BIN=../godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64.native-metal
"$GODOT_METAL_BIN" --path . --rendering-driver metal --script res://tests/test_native_metal.gd
```

The 4.5 tag specifies the binding API, not another tested engine version. All engine executions in this step used 4.8-dev. Build configuration/library files are generated under the ignored build directory, so ordinary addon clones do not load a missing optional extension.

`test_native_metal.gd` renders four output views from two source cameras, explicitly requests 120 warmup updates with short waits, then stops requesting updates and finishes additional Godot frames. Capture and dispatch counters must remain fixed before copying. The same-queue sentinel fences **already committed** work: it cannot flush unsubmitted RenderingDevice lists. The test performs no source pixel readback before native copying. Afterwards, all 16,384 half-float components of the 64×64 quilt must match the fixture output and the image must contain visible RGB data. Three final repeats passed. This is not validation of arbitrary frame_post_draw consumption, dynamic textures or real SDK consumer fences.

The new 4.8-dev native Metal runtime successfully executes compute, but only **13/16** addon regression checks passed. Failures: on-demand continuous/cached equivalence, capture/workgroup equivalence after resize, and borrowed-buffer policy equivalence. An explicit settled-startup refresh did not guarantee equality. The Vulkan 4.8-dev suite still passes all **16**. Native Metal is therefore experimental, not a general support claim. Initial empty/cold-start copy probes are retained as rejected attempts; their cause is not established. The 120-update warmup is a test setup, not an automatically implemented production warmup guarantee.

Next remains a real calibrated SDK window, validated output format/transfer/orientation, threading and consumer completion before streaming. The Godot driver-resource access and fixture GPU-copy portion is now executed rather than only proposed.


## Real SDK offscreen diagnostic

`build.py` also builds `build/probe-offscreen`. Run it with the installed SDK library as its single argument, under a bounded subprocess timeout (40 seconds was used). It dynamically resolves the official header signatures, initializes Bridge, queries display count, attempts only `instance_offscreen_window_metal` with `FIRST_LOOKING_GLASS_DEVICE`, and shuts down. It never submits a quilt, creates a physical display window, or invents calibration. Its successful exit means the diagnostic/query/teardown succeeded, not that offscreen creation succeeded; inspect the printed fields.

On Apple M4 with installed Bridge 2.6.3, initialization/query/shutdown succeeded, display count was zero, and Metal offscreen creation returned false with handle zero. The SDK exposed no detailed error here. This blocks this tested no-device route, without proving every offscreen route impossible. The generic calibration-file offscreen entry point is documented with OpenGL; it is not evidence that the Metal API accepts a calibration file.

Header references in the external SDK sample tree: `BridgeRuntime/bridge.h:156` (generic calibration-file API), `:379` (Metal offscreen device-index API), `:380` (output texture), and `:544` (display query). No explicit consumer fence/completion function was found in that header. Draw-return must remain distinct from GPU completion: production streaming requires a documented consumer ownership/completion contract or another independently validated synchronization mechanism. No ring-buffer reuse or performance improvement is claimed. See [observed results](../../benchmarks/native-bridge/offscreen-results.json) and the [official native API reference](https://lfdocs.lookingglassfactory.com/software/looking-glass-bridge-sdk/native-function-reference).


## Native Metal synchronization diagnosis

The default-barrier Metal path still fails three addon regressions. These failures were repeated after the hazard-tracking runs, so GPU warmup alone did not make them pass. The nine-rig diagnostic isolates differences in source color and final viewport images, not only compute output: the first left source matches an opposite/right source despite equal left-camera transforms and projections. Two default-barrier diagnostics matched only 32/80 cross-rig snapshot comparisons; native hazard tracking matched all 80/80. Adding a diagnostic guard viewport also removed the previously observed cross-rig quilt mismatch, but this is not a production workaround.

On the latest local 4.8-dev native Metal build / Apple M4, this existing engine switch passed **all 16 regression checks**, the full 15-case buffer compatibility matrix, and the static native fixture copy:

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal
GODOT_MTL_SYNC_MODE=none python3 tests/run_checks.py --godot "$GODOT" \
  --driver metal --output-dir benchmarks/native-bridge/regression-metal-hazard
```

Set `GODOT` to your latest native Metal engine executable. This switch means native hazard tracking, not disabled synchronization (`rendering_device_driver_metal.cpp:2873`). It is opt-in at process launch; no addon rendering defaults or engine sources were changed. The switch also changes resource allocation/heap policy, so an exact driver cause is not established. No performance comparison was made. A smaller standalone camera test failed once, then passed later controls and six further default-barrier runs; its failure is intermittent. Six hazard-tracking repeats passed. General support on other engines/GPUs, producer streaming and real Bridge output remain unvalidated.

See [outcomes](../../benchmarks/native-bridge/metal-sync-results.json) and [unpublished upstream issue draft](../../docs/native-metal-issue-draft.md).


## Connected hardware and format boundary

The no-device blocker is superseded for the connected display. `build.py` now also builds `probe-hardware`: a separate native SDK diagnostic supporting offscreen RGBA8, explicit physical window visibility and a 30-second immutable-color presentation. The user confirmed physical blue output. The probe dynamically resolves the optional SDL pump; it does not mutate the texture during consumption or establish an animated consumer fence. The existing Godot GDExtension remains fixture-only. Both tested shared RGBA16Float SDK descriptors failed allocation; RGBA8 worked, so Godot preview conversion is the next integration step. The connected preset has 66 views, while the addon caps views at 48. See [device, format, GL warning, user observation and reproduction](../../benchmarks/hardware/README.md).
