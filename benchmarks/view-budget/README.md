# Real-view budget: speed and quality

```sh
python3 benchmarks/view-budget/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/view-budget/rendered1024
python3 benchmarks/view-budget/quality.py benchmarks/view-budget/rendered1024
```

Quality.py требует NumPy/Pillow; локально bundled Python `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. Main runner — standard library.

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK. Сравниваются uniform real budgets 12/16/24/32 при одинаковых 48 outputs, tile 1024². Static opaque scene: 512 MultiMesh boxes, foreground bars/несколько глубин, четыре SpotLight shared atlas. Borrowed raw color/depth с production snapshot policy, ordinary depth math, 8 iterations, 8×8, rescue off. Viewport timestamps off, quilt profiling on во всех режимах. Три повтора каждого бюджета; порядок циклический: 12/16/24/32, 16/24/32/12, 24/32/12/16. 90 warmup + 240 observed update intervals. GPU quilt mean включает startup и не является whole-frame GPU time.

Отдельный 48-real reference использует тот же shader HDR→gamma transfer. Whole-quilt RGB MAE/PSNR сравнивает одинаковые 48 outputs для всех бюджетов. Synthesized subset приводится отдельно: её состав меняется с anchor count, поэтому сравнивать только её PSNR между бюджетами некорректно. Real anchor pixels обязаны совпасть с reference; иначе quality script отклоняет сравнение. Сохраняются per-view SSE/SAE/changed counts для последующего анализа placement. Round(i*47/(real_count-1)) повторяет uniform anchor choice rig.

Wall/engine ratio>1.5 отмечает аномалии: они не удаляются автоматически. Не следует заявлять speedup по среднему с anomalous run. При повторном измерении сохраняются исходные записи и явно указываются replacement/provenance. Шейдер, scene geometry и output resolution между режимами не меняются.

Это exploration presets, а не реализованный adaptive controller. Real-count setting уже доступен в addon/CLI (`--real=N`). Полученная speed/quality curve относится к одной static scene/GPU; не означает universal preset, perceptual equivalence, temporal quality или physical-display качество. На curved geometry, transparency/particles, motion, other GPUs и native Metal сравнение пока не проведено. Новый engine patch не нужен.


## Measured curve

Apple M4, 48 outputs, 1024², три timing records на бюджет:

| Real cameras | Update interval ms ± run stddev | Whole-quilt PSNR vs 48 real | RGB MAE (8-bit units) |
|---|---:|---:|---:|
| 12 | 33.310 ± 3.490 | 18.521 dB | 5.570 |
| 16 | 37.999 ± 1.765 | 21.782 dB | 2.742 |
| 24 | 47.782 ± 0.128 | 25.768 dB | 1.166 |
| 32 | 58.813 ± 0.207 | 27.778 dB | 0.740 |

Для этой сцены `--real=16` уменьшает mean update interval относительно 24 примерно на 20.47%, но ухудшает whole-quilt PSNR на 3.99 dB. `--real=12` ещё быстрее в среднем (−30.29%), с заметной потерей качества (−7.25 dB) и большим timing spread. `--real=32` повышает PSNR на 2.01 dB, но update interval +23.09%. Это контролируемый tradeoff, не бесплатное ускорение. Выбор preset должен зависеть от содержания и physical-display оценки; defaults не изменены.

PSNR в этой таблице считается по всем 48 одинаковым output views, включая exact real anchors. Ранее 22.757 dB для режима 24 относились только к 24 synthesized tiles; whole quilt здесь 25.768 dB. Эти показатели не противоречат друг другу.

В summary.json сохранена исходная серия, где 12-1 дал wall 131.544 ms при engine delta 31.416 ms. Он исключён только из accepted timing mean. Для режима 12 использованы 12-2,12-3 и отдельный 12-controlled после завершения quality computation. Дополнительный 12-recheck.json/PNG сохранён, но не включён в means, поскольку был запущен параллельно CPU image analysis. Остальные бюджеты используют исходные три runs. Полная provenance: accepted-summary.json. Изображение 12-1 используется только для quality; все real anchors совпали с fresh 48-real reference.

Нормальные profiler durations GPU quilt составляют ~12.6/12.4/11.0/10.1 ms для 12/16/24/32 в initial series; меньше real cameras означает больше synthesis work, но меньше rendering work. Разделение CPU/GPU причин общей экономии не установлено. При уменьшении count не меняются output dimensions или shader quality settings.

Артефакты: per-run JSON/log/PNG, summary.json, accepted-summary.json, quality.json с per-view errors, reference JSON/PNG. Benchmark/native feature API существовали до этого шага; новый adaptive controller и новые shader algorithms не реализованы.
