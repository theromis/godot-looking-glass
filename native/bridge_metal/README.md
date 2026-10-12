# Experimental Metal-to-Bridge boundary

Own MIT-licensed Objective-C++ code, separate from the Godot addon. This is a **one-shot native diagnostic**, not a GDExtension or working Godot display output. It accepts an actual `id<MTLTexture>` and its committed producer `id<MTLCommandBuffer>`, copies the quilt on GPU into an SDK-created texture, then calls the documented Metal quilt function. Do not pass Vulkan handles to this interface.

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

The selected Godot 4.8-dev runtime is Vulkan/MoltenVK-only. Its texture handle is not a native Metal handle. The inspected SDK header exposes Metal APIs but no direct Vulkan image submission. A MoltenVK texture accessor alone would not establish when Godot's producer commands have been submitted/completed or when Bridge has finished consuming the texture.

Next: provide a tested native Metal Godot runtime/GDExtension and render-thread handle access with a real producer completion contract, or design a separately validated Vulkan/Metal interop path. Then verify calibrated hardware, SDK formats, color transfer, session/window threading, consumer completion and bounded output slots before adding streaming to the addon.

Source evidence: external `bridge.h:108–118` (version query), `:373–380` (Metal APIs); Godot `drivers/metal/rendering_device_driver_metal.cpp:2545–2568` (device/queue/texture handles), base `232e6b14abf6e590b41d60f11704e42de22bff72`. No proprietary implementation source was copied.
