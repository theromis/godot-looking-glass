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

## Prerecorded Godot-frame transport control

The worker optionally accepts a directory containing two 704×684 raw RGBA8 files named `frame-0.rgba` and `frame-1.rgba`. It validates exact input lengths before SDK initialization, uploads the two frames to separate shared Metal buffers once, and blits each selected frame into the same SDK texture. GPU output is checked against each source frame through diagnostic-only readback.

```sh
# Pillow is needed only for preparation. Use your configured Python interpreter.
python3 native/bridge_metal/prepare_worker_frames.py benchmarks/hardware/sequence-inspect/frame-0.png benchmarks/hardware/sequence-inspect/frame-1.png worker-frames
native/bridge_metal/build/probe-persistent "$BRIDGE_LIBRARY" 1 --experimental-reuse worker-frames
```

The PNG captures are local diagnostic artifacts, not tracked assets. Regenerate them with the sequence inspection test described in `bridge-live-output.md`. Raw files also remain local. CPU decoding/file transfer and initial uploads are explicit; this is not live Godot transport or zero-copy sharing.

Both initial and repeat runs completed 40 exact GPU updates with successful release/shutdown. The user confirmed orange/cyan cube color switching in the repeat. Frame-preparation output also matched the original raw buffers byte-for-byte. See [input hashes](../benchmarks/hardware/persistent-godot-frame-input.json), [initial run](../benchmarks/hardware/persistent-godot-worker.json) and [physically confirmed repeat](../benchmarks/hardware/persistent-godot-worker-repeat.json).

## RotatingCube comparison

The user reports `python -m bridge_python_sdk.Examples.RotatingCube` working well. In official revision `dff2cfe54d2dc8c2efec94d4ab6ea6093aea1f96`, `Examples/RotatingCube.py:476` calls `Render.render_frame()`. [Rendering/Render.py:183-229](https://github.com/Looking-Glass/Bridge-Python-SDK/blob/dff2cfe54d2dc8c2efec94d4ab6ea6093aea1f96/src/bridge_python_sdk/Rendering/Render.py) draws the center preview, renders off-axis views into the persistent quilt FBO, submits `self.quilt_tex` via the GL API and swaps/polls window events. This uses OpenGL, not Metal texture-identity switching. It is a useful working lifecycle reference, but does not provide the missing Metal consumer-completion contract.
