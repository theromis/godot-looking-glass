# Direct IOSurface quilt target experiment

## Verified native primitive

On October 12, 2026, Apple M4 native Metal, `test-surface-direct` exited 0 with `PASS direct surface GPU writes, imported bytes and ACK backpressure`.

`SurfacePublisher::direct_texture()` exposes the existing transported RGBA8 IOSurface texture. A compute producer writes directly into it. `publish_rendered()` waits on an empty command buffer committed after producer commands on the same queue, then publishes the surface identifier. It creates no blit encoder and performs no producer texture copy. Diagnostic checksum mode reads pixels on the CPU; it is for tests only.

The test performs three distinct full-surface coordinate patterns at 704×684. A separately created Metal texture backed by the received Mach-port IOSurface reads exactly the expected bytes. It checks the published checksum and identifier, rejects publication until worker ACK, and verifies readiness after ACK. This is a native same-process transport/import test, not a Godot integration, cross-process race test, Bridge presentation test or throughput benchmark.

## Integration requirements

Godot already offers `RenderingDevice.texture_create_from_extension()`, and our synthesizer accepts `rig.external_quilt_target`. The existing static SDK direct-target diagnostic exercises that import mechanism. The new transported-surface primitive has not yet been wired to the managed live output node.

Before wiring it, the scheduler must acquire worker readiness **before requesting any rendering into the shared target**. Checking readiness only when publishing is too late. Rig automatic transform updates must remain disabled for the whole shared-target lifetime. Import/compute uniform sets must be created and freed on the rendering thread; imported RIDs must be released after producer work has finished and before closing the publisher. Startup, Stop, immediate Stop, restart, scene removal and failed-worker cleanup need dedicated checks.

A single shared target cannot retain the existing private-next-quilt overlap while the worker is still reading it. Removing a copy can therefore reduce cadence. Compare against the selected blocking-copy/private-overlap baseline using identical quality settings and physical-display feedback. A ring of shared targets would require an explicit per-slot acquire/ACK protocol and further lifetime tests.

The worker-to-persistent-SDK-texture copy remains. Eliminating it would require a tested Bridge external IOSurface path or transferring the SDK-owned surface back to Godot, plus a known consumer-completion contract. Successful draw return and the current worker source-copy ACK are not proof that the SDK has finished sampling its output.

## Reproduce

```sh
clang++ -std=c++17 -fobjc-arc native/bridge_metal/test_surface_direct.mm \
  -framework Metal -framework Foundation -framework IOSurface \
  -o native/bridge_metal/build/test-surface-direct
native/bridge_metal/build/test-surface-direct
```

No SDK or physical display is required. Do not enable this primitive in production until the managed lifetime and cadence checks above pass. Current TPS defaults remain the measured private-quilt overlap path.
