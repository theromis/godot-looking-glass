# Bridge Metal consumer lifetime: questions for SDK maintainers

These questions are prepared for discussion, not submitted to any external party. We use the public Bridge 2.6.3 Metal input API with IOSurface-backed RGBA8 textures on Apple M4. Frozen Godot quilts render correctly on the connected display.

The inspected external `BridgeRuntime/bridge.h:375-378` exposes creation, copy, release and quilt submission but no explicit consumer fence. The [native API reference](https://lfdocs.lookingglassfactory.com/software/looking-glass-bridge-sdk/native-function-reference) does not establish a Metal input texture reuse contract.

1. Does successful `draw_interop_quilt_texture_metal()` return after the SDK finishes all reads of the input IOSurface, or only after submitting work?
2. If it is asynchronous, how should the producer obtain a completion event/fence or safe input-slot reuse notification?
3. Does `release_metal_texture()` wait for outstanding consumers, retain the allocation until those consumers finish, or require a caller-side wait?
4. Is input sharing with OpenGL internally synchronized on macOS, and what producer/consumer synchronization is required from a Metal application?
5. Must window creation, draw submission, event pumping and teardown occur on the main thread?
6. Is a GPU-only bounded texture ring supported, and is there an official animated Metal sample demonstrating its lifetime guarantees?

Until this is resolved, our animation diagnostic allocates a separate texture for each prerecorded pose, never modifies submitted textures and holds them through SDK release/shutdown. This is a finite clip rather than continuous interactive streaming.
