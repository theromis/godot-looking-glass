# Managed Metal lifecycle and RSS checks

This test exercises the addon node rather than the older Python-supervised pixel transport. It reuses one 24-source/66-view 4092×4092 rig and one output node, starts/stops five short worker sessions, then runs a sixth session for 120 seconds. Each session must receive every submitted frame, report SDK teardown, and exit with code 0. Startup readiness is included in the requested session time. No readback, manual draw or pixel files are used.

Build native artifacts as described in [managed output setup](managed-metal-output.md). Set external paths and run from the repository root:

```sh
python3 native/bridge_metal/run_managed_stress.py \
  --godot "$GODOT_BINARY" \
  --runtime "$BRIDGE_LIBRARY"
```

The runner supplies the tested native Metal hazard-tracking setting, samples Godot and its own worker child RSS every second, filters diagnostics, and records results in `benchmarks/hardware/managed-metal-stress.json`. A 180-second watchdog terminates only the run's child processes. Progress is written through stderr because the release engine buffers ordinary stdout. A runtime error or missing final PASS fails the run.

RSS measures process resident memory, not dedicated GPU allocations or a proof of leak-free operation. Compare samples after startup rather than the first sample. This test does not recreate the rig between sessions, exercise unplug/reconnect, guarantee optical correctness or establish the SDK texture-consumption contract. A new physical visual confirmation must be collected separately if needed.

## Executed result — October 12, 2026

Godot 4.8 c61fc0118, native Metal Forward+, Apple M4, 24 real views → 66 output views, quilt 4092×4092:

| Session | Submitted / received | SDK cleanup |
| --- | --- | --- |
| Short cycle 1 | 81 / 81 | Passed |
| Short cycle 2 | 72 / 72 | Passed |
| Short cycle 3 | 77 / 77 | Passed |
| Short cycle 4 | 75 / 75 | Passed |
| Short cycle 5 | 74 / 74 | Passed |
| 120-second session | 2331 / 2331 | Passed |

All six worker exits and the harness exit were 0. The sampled steady interval was 40.533–148.573 seconds from harness startup, during the final session.

| Process | First steady RSS | Last steady RSS | Delta | Peak in interval |
| --- | --- | --- | --- | --- |
| Godot | 257584 KiB | 258048 KiB | +464 KiB | 258224 KiB |
| Worker | 140592 KiB | 140896 KiB | +304 KiB | 140928 KiB |

No large resident-memory accumulation was observed in this interval. This does not establish indefinite safety or the Bridge consumer-completion contract. No new user visual confirmation was collected. The full [record](../benchmarks/hardware/managed-metal-stress.json) includes one-second samples.

The initial run was interrupted by the operator because buffered release stdout obscured progress; its partial memory record is [preserved separately](../benchmarks/hardware/managed-metal-stress-interrupted.json). No functional regression was established from that interrupted run. Progress was moved to stderr before the successful complete run.

## Rig recreation and active close — October 12, 2026

Two additional tests use the actual interactive demo code and supported device discovery/settings. Run them independently; native Bridge sessions must not overlap:

```sh
python3 native/bridge_metal/run_managed_stress.py --test recreate \
  --godot "$GODOT_BINARY" --runtime "$BRIDGE_LIBRARY"
python3 native/bridge_metal/run_managed_stress.py --test close \
  --godot "$GODOT_BINARY" --runtime "$BRIDGE_LIBRARY"
```

Each mode writes a separate result file by default. The recreation test uses the demo's Start/Stop methods, creates a new 24-source/66-view 4K rig each time, and checks after eight engine frames that the old rig and native publisher weak references have expired, the old quilt RID is invalid, and the owned worker process has exited. No new rig is started until the previous one passes cleanup.

| Fresh rig cycle | Submitted / received | Resource checks and SDK teardown |
| --- | --- | --- |
| 1 | 71 / 71 | Passed |
| 2 | 74 / 74 | Passed |
| 3 | 74 / 74 | Passed |
| 4 | 80 / 80 | Passed |

The active-close test invokes `NOTIFICATION_WM_CLOSE_REQUEST` on the demo while output is running. It exercises the same handler used for native window-close events: request worker stop, wait for acknowledgment and SDK teardown, then quit the engine. It passed with 68/68 frames, worker exit 0 and engine exit 0. The test injects the notification; it does not click the operating-system window button or simulate a forced kill. GPU-RID invalidation is checked by the recreation test, not after process exit in the close test.

See [recreation record](../benchmarks/hardware/managed-metal-recreate.json) and [close record](../benchmarks/hardware/managed-metal-close.json). These checks establish bounded resource lifecycle behavior in the tested native Metal configuration; hot-unplug, indefinite operation and SDK consumer synchronization remain separate concerns. No new user visual confirmation was collected.
