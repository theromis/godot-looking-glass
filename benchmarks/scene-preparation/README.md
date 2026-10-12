# Измерения подготовки сцены и бюджета ракурсов

Apple M4, patched Godot 4.8-dev, Vulkan/MoltenVK. 512 дополнительных статичных кубов, один общий BoxMesh и материал, одинаковые transforms; исходный движущийся caster, четыре SpotLight. Общие позиционные тени включены во всех режимах. Native Metal, другие GPU и физический Looking Glass здесь не проверены.

```sh
python3 /Users/roman/work/godot-looking-glass/benchmarks/scene-preparation/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 /Users/roman/work/godot-looking-glass/benchmarks/scene-preparation/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --suite synthesis
```

Runner создаёт изолированный project с отключённым tighter caster culling и требует runtime с экспериментальным shared-shadow API. Перед запуском должны быть выполнены импорты основного проекта, как описано в основном README. Не запускайте параллельную GPU-нагрузку. Три повтора каждого режима, 90 warmup + 240 samples. Повторный запуск перезаписывает результаты соответствующего suite.

| Режим | Frame mean, ms | CPU anchor sum, ms | GPU anchor sum, ms |
|---|---:|---:|---:|
| 48 real, отдельные объекты, 128² | 22.447 | 2.480 | 19.767 |
| 48 real, MultiMesh, 128² | 22.594 | 1.332 | 19.916 |
| 48 real, отдельные объекты, 64² | 22.468 | 2.472 | 19.879 |
| 12 real → 48, MultiMesh, 128² | 16.173 | 0.750 | 6.252 |
| 24 real → 48, MultiMesh, 128² | 16.554 | 1.060 | 9.195 |

MultiMesh снижает CPU-подготовку на 46.3%, но FPS-выигрыш не подтверждён. Уменьшение тайла в четыре раза по площади также не даёт ускорения. Godot Forward+ уже применяет automatic instancing для совместимых отдельных поверхностей. Один большой MultiMesh может ухудшить frustum culling; для произвольных сцен нужны пространственные группы.

48-real separate/MultiMesh PNG совпали побайтно. Синтез намеренно меняет изображение: относительно all-real MultiMesh PSNR 16.902 dB для 12 anchors и 21.268 dB для 24. MAE соответственно 0.04414 и 0.02477 (нормированный RGB). Это full-quilt сравнение, которое включает отличие compute gamma от Godot tonemapping, и не доказывает оптическое качество на дисплее.

В этом тесте практический кандидат — 24 реальных ракурса с синтезом: время кадра около 16.55 вместо 22.59 ms (−26.7%), качество выше 12-anchor варианта. Это конфигурация существующего compute pipeline, а не новый алгоритм. Разницу скорости 12/24 не следует считать устойчивой: scheduling и frame pacing могут ограничивать результат.

Суммы CPU/GPU ракурсов не являются critical path всего кадра. Global CPU frame setup записан отдельно; main viewport и quilt исключены из anchor сумм. Frame metric использует engine process delta, не независимый OS wall-clock timer. Данные GPU compute лежат отдельно в individual synthesis JSON и synthesis-summary.json. Все инструментированные режимы опрашивают одинаковые типы счётчиков, но абсолютная стоимость опроса зависит от количества ракурсов.

`summary.json` и `synthesis-summary.json` содержат средние и межпрогонные sample standard deviations. JSON/log/PNG отдельных прогонов сохранены рядом. `quality-12.log` и `quality-24.log` — executed image comparison. `discarded/` содержит первые отклонённые прогоны: параллельная GPU-проверка и лишние samples при ожидании frame_post_draw. Они не входят в итоговые сводки.

Исправления benchmark: `_finish()` отключает `_process` перед ожиданием GPU-кадра; сбор статистики ограничен 240 samples и включается только при наличии `--benchmark`. Обычный preview больше не накапливает arrays со статистикой.
