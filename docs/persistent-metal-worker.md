# Persistent Metal worker experiment

`native/bridge_metal/probe_persistent.mm` is a standalone, explicitly bounded diagnostic that updates one SDK-created RGBA8 IOSurface using a Metal compute shader. Blue/red patterns alternate at a requested 2 Hz for 20 seconds. Diagnostic CPU readback checks every generated pattern; it is not a proposed production readback path.

```sh
python3 native/bridge_metal/build.py --sdk-headers "$BRIDGE_HEADERS"
native/bridge_metal/build/probe-persistent "$BRIDGE_LIBRARY" 1 --experimental-reuse
```

Unlike the previous immutable texture-switch tests, this modifies the same input texture. It requires explicit experimental mode and is not integrated into Godot or the normal adapter's immutable-output contract.

Before subsequent writes, the program requires the same nonnull current CGL context observed after SDK submission and calls `glFinish`. It waits for each Metal producer command buffer before submitting. A missing/changed context or GL completion error aborts updates. This only completes commands already submitted on the observed GL context; it does not establish a public SDK consumer-completion guarantee for other contexts or future reads. Therefore even physical success would validate visible updating, not production-safe reuse.

The process creates one texture, attempts release/shutdown after the bounded run and records API outcome separately from the user's display observation. No indefinite loop, Godot streaming implementation or measured frame-rate claim is made. Requested 2 Hz may include CPU/GPU/event processing overhead.

See [execution record](../benchmarks/hardware/persistent-metal-worker.json). The next stage depends on whether the persistent input visibly changes, then on establishing the supported lifetime/synchronization contract and cross-process Godot transport.

On 2026-10-12, Bridge 2.6.3 on Apple M4 completed 40 GPU updates, exact pattern checks, 39 observed-context GL finishes and successful release/shutdown. The user confirmed changing blue/red colors on the physical display. This supports a persistent-input Metal worker direction; it does not establish a portable consumer-completion contract or a Godot cross-process path.
