# Bounded shared-memory CPU fallback

The isolated Metal worker and Godot producer can use a one-frame POSIX shared-memory mailbox instead of a pipe. A named semaphore protects payload and sequence together, so the worker copies a complete frame into private CPU memory before releasing the lock. New producer frames may replace unpublished intermediate frames. No unbounded queue is created.

```sh
python3 native/bridge_metal/run_live_shm.py --godot "$GODOT_LG_BIN" --runtime "$BRIDGE_LIBRARY" --display-index 1 --large
```

The launcher generates private unique IPC names, waits for worker readiness before starting Godot and bounds child-process waits. Both the worker RAII owner and launcher cleanup remove only their own named IPC objects. Followers close mappings/handles without unlinking the owner's objects. A failed/dead lock holder causes a two-second semaphore acquisition timeout rather than indefinite waiting. Worker startup failure is reported; no output is claimed from a ready marker alone.

`shared_frame.hpp` validates names, dimensions, mapping size, payload length and increasing sequence. macOS reports a page-rounded shared object size; the actual size is accepted only between the requested and rounded sizes. The first startup test incorrectly required exact size and failed before output; the validation was corrected. `test_shared_frame.cpp` passed cross-process competing publication/read checks, payload rejection, final sequence and cleanup, observing nine coherent snapshots from 32 updates.

## 4K result and measurement scope

On 2026-10-12, the producer rendered eight 4092×4092 RGBA8 quilts. The worker presented sequences 1, 3, 5, 6 and 8, checked output pixels exactly, then released the texture and session. Average producer `get_image()` elapsed time was 12.057 ms and shared-memory publication elapsed time was 20.786 ms. The latter includes image data access, native call, semaphore wait and CPU payload copy; it is not memcpy bandwidth alone.

The preceding single-run pipe result was 11.615 ms readback and 1494.582 ms blocking write per frame. These differently backpressured single runs establish lower measured publication cost for this shared-memory control, not an end-to-end FPS speedup. The worker still requests only 2-Hz updates, skips intermediate source frames and performs diagnostic readback/validation. GPU buffers and CPU copies are not yet optimized.

Physical user observation is stored separately in [execution record](../benchmarks/hardware/live-shm-4k.json). The current Metal consumer synchronization remains experimental; the semaphore protects CPU memory only.

## Relation to RotatingCube

The user-confirmed official example renders directly into a persistent GL quilt and submits it, without our GPU-to-CPU cross-process transfer. We follow the persistent-output principle but have a different Godot/Metal transport boundary. This CPU mailbox is a compatibility/profiling step. Removing readback and sharing GPU surfaces requires a separately verified producer/consumer protocol; shared CPU memory does not provide it.
