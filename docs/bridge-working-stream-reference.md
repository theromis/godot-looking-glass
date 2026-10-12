# Working streaming references and revised output plan

## Scope correction

Our verified failure is switching distinct immutable Metal SDK textures on Bridge 2.6.3 in the tested adapter. It is not evidence that Bridge cannot stream. The video and game examples use a different path: a persistent OpenGL texture updated over time. They do not establish the consumer-completion contract for our Metal path.

## User-supplied game implementation

[Genesis-Plus-GX PR 412](https://github.com/libretro/Genesis-Plus-GX/pull/412), inspected head `9b1c070627b4ec64c4b926443bca7aa61d79d754` in `theromis/Genesis-Plus-GX`:

- [retroarch_bridge_worker.py](https://github.com/theromis/Genesis-Plus-GX/blob/9b1c070627b4ec64c4b926443bca7aa61d79d754/extras/stereo3d/retroarch_bridge_worker.py): lines 46–61 create a separate GLFW OpenGL context/window and Bridge GL window. Lines 69–88 poll events, read a shared-memory layer atlas, compose the quilt, restore the producer context, flush and submit `renderer.quilt` via `draw_interop_quilt_texture_gl`.
- [live_viewer.py](https://github.com/theromis/Genesis-Plus-GX/blob/9b1c070627b4ec64c4b926443bca7aa61d79d754/extras/stereo3d/live_viewer.py): `Renderer` creates persistent atlas/quilt textures at lines 228–230. `Renderer.compose()` at lines 241–279 uploads the atlas, allocates quilt storage only when dimensions change, and renders into the same quilt texture.
- [RETROARCH_LOOKING_GLASS.md](https://github.com/theromis/Genesis-Plus-GX/blob/9b1c070627b4ec64c4b926443bca7aa61d79d754/extras/stereo3d/RETROARCH_LOOKING_GLASS.md): lines 10–11 describe SDL/Cocoa class conflicts and process isolation; lines 114–124 report an in-process visibility failure, subsequent user-confirmed Sonic video/audio and synthetic worker validation. Those are the author's recorded results, not tests executed in this Godot project.

The core remains in RetroArch; the worker receives a compact layer atlas through shared memory, uploads it, and composes views on its GPU. This is neither a CPU-free cross-process path nor a full-quilt transfer. The root `LICENSE.txt` includes noncommercial restrictions; no implementation from this repository is copied into the MIT addon. It is reference-only.

## Official video stream

Looking Glass Bridge-Python-SDK revision `dff2cfe54d2dc8c2efec94d4ab6ea6093aea1f96`:

- [Examples/StreamAndDisplayRGBD.py](https://github.com/Looking-Glass/Bridge-Python-SDK/blob/dff2cfe54d2dc8c2efec94d4ab6ea6093aea1f96/src/bridge_python_sdk/Examples/StreamAndDisplayRGBD.py): CLI for file/camera sender and stream receiver.
- [Rendering/Stream.py](https://github.com/Looking-Glass/Bridge-Python-SDK/blob/dff2cfe54d2dc8c2efec94d4ab6ea6093aea1f96/src/bridge_python_sdk/Rendering/Stream.py): `preview_loop()` begins at line 156; lines 208–209 allocate RGBA8 texture storage. Lines 217–249 consume CPU-decoded frame bytes, update the same texture with `glTexSubImage2D`, call `draw_interop_rgbd_texture_gl`, swap and poll events.
- Root `LICENSE` is MIT, Looking Glass Factory. No source has been vendored here.

This example submits RGBD rather than our multiview quilt and uses CPU video decoding/upload. It demonstrates an intended GL streaming path, not Metal texture switching or a verified zero-copy integration.

## Next implementation steps

1. Build an independently written standalone GL-worker diagnostic with one persistent texture and synthetic animated pixels. Physically verify frame changes before integrating Godot. Isolate SDK/SDL/Cocoa from Godot.
2. Implement a bounded, explicit CPU-readback/shared-memory/upload fallback for Godot as a measurable compatibility path. Record transferred bytes, copy/readback/upload times and end-to-end latency. A 4092-square RGBA8 quilt contains about 63.9 MiB per frame, so this is not presumed fast.
3. Evaluate macOS IOSurface GPU sharing as a separate optimization, including supported cross-process import, producer/consumer ordering and slot lifetime. Do not reuse the failed Metal-switch results as a completion guarantee.
4. Keep static direct Metal output and local GPU preview available. Revisit a persistent Metal-target update only with a justified consumer completion protocol.

No new GL-worker implementation or benchmark is claimed in this reference audit. The support draft remains useful for Metal-specific switching/synchronization questions; it does not imply that SDK support is required for every possible streaming path.
