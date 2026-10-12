# Native Metal boundary validation

This is correctness testing, not a performance benchmark. No FPS, GPU duration, power, optical-output or Godot-to-Bridge throughput result is claimed.

`build.log`: adapter and SDK fixture compiled successfully with Apple clang 21.0.0. `fixture.log`: real Apple M4 Metal GPU copy into a real IOSurface, exact half-float data and lifecycle/error checks passed. `installed-sdk.log`: the installed Bridge 2.6.3 library's symbols/version passed; this probe initializes no session or hardware output.

The fixture is our own implementation of the documented API for tests. A successful fixture draw is not a real Bridge display draw. No connected calibrated Looking Glass was available, and Godot native Metal/Vulkan interop is not implemented by this step. See [component contract and reproduction](../../native/bridge_metal/README.md).

`results.json` records tested scope, source hashes and compiled artifact hashes. Binaries and external SDK headers are excluded from Git. This native test is separate from the previously passed 16 Godot regressions; it does not add a hardware test to that suite.
