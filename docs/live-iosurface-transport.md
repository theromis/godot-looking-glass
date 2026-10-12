# Private IOSurface GPU frame transport

The macOS native Metal diagnostic can pass Godot quilts to the isolated worker without CPU pixel transfer. It is still a bounded prototype; Bridge consumer synchronization remains experimental.

```sh
# Diagnostic checksums: intentional source/output readbacks, not a benchmark.
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1 --large --verify
# GPU pixel transport, no diagnostic pixel readback:
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1 --large
```

## Resource and ordering contract

1. The worker creates a 32-byte descriptor/ack mailbox and a temporary Mach endpoint, then reports readiness.
2. The Godot GDExtension creates one private RGBA8 IOSurface on the actual Godot Metal device. It sends an IOSurface Mach-port right to the worker. The surface is not made globally accessible.
3. After flushing/finalizing the requested frozen Godot revision, the producer copies the quilt into that surface on the producer Metal queue and waits for GPU completion before publishing its sequence.
4. The worker imports the surface using the received right, copies into its persistent SDK texture on the worker queue, and waits for completion.
5. The worker acknowledges that source copy. Only then may Godot overwrite the shared source. The acknowledgment does not mean display completion.
6. The SDK output is a separate texture. Rewriting it still uses the experimental observed-context GL completion check; the public all-consumer lifetime guarantee is unresolved.
7. Godot waits for the final source acknowledgment before releasing its publisher. The worker retains its imported surface independently until cleanup.

There are two GPU copies: Godot quilt to shared source, then shared source to SDK output. This is GPU-only pixel transport in non-verify mode, not zero-copy rendering. CPU orchestration, semaphore waits and blocking producer/copy completion waits remain.

The initial numeric `IOSurfaceLookup` attempt failed for a private cross-process surface. The corrected route follows Apple's [IOSurfaceCreateMachPort/lookup-from-port API](https://developer.apple.com/documentation/iosurface/iosurfacelookupfrommachport%28_%3A%29), with [Metal IOSurface-backed texture creation](https://developer.apple.com/documentation/metal/mtldevice/maketexture%28descriptor%3Aiosurface%3Aplane%3A%29?language=objc). Numeric IDs only validate identity after rights-based import; they are not used to obtain access.

## Executed tests and measurement scope

- Cross-process control test completed 32 acknowledgments, rejected outstanding-frame overwrite, wrong acknowledgment and stale sequence.
- Mach endpoint close/re-register test passed. An initial unsupported null-port unregister call returned NAME_IN_USE; cleanup now releases owned port rights, and same-name reuse was verified.
- The 4K diagnostic run copied eight frames and matched per-frame FNV-1a checksums between producer IOSurface and worker SDK output. These are diagnostic checksums, not an exhaustive byte-by-byte identity proof or performance measurement.
- The non-verify 4K run copied eight frames without producer or worker pixel readback. Initial average producer publication/copy-wait elapsed time was 2.678 ms; the final repeat after endpoint cleanup correction was 2.195 ms. This excludes prior rendering, waiting for the previous acknowledgment, worker copy/draw and display latency. `get_image()` is not called in this mode; its zero counter does not claim a free readback operation.

See [diagnostic record](../benchmarks/hardware/live-surface-4k-verify.json), [GPU-only record](../benchmarks/hardware/live-surface-4k-gpu.json) and [retained failed ID-lookup attempt](../benchmarks/hardware/live-surface-id-lookup-failed.json). Physical observations are separate from API completion.

## Remaining limitations

The temporary standalone rendezvous uses deprecated `bootstrap_register`; modern XPC packaging and hardened peer authorization are still future work. Current support is the tested unsandboxed macOS desktop native Metal setup, with fixed small/4K quilt presets. Vulkan/MoltenVK import, indefinite operation, full-rate animation and scene-quality/transparency validation are not covered. No SDK source or runtime is vendored.

## Hardware-confirmed repeat

On 2026-10-12, the 20-second 4092×4092 repeat delivered all eight sequences without producer/worker pixel readback, completed SDK release/shutdown, and the user confirmed that it works on the physical display. Mean producer publication/copy-wait elapsed time was 2.361 ms with the exclusions above. See the [repeat record](../benchmarks/hardware/live-surface-4k-gpu-repeat.json). This confirms the bounded visual update test; continuous full-rate operation and the SDK consumer-completion contract remain unverified.

## Extended animation test

Add `--duration 120` to the GPU-only command to keep the worker alive for two minutes and generate fresh Godot revisions for approximately 105 seconds. The remaining time allows startup/final acknowledgment and holds the last frame. The duration is bounded to 20–600 seconds; the default 20-second eight-frame 4K test remains unchanged. Longer runs write distinct `-duration-120` result files.

The worker still checks for updates at approximately 2 Hz, and the producer intentionally waits 0.4 seconds after each synchronously flushed revision. This tests sustained ownership and visual updates, not maximum throughput. `worker_update_rate_hz` counts new-frame SDK submissions between the first and last update, not physical display refresh. Process RSS is sampled once per second with `ps`; it excludes GPU allocation accounting and is not a leak proof. Producer publication timing excludes rendering, previous-copy acknowledgment wait and worker/display work.

### Two-minute result (2026-10-12)

The 4092×4092 run produced and received all 212 frames in order during 105.086 seconds of animation, then held the last frame until worker shutdown. The user confirmed ongoing visible updates. The SDK-submission rate between first and last new frame was 2.009 Hz under the approximately 2 Hz cap. Mean producer publication/copy-wait elapsed time was 3.329 ms. No diagnostic pixel readback was performed. Both processes exited successfully and SDK release/shutdown passed.

After ten seconds of warmup, producer RSS was 242,128 KiB initially and 189,008 KiB at its final sample; worker RSS was 91,440 KiB initially and 90,752 KiB at its final sample. Memory samples are recorded below; these values do not establish absence of GPU leaks. The known SDK initialization GL_INVALID_ENUM was still logged despite successful visible output. See the [full measurements](../benchmarks/hardware/live-surface-4k-gpu-duration-120.json) and [sanitized log](../benchmarks/hardware/live-surface-4k-gpu-duration-120.log). SDK consumer-completion guarantees and higher-rate stability remain unresolved.

## Uncapped diagnostic mode

Use `--large --duration 60 --uncapped` with the launcher to remove the producer's 0.4-second delay and the worker's 2 Hz admission cap. The event loop still yields for approximately 1 ms and each Godot revision still uses eight explicit frame flushes. One outstanding source frame and copy acknowledgment are retained. This is the throughput of this synchronous diagnostic harness, not the maximum native renderer throughput.

Additional stage means are CPU wall-clock measurements: `mean_revision_flush_ms` includes eight Godot process-frame waits and forced draws/synchronization; `mean_ack_wait_ms` covers waiting for the previous source-copy acknowledgment; `mean_surface_publish_elapsed_ms` includes producer copy/publication; worker `worker_mean_finish_ms` covers the experimental observed-context `glFinish`, `worker_mean_copy_wait_ms` covers encoding/submission/completion of the worker GPU copy, and `worker_mean_new_frame_draw_ms` covers the new-frame SDK call. Repeated event-loop redraws and display completion are outside the last metric. Stages overlap across processes and must not be added as end-to-end latency. No Metal GPU timestamps or physical refresh measurement are implied.

### Uncapped 4K result (2026-10-12)

The 60-second worker run received all 1,238 frames in order over 44.884 seconds between first/last submissions, averaging 27.560 new SDK frame submissions per second. The user confirmed normal visible updates. There was no producer/worker pixel readback and SDK release/shutdown passed. This is a simple unshaded cube scene with 66 actual cameras and a synchronous eight-flush harness, not a general game benchmark or measured panel FPS. The initial run advanced rotation/color per frame; uncapped animation now advances by elapsed time.

| CPU wall-time stage | Mean ms |
| --- | ---: |
| Godot revision preparation (eight flushes, waits/draw/sync included) | 34.269 |
| Previous source acknowledgment wait | 0.147 |
| Producer GPU copy and publication | 1.922 |
| Worker observed-context finish | 0.006 |
| Worker GPU encoding/copy/completion wait | 3.401 |
| Worker new-frame SDK draw call | 11.624 |

The longest measured producer stage is revision preparation; its eight forced flushes are diagnostic overhead mixed with actual rendering, so this does not isolate GPU scene cost. Worker stages execute concurrently with producer work. The next useful experiment is reducing flushes while validating that each received quilt contains the intended revision; it should precede speculative buffering changes. See [measurements](../benchmarks/hardware/live-surface-4k-gpu-duration-60-uncapped.json).

The subsequent elapsed-time animation code passed a 30-second API run: all 432 frames were received, new-frame submissions averaged 28.744 Hz and SDK cleanup passed. A separate physical assessment was not requested for that repeat; the user observation above belongs to the initial 60-second run. See the [repeat record](../benchmarks/hardware/live-surface-4k-gpu-duration-30-uncapped.json).

## Revision-driven flush completion

The optional `--adaptive-flush` producer stops the manual flush loop when `completed_revision == requested_revision`, retaining the eight-iteration limit and failure check. The existing rig marks completion after all requested source captures have advanced and quilt dispatch has been submitted; the native publication copy still runs on the Godot queue and waits for its GPU completion. No source-copy ownership or Bridge synchronization rules are relaxed.

`--adaptive-flush --validate-flush --large` intentionally reads the candidate quilt back, requests a fresh capture of the identical frozen scene, flushes eight times, and compares complete image byte arrays. Eight distinct cube poses/material states passed exactly, using two candidate flushes each. Worker SDK output checksums are a separate test; this comparison validates source quilt contents against the conservative capture path. The first validation log incorrectly reported no diagnostic readback in its producer summary; the JSON explicitly corrects that label and the code now reports validation readback. See the [validation record](../benchmarks/hardware/live-surface-4k-gpu-adaptive-validation.json).

The test covers this simple opaque scene on the tested native Metal build, not arbitrary animation, shadows, transparency or cross-backend completion. The adaptive mode remains opt-in.

### Adaptive throughput result

The 60-second worker run received all 1,272 frames in order, used two flushes per revision, and submitted new SDK frames at 28.265 Hz. The user confirmed correct visible animation. Producer revision preparation averaged 30.074 ms, previous-copy acknowledgment wait 0.799 ms, and copy/publication 4.506 ms. Worker copy/wait averaged 3.693 ms and its new-frame SDK call 12.695 ms. No pixel readback was enabled; cleanup passed. See [full results](../benchmarks/hardware/live-surface-4k-gpu-duration-60-uncapped-adaptive.json).

This did not establish a material throughput improvement: the earlier eight-flush 60-second run reached 27.560 Hz and its elapsed-time 30-second repeat reached 28.744 Hz. Run durations and animation differ, and repeated matched trials were not performed. Removing six flushes reduces explicit work, but preparation still includes main-loop/process-frame waits; the timings do not isolate GPU rendering. Next investigate those waits and presentation pacing before claiming a benefit or changing addon defaults.

## Main-loop wait breakdown (2026-10-12)

The instrumented adaptive 4K run submitted all 582 frames in order at 29.107 new SDK frames/s during approximately 20 seconds of animation, then held its final frame to the 35-second worker deadline. Both processes and SDK cleanup passed. No diagnostic readback was used. Physical observation remains pending for this separate run; the preceding adaptive hardware run was user-confirmed.

| Producer CPU wall time per revision (two flushes) | Mean ms |
| --- | ---: |
| Awaiting process-frame signals | 0.211 |
| force_draw calls | 27.641 |
| force_sync calls | 0.001 |
| Total revision preparation | 27.885 |
| Previous source-copy acknowledgment wait | 2.337 |
| Copy/publication | 4.162 |

The project's VSync mode is already disabled (`project.godot`, `display/window/vsync/vsync_mode=0`), so no redundant VSync-off trial was performed. Earlier speculation that main-loop waits dominated the approximately 30 ms preparation is contradicted by this breakdown: almost all measured preparation time is inside `force_draw`. That call includes rendering and any internal waits; CPU/GPU contributions are not isolated here. In the tested engine source, `servers/rendering/rendering_server.cpp:3589–3590` binds force_sync/draw to sync/draw; `servers/rendering/rendering_server_default.cpp:439–459` flushes/synchronizes the render command queue and invokes/enqueues `_draw`. The files refer to external Godot revision `c61fc0118854f38d75474346a417db55e52d0ffd`; no engine patch was made.

The producer renders 66 actual camera views at 372×682, with a 4092×4092 quilt. The next experiments should split the first/second draw costs or vary actual camera count while checking synthesized output quality, rather than treating process-frame sleep or VSync as the established bottleneck. See the [breakdown record](../benchmarks/hardware/live-surface-4k-gpu-duration-35-uncapped-adaptive.json).

## First versus second draw and copy-first validation

The 36-second control run produced/received all 581 frames at 27.670 new SDK submissions/s. First draw CPU wall time averaged 5.625 ms and the second draw 24.473 ms. These are blocking call timings, not isolated GPU durations; no throughput improvement was made in this experiment. See [draw breakdown](../benchmarks/hardware/live-surface-4k-gpu-duration-36-uncapped-adaptive.json).

An attempted pre-draw completion check skipped the second draw when the logical rig revision was complete. Comparing the source quilt through `get_image()` initially passed all eight poses with one draw. That comparison was insufficient: readback can affect pending GPU work, so it did not prove the contents copied by the ordinary publication path. The stronger test publishes through the native Metal copy first, reads the resulting IOSurface afterward via diagnostic `read_surface_pixels()`, and compares all copied bytes against a fresh eight-flush capture of the identical scene.

That stronger test failed at zero-based frame 1 when the second draw was skipped. The two-draw control passed all eight copied IOSurface comparisons and SDK cleanup. Thus logical `completed_revision` alone is insufficient to bypass the second draw before native publication in this setup. Pending GPU submission/ordering is the likely explanation, not a verified internal root cause. The unsafe precheck is restricted to an explicit validation-only negative control; it is not enabled for normal output.

See [retained source-readback false positive](../benchmarks/hardware/live-surface-4k-gpu-adaptive-validation-precheck-source-readback.json), [failed copy-first negative control](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation-precheck.json), and [passing two-draw copy-first control](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation.json). Validation readbacks are intentional; their publication timing is omitted because the copy occurs outside the usual timed publication block. To reproduce the passing stronger test, use `--large --adaptive-flush --validate-flush`; append `--check-before-draw` only to reproduce the expected failed control.

Any future removal of the second draw needs a verified GPU submission/completion boundary, tested by copying before readback. Performance numbers or source readback comparisons alone are insufficient.

## Capture-stage composition (opt-in)

The source audit explains the late dispatch: in the external tested Godot revision, `servers/rendering/rendering_server_default.cpp:112–140` ends the rendering frame before running post-draw callbacks, and `:229` emits `frame_post_draw`. `servers/rendering/renderer_rd/renderer_compositor_rd.cpp:136–138` ends the frame using `RenderingDevice.swap_buffers`; `servers/rendering/rendering_device.cpp:8115–8129` ends/executes the frame and starts recording another. Its `:8131–8145` rejects submit/sync on the main device. No engine patch or unsupported submission call is used.

The rig's optional `compose_in_capture_callback` attaches a render-thread callable to every source capture. Once color/depth capture commands are recorded, it invokes the existing `_dispatch_requested` gate. Only the last required fresh capture passes the all-capture-count check; quilt compute is then recorded before the current frame ends. The post-draw fallback stays connected and the completed-request gate prevents a duplicate dispatch. This mode applies to on-demand compute output and defaults to false. Capture release clears the callable.

To test or measure, add `--adaptive-flush --capture-compose` to the launcher. A single manual draw is followed by the next process-frame boundary to deliver logical completion. Native publication still copies on the actual Godot Metal queue and waits for completion; the IOSurface copy-ack and experimental Bridge consumer rules are unchanged.

The 36-second GPU-only run produced/received 616 frames in order at 29.355 new SDK submissions/s, with user-confirmed correct animation and clean teardown. Revision preparation fell to 4.624 ms (one draw), but copy/publication rose to 19.148 ms and previous-copy acknowledgment wait to 10.308 ms. Worker copy/wait averaged 3.733 ms and new-frame SDK calls 9.206 ms. The old two-draw control reached 27.670 Hz. These single runs do not establish a universal speedup; waiting moved between stages, and substantial rendering/GPU work remains. See [same-frame run](../benchmarks/hardware/live-surface-4k-gpu-duration-36-uncapped-adaptive-capture-compose.json).

Broader moving occluder, lighting, transparency, synthesized-view, borrowed-buffer and alternate-backend tests remain necessary before making this an addon default.

The final copy-first validation disabled capture notifications on the render thread for each reference, restoring the original post-draw composition schedule and eight flushes. All eight one-draw IOSurface copies matched those original-schedule reference byte arrays exactly; SDK cleanup passed. See [cross-schedule validation](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation-capture-compose.json). Diagnostic readback follows the candidate GPU copy and does not precede it.

## Configurable real-view budget

`--real-views 24` selects 24 actual scene cameras and synthesizes the remaining views of the 66-view quilt; 12, 24, 36, 48 and 66 are accepted. Default remains 66. This changes scene rendering and synthesis work while retaining 4092×4092 output and the same native transport. `--run-label` optionally writes separate result records without overwriting previous runs.

The capture-stage 24→66 path passed all eight copy-first comparisons against the same 24→66 scene using the original post-draw/eight-flush schedule. This checks scheduling/copy correctness, not quality equivalence to rendering all 66 cameras. See [24→66 validation](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation-capture-compose-real-24.json). Dynamic disocclusions, lighting and transparency require separate visual assessment.

### Paired 4K view-budget run (2026-10-12)

| Actual cameras → output views | Frames received | New SDK submissions/s | Producer copy/publication mean ms |
| --- | ---: | ---: | ---: |
| 24 → 66 | 1,223 | 58.314 | 5.655 |
| 66 → 66 | 615 | 29.330 | 23.972 |

Both sequential runs used the same 36-second worker duration, approximately 21 seconds of elapsed-time animation, 4092×4092 quilt, one draw/capture-stage composition, no diagnostic readback and the same simple unshaded cube. All produced sequences were received in order and SDK cleanup passed. The measured submission-rate ratio is approximately 1.99; this is one trial per budget, not a statistically established universal gain or physical panel FPS.

Native publication timing includes waiting for prior Godot GPU work on its queue, so its reduction does not mean the 64 MiB blit itself became four times faster. The comparison is consistent with lower scene-rendering work, but does not isolate GPU stage durations. The user subsequently confirmed that the current animated 24→66 output looks normal on the display. This observation covers the simple cube, not complex occlusion, lighting or transparency. The real-camera default remains 66 until broader visual/scene testing. See [paired summary](../benchmarks/hardware/live-surface-view-budget-comparison.json).

## Lit occlusion and alpha-panel fixture

`--complex-scene` adds a moving orange occluder in front of three RGB spheres at different depths, one shadowed OmniLight, a floor receiving shadows and a translucent cyan panel. Geometry/material setup lives in `tests/worker_scene_fixture.gd`; the live producer freezes a scene pose while preparing each quilt. Rotation/translation use elapsed time in uncapped mode.

```sh
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --large --adaptive-flush --capture-compose --real-views 24 --complex-scene --validate-flush
python3 native/bridge_metal/run_live_surface.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --large --adaptive-flush --capture-compose --real-views 24 --complex-scene --uncapped --duration 36
```

All eight copied IOSurfaces matched the original post-draw/eight-flush references with the same 24 actual cameras. This verifies scheduling/copy correctness, not equivalence to 66 actual cameras. The GPU-only animated run received all 628 frames in order at 29.972 new SDK submissions/s, used one draw, performed no diagnostic pixel readback and completed SDK teardown. The user reported that the scene looks normal, including moving occlusions and the alpha panel. This is qualitative scene-specific feedback, not a guarantee for arbitrary transparency or disocclusions.

Revision preparation averaged 4.343 ms, previous-copy acknowledgment wait 5.599 ms, and producer copy/publication (including prior queue work) 23.529 ms. Worker copy/wait averaged 2.960 ms and its new-frame SDK call 3.422 ms. The earlier simple cube reached 58.314 Hz with the same 24-view budget, but these different scenes are not an isolated shadow, lighting or transparency A/B test. Further profiling should isolate those costs before attributing the loss to a particular feature.

See [copy-first validation](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation-capture-compose-real-24-complex.json) and [animated hardware result](../benchmarks/hardware/live-surface-4k-gpu-duration-36-uncapped-adaptive-capture-compose-real-24-complex.json). The known initialization GL_INVALID_ENUM remains in successful SDK logs. Long-term/full-rate SDK consumer synchronization is still experimental.

## Shadow and alpha-panel cost controls (2026-10-12)

The launcher supports `--no-shadows` (disables the fixture OmniLight's shadow maps while retaining its lighting) and `--no-alpha-panel` (hides the panel). Run the complex 24→66 command with `--duration 30 --uncapped` and a distinct `--run-label`, using neither flag, either flag alone, and both flags. All other scene parameters, output size and transport remain identical. The alpha control removes one mesh; it is not a same-geometry opaque-versus-transparent material comparison.

| Shadow maps | Alpha panel | Frames received | New SDK submissions/s |
| --- | --- | ---: | ---: |
| On | Visible | 443 | 30.109 |
| Off | Visible | 786 | 52.486 |
| On | Hidden | 451 | 30.080 |
| Off | Hidden | 799 | 53.369 |

Each sequential run kept the worker alive for 30 seconds and animated for approximately 15 seconds. All sequences arrived in order, no diagnostic pixel readback was used, and SDK cleanup passed. There was one trial per mode; startup, scheduling/thermal variation and SDK behavior are not eliminated. No separate visual assessment was requested for these ablations; the earlier full fixture was user-confirmed.

Disabling shadow maps produced the dominant throughput difference in this scene. Removing the alpha panel did not produce a detectable gain with shadows enabled; the small no-shadow difference is not statistically established. These results do not mean transparency is free in other scenes. Native copy/publication includes waiting for scene GPU work; its time cannot be interpreted as pure blit cost.

The next candidate is the existing opt-in shared positional shadow atlas with this moving OmniLight scene. That requires separate correctness and throughput comparisons and does not follow automatically from earlier shadow benchmarks. See [matrix and per-run records](../benchmarks/hardware/live-surface-scene-cost-comparison.json).

## Experimental shared positional shadow atlas

`--shared-shadows --full-shadow-casters` enables the existing rig/engine prototype. The launcher requires the API and the producer refuses the mode if tighter caster culling remains enabled. Full-caster tests create an owned temporary project outside the repository with links to project resources and a copied configuration setting `rendering/lights_and_shadows/tighter_shadow_caster_culling=false`; the root project and user overrides are untouched. The launcher cleans up that temporary project. Both shared and independent full-caster controls disable mesh LOD for the viewports.

The tested external engine is revision `c61fc0118854f38d75474346a417db55e52d0ffd`. `servers/rendering/renderer_viewport.cpp:335–350` selects the source atlas only with compatible scenario, LOD, size/format and camera conditions. `servers/rendering/renderer_scene_cull.cpp:157–161` requires the full visibility mask and full caster mode; `:4550` reads the tighter-culling setting. This is not a stock Godot API; ordinary builds are rejected for this test rather than silently benchmarked as if sharing worked. No new engine patch was made.

The initial test without full caster culling did not establish sharing and failed comparison. After configuring the required mode, the first frozen pose still failed strict byte comparison. An actual IOSurface-versus-independent-atlas reference image comparison found 51 differing pixels out of 16,744,464, maximum RGB difference 2/255, mean absolute RGB difference 0.000001612 in 8-bit levels. Only this first pose was quantitatively compared; exact equivalence across the animation is not established. Cropped local images appeared visually alike. The cause of the tiny difference is unresolved. Image diagnostics are ignored local PNGs; numerical results are tracked in [difference record](../benchmarks/hardware/shared-shadow-image-difference.json).

| Full-caster, LOD=0 mode | Frames received | New SDK submissions/s | Mean shadow draw calls/revision |
| --- | ---: | ---: | ---: |
| Independent atlases | 450 | 30.028 | 282.987 |
| Shared atlas | 722 | 50.125 | 11.801 |

All frames arrived in order and SDK cleanup passed in these GPU-only runs. The user confirmed correct-looking shared shadows without flicker or new motion artifacts. The approximately 1.67× submission-rate ratio and roughly 24× reduction in shadow draw calls apply to one trial per mode of this moving OmniLight fixture; they are not universal gains or measured display FPS. Draw-call counts sum viewport shadow statistics after each requested revision. The normal shadow-sharing default remains false.

See [paired measurements](../benchmarks/hardware/live-surface-shared-shadow-comparison.json) and [strict failed full-caster comparison](../benchmarks/hardware/live-surface-4k-gpu-adaptive-copy-validation-capture-compose-real-24-complex-shared-shadows-full-casters.json). Remaining work includes quantifying more poses, explaining residual differences, atlas overflow/coverage/subdivision compatibility and broader scenes. The hardware speed run is an experimental quality/performance result, not a passed byte-exact regression.

The final system-temporary-project smoke test delivered all eight frames with the shared API active and completed cleanup. Its approximately 2 Hz intentionally paced producer is not a throughput result. See [staging smoke record](../benchmarks/hardware/live-surface-4k-gpu-adaptive-capture-compose-real-24-staging-cleanup-smoke-complex-shared-shadows-full-casters.json).
