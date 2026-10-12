# Test setup observations (not benchmark results)

- Initial manual-draw test with render loop disabled did not retrieve GPU samples. One retry using force_draw(true) printed timestamp_pairs=140, GPU samples=0, CPU samples=4 on 4.5.1. This run failed the expected nonempty GPU-ring assertion; it is not accepted evidence for profiling correctness.
- Normal render loop on 4.5.1 printed timestamp_pairs=140, GPU samples=4, CPU samples=4 and passed exact moving-object quilt comparison.
- A fixed 140-process-call test on 4.8 printed only 89 timestamp pairs, GPU samples=4, CPU samples=0. CPU recording starts after 90 actual dispatches, so this did not run long enough. The test now waits for at least 140 completed quilt updates with a bounded process-call timeout.
- The pre-existing resize test waited 12 process calls. A later 4.8 run failed. After waiting for current capture dimensions and at least four new dispatches per rig, the same raw image/lifetime assertions passed. Full final 4.8 checks passed, without changing shader output or weakening equality checks.

These observations were recorded during tool runs. Final logs are checks-4.5.log/checks-4.8.log and benchmarks/profiling.log. Timing from these tests is not used for speedup claims.
