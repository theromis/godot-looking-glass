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

The 24-anchor synthesized clip and 66-real-camera baseline were executed sequentially on 2026-10-12 with a moving/rotating box behind a cyan alpha-blended quad. Both eight-pose, twenty-second SDK sessions passed submission and teardown. In the repeated comparison, the user reported angular jumps in the 24-anchor clip while rotating the monitor, while the 66-real baseline transitioned smoothly. This is an angular continuity failure, not a measured temporal FPS result. No transparency correctness or isolated cause is claimed. The requested five-pose-per-second cadence is a deliberate discrete clip rate, not a measured render FPS. The synthesis depth buffer does not represent separate transparent depth layers. See [24-anchor outcome](sequence24-transparency.json), [all-real outcome](sequence66-transparency.json), and [commands and limits](../../native/bridge_metal/README.md#motion-and-transparency-qualitative-comparison).

## Opaque angular-continuity controls

On 2026-10-12 the same eight-pose clip was shown without the alpha panel, with 24, 36 and 48 real cameras reconstructed into 66 views. API submission and teardown passed in all three runs. The user confirmed that angular jumps persist at 24 cameras even without transparency, so alpha blending is not the sole cause. At 48 cameras the user reported smooth angular transitions. The 36-camera observation is pending; the minimum acceptable budget is not established. These are qualitative results for this low-resolution opaque scene, not transparency validation, continuous streaming or measured FPS.

See [24-camera control](sequence24-opaque-control.json), [36-camera control](sequence36-opaque-control.json) and [48-camera control](sequence48-opaque-control.json). The shader currently shares nearest-filtered sampling for color/depth: `synthesizer.gd` does not override sampler filters, and the inspected Godot `rendering_device_commons.h:527-528` defaults to nearest. Subpixel color filtering is a candidate investigation, not a verified explanation or adopted fix.

## Default-resolution physical comparison

On 2026-10-12 the same static opaque scene was tested at the connected device's 4092×4092 default quilt dimensions (372×682 per view). With 66 real cameras the user confirmed a noticeably sharper image. With 24 real cameras reconstructed into 66 views the user confirmed a clear image and smooth angular transitions when rotating the monitor. Both real-SDK direct-target sessions passed and shut down cleanly.

Earlier angular jumps at 24 cameras were observed at 704×684 (64×114 per view). The larger-resolution control shows that those failures do not establish that 24 anchors are inherently insufficient for this scene. Nearest color/depth filtering and AA settings were unchanged. Resolution was changed without adopting a new synthesis algorithm. This does not prove the exact aliasing mechanism or validate full-resolution motion, transparency, optical calibration accuracy or universal quality.

See [all-real reference](full-resolution-real66.json), [24-anchor assessment](full-resolution-synth24.json) and [commands](../../native/bridge_metal/README.md#default-resolution-physical-target-check). The finite animated clips remain small-resolution tests with a separate memory limit.

## Lit/shadowed depth control

On 2026-10-12 the 4092² all-real baseline was repeated with per-pixel material lighting, ambient fill, a warm directional light, shadow-enabled angular size 2° and a gray receiving floor. The user reported that shading improved the image, but foreground/background objects doubled. The same lit scene with the virtual camera cone reduced from 54° to 30° was reported to have noticeably less doubling. Both SDK sessions passed and closed cleanly; the lit fixture also passed exact, nonempty RGBA8 comparison.

This points to virtual parallax/depth as a useful control for this scene, not a proven optical/calibration diagnosis. The actual Bridge device calibration cone remains 54°. No postprocess depth blur or tonemapping fix was added. Residual double images, apparent-depth preference, synthesis with shading and temporal output remain unassessed. See [lit baseline](full-resolution-lit66.json), [30° control](full-resolution-lit66-cone30.json) and [commands](../../native/bridge_metal/README.md#lit-full-resolution-baseline).

## Foreground convergence control

The user clarified that the lit 30° baseline looked good at the rear object/back of the middle object but blurred the foreground/front of the middle object. The 4092², 66-real lit scene was repeated with convergence distance 5.2 instead of 6.0. Camera world positions and eye spacing stayed fixed using `camera_span_reference_distance=6.0`; device calibration, lighting and virtual cone were unchanged. The user reported sharper foreground and worse rear geometry.

This confirms that the perceived clarity distribution changes with convergence in this diagnostic. It does not establish a calibration diagnosis, a universally acceptable focus, or uniformly sharp depth. No depth-of-field blur or synthesis is involved. A midpoint convergence and/or reduced parallax are next candidate controls, not verified fixes. See [actual settings and observation](lit66-focus52.json).

## Midpoint convergence and 20-degree parallax control

The lit 4092² all-real scene was shown at convergence 5.6 and virtual cone 30°, then at the same convergence with cone 20°. Both SDK runs passed and shut down cleanly. The user withdrew the initial negative report and explicitly clarified that the latest 20° test reduced double images, with slight residual doubling. The 30° midpoint test therefore has no confirmed replacement visual assessment.

At 20°, the camera span reference remains 6.0, convergence is 5.6, lighting and resolution are unchanged and device calibration is not edited. This is a qualitative improvement, not elimination of ghosting, instrumented optical validation or an accepted universal preset. See [30° test](lit66-focus56.json) and [confirmed 20° observation](lit66-focus56-cone20.json).

## Convergence-grid and depth-direction validation

On 2026-10-12 the 4092², 66-real diagnostic displayed a grid on the convergence plane and red/blue markers on opposite sides of it. The user confirmed a stable sharp grid and correct marker depth. API geometry checks also passed, including the fixed-baseline 66-view case. This helps exclude gross focus-registration and simple reversed-depth errors, but does not validate exact calibration or eliminate residual ghosting. See [physical record](projection-grid.json) and [official-source audit](../../docs/projection-and-quilt-audit.md).

## Angular-spacing and device-aspect candidates

Two separate lit all-real controls ran at 4092², reference cone 20° and convergence 5.6. With official-style angular spacing, the user reported a good cube but slight doubling elsewhere. With original linear spacing and a 9:16 source projection (378×672 rendered into 372×682 tiles), the user reported it seemed better. No complete removal of double images or precise relative gain was confirmed. The aspect control also changes source pixel dimensions/resampling, so it does not isolate aspect alone. Both SDK sessions passed. Geometry tests and a combined-option synthesized fixture test passed. No default has been changed and no performance claim is made.

See [angular observation](angular-sampling-lit66.json), [aspect observation](display-aspect-lit66.json), and [options/method](../../native/bridge_metal/README.md#official-style-camera-controls).

## User-requested 54-degree cone with corrected source aspect

The lit 4092², 66-real, display-aspect scene was repeated at convergence 5.6 and cone parameter 54° on 2026-10-12. Original linear eye spacing and span reference 6.0 were retained. The user reported noticeably stronger double images than the previous 20° setting. Thus 54° is not preferred for this scene; it is not an accepted optical-quality preset. Device calibration was unchanged. The parameter sets the baseline relative to distance 6.0, not the exact subtended angle at convergence 5.6. See [settings and observation](lit66-focus56-cone54-aspect.json).

## Dark-ghost controls and 48-view quilt

Combined angular sampling + display aspect produced almost no reported change, with a dark ghost near the rear sphere. Disabling only shadow maps left the artifact almost unchanged. Switching to a user-requested 48-total-view, 8×6 quilt (4096×4092, all views real) also left it almost unchanged. Source resolution was retained, while output tile width/resampling changed with grid. None of these observations identifies a definitive cause or establishes a numerical crosstalk measurement.

An opt-in no-presentation flat capture found no obvious duplicated geometry in center view 32; some sphere silhouettes are clipped at the view bounds. Only one view was visually inspected. A smaller fixture regression passed source-dimension and exact-pixel checks with the new CLI options. See [combined observation](combined-angular-aspect-lit66.json), [shadow control](combined-lit66-no-shadows.json), [48-view comparison](quilt48-lit.json), [flat-capture hash/limits](flat-lit-views.json), and [reproduction](../../native/bridge_metal/README.md#combined-controls-shadows-and-output-view-count).

## Fully in-frame compact objects

The 48-real 8×6 lit scene was repeated with smaller X/Y subject scales and narrower X spacing, leaving their Z centers/extents and camera settings unchanged. Every subject AABB was verified inside every source camera with minimum 14.5038 pixels of margin. The user reported better overall appearance but residual double images, most visible on the rear sphere; smaller object size may reduce salience elsewhere. Thus source-view clipping is not sufficient to explain the artifact. Shape normals/layout also changed, so the improvement is not assigned uniquely to clipping removal. The small fixture passed exact-pixel and bounds checks. See [configuration and observation](quilt48-compact-lit.json).

## Compressed subject depth

The compact 48-real lit 8×6 scene was repeated with subject Z centers/extents compressed to 35% around convergence at world Z=0.4. Camera settings, source aspect and output resolution were retained. Subjects passed every-camera AABB checks with 56.076 pixels of minimum margin; SDK submission/teardown passed. A smaller four-view fixture passed bounds/source-size and exact nonempty RGBA8 checks. On repeat, the user reported reduced double images but insufficient apparent volume. The floor remains unchanged, and subject shape normals/shadows change with compression. This is not an isolated optical-crosstalk measurement or a default preset. See [result](quilt48-depth035-lit.json).

## Depth/cone tradeoff at 35-percent geometry depth

The 48-real compact lit setup was repeated unchanged at depth factor 0.35 and reference cone 20°; the user reported less doubling but excessive flatness. At the user's requested 30° cone, with depth factor still 0.35, the user reported better volume but stronger doubling. Both API sessions passed; objects remain fully in frame (30° minimum margin 49.845 pixels). No setting satisfying both volume and ghosting requirements has been established. See [repeat](quilt48-depth035-repeat.json) and [30° control](quilt48-depth035-cone30.json).

## Accepted scene-specific 40-degree depth-compressed setup

The user-requested 40° reference-cone test retained depth factor 0.35, focus 5.6, compact subjects, display-aspect source views, angular spacing, lighting and shadow maps. The 48-real 8×6 session passed, with all subject bounds inside every camera and minimum margin 43.3149 source pixels. The user reported better volume and acceptable doubling. This is the first explicit acceptance of this particular compressed-depth compromise, not complete ghosting elimination or a universally valid calibration/preset.

The reproducible configuration is saved in [accepted scene profile](accepted-lit48-profile.json); it does not automatically alter addon defaults. [Executed result](quilt48-depth035-cone40.json) retains the actual observation. Movement, transparency, arbitrary scenes and performance are still unvalidated for this profile.

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal --script tests/test_bridge_direct_target.gd -- --large --views=48 --real-views=48 --lit --view-cone=40 --focus=5.6 --display-aspect --angular-sampling --compact-objects --depth-scale=0.35
```

## 54-degree control at 35-percent geometry depth

The same compact lit 48-real-view setup was shown at reference cone 54 degrees, with focus 5.6 and depth factor 0.35 unchanged. The successful repeat completed presentation and teardown; minimum source-camera subject margin was 29.966 pixels. The user reported very strong double images on the rear red sphere, slight spreading elsewhere, and an overall tolerable image. At 40 degrees, the user clarified that the rear red sphere doubles most strongly while other objects look normal. The 40-degree profile remains the preferred recorded compromise. These qualitative observations do not isolate depth, color/contrast, or optical crosstalk as the cause. See [54-degree result](quilt48-depth035-cone54.json).

## Rear/front color-swap control

The diagnostic accepts `--swap-depth-colors` to exchange only the rear/front sphere albedo colors (rear blue, front red; green unchanged). The 54-degree, focus-5.6, depth-0.35 configuration is retained for direct comparison with the preceding 54-degree run. Positions, geometry, lights, source dimensions and quilt remain unchanged. This tests whether the most noticeable double image follows the position or the material color; luminance/contrast also change, so it cannot independently diagnose a hardware color-channel defect. The [execution record](quilt48-depth035-cone54-swapped.json) keeps the user assessment pending until supplied.

Execution limitation: both color-swap attempts timed out at 110 seconds. The retained retry produced no startup/PASS output, so neither presentation nor clean SDK teardown is verified. No optical conclusion is recorded. The wrapper killed the timed-out child process; the control remains pending.

The stall was localized to the conditional assignment of untyped array literals to `Array[Color]` in the test script. A minimal headless reproduction stops at that assignment without Metal or SDK access. Godot release-template VM typed-array assignment checks element types and aborts on mismatch; diagnostic error text is guarded by DEBUG_ENABLED (engine `modules/gdscript/gdscript_vm.cpp:1476-1504`). The deferred test function aborts while the SceneTree event loop stays alive. The fix selects an index in the existing color array instead. A local fixture completed exact-pixel verification and clean teardown after the fix. Opt-in `--diagnostic-stages` now emits progress to stderr to distinguish script progress from an idle process. Earlier absence of buffered stdout was insufficient evidence of a startup failure.

After the successful color-swap presentation, the user reported that strong doubling remained at the rear blue sphere, while the front red sphere also showed more noticeable doubling. The user suggested that a dark ghost is less noticeable against blue. The artifact therefore did not follow red exclusively. Position/depth and material-dependent contrast remain candidate contributors to visibility; this does not prove a channel-specific hardware defect or isolate the physical cause. Rear/front subjects also differ in screen position, so this is not a pure depth-only comparison.

## Neutral-sphere, shadow-free control

The diagnostic accepts `--neutral-spheres` to give all three spheres the same albedo (0.5, 0.5, 0.5); it overrides the optional color swap. The requested control retains the 54-degree reference cone, focus 5.6, depth factor 0.35, geometry and camera settings, with per-pixel shading/lights active and `--no-shadows`. This changes color and shadow maps together; it is not an independent isolation of either variable. Lighting can still produce unequal displayed luminance. All 48 views are real. See [execution and pending physical assessment](quilt48-depth035-cone54-neutral.json).
