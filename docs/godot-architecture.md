# Godot 4 architecture

## Decision

Recommended hybrid: standalone public-API addon, optional small Bridge-native GDExtension, and a separate engine-module experiment for batched views. First measure all-real reference and compute-synthesis quality. The current MVP needs no engine changes.

Executed official 4.5.1 `f62fdbde15035c5576dad93e586201f4d41ef0cb`, Apple M4, Forward+, Vulkan 1.2.283/MoltenVK. User checkout `../godot`: 4.8.0-dev `232e6b14abf6e590b41d60f11704e42de22bff72`, inspected and modified through an opt-in positional-shadow patch. Runtime built/executed; separate results in engine-patches/README.md and benchmarks/engine-shadows. Running 4.5.1 is not testing 4.8-dev. Original multiview references target that base; patch provided separately.

## Options compared

| Option | Available capabilities | Limitations/cost | Assessment |
|---|---|---|---|
| A. GDExtension/SubViewport/RD | Real off-axis cameras, viewport textures, CompositorEffect color/depth, GPU quilt; native Bridge | Repeated viewport culling/lighting/shadows; no public arbitrary camera batch | Best portable baseline; MVP uses GDScript, no GDExtension needed yet |
| B. Custom renderer module | Union culling, shared shadows, source arrays, close profiling | ABI/engine maintenance, cascade/view-dependent risks | Next after proving the bottleneck |
| C. Multiview fork | Batch masks and raster gl_ViewIndex | Two-view scene renderer, shader/UBO/SSR/SSIL/GI/sky assumptions; caps | Research backend, not production default |
| D. Hybrid | Working addon plus optional native output/grouped renderer | More test combinations | Recommended; independent-viewport fallback |

## Actual Godot capabilities

[Compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html) callbacks run on the render thread. [RenderSceneBuffersRD](https://docs.godotengine.org/en/stable/classes/class_renderscenebuffersrd.html) exposes color/depth layers. [Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) provides asymmetric frusta. RenderingServer and RenderingDevice texture RIDs are separate namespaces and cannot be arbitrarily mixed. Compute uses main RD/Texture2DRD; local RD is limited to isolated submit/sync GPU tests.

Checkout bindings: [render_scene_buffers_rd.cpp:65](<../../godot/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp:65>); `Camera3D::_get_camera_projection` / `Projection::set_frustum`: [camera_3d.cpp:285](<../../godot/scene/3d/camera_3d.cpp:285>), [projection.cpp:508](<../../godot/core/math/projection.cpp:508>). KEEP_HEIGHT near-plane size is `2*near*tan(vertical_fov/2)`; projection multiplies by aspect. Focus plane at F stays registered for eye e with offset `-e*near/F`. Verified on nonsquare 160×200 tiles.

## MVP path

`rig.gd` creates shared-World3D SubViewports, uniformly spaced anchors including cone endpoints, parallel off-axis cameras. All-real tiles are TextureRects in a quilt SubViewport, GPU-only without per-frame `Image.get_image`. View 0 is bottom-left; rows run bottom-to-top; unused final-row tiles black. Set exports before `_ready`; recreate for count/size/mode changes. Camera offsets cached; transforms updated only when rig transform changes.

`capture.gd` copies POST_TRANSPARENT HDR color/reverse-Z depth into owned RGBA16F/R32F textures. Two GPU copies/compute writes per anchor preserve lifetime for consumption after all sources. Capture frame numbers must agree before composition. Viewports update continuously; coherence applies to independent always-update views. Dynamic dependencies/recreation need separate tests.

`synthesizer.gd` queues render-thread work after frame_post_draw. `synthesize.glsl` dispatches per tile, copying real views or bounded inverse-warping two neighboring anchors (up to 8 iterations/source, exact unchanged-depth early exit). Chooses smaller linear eye depth; otherwise unwarped fallback or debug_holes magenta. Bounds/residual <1 pixel checked. Uniform sets/push constants cached; source-RID changes rebuild sets, debug flag updated separately. RGBA16F quilt exposed through Texture2DRD. Live loop has no CPU readback; explicit captures/GPU tests do. Unused raster quilt disabled in synthesis mode.

Basic depth reprojection, not complete hidden-surface reconstruction. Inverse warp can select wrong surfaces or oscillate at discontinuities. No depth-aware fill, temporal history, adaptive sampling or per-view transparency pass is implemented here. Preview gamma 1/2.2 differs from Godot filmic tone mapping; all-real color comparisons include that difference. Display-encoded output needs format/transfer agreement before native Bridge submission.

## Target synthesis backend

Capture opaque color, linear depth, projection/inverse projection, source eyes and optional motion vectors. Select anchors using worst disparity `|Δeye|*|1/z-1/F|/horizontal_slope`, depth edges, thin geometry and holes. Start uniform, refine difficult intervals within budget, retain endpoints and use hysteresis. GPU reduction returns small delayed statistics rather than images; fixed N also avoids feedback.

Proposed multi-source resolve: forward splat 2–4 neighbors into target visibility depth + owner id, separate deterministic nearest-depth resolve/color gather. No concurrent float-color writes without ownership. Convert reverse-Z through inverse projection; support jitter/oblique projections. Confidence-blend consistent depths, choose nearest-visible source at edges. Output validity/confidence and hole ratio.

Bounded hole-fill pass uses nearby valid samples with similar depth, preferably background-side, without crossing foreground edges. Mark large invisible regions invalid and add real anchors; depth cannot reliably reconstruct hidden geometry. Temporal history requires motion vectors, cut/motion/depth/view-remap rejection, per-group history and calibration/scene invalidation.

Transparency choices: all-real; opaque synthesis plus per-target transparent rendering against reconstructed depth; or layered depth/weighted OIT with explicit accuracy loss. Particles/reflections may be view-dependent; reprojection cannot recompute BRDF/sorting. Shadows require union coverage; cascades/contact shadows need separate benchmarks.

## Native Bridge and calibration

`bridge_client.gd` implements HTTP PUT orchestration, calibrated-device filtering, calibration unwrap, camera geometry, graceful missing-service handling and session closure. `--bridge` detects automatically; `--calibration=calibration/visual.json` is manual fallback. Optical pitch/slope/center await native output. Device defaults do not automatically alter count/grid, preserving benchmark configuration; production presets must integrate them.

Installed Bridge 2.6.3: `Looking Glass Bridge 2.6.3.app/Contents/MacOS/libbridge_inproc.dylib` in the installed Bridge application bundle and headers. Live HTTP session/list succeeded; returned an ordinary third-party monitor without calibration. Filtered result: 0 calibrated LKG devices. Hardware rendering unverified.

Public header exposes Metal window/IOSurface texture/draw APIs at [bridge.h:372](<../../looking-glass-reference/bridge-sdk-samples/BridgeRuntime/bridge.h:372>) (372–380), plus OpenGL quilts. Native Metal is promising versus MoltenVK→OpenGL. Godot binds `get_driver_resource` at [rendering_device.cpp:9484](<../../godot/servers/rendering/rendering_device.cpp:9484>); Metal device/texture return native pointers at [rendering_device_driver_metal.cpp:2545](<../../godot/drivers/metal/rendering_device_driver_metal.cpp:2545>). A small Objective-C++ extension is plausible, but handles alone do not settle usage, IOSurface export, retention, completion, formats or ownership. First copy into SDK-created IOSurface textures, then investigate sharing. Never pass VkImage where MTLTexture/GLuint is expected. Validate Windows DX sharing separately; inspected Bridge header has no Vulkan external-memory API.

Native texture submission is unimplemented: no hardware to validate interlacing, view order, synchronization or optics. Header/API are available; blockers are backend implementation and hardware testing, not SDK download. HTTP control is not live GPU texture transport.

## Multiview in the supplied engine

`MAX_RENDER_VIEWS=2`: [renderer_scene_render.h:50](<../../godot/servers/rendering/renderer_scene_render.h:50>). Fixed arrays: [render_scene_data_rd.h:58](<../../godot/servers/rendering/renderer_rd/storage_rd/render_scene_data_rd.h:58>), UBO arrays :129. Vulkan already queries `maxMultiviewViewCount` and uses masks; render-pass `(1 << p_view_count)-1` at [rendering_device_driver_vulkan.cpp:5461](<../../godot/drivers/vulkan/rendering_device_driver_vulkan.cpp:5461>). Count 32 needs shift correction; 48 cannot fit one 32-bit mask. Choose 2/4/8 batches from caps/profiling rather than assume one 48-view pass.

Needs dynamic/group matrix buffers, shader indexing, view-count interface, union/group culling, light clusters, sky/GI/SSR/SSIL/motion arrays, transparent sorting and renderer tests. Raising MAX_RENDER_VIEWS to 48 is unsafe; driver support is not arbitrary scene multiview support.

[Khronos VkRenderPassMultiviewCreateInfo specification](https://docs.vulkan.org/refpages/latest/refpages/source/VkRenderPassMultiviewCreateInfo.html) defines 32-bit masks, layered attachment draw broadcast and maxMultiviewViewCount highest-bit limits. Thus 48 views need multiple groups; multiview alone promises no raster-work reduction.


## Executed opt-in engine experiment

Shared positional shadow atlas API added/executed on 4.8-dev Vulkan/MoltenVK. Reuses Omni/Spot shadows, not batched geometry. Rig uses `has_method`/`call` for stock compatibility. Requires shared scenario, all-layer cameras, full caster culling, zero mesh LOD, equal atlas size/precision; render thread checks source lifetime. Directional shadows independent. Sources/build: `engine-patches/README.md`; measurements: `docs/performance-optimization.md`. Gain verified only for a specific 48-view shadow workload.

### Experimental direct HDR color input

Rig borrow_source_color (default false) reaches Capture before render-thread initialization. Copy owns two textures; borrowed mode retains RenderSceneBuffersRD and color RID, owning only depth/depth-only compute. Same synthesis interface, cached sets refreshed on RID change. Idempotent release never frees borrowed color; resize executed.

Capture frame id is shared RD slot + 1 rather than independent callback count. Earlier counter mismatch was not established; baseline/borrow both changed. Effects modifying color after POST_TRANSPARENT require snapshot or a later consume point; reuse stays opt-in. Ownership/frame id alone cannot guarantee arbitrary-effect equivalence.


## Experimental borrowed depth

`rig.borrow_source_depth` selects `synthesize_raw_depth.glsl` and near/far constants before Capture initialization. Capture retains buffer_owner, refreshes both POST_TRANSPARENT RIDs, owns no color/depth textures and submits no capture compute. Default shaders retained. Resize refresh rebuilds cached sets; idempotent release preserves borrowed RIDs. Exact copy/borrow-color/borrow-both quilts tested at 64/48/80 sources. Specific Forward+ Vulkan validation, not arbitrary-feature lifetime/snapshot guarantee.


Compute local size: `synthesis_workgroup` (0=8×8, 1=16×8, 2=16×16). Initialization selects a pre-imported variant; dispatch uses the same Vector2i and retains bounds checks. Canonical 8×8 shaders feed `shaders/generate_workgroups.py`; variants differ only in layout. All 9 capture/group combinations compared at 65×67; M4 measurements retain default 8×8.


`reprojection_iterations` (2/4/8, default 8) chooses a compiled variant without changing dispatch geometry/constants. Only gather limit changes; exact exit, validity and fallback remain. Quality/performance control, not equivalence to 8. Planar tests cover 2/4/8; benchmark also compares all-real 48.


## Bounded depth-hypothesis rescue

Opt-in `disocclusion_rescue` selects separate shaders; baseline unchanged. After two failed gathers, six horizontal offsets per source generate hypotheses; actual landing depth and forward residual <0.5 pixel validate them. Nearest valid surface selected without neighboring output reads/scatter writes. Hidden geometry remains unavailable. Before/after debug masks and fresh all-real comparison show slightly higher PSNR here, GPU +3.34%; default off.


## Borrowed-buffer compatibility fallback

15 renderer configurations tested on Apple M4/Vulkan, 4.5.1/4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, additional compositor, reset. Final raw RGBAH matrix compares default copy, borrowed color, borrowed color+depth. Production policy yields exact results; all nine regressions passed on both versions.

Direct color without fallback differs with TAA or a later color-modifying POST_TRANSPARENT effect. Capture snapshots color/depth for TAA or any additional enabled compositor, then returns to direct access when removed. Raw fallback preserves reverse-Z in R32F and synthesis interpretation. RID changes refresh descriptors; only owned textures freed. Compositor WeakRef avoids cycles.

MSAA/FXAA/FSR1/FSR2/scaling/glow/tonemap retained tested equivalence, specifically to POST_TRANSPARENT snapshots. Final temporal/postprocessing output is not in quilts; jitter/dynamic quality untested. Manual draw/sync are correctness tools, not timing benchmarks. New policy speed unmeasured; reports expose effective borrowing, fallback reasons and actual-dimension payload.

Initial internal-48² FSR2 probe produced uavMip errors and was rejected; internal 128² repeat passed. Engine bug/minimum size unresolved. Native Metal, other GPUs, physical Looking Glass, motion/particles/transparency untested. Commands/JSON/log: benchmarks/buffer-compat/README.md.


Default `profile_synthesis=false`: no LG timestamps, result scans or sample callbacks. Demo benchmark/--profile-quilt/--profile-passes enable it; --no-quilt-timing disables it. `profiling_sample_limit` (480, 1..4096) bounds ring arrays. Timestamp delivery needs ordinary RD frame progression; moving-object tests await actual updates and compare on/off. Unmeasured durations are null, not zero.


`inverse_depth_reprojection` requests raw capture and synthesize_raw_depth_inverse[_rescue]. Clip.zw hold 1/far and 1/near−1/far; greater inverse depth is nearer. TAA/compositor snapshots preserve interpretation. FP differences measured; exact equality not guaranteed. M4 speedup unconfirmed; default false.


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](../benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](../benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](../benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](../benchmarks/depth-overhead/README.md).


## Static quilt updates on demand

Optional `update_on_demand` renders source views and assembles the compute quilt only when `request_update()` is called. Rig motion requests updates automatically; the application explicitly reports object, light, material and environment changes. On current Godot 4.8-dev / Apple M4, three pairs of the static 24→48 scene with 1024² tiles reduced process/presentation interval from 47.408±0.296 to 16.535±0.121 ms. After warmup, the cached quilt matches the continuous reference bit-for-bit. Idle performs no repeated source captures or compute dispatches; the window keeps presenting the cached texture. This saves static-scene work rather than accelerating new animated views. The first large-scene frame differed in 76 RGBA components by at most 1/255, so the benchmark explicitly refreshes the quilt before measured idle. The startup difference has no established cause; no automatic warmup is implemented. Mode is off by default and does not modify the engine fork. See [API, limitations and measurements](../benchmarks/on-demand/README.md).


## Native Metal boundary prototype

A standalone Objective-C++ Metal boundary now dynamically loads Bridge, verifies SDK symbols/version and performs a one-shot GPU copy into an SDK-created texture before submission. Real Metal/IOSurface fixture tests and installed SDK 2.6.3 probing passed on Apple M4, including failure/retry and ownership checks. This is not a Godot GDExtension: the current 4.8 runtime is Vulkan-only, no real SDK draw/hardware output was executed, and consumer completion/streaming remain unverified. Blocking producer/copy waits are a correctness baseline; no speedup is claimed. See [component and next integration steps](../native/bridge_metal/README.md) and [executed scope](../benchmarks/native-bridge/README.md).


## Executed Godot native Metal diagnostic

A new 4.8-dev native Metal runtime and optional test-fixture-only GDExtension now execute Godot quilt → Metal blit → SDK-fixture IOSurface copying. Three final 64×64 repeats matched every half-float component after explicit 120-update warmup and a verified frozen interval. Vulkan handles are rejected before native access. The same-queue sentinel requires already committed producer work; no streaming or real SDK display output is validated. Full native Metal QA passed 13/16, failing on-demand, resize/capture equivalence and borrowed-buffer policy; a settled refresh did not guarantee equality. Vulkan 4.8 still passes all 16. All failures are retained, and general native Metal support remains experimental. See [Godot diagnostic contract](../native/bridge_metal/README.md) and [results](../benchmarks/native-bridge/README.md).


## Native Metal correctness gate: optional hazard tracking

The latest native Metal 4.8-dev addon suite passes 16/16 with `GODOT_MTL_SYNC_MODE=none`; the static Godot-to-fixture copy also passes. Repeating default barriers still fails the three prior image-equivalence checks. Diagnostics isolate source/final-viewport mismatches and an opposite-camera image substitution; the exact driver cause remains open. The smaller standalone reproduction is intermittent. No production rendering code was changed and no performance gain is claimed. Default-barrier engine correctness, other GPUs/versions, real Bridge output and safe consumer-side texture reuse remain open. See [findings and launch instructions](../native/bridge_metal/README.md#native-metal-synchronization-diagnosis) and [unpublished engine issue draft](native-metal-issue-draft.md).


## Connected hardware checkpoint

A connected 1440×2560 / 60 Hz Looking Glass is now detected by native Bridge 2.6.3 and the corrected HTTP client. The SDK preset is 4092², 11×6 / 66 views, aspect 0.5625, cone 54°. Serialized calibration required a second recursive unwrap after JSON parsing; fixture and real detection pass. Real SDK RGBA8 allocation/draw succeeds, and the user confirmed a solid blue image after explicit window visibility plus an event-loop/repeated immutable-submission test. Both tested RGBA16Float allocation descriptors fail. SDK initialization logs an OpenGL error even in the visually successful test. Godot scene conversion/delivery, the current 48-view cap, optical validation and animated consumer lifetime remain open. See [hardware evidence](../benchmarks/hardware/README.md).
