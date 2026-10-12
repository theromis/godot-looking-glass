# Implementation roadmap and status

## Phase 0 — provenance and licensing: complete

Public official ZIP downloaded; headers/SHA-256 recorded; all 5217 files matched. Unitypackage safely extracted separately. Inventory/line-level analysis complete. New addon excludes proprietary source, Unity Companion code and SDK binaries.

## Phase 1 — executable baseline: completed on Godot 4.5.1

Shared World3D, 1–48 off-axis cameras, configurable grid/resolution/cone/focus, GPU raster quilt, hardware-free preview, multiple depths/thin occluders/directional shadows/alpha panel. Tests verify focus, disparity signs, nonsquare vertical FOV, 1/2/12/47/48-view dimensions. Apple M4 Vulkan execution/PNG capture completed.

## Phase 2 — experimental synthesis: complete with limitations

POST_TRANSPARENT HDR/depth capture, two neighbors, bounded inverse warp, minimum-eye-depth visibility, GPU quilt/timestamps. Synthetic planar tests compare zero/positive/negative shifts analytically. Demo captured; complex occlusion/transparency artifacts remain. Disabled by default: experimental MVP, not finished disocclusion reconstruction.

## Phase 3 — Bridge control plane: complete

HTTP client, automatic `--bridge` detection, calibration unwrap/geometry, manual visual.json, ordinary-monitor filtering and session close. Fixture passed; live Bridge 2.6.3 reports 0 calibrated LKG devices. Installed native SDK not copied.

## Phase 4 — quality and native output: incomplete

1. Depth-aware fill with validity map, GPU coverage statistics and opaque all-real comparisons.
2. Separate opaque capture, production transparency preset and view-dependent shading diagnostics.
3. Objective-C++ Metal Bridge GDExtension: dynamic SDK loading, SDK-created IOSurface output, GPU copy, explicit queue synchronization, version checks and ownership teardown.
4. Connected Looking Glass: serial/device calibration matching, default quilts, orientation, lenticular quality, pacing/latency, reconnect and multi-display selection.

Native-output readiness: calibrated hardware displays a known view test without stale/tearing frames; copies/fences verified, disconnect/shutdown handled. Currently unverified.

## Phase 5 — adaptation and temporal reuse: incomplete

GPU disparity/edge/hole statistics, budgeted anchors with hysteresis, motion-vector rejection and history remapping. Requires motion capture and animated geometry/particles/cut tests. Fewer real views alone prove neither speed nor quality.

## Phase 6 — optional engine backend: positional-shadow experiment

4.8-dev has driver multiview but limits scene rendering to 2 views. Prototype grouped 2/4/8 module/union culling, then extend UBO/shaders/effects; compare identical addon baseline. Fork only with verified gains/accepted maintenance. Opt-in shared positional atlas added; `engine-patches/README.md` describes requirements. Union culling/native batches remain absent.

## Remaining limitations

Bridge reports no calibrated physical LKG; optical/native output untested. No Unity editor or matched Unity/Godot scene comparison. Minimal 4.8-dev built for Vulkan/MoltenVK, not native Metal. No Windows/Linux GPU or RenderDoc/Xcode capture. All-real no-RD Compatibility fallback passed. No adaptive scheduler, temporal history, depth-aware fill, export native backend or transparent overlay. Quilt timestamps available; summed viewport times are not total critical path.

## Completed addon optimizations

Cached uniforms/constants/camera offsets; source-RID invalidation; transforms updated only on rig motion. Gather exits at exact depth fixed points, retaining up to 8 steps otherwise. CPU/GPU A/B, byte-identical quilts and regressions in `benchmarks/optimization`, detailed in performance-optimization.md. No union culling/native multiview; shadow experiment separate in engine-patches.


## Verified engine experiment

4.8-dev built/executed. 48 real views/four SpotLights: shared atlas reduced wall 33.3%, viewport GPU sum 40.7%, exact PNGs, three pairs. Omni/Spot tests cover LOD/mask/chain/owner-free fallback; stock/patched regressions passed. Production needs allocation/coverage, changing masks/worlds, crowded lights, transparency, XR and other GPUs. Directional reuse/native multiview need separate architecture.

Additional 512-object separate/MultiMesh, pixel-cost and 12/24-anchor experiments completed. MultiMesh lowers CPU preparation without FPS gain; fewer views help with measured quality loss. Shared engine culling unimplemented; data do not identify it as the principal bottleneck. Next: 48-real GPU profiling and transfer-function alignment before adaptive quality work. See benchmarks/scene-preparation/README.md.

GPU diagnostic completed: timestamps strongly affect M4/MoltenVK and now default off. Viewport timing removal reduced wall 10.6%; uninstrumented shared shadows verified at 28.795 → 20.145 ms. No new engine patch needed. Detailed markers remain optional and do not identify an unprofiled shader bottleneck. Next: capture without mass queries.

Opt-in direct HDR RID implemented/measured, retaining linear depth. Static 1024²/24→48: interval −4.88%, 192 MiB payload removed, exact PNGs. 512²: no confirmed FPS gain, 48 MiB removed. Lifetime/resize/nonempty checks passed on 4.5.1/4.8. TAA/FSR2/MSAA/post effects need further tests/possible snapshots; default copy retained. No engine patch.


Borrowed depth MVP uses existing RD APIs, no engine patch. Next: MSAA resolve, TAA/FSR2, runtime scale/near/far changes, same-size buffer recreation. Direct sources remain opt-in; automated feature fallback not implemented at this stage.


Iteration experiment: 4 saves ~2.09% GPU quilt / 0.54% update interval in one scene; default 8. Next: curves, thin occlusions, motion/flicker, particles/transparency. All-real baseline PSNR 22.757 dB prioritizes visibility/disocclusions over switching all scenes to 2 steps.


Rescue MVP recovered 2.03% failed correspondences in one static test, GPU +3.34%, default off. Production needs curved/moving/transparency scenes, boundary quality, wider baselines, false-visibility/flicker checks. Additional sources, forward visibility or hierarchy are proposals without proven gains.


## Borrowed-buffer compatibility fallback

15 renderer configurations tested on Apple M4/Vulkan, 4.5.1/4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, additional compositor, reset. Final raw RGBAH matrix compares default copy, borrowed color, borrowed color+depth. Production policy yields exact results; all nine regressions passed on both versions.

Direct color without fallback differs with TAA or a later color-modifying POST_TRANSPARENT effect. Capture snapshots color/depth for TAA or any additional enabled compositor, then returns to direct access when removed. Raw fallback preserves reverse-Z in R32F and synthesis interpretation. RID changes refresh descriptors; only owned textures freed. Compositor WeakRef avoids cycles.

MSAA/FXAA/FSR1/FSR2/scaling/glow/tonemap retained tested equivalence, specifically to POST_TRANSPARENT snapshots. Final temporal/postprocessing output is not in quilts; jitter/dynamic quality untested. Manual draw/sync are correctness tools, not timing benchmarks. New policy speed unmeasured; reports expose effective borrowing, fallback reasons and actual-dimension payload.

Initial internal-48² FSR2 probe produced uavMip errors and was rejected; internal 128² repeat passed. Engine bug/minimum size unresolved. Native Metal, other GPUs, physical Looking Glass, motion/particles/transparency untested. Commands/JSON/log: benchmarks/buffer-compat/README.md.


Quilt instrumentation is opt-in with bounded arrays. 24→48/1024² A/B: 47.6166 ms on / 47.6215 off; no FPS gain, exact PNGs. Choose further optimizations from measured workloads; removing the last two markers yielded no meaningful speedup here. Resize/profiling tests await actual quilt updates rather than fixed process-call counts.


Inverse-depth experiment completed: GPU 11.346 → 11.316 ms, standard deviations 0.238/0.290; speedup unconfirmed. Baseline PSNR 88.875 dB; ordinary default retained. Further formula tuning lacks profiling justification. Larger candidates: real count/placement and pixel workload, requiring quality/performance tests before automation.


12/16/24/32 → 48 real-count curve establishes a speed/quality tradeoff; per-view SSE/MAE retained for placement. Runtime adaptation needs reference-free proxy validation, motion stability and hysteresis/rebuild strategy. `--real` already applies measured budgets; no automatic controller.


## Nonuniform anchors: measured negative result

Added optional strictly increasing `custom_anchor_indices` (demo `--anchors=`), with validation and effective anchor telemetry. An offline selection of 24 cameras from the previous 16-view RGB errors worsened whole-quilt PSNR from 25.768 to 24.088 dB and increased squared error 47.21%; observed quilt-update intervals 48.317±0.425 versus 48.204±0.090 ms do not establish acceleration. Uniform remains the default; no runtime adaptive controller is implemented. See [benchmark details](../benchmarks/anchor-placement/README.md).


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](../benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](../benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](../benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](../benchmarks/depth-overhead/README.md).


## Compact GPU depth feedback

GPU reduction of the optional depth diagnostic now returns 768 bytes instead of 786,432 bytes for 48 views at 256². On current Godot 4.8-dev / Apple M4, three repeated async experiments reduced CPU decoding from 20.499±1.021 to 0.306±0.009 ms per callback (about 67×). Isolated GPU scopes 1.371±0.021 versus 1.365±0.043 ms show no measurable extra GPU cost; quilt update intervals remain 48.27 ms and callback latency about 97 ms. GPU totals match CPU sums exactly, all output PNGs match byte-for-byte, and all 15 regression checks pass. This reduces diagnostic CPU work, with no established FPS gain. Uniform view selection and addon defaults remain unchanged. See [implementation, measurements and reproduction](../benchmarks/depth-reduction/README.md).


## Static quilt updates on demand

Optional `update_on_demand` renders source views and assembles the compute quilt only when `request_update()` is called. Rig motion requests updates automatically; the application explicitly reports object, light, material and environment changes. On current Godot 4.8-dev / Apple M4, three pairs of the static 24→48 scene with 1024² tiles reduced process/presentation interval from 47.408±0.296 to 16.535±0.121 ms. After warmup, the cached quilt matches the continuous reference bit-for-bit. Idle performs no repeated source captures or compute dispatches; the window keeps presenting the cached texture. This saves static-scene work rather than accelerating new animated views. The first large-scene frame differed in 76 RGBA components by at most 1/255, so the benchmark explicitly refreshes the quilt before measured idle. The startup difference has no established cause; no automatic warmup is implemented. Mode is off by default and does not modify the engine fork. See [API, limitations and measurements](../benchmarks/on-demand/README.md).


## Native Metal boundary prototype

A standalone Objective-C++ Metal boundary now dynamically loads Bridge, verifies SDK symbols/version and performs a one-shot GPU copy into an SDK-created texture before submission. Real Metal/IOSurface fixture tests and installed SDK 2.6.3 probing passed on Apple M4, including failure/retry and ownership checks. This is not a Godot GDExtension: the current 4.8 runtime is Vulkan-only, no real SDK draw/hardware output was executed, and consumer completion/streaming remain unverified. Blocking producer/copy waits are a correctness baseline; no speedup is claimed. See [component and next integration steps](../native/bridge_metal/README.md) and [executed scope](../benchmarks/native-bridge/README.md).


## Executed Godot native Metal diagnostic

A new 4.8-dev native Metal runtime and optional test-fixture-only GDExtension now execute Godot quilt → Metal blit → SDK-fixture IOSurface copying. Three final 64×64 repeats matched every half-float component after explicit 120-update warmup and a verified frozen interval. Vulkan handles are rejected before native access. The same-queue sentinel requires already committed producer work; no streaming or real SDK display output is validated. Full native Metal QA passed 13/16, failing on-demand, resize/capture equivalence and borrowed-buffer policy; a settled refresh did not guarantee equality. Vulkan 4.8 still passes all 16. All failures are retained, and general native Metal support remains experimental. See [Godot diagnostic contract](../native/bridge_metal/README.md) and [results](../benchmarks/native-bridge/README.md).


## Real Bridge offscreen route checked

Real SDK 2.6.3 initialization, zero-device query and shutdown passed. Metal offscreen creation with the first-device sentinel failed with handle zero. This tested route cannot yet provide hardware-free real SDK texture transfer. No detailed SDK error or consumer completion contract was obtained. Next production milestones require a calibrated device and verified consumer lifetime semantics; one-shot fixture copying remains the executed boundary. See [native diagnostic](../native/bridge_metal/README.md#real-sdk-offscreen-diagnostic).


## Native Metal correctness gate: optional hazard tracking

The latest native Metal 4.8-dev addon suite passes 16/16 with `GODOT_MTL_SYNC_MODE=none`; the static Godot-to-fixture copy also passes. Repeating default barriers still fails the three prior image-equivalence checks. Diagnostics isolate source/final-viewport mismatches and an opposite-camera image substitution; the exact driver cause remains open. The smaller standalone reproduction is intermittent. No production rendering code was changed and no performance gain is claimed. Default-barrier engine correctness, other GPUs/versions, real Bridge output and safe consumer-side texture reuse remain open. See [findings and launch instructions](../native/bridge_metal/README.md#native-metal-synchronization-diagnosis) and [unpublished engine issue draft](native-metal-issue-draft.md).


## Controlled Metal engine experiments

Seven selected-check variants tested stronger encoder ordering, CPU staging allocation, per-frame camera UBO allocation, explicit resource declarations, producer attachment reads, and a combined variant. None passed all three previously failing checks. The per-frame UBO variant matched 80/80 source/viewport/quilt comparisons and passed resize/capture plus buffer compatibility, but still failed on-demand after an explicit settled refresh. A separate 64-update uniform-buffer compute control passed on both Metal modes and Vulkan, so it does not reproduce the raster failure. Production engine/addon changes were restored; no upstream-ready fix or speedup is claimed. See [experiment matrix, patches and provenance](../benchmarks/metal-barriers/README.md).
