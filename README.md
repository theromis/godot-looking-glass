# Looking Glass Godot Lab

## Project plan and status

Checked items are implemented or completed experiments, with their limits recorded below. Unchecked items are unfinished. “In progress” identifies existing prototypes and research; it does not imply that a production implementation is ready. Latest regression runs: **16/16 checks passed on Godot 4.8-dev Vulkan/MoltenVK and native Metal with `GODOT_MTL_SYNC_MODE=none`**. Native Metal with default barriers still fails three checks; see [synchronization findings](benchmarks/native-bridge/metal-sync-results.json).

### Completed

- [x] Inspect the official Unity 6.1 plugin, record download provenance, inventory sources and document licensing boundaries.
- [x] Build a standalone Godot addon and demo with shared World3D, configurable off-axis cameras and hardware-free quilt preview.
- [x] Compose quilts entirely on GPU and implement experimental two-source depth reprojection with configurable real-view budgets.
- [x] Implement Bridge HTTP device detection, calibration parsing and session management; validate serialized/wrapped calibration with a fixture and the connected display.
- [x] Write frozen Godot RGBA8 quilts directly into imported SDK IOSurfaces without an output blit; exact fixture and real-SDK API tests passed, physical visual confirmation pending.
- [x] Implement bounded GPU-only playback of eight prerecorded Godot poses using distinct immutable SDK textures; real SDK API checks passed, visual animation confirmation pending.
- [x] Detect a 1440×2560 Looking Glass and display a user-confirmed solid color through real Bridge RGBA8/Metal interop; record the 66-view preset and format limitations.
- [x] Add cached GPU bindings, borrowed color/depth with tested snapshot fallback, optional profiling and resource-lifetime checks.
- [x] Execute the shared positional-shadow-atlas engine experiment and document scene-specific gains and compatibility restrictions.
- [x] Reduce depth-diagnostic feedback on GPU and support explicit on-demand quilt updates for static scenes.
- [x] Isolate native Metal viewport/camera equivalence failures and validate all 16 checks with the engine’s optional hazard-tracking mode.
- [x] Record reproducible benchmarks, image-quality comparisons, negative results and regression tests; keep repository text in English and paths relative.

### In progress: prototypes and research

- [ ] **Native Bridge output:** an optional GDExtension copies a frozen Godot 4.8 Metal quilt into a real IOSurface SDK fixture; a separate real-SDK RGBA8 color probe displayed on hardware. A frozen 66-real-camera Godot RGBA8 scene reached the physical display and was reported correct; optical measurements and animated streaming remain unfinished. See [native boundary](native/bridge_metal/README.md).
- [ ] **Synthesis quality:** the inverse-warp MVP and bounded rescue exist; robust visibility, disocclusion handling and motion/transparency quality remain unfinished.
- [ ] **Adaptive view selection:** fixed budgets and offline placement are evaluated; depth-only selectors worsened quality, so a reliable runtime controller is still missing.
- [ ] **Shared-shadow production readiness:** the optional patch is tested; atlas overflow, coverage/subdivision changes, changing worlds/masks and broader upstream validation remain pending.

### Required next steps

- [ ] Connect Godot quilts to the validated RGBA8 SDK output path with direct RGBA8 composition, explicit ownership and queue synchronization.
- [ ] Validate a connected Looking Glass: calibration/device matching, view order, optical output, latency, disconnect/reconnect and shutdown.
- [ ] Test animated geometry, camera cuts, thin occluders, transparent objects and particles against all-real references.
- [ ] Resolve production color/tonemapping and temporal-jitter behavior; current compute preview is not final Godot postprocessed output.
- [ ] Resolve the native Metal default-barrier defect ([controlled experiments](benchmarks/metal-barriers/README.md) improve camera equivalence but still fail on-demand), validate other GPUs/platforms, and verify physical output before claiming general support.
- [ ] Package a reproducible addon release and test shader import, exported projects and a fresh clone; define quality/performance presets from measured results.

### Ideally add, if benchmarks justify the cost

- [ ] Multi-source visibility reconstruction and bounded depth-aware hole filling with confidence/validity maps.
- [ ] Temporal reprojection with motion vectors, rejection rules and history invalidation.
- [ ] Adaptive real-view budgets and placement with hysteresis, quality limits and bounded asynchronous feedback.
- [ ] Optional grouped engine rendering with texture arrays, union culling and Vulkan multiview where supported.
- [ ] Direct native texture sharing, multiple-display support and automated quality/performance regression coverage across GPUs.

Detailed implementation history and readiness criteria: [implementation roadmap](docs/implementation-roadmap.md). Architecture and tradeoffs: [Godot architecture](docs/godot-architecture.md). Measurements and limitations: [performance analysis](docs/performance-optimization.md).

Standalone research addon and demo for Godot 4: off-axis cameras, GPU quilt preview, experimental GPU depth synthesis, and Bridge detection. Unity/Looking Glass code and SDK binaries are not included in the project.

Executed on Godot 4.5.1, Apple M4, Vulkan Forward+ through MoltenVK. The project runs from the repository root (`.`); engine sources in the optional sibling checkout `../godot` (4.8-dev) were inspected, and an optional experimental shared positional shadow patch was added (see `engine-patches/README.md`). The connected 1440×2560 display is detected, and real Bridge RGBA8 solid-color output is user-confirmed. Frozen Godot scene submission succeeded through real Bridge; the 66-real-camera baseline was reported correct. Optical measurements and streaming remain unfinished. See [hardware results](benchmarks/hardware/README.md).

## Development disclosure

Codex/LLM tools are used to generate and edit code, tests and documentation in this project. Reported measurements come from executed experiments, with raw results and limitations recorded. This is an independent experimental project; a standalone SDK color test is visually confirmed, while Godot scene output and optical quality remain unvalidated. Proprietary Unity implementations and Bridge runtime binaries are not included.

## Running

Run the commands below from the repository root. Command arguments, inventory paths and archived artifact paths are relative to that root; Markdown links are relative to their document. External engine/reference checkouts are optional sibling directories (`../godot`, `../looking-glass-reference`, `../Looking.Glass.Plugin.4.0.1-alpha-6.1`). Historical system-library paths in diagnostic logs are normalized relative to the original repository root; they are provenance, not runtime configuration. Benchmark measurements and artifact hashes are unchanged. Set the Godot executable and Python environment to your local installation; no user-specific installation path is required.

Open `project.godot` in Godot 4.5+ and press F6/F5. The default is 12 real views and a quilt preview; no hardware is required. Import shaders before the first command-line run.

```sh
GODOT_LG_BIN=godot  # Godot on PATH, or a relative path to your chosen binary
"$GODOT_LG_BIN" --headless --path . --editor --import --quit
"$GODOT_LG_BIN" --path . --rendering-driver vulkan
# 12 output views, 4 real: experimental compute
"$GODOT_LG_BIN" --path . --rendering-driver vulkan -- --views=12 --real=4 --tile=128
# Bridge device detection, without native optical output
"$GODOT_LG_BIN" --path . --rendering-driver vulkan -- --bridge
```

Arguments after `--`: `--borrow-color` (experimental direct HDR color access), `--rendered-benchmark` (samples quilt updates; use --static for comparable captures), `--objects=N` (0–4096 additional identical objects), `--batch-objects` (combine them into a MultiMesh), `--no-viewport-timing` (benchmark without viewport timestamps), `--profile-passes` (detailed intervals; requires engine flag `--gpu-profile` before `--`), `--views=N` (1–48), `--real=N` (enables synthesis; endpoints are always real), `--tile=N` (square tile), `--static`, `--opaque`, `--positional-lights=N`, `--no-positional-shadows`, `--fixed-motion`, `--no-mesh-lod`, `--shared-shadows`, `--bridge`, `--calibration=calibration/visual.json`, `--benchmark=res://benchmarks/run.json`, `--capture=res://benchmarks/run.png`. Without `--tile`, tiles are 192×256. CLI applies views before real; use this argument order. Before running arbitrary scenes, configure cone/FOV/focus/near/far/grid/resolution exports in `rig.gd`. Recreate the rig to change configuration at runtime.

## Addon integration

Copy only `addons/looking_glass` into your Godot 4.5+ project. Enabling the editor plugin in Project Settings → Plugins adds LookingGlassRig. Alternatively, create a rig from a script, set its parameters before add_child, and point its local -Z axis toward the scene. The focal plane is `focus_distance` ahead of the rig. Assign `rig.quilt_texture` to a TextureRect. Rig translation and rotation are supported; scale and nonstandard projection modes are not separately supported. Keep WorldEnvironment and the scene in the shared World3D.

The all-real quilt uses GPU Canvas draws. Compute uses CompositorEffect and the main RenderingDevice. The Compatibility renderer falls back to all-real views. There are no continuous CPU readbacks; PNG saving and GPU unit tests perform one-time reads.

## Feature status

| Feature | Status |
|---|---|
| Off-axis 1–48 views, nonsquare projection | Implemented; test passed |
| GPU raster quilt, preview without LKG | Executed on Vulkan and Compatibility |
| GPU color/depth capture and two-source compute synthesis | Executed on Vulkan; experimental, with occlusion/alpha artifacts |
| GPU timestamps / wall frame benchmarks / PNG captures | Executed; raw results in benchmarks |
| Bridge orchestration, device detection, calibration geometry | Fixture and actual Bridge tested; 0 calibrated devices |
| Native Bridge GPU texture handoff / lenticular display output | Not implemented |
| Adaptive anchors / temporal motion vectors / depth-aware hole fill | Architecture and roadmap; not implemented |
| Shared positional shadows (optional engine patch) | Executed on 4.8-dev; Omni/Spot, safe fallback; requirements in engine-patches |
| Engine multiview backend | 4.8-dev sources inspected; not implemented |
| Native Metal | 4.8 addon checks 16/16 with `GODOT_MTL_SYNC_MODE=none`; default barriers fail 3/16. Static fixture copy passes; hardware output and general support remain unverified |

Use all-real rendering as the reference. Synthesis cannot recover hidden geometry; transparent surfaces are absent from opaque depth, so RGB/depth mismatch causes errors. Compute preview uses simple gamma rather than complete Godot tone mapping. The native backend must apply optical calibration separately.

## Tests and measurements

```sh
python3 tests/run_checks.py --godot "$GODOT_LG_BIN"
```

The suite checks the focal plane, FOV, near/far disparity, 1/2/12/47/48-view quilt dimensions, analytical GPU planar synthesis with both displacement signs, and a Bridge HTTP fixture on port 33335. The fixture stops automatically; the port must be available. GPU tests require the windowed Vulkan renderer. Logs contain PASS; the runner rejects errors even when Godot exits with code 0.

One opaque static scene: 48 output/48 real views took 35.817 ms/frame; 48 output/12 real took 16.420 ms/frame, with 0.631 ms GPU quilt compute. Tiles: 128×128; 90 warmup + 240 frame samples. This is one local test with quality loss, not a universal speedup. Synthesized-tile PSNR against all-real: 16.94 dB, including the transfer-function difference. See [method and limitations](docs/performance-optimization.md).

## Documents

- [unity-plugin-analysis.md](docs/unity-plugin-analysis.md): download provenance, inventory, licensing, source paths/classes/functions/lines, verified findings and hypotheses.
- [godot-architecture.md](docs/godot-architecture.md): options A–D, current pipeline, engine multiview limitations and native interop.
- [performance-optimization.md](docs/performance-optimization.md): measurements, tradeoffs and benchmark campaign plan.
- [implementation-roadmap.md](docs/implementation-roadmap.md): completed work, next steps and readiness criteria.

The official archive/reference is stored separately in `../looking-glass-reference`. Do not include it in an open-source addon release. New code is MIT-licensed; external reference implementations and installed runtime libraries retain their own licenses. Research is not permission to copy proprietary source.

After CPU optimization (3 before/after runs), compute submission takes 0.0225 rather than 0.327 ms; the reference quilt matches byte-for-byte. A significant whole-scene speedup is not established. Data: `benchmarks/optimization/summary.json`.

The synthesis+quilt GPU pass improved from 4.058 to 3.189 ms (−21.4%) with 512×512 tiles, 48 output/12 real views; three before/after runs, byte-identical PNGs. FPS improvement is unconfirmed because of unstable frame pacing. Summary: `benchmarks/optimization/summary-gpu.json`.


Optional engine backend executed on Godot 4.8-dev: shared Omni/Spot shadow atlas. With 48 real views and four SpotLights, frame time fell from 32.964 to 21.983 ms (−33.3%, three paired runs, Apple M4); reference PNG identical. No whole-scene speedup is confirmed at 12 views. Backend is disabled by default; requirements, build and fallback are documented in [engine-patches/README.md](engine-patches/README.md). Native multiview and shared directional shadows remain unimplemented.

Additional scene-preparation test: 512 identical objects, 48 real views, shared atlas. MultiMesh reduced summed viewport CPU time from 2.480 to 1.332 ms (−46.3%), but frame time remained around 22.5 ms; no FPS gain confirmed. Both PNGs match byte-for-byte. Method and raw data: [benchmarks/scene-preparation/README.md](benchmarks/scene-preparation/README.md).

Per-viewport timing is now disabled by default in the addon (`measure_render_time=false`) and enabled by the demo for benchmarks. The detailed GPU profiler is optional: [benchmarks/gpu-passes/README.md](benchmarks/gpu-passes/README.md). Timestamps substantially alter the Apple M4/MoltenVK workload; compare profiled results against a control mode.

On Apple M4/Vulkan, disabling viewport timestamps in the 48-real-view stress scene reduced wall frame time from 22.533 to 20.145 ms (−10.6%, three runs per mode); PNGs identical. Detailed engine GPU markers were expensive (~64 ms/frame), so they are diagnostic and require a control. Shared shadows without viewport timings were also tested: 28.795 → 20.145 ms in this stress scene.

The experimental `--borrow-color` path removes the intermediate HDR color copy while retaining an owned linear-depth texture. On Apple M4, 24 real → 48 output views, 1024² tiles, quilt update interval fell from 52.205 to 49.656 ms (−4.88%, three runs), with byte-identical PNGs and 192 MiB of texture payload removed. At 512², FPS gain is unconfirmed; 48 MiB removed. This is an addon change requiring no new engine patch. Default copy path retained; TAA/FSR2/MSAA/post effects with borrowed input were not yet tested at this stage. [Method and limitations](benchmarks/borrow-color/README.md).


Experimental `--borrow-depth` also enables direct HDR color and removes separate depth capture/linearization. `borrow_source_depth=false` by default. Raw reverse-Z is converted to linear depth inside gather; 24 sources at 1024² avoid 96 MiB of owned R32F allocation. This is calculated payload, not total VRAM. Resize/ownership/exact-quilt tests passed on Godot 4.5.1 and experimental 4.8. TAA/FSR2/MSAA/post effects were not yet tested at this stage; using engine-owned buffers after the callback required confirmation. Commands and results: [benchmarks/borrow-depth/README.md](benchmarks/borrow-depth/README.md).

Repeated 24-real → 48-output series, 1024²: direct depth reduced the observed update interval 50.90 → 48.69 ms (−4.35%, three pairs). Synthesis+quilt GPU time: 12.54 → 11.09 ms; identical PNGs. [Results and unstable first series](benchmarks/borrow-depth/README.md).

Compute workgroups 8×8 / 16×8 / 16×16 tested: GPU quilt 11.179 / 11.470 / 11.270 ms on M4, three repeats. Speedup unconfirmed; default 8×8 retained. Selectors `--workgroup=16x8` and `--workgroup=16x16` are available for other GPUs. [Data and limitations](benchmarks/workgroups/README.md).

Optional `--iterations=4` reduces synthesis+quilt GPU time 11.005 → 10.775 ms (−2.09%) in the M4 benchmark; update interval 48.029 → 47.770 ms (−0.54%). 0.01197% of synthesized pixels differ from 8 iterations; equivalence is not exact. Default 8 retained; `--iterations=2` experimental. [Speed and comparison against 48 real views](benchmarks/iterations/README.md).

Experimental `--rescue` recovers some invalid depth correspondences by testing ±1/±2/±4 source-texel hypotheses for the same target pixel. On M4, 2.03% of the invalid mask recovered, synthesized PSNR 22.757 → 22.843 dB; GPU quilt 10.997 → 11.364 ms. No speedup; default off. [Results and limitations](benchmarks/disocclusion/README.md).

Borrowed-buffer policy now automatically falls back to snapshot copies for TAA and additional enabled compositor effects. 15 configurations × 3 capture modes tested on 4.5.1 and 4.8; exact quilts with policy, including reset and render-scale transitions. MSAA/FXAA/FSR1/FSR2/glow/tonemap matched in the static matrix. Quilt remains pre-postprocessing HDR; dynamic/jitter quality unverified. [Matrix and limitations](benchmarks/buffer-compat/README.md).

Quilt profiling is disabled by default (`profile_synthesis=false`); benchmarks enable it explicitly. --no-quilt-timing disables benchmark measurement. GPU/CPU buffers default to 480 samples maximum. M4 on/off A/B: 47.6166 / 47.6215 ms; no FPS gain confirmed, PNG exact. [Measurements and tests](benchmarks/quilt-profiling/README.md).

Optional `--inverse-depth` uses affine reverse-Z inverse depth and requests raw capture. M4 A/B GPU quilt: 11.346 / 11.316 ms; speedup not established against run variation. 0.017% of synthesized pixels changed, PSNR against baseline 88.875 dB. Default ordinary math retained. [Experiment and quality](benchmarks/inverse-depth/README.md).

Real-view budget measured for 48 outputs / 1024²: 12/16/24/32 sources produced 33.310/37.999/47.782/58.813 ms and whole-quilt PSNR 18.521/21.782/25.768/27.778 dB. In this scene, `--real=16` reduces interval by 20.47% versus 24, with quality loss. Defaults unchanged; no adaptive controller implemented. [Speed/quality curve and rejected timing](benchmarks/view-budget/README.md).


## Nonuniform anchors: measured negative result

Added optional strictly increasing `custom_anchor_indices` (demo `--anchors=`), with validation and effective anchor telemetry. An offline selection of 24 cameras from the previous 16-view RGB errors worsened whole-quilt PSNR from 25.768 to 24.088 dB and increased squared error 47.21%; observed quilt-update intervals 48.317±0.425 versus 48.204±0.090 ms do not establish acceleration. Uniform remains the default; no runtime adaptive controller is implemented. See [benchmark details](benchmarks/anchor-placement/README.md).


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](benchmarks/depth-overhead/README.md).


## Compact GPU depth feedback

GPU reduction of the optional depth diagnostic now returns 768 bytes instead of 786,432 bytes for 48 views at 256². On current Godot 4.8-dev / Apple M4, three repeated async experiments reduced CPU decoding from 20.499±1.021 to 0.306±0.009 ms per callback (about 67×). Isolated GPU scopes 1.371±0.021 versus 1.365±0.043 ms show no measurable extra GPU cost; quilt update intervals remain 48.27 ms and callback latency about 97 ms. GPU totals match CPU sums exactly, all output PNGs match byte-for-byte, and all 15 regression checks pass. This reduces diagnostic CPU work, with no established FPS gain. Uniform view selection and addon defaults remain unchanged. See [implementation, measurements and reproduction](benchmarks/depth-reduction/README.md).


## Static quilt updates on demand

Optional `update_on_demand` renders source views and assembles the compute quilt only when `request_update()` is called. Rig motion requests updates automatically; the application explicitly reports object, light, material and environment changes. On current Godot 4.8-dev / Apple M4, three pairs of the static 24→48 scene with 1024² tiles reduced process/presentation interval from 47.408±0.296 to 16.535±0.121 ms. After warmup, the cached quilt matches the continuous reference bit-for-bit. Idle performs no repeated source captures or compute dispatches; the window keeps presenting the cached texture. This saves static-scene work rather than accelerating new animated views. The first large-scene frame differed in 76 RGBA components by at most 1/255, so the benchmark explicitly refreshes the quilt before measured idle. The startup difference has no established cause; no automatic warmup is implemented. Mode is off by default and does not modify the engine fork. See [API, limitations and measurements](benchmarks/on-demand/README.md).

### Direct RGBA8 compute quilts

Set `rig.synthesis = true` and `rig.quilt_rgba8 = true` before adding the rig to the scene. The selected synthesis shader writes normalized RGBA8 directly, without a separate conversion dispatch. The default remains RGBA16Float. This mode clamps the existing gamma-encoded shader result to [0, 1]; it adds neither a second gamma curve nor HDR tonemapping. Source color captures remain float textures. Shader compilation occurs once per rig initialization; exported projects using this mode must include the raw addon shader `.glsl` files for runtime compilation.

The configurable view ceiling is now 96. A 66-view, 11-column quilt with two real cameras and 16² tiles passed format, nonempty output, on-demand freezing and clamped-float comparison checks on Godot 4.8 Vulkan/MoltenVK and native Metal with `GODOT_MTL_SYNC_MODE=none`. This is not a 66-real-camera benchmark, a full-resolution device preset test or real Bridge scene output. See [test evidence](benchmarks/hardware/godot-rgba8.json). Run `tests/test_quilt_rgba8.gd` through the latest engine with `--path . --script tests/test_quilt_rgba8.gd`.

### Bounded Bridge animation experiment

`tests/test_real_bridge_sequence.gd` captures eight poses into separate SDK RGBA8 textures and plays them for 20 seconds. Every output allocation remains immutable through teardown. This is finite prerecorded playback, not continuous scene streaming. The adapter limits sequences to 16 frames / 128 MiB calculated texture payload; no render-FPS improvement is claimed. Real-SDK API execution and exact fixture pixel checks passed. See [outcomes](benchmarks/hardware/godot-real-sequence.json), [native setup](native/bridge_metal/README.md#bounded-immutable-animation-diagnostic) and [unsubmitted SDK lifetime questions](docs/bridge-consumer-lifetime-questions.md).

### Direct Bridge target experiment

The native Metal extension can allocate an SDK RGBA8 IOSurface, import it through public `RenderingDevice.texture_create_from_extension()` and let the rig compose directly into it via `external_quilt_target`. A frozen 66-real-camera run passed the real SDK API boundary; an own-fixture run checked exact, nonempty RGBA8 pixels. The output blit is removed, but no frame-time speedup or continuous streaming support is claimed. See [instructions](native/bridge_metal/README.md#direct-imported-sdk-target-frozen-frame-experiment) and [results](benchmarks/hardware/godot-direct-target.json).

### Direct-target microbenchmark

On Apple M4, a synthetic 4092² RGBA8 constant-fill test measured 0.64–0.73 ms for direct SDK IOSurface compute writes versus 1.96–2.20 ms for private compute output plus blit, across three runs. No Bridge consumer draw or Godot scene rendering was timed. This supports retaining the optional direct target path but is not an end-to-end FPS claim. See [method, distributions and reproduction](benchmarks/hardware/direct-target-microbenchmark.md).

### Godot synthesis comparison

The actual addon kernel (24 real cameras → 66 views, borrowed raw depth, eight iterations) was tested against a real SDK target at 4092². Across three paired runs, direct output reduced synchronous draw/submission/GPU-wait medians by 1.25–2.12 ms versus an intermediate Godot RD texture plus copy. Complete output bytes matched in every run. These are elapsed wall measurements with frozen source cameras, not isolated GPU time or scene FPS; absolute times varied strongly. Small-quilt gains were marginal. See [protocol and all samples](benchmarks/hardware/sdk-synthesis-benchmark.md).

### 66-view anchor quality checkpoint

A same-format 66-real reference was compared against 12/24/36 real-camera budgets at the connected device's 54° cone. In the tested static opaque scene, synthetic-view PSNR was 27.82 / 29.81 / 29.74 dB; the common synthesized-view mask gives 27.81 / 29.81 / 29.82 dB. Every anchor tile matched exactly. Twenty-four real cameras are a candidate balanced setting for this scene; the user reported that the physical 24-anchor output looked approximately normal in the static test. Broader scene coverage, transparency and motion remain unvalidated. See [protocol and per-view results](benchmarks/view-budget66/README.md).

### Physical angular continuity limitation

The subsequent moving-box/alpha-panel comparison exposed a limitation: when the user rotated the monitor, the 24-real → 66 synthesized clip jumped between angular views, while the 66-real baseline transitioned smoothly. The earlier static 24-anchor image was reported approximately normal, but it does not validate angular continuity. Do not treat 24 anchors as a generally accepted display preset. Sparse source coverage and single-layer depth for transparency are hypotheses, not isolated causes. The next controlled checks should compare synthesized and all-real quilts without the alpha panel, then vary source budgets. See [repeated physical observations](benchmarks/hardware/transparency-repeat.json).

### Opaque physical budget controls

Removing the alpha panel did not eliminate user-observed angular jumps at 24 real cameras. The subsequent 48-real → 66-view opaque clip was reported smooth when rotating the monitor; the 36-camera assessment remains pending. Forty-eight is a visually accepted candidate for this scene, not a universal preset or a measured performance result. The minimum acceptable budget and cause of sparse-view discontinuities remain unresolved. See [hardware controls](benchmarks/hardware/README.md#opaque-angular-continuity-controls).

### Default-resolution hardware correction

The earlier hardware clips used only 64×114 pixels per view. At the actual 4092² default quilt dimensions (372×682 per view), the user reported a noticeably sharper 66-real-camera reference and **clear, smooth angular transitions with 24 real cameras reconstructed into 66 views**. No sampler or AA settings were changed. Thus the low-resolution angular failures should not be used to reject 24 anchors at normal resolution for this static scene. Full-resolution animation, transparency and broader scene coverage remain unvalidated. See [physical evidence](benchmarks/hardware/README.md#default-resolution-physical-comparison).

### Lit display test and parallax control

The physical diagnostic supports `--lit` for per-pixel shading, ambient fill, a directional light and soft-shadow parameters with a receiving floor. At full 4092² resolution the user reported better shading but foreground/background doubling in the all-real scene. Reducing only the virtual camera cone to 30° noticeably reduced that doubling; device calibration remains unchanged. This is a scene-specific parallax adjustment, not an established calibration fix. Use `--large --real-views=66 --lit --view-cone=30` for reproduction. [Hardware observations](benchmarks/hardware/README.md#litshadowed-depth-control).

### Fixed-baseline convergence assessment

For the lit 66-real, 4092², 30° scene, moving convergence from 6.0 to 5.2 at fixed camera spacing made the foreground sharper and the rear worse, according to the user. This distinguishes the current foreground/rear clarity issue from sparse-view synthesis. No universally sharp focus setting or calibration fix is established. The diagnostic accepts `--focus=5.2`; [method and observation](benchmarks/hardware/README.md#foreground-convergence-control).

### Projection and ordering checkpoint

A full-resolution 66-real grid on the convergence plane was user-confirmed stable/sharp, with correct foreground/background markers. Godot API projection checks passed, including the fixed-baseline 66-view case. The official reference audit found matching off-axis convergence principles and conceptual tile order, with remaining differences in interior angular sampling and tile-versus-display aspect. These are candidate investigations, not proven causes. See [source paths, lines and limitations](docs/projection-and-quilt-audit.md).

### Optional angular and device-aspect controls

`angular_view_sampling` and `source_view_size` allow independent reference-style camera spacing and camera aspect experiments. Neither changes the default when unset. The angular-only physical test retained slight doubling on some objects; the device-aspect-only test was reported somewhat better. Source-aspect correction renders 378×672 views into the same 372×682 quilt tiles, so resampling also changes. Geometry and synthesized fixture checks passed, but full optical correction and a combined-option hardware benefit remain unconfirmed. See [method and observations](native/bridge_metal/README.md#official-style-camera-controls).

### Accepted static lit hardware example

The user accepted the compact lit scene with 48 real views (8×6, 4096×4092), source aspect 9:16, angular sampling, convergence 5.6, reference cone 40° and subject depth factor 0.35: volume was better and double images acceptable. This is a scene-specific qualitative compromise, not elimination of ghosting or a default preset for all content. No motion/transparency/performance claim is made. The [complete configuration](benchmarks/hardware/accepted-lit48-profile.json) and [reproduction](benchmarks/hardware/README.md#accepted-scene-specific-40-degree-depth-compressed-setup) preserve the accepted example.
