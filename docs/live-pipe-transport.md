# Bounded CPU pipe transport

The small-quilt experiment can now transfer live Godot frames without per-frame disk writes. A private POSIX FIFO connects Godot's native GDExtension POSIX writes directly to the separate Metal worker's stdin. The FIFO has a temporary filesystem name, but frame bytes travel through kernel pipe buffers, not saved frame files.

```sh
python3 native/bridge_metal/run_live_pipe.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1
```

Run from the project root after building the native tools. The launcher creates a private temporary directory/FIFO, starts the worker and Godot, applies bounded timeouts, kills only its own remaining children on failure and removes the FIFO after completion. The worker holds its end open for the bounded session. Godot can block on writes when the consumer is slow; this is an experimental backpressure path, not suitable for an unbounded production main-thread loop.

The existing 16-byte header and fixed 704×684 RGBA8 payload are retained. The worker reads nonblocking chunks, assembles partial packets, validates magic/dimensions/sequence, and retains the newest complete packet from each batch. The read batch is capped at 64×65536 bytes; incomplete packet memory is bounded by the fixed packet size. Intermediate complete frames may be superseded before presentation. Malformed packets abort the experiment.

GPU readback in Godot, CPU/kernel copying, Metal upload and explicit diagnostic worker readback remain. The persistent SDK texture is still protected only by the experimental observed-context GL completion check. No GPU-only sharing or public all-consumer completion contract is claimed.

The diagnostic produces 24 new frames while the worker runs for 20 seconds at a requested 2-Hz update schedule. It records received sequences and elapsed `get_image()` time; this excludes transport/upload/display latency and is not an end-to-end FPS measurement. Full-resolution 4K and indefinite operation are not validated here.

See [run results](../benchmarks/hardware/live-pipe-worker.json). Atomic file transport remains available as a separate fallback; pass `--pipe-path` only for this launcher-managed FIFO mode.

Godot FileAccess did not open the FIFO in the initial run; that failure and the user-reported absence of output are retained separately. Pipe mode now loads the diagnostic GDExtension solely for open/write/close operations, without initializing or loading the Bridge runtime in the Godot process. The native writer retries partial writes/EINTR and rejects non-FIFO paths and invalid payload sizes.

The first native pipe run produced visible updates but transferred only three frames: yielding to SDK/window work for every partial packet starved the pipe reader until the worker deadline, and the producer received SIGPIPE. That partial result is retained separately. The receiver now drains an incomplete packet promptly while retaining the outer time bound; native Darwin pipe writes suppress SIGPIPE per descriptor so an unavailable reader becomes a checked write failure.

On 2026-10-12, the corrected run produced and presented all 24 frames, passed exact worker GPU pixel checks and closed the producer, SDK texture and session cleanly. The user confirmed sustained motion/color updates. Average producer get_image elapsed time was 0.588 ms for 704×684 RGBA8; no total latency or FPS improvement is established. The earlier failed and partial attempts are preserved in live-pipe-worker-initial.json and live-pipe-worker-partial.json.
