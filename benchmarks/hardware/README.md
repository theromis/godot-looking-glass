# Connected Looking Glass: real Bridge tests

On 2026-10-11 the connected display was detected by macOS, native Bridge 2.6.3, and the corrected addon HTTP client on Apple M4. The device serial, device-specific lens values and calibration file path are redacted in published logs.

## Observed device configuration

| Property | Observed value |
| --- | --- |
| Native/HTTP device index | 1 |
| Display | 1440 × 2560, 60 Hz |
| View cone | 54° |
| SDK default quilt | 4092 × 4092 |
| Default grid | 11 × 6, 66 views |
| View aspect | 0.5625 |

No product model is inferred solely from resolution. This is one connected device, not compatibility coverage for the Looking Glass product range.

## Executed SDK boundary

The native SDK now creates Metal offscreen windows. `create_metal_texture_with_iosurface()` succeeds with a shared RGBA8Unorm texture using shader-read/render-target usage; the test source is 704×384 (64² tiles, a uniform color rather than a rendered 4092² scene), a GPU render-pass clear completes, quilt submission returns true, and the SDK exposes an offscreen RGBA8 texture sized 1440×2560. Offscreen pixel values were not verified and output retrieval is not treated as a completion fence.

RGBA16Float allocation failed with both shader-read/render-target usage and the shader-read-only descriptor matching the existing adapter. This establishes a failure for the tested descriptors, not a universal statement about all SDK formats or versions. The existing RGBA16Float adapter remains fixture-validated; it is not silently switched to RGBA8.

The initial onscreen test returned success but the user reported no visible change. A second test explicitly called `show_window()`, ran an event loop with an optional SDL pump and resubmitted the same unchanged RGBA8 texture for 30 seconds. **The user confirmed that the blue color appeared on the physical Looking Glass.** No texture contents were overwritten during consumption. Release and SDK shutdown returned true. The independent native probe uses no Godot runtime; this is not end-to-end Godot scene output or animated quilt streaming.

SDK logs include `GL_INVALID_ENUM` during renderer initialization even in the visually successful run. Its cause and impact remain unknown. OpenGL renderer/version messages occur while the public Metal input APIs are used; no purely Metal consumer pipeline or cross-API synchronization contract is assumed.

See [structured outcomes](results.json), [offscreen RGBA8](real-sdk-offscreen-rgba8.log), [RGBA16Float shader-read-only failure](real-sdk-rgba16-read-only.log), [initial invisible attempt](real-sdk-onscreen-rgba8.log), and [visually confirmed attempt](real-sdk-onscreen-shown-rgba8.log).

## HTTP calibration fix

`addons/looking_glass/bridge_client.gd:68` parses serialized calibration JSON. The parsed object also needs recursive `unwrap()` because its numeric values contain nested Bridge `value` wrappers. Previously the real device was filtered out; after the fix, index 1 and its 1440×2560 / 54° geometry are detected. The fixture now uses this serialized/wrapped form, and the test separately checks direct dictionary wrappers. Session close and geometry checks passed on the latest native Metal 4.8-dev engine. See [fixture log](http-string-calibration-fixture.log).

## Reproduction

Build our own probes using externally installed SDK headers:

```sh
python3 native/bridge_metal/build.py --sdk-headers "$BRIDGE_HEADERS"
native/bridge_metal/build/probe-hardware "$BRIDGE_LIBRARY" --rgba8
native/bridge_metal/build/probe-hardware "$BRIDGE_LIBRARY" --rgba8 --compute-write
native/bridge_metal/build/probe-hardware "$BRIDGE_LIBRARY" --rgba8 --onscreen
native/bridge_metal/build/probe-hardware "$BRIDGE_LIBRARY" --allocation-only
```

Set `BRIDGE_HEADERS` and `BRIDGE_LIBRARY` to your external SDK header directory and runtime library. The default format is RGBA16Float; `--rgba8` selects RGBA8Unorm. `--allocation-only` uses shader-read-only usage and makes no draw attempt. `--onscreen` opens a temporary output window on the first SDK-listed calibrated display. Device choice must become explicit before multi-display use. Keep probes in bounded subprocesses (40 seconds was used), and do not run another native adapter session concurrently. The SDL event pump is dynamically resolved from the SDK's dependency; its availability is not assumed for other platforms/runtimes.

Headers, SDK libraries, compiled probes, raw device serials and local calibration files are not vendored. Next steps are GPU conversion of Godot's preview quilt to RGBA8, support for the device's 66-view preset (the addon currently caps views at 48), actual Godot-to-display validation, optical view-order checks and a verified animated consumer lifetime contract. No FPS or latency result is claimed.

## Direct compute output checkpoint

The real SDK accepted an IOSurface-backed RGBA8Unorm texture with shader-read and shader-write usage. A Metal compute shader wrote a constant color directly to that texture. After producer completion, a diagnostic-only CPU readback verified every one of its 1,081,344 byte components against RGBA (51, 102, 153, 255). Quilt submission, resource release and SDK shutdown returned true; the process exited zero. See [structured evidence](compute-write-rgba8.json).

This establishes that a separate float-to-RGBA8 conversion pass is not intrinsically required by this SDK/device combination: a future native quilt compositor can write RGBA8 directly. It does not establish that Godot can import this texture through its public RenderingDevice API, or that the existing RGBA16Float synthesizer can already target it. A native compute compositor or a supported texture import path still needs implementation and validation. The constant-color probe performs no HDR tonemapping, synthesis or color-space validation, and provides no speedup measurement. SDK offscreen output pixels were not read back; physical visibility was not checked in this run.

`--compute-write` requires `--rgba8`, is incompatible with `--allocation-only`, and requests shader-read/shader-write usage instead of render-target usage. The diagnostic CPU readback belongs only to this test; it is not a proposed production frame path.

## Frozen Godot scene submission

The optional native extension copied a frozen Godot 4.8 RGBA8 quilt into a real SDK IOSurface using a GPU blit, then showed it for 20 seconds with event processing and immutable resubmission. No CPU pixel readback occurs in this path. Both the two-anchor and 66-real-camera runs returned success and exited zero. The user confirmed that the first scene appeared but looked incorrect. The user reported that the all-real baseline looked correct. This is qualitative physical confirmation, not an optical view-order, color-accuracy or depth measurement. See [outcomes](godot-real-static.json) and the [diagnostic instructions](../../native/bridge_metal/README.md).

## Immutable clip playback

An eight-pose Godot clip was copied on GPU into eight distinct SDK RGBA8 textures and played for 20 seconds. The API path and teardown returned success. Hardware animation observation is pending. This diagnostic retains all frame textures unchanged until teardown; no output slot is reused. See [results](godot-real-sequence.json) and [instructions and memory bound](../../native/bridge_metal/README.md#bounded-immutable-animation-diagnostic). It does not establish safe continuous streaming or a measured render FPS.

## Direct imported target

On 2026-10-12, Godot compute wrote directly into an imported real Bridge RGBA8 IOSurface. The native path allocates no intermediate output quilt and performs no output blit. The 66-real-camera physical API test returned success and shut down cleanly; visual confirmation is pending. A separate fixture run verified exact RGBA8 pixels and nonempty content. This is a frozen-frame experiment, not continuous streaming or a measured speedup. See [evidence](godot-direct-target.json) and [setup](../../native/bridge_metal/README.md#direct-imported-sdk-target-frozen-frame-experiment).

## 24-anchor physical check

On 2026-10-12 the frozen 24-real-camera scene reconstructed into 66 views was submitted directly to the real Bridge RGBA8 allocation and shown for 20 seconds. API execution and teardown passed. The user reported that the image looked approximately normal. This is qualitative confirmation for the tested static scene; no balanced preset is enabled automatically. See [record](godot-24-anchor-display.json) and [sanitized log](godot-24-anchor-display.log). The same new budget argument passed a smaller synthesized fixture test with exact, nonempty RGBA8 output.

## Motion with an alpha-blended panel

The 24-anchor synthesized clip and 66-real-camera baseline were executed sequentially on 2026-10-12 with a moving/rotating box behind a cyan alpha-blended quad. Both eight-pose, twenty-second SDK sessions passed submission and teardown. Visual comparison is pending, and no transparency correctness is claimed. The requested five-pose-per-second cadence is a deliberate discrete clip rate, not a measured render FPS. The synthesis depth buffer does not represent separate transparent depth layers. See [24-anchor outcome](sequence24-transparency.json), [all-real outcome](sequence66-transparency.json), and [commands and limits](../../native/bridge_metal/README.md#motion-and-transparency-qualitative-comparison).
