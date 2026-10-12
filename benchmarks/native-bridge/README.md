# Native Metal boundary validation

This is correctness testing, not a performance benchmark. No FPS, GPU duration, power, optical-output or Godot-to-Bridge throughput result is claimed.

`build.log`: adapter and SDK fixture compiled successfully with Apple clang 21.0.0. `fixture.log`: real Apple M4 Metal GPU copy into a real IOSurface, exact half-float data and lifecycle/error checks passed. `installed-sdk.log`: the installed Bridge 2.6.3 library's symbols/version passed; this probe initializes no session or hardware output.

The fixture is our own implementation of the documented API for tests. A successful fixture draw is not a real Bridge display draw. No connected calibrated Looking Glass was available, and Godot native Metal/Vulkan interop is not implemented by this step. See [component contract and reproduction](../../native/bridge_metal/README.md).

`results.json` records tested scope, source hashes and compiled artifact hashes. Binaries and external SDK headers are excluded from Git. This native test is separate from the previously passed 16 Godot regressions; it does not add a hardware test to that suite.

## Godot 4.8 native Metal integration diagnostic

The native runtime built with `metal=yes`, `vulkan=no`, `extra_suffix=native-metal`, and a workspace Clang module cache. Original Vulkan binary was preserved; both test runtimes are 4.8-dev. The first build was rejected because the sandbox blocked Clang's default module cache, then the workspace-cache retry succeeded without engine source changes. Initial trimmed godot-cpp build lacked OS bindings; the profile was corrected and the retry succeeded. SDK headers and MIT godot-cpp sources stay outside this repository; compiled binaries remain ignored.

Accepted fixture-copy runs: `godot-metal-copy-1.log` through `-3.log`, each passing exact raw RGBA16Float comparison for a nonempty 64×64 Godot quilt. Explicit 120-refresh warmup is followed by a frozen capture/dispatch interval, completed Godot frames and a native same-queue sentinel; no source readback precedes the copy. `vulkan-guard.log` verifies fail-closed handling of Vulkan handles. `metal-analytic.log` verifies compute including reduction on Metal. `fixture-current.log` revalidates standalone lifecycle tests after fixture extensions.

Rejected copy probes: `godot-metal-copy-initial.log`, `godot-metal-copy-cold-start.log`; no successful nonempty result was established there. Their cause is unknown. The fixed warmup in the accepted test is not a production warmup policy.

Addon regression results: **Vulkan 16/16**, **Metal 13/16**. Metal failures are on-demand equality, capture/workgroup equality after resize and borrowed-buffer policy. The suite initially stopped at on-demand; remaining checks ran separately, as recorded in `regression-artifacts/remaining.json`. Raw logs are preserved in `regression-metal48.log` and `regression-artifacts/`; no failed test was converted to a pass. Settled-startup attempts also failed. One captured mismatch contained 837 changed components out of 139,360, maximum absolute float delta 0.55181885; see `on-demand-metal-difference.json`. Causes are not established. Diagnostic binary dumps remain local and are hash-identified in that JSON.

`godot-integration-results.json` records source/binding revisions, artifact hashes and the limited executed scope. No physical Looking Glass, real SDK texture draw, dynamic-frame handoff, multi-frame consumer lifetime or performance is claimed. No engine source patch was added by this stage.
