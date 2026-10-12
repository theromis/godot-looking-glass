# Draft: Metal input texture switching and completion semantics

This report is prepared for Looking Glass SDK support. It has not been sent.

Scope: this concerns switching distinct Metal input textures, not Bridge streaming in general. Official GL video examples and the user-supplied Genesis-Plus-GX PR update persistent GL textures; see `bridge-working-stream-reference.md` for the separate fallback plan.

## Environment and symptom

Apple M4, native Metal, Looking Glass Bridge 2.6.3. SDK enumeration returns one display at index 1, quilt 4092×4092, 11×6, aspect 0.5625. Diagnostic input textures are 704×684 RGBA8Unorm, Shared storage, SDK-created IOSurfaces.

A single immutable blue texture is visibly displayed. A direct imported static Godot 4.8 quilt is also visibly displayed. When alternating two distinct immutable SDK textures, the display remains on one image although every draw call returns true. The symptom reproduces in a standalone native program without Godot.

## Minimal reproduction

Own MIT-licensed diagnostic source: `native/bridge_metal/probe_copy.mm`, with adapter in `adapter.hpp/mm`. No proprietary SDK source is included.

```sh
python3 native/bridge_metal/build.py --sdk-headers "$BRIDGE_HEADERS"
native/bridge_metal/build/probe-copy "$BRIDGE_LIBRARY" 1 --two-color
```

1. Initialize SDK and create one Metal window for explicitly enumerated display index 1.
2. Fill an independent producer texture with blue fixture pixels.
3. Allocate SDK texture A, blit the fixture into A, wait for the producer/copy command buffers and submit A.
4. Fill the producer with red, allocate SDK texture B, blit and wait, then submit B.
5. Retain A and B, without modifying either. Alternate `draw_interop_quilt_texture_metal` with A/B approximately once per second for 20 seconds. Show the window and process available SDL events plus the main NSRunLoop.
6. Release both textures and shut down the SDK.

Both output textures were checked via explicit diagnostic CPU readback and match their blue/red fixtures exactly. Calls and teardown return success. The user reports that the display stays one color. Separate Godot captures also show correct orange/cyan input frames and byte-exact SDK copies, but only the orange scene is seen.

Adding ShaderWrite usage to copied targets and opening the SDK window before Godot warmup did not restore switching in those controls; the usage change was reverted. A known GL_INVALID_ENUM initialization message appears even in physically successful single-image tests, so it has not been isolated as the cause.

## Questions

1. Does `draw_interop_quilt_texture_metal` support changing the input MTLTexture/IOSurface for an existing window? Is a separate registration/reset operation required?
2. Does the runtime cache the initial IOSurface, or is another event/context operation necessary for switching?
3. What exact completion guarantee does draw/release provide for consumer access? Is a fence, callback or documented synchronous boundary available?
4. What is the supported procedure for indefinitely updating quilts while safely reusing bounded GPU memory?

The current prototype retains immutable outputs and enforces 16-frame/128-MiB payload limits. It does not overwrite in-use textures or claim that a successful draw return is a completion fence.

## Recorded evidence

- `benchmarks/hardware/native-copy-blue.json`: single copied native image visible.
- `benchmarks/hardware/native-two-color.json`: exact native blue/red copies; no visible color switching.
- `benchmarks/hardware/sequence-inspect.json`: exact Godot source/SDK copies and capture hashes.
- `benchmarks/hardware/two-frame-early-window.json`: orange scene visible, no cyan switching.
- `benchmarks/hardware/direct-output-recheck.json`: direct static Godot output visible.

Device serials, lens calibration and absolute installation paths are excluded from the tracked report/logs.
