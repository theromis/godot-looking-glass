# Bounded live Godot-to-Metal file transport

This diagnostic connects a running Godot renderer to the separate persistent Metal worker. It is a CPU fallback experiment, not zero-copy streaming or a production-synchronized SDK path.

`tests/test_worker_live.gd` renders 24 new all-real 66-view quilts at 704×684. Each requested revision is flushed before reading the RGBA8 image. It writes a temporary file containing four little-endian uint32 words (magic 0x4c475131, sequence, width, height), followed by raw RGBA8 pixels, then atomically renames it to `latest.bin`.

`probe-persistent --experimental-reuse --live-directory=DIR` polls that file for 20 seconds. It checks exact length, magic, dimensions and monotonically increasing sequence, uploads the latest frame into a Metal buffer, blits it to the same SDK texture, waits for the producer and submits it. It compares output pixels to incoming bytes diagnostically. Slow consumers skip intermediate frames instead of growing a queue. File replacement preserves already-open readers' previous file contents; no concurrent payload overwrite is used.

The existing observed-context GL completion checks remain experimental. They do not cover undocumented SDK contexts/future reads. Source readback, file copying, worker upload and validation readback incur CPU/memory traffic. The producer reports elapsed `get_image()` time only; this excludes serialization, file transport, upload, SDK processing and display latency.

```sh
# Start worker in one terminal, after clearing stale output in a dedicated run directory:
native/bridge_metal/build/probe-persistent "$BRIDGE_LIBRARY" 1 --experimental-reuse --live-directory=benchmarks/hardware/live-transport
# Run producer in another:
GODOT_MTL_SYNC_MODE=none "$GODOT_LG_BIN" --path . --rendering-driver metal --script tests/test_worker_live.gd
```

The producer creates its directory; use a fresh directory or remove only its known generated latest.bin before each worker run because sequence numbers restart. Local transport files are ignored by Git. Current worker dimensions and quilt grid are fixed; full-resolution animation is not covered. See [execution and physical observation](../benchmarks/hardware/live-file-worker.json).
