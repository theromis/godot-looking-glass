# Optional quilt profiling

`rig.profile_synthesis=false` по умолчанию. Обычный preview не отправляет LG quilt GPU timestamps, не читает timestamp results и не вызывает deferred sample recorders. `dispatch_count` сохраняется для synchronization/benchmark progression. Capture продолжает читать RD slot frame index для проверки согласованности источников; это getter, а не отправка GPU query.

Demo включает profiling для benchmark и `--profile-passes`/`--profile-quilt`. `--no-quilt-timing` отключает его даже в benchmark, оставляя independent wall update measurement. `--no-viewport-timing` — отдельный переключатель engine viewport timestamps; оба нужны для control без addon/viewport timing. Native `--gpu-profile` — отдельное engine instrumentation и в данном benchmark не используется.

GPU/CPU sample arrays ограничены `profiling_sample_limit` (default 480, 1..4096) и после заполнения перезаписываются кольцевым способом, без pop_front и сдвига массива. Порядок заполненного буфера не хронологический; demo использует aggregate mean. CPU submission samples по-прежнему начинаются после 90 dispatches, GPU samples включают startup. В отключённом режиме samples пусты, durations null (не 0), timestamp_pairs=0.

```sh
python3 benchmarks/quilt-profiling/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/quilt-profiling/rendered1024
python3 tests/run_checks.py --godot /path/to/godot --driver vulkan
```

A/B: одинаковая static opaque scene, 512 MultiMesh objects, четыре SpotLight shared atlas, 24 real → 48 output, 1024², borrowed color/depth с новой snapshot fallback policy, 8 iterations, 8×8 groups, rescue off. Три пары on/off с чередованием порядка. 90 warmup + 240 observed update intervals, не isolated GPU time. Сравнивается wall mean и saved PNG SHA256. Off-mode GPU measurement намеренно отсутствует: нельзя заявлять о GPU-ускорении по отсутствующим timestamps. CPU/GPU settings и sample counts проверяются; anomalies wall/engine ratio>1.5 сохраняются.

Test profiling сравнивает два quilt при движущемся объекте после >100 updates: disabled counters/arrays пусты, enabled GPU/CPU rings заполнены и имеют ровно четыре samples, raw output exact и nonempty. Этот тест использует обычный render loop для получения timestamp results. Первый manual-draw вариант с render_loop disabled отправлял marker pairs, но не вернул GPU samples; это особенность test setup, не accepted profiling result. Buffer compatibility test отдельно продолжает использовать manual draw для snapshot equality.

Ограничения: одна сцена/один GPU, fullscreen/display hardware/native Metal не проверены. Удаление двух timestamp commands не предполагается заранее быстрее; exact output и bounded memory полезны даже без подтверждённого frame-time выигрыша. Default preview теперь profiling off, предыдущие measurement benchmarks остаются profiling on благодаря явной demo настройке.


## Measured result

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, 24 real → 48 output, 1024², три пары:

| Quilt profiling | Observed update interval ms | Run stddev ms | Recorded GPU/CPU samples |
|---|---:|---:|---|
| on | 47.6166 | 0.0835 | 327 GPU / 240 CPU per run |
| off | 47.6215 | 0.0460 | 0 / 0 |

Выигрыш времени обновления не подтверждён: разница +0.0049 ms меньше разброса. Каждый прогон имеет 240 measured samples и 331 dispatches. On-mode отправил 331 marker pairs; off-mode 0. Off-mode GPU/CPU submission durations null, а не нулевое время работы. Saved PNG первой пары exact SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Wall/engine ratio>1.5 anomalies не обнаружены.

Default profiling off устраняет ненужную инструментальную работу и постоянное накопление samples в ordinary preview; этот результат не означает FPS ускорения на данной сцене. В profiling mode bounded ring test с limit=4 подтвердил сохранение ровно четырёх GPU/CPU samples после не менее 140 actual quilt updates и exact output на движущемся объекте.

Данные: rendered1024/summary.json, per-run JSON/log/PNG, checks-4.5/4.8.log. Предыдущие viewport timestamps измерения (+1719 native markers) относятся к другой нагрузке и не складываются с этим on/off результатом.
