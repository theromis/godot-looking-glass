# Прямое чтение depth: A/B benchmark

Экспериментальный `--borrow-depth` также включает `--borrow-color`. Capture сохраняет ссылки на RenderSceneBuffersRD и исходные color/depth RID, обновляет их каждый callback и не освобождает engine-owned текстуры. Отдельный capture compute pass отсутствует. Synthesis преобразует reverse-Z depth в linear depth при каждом чтении; обычный shader и default copy path сохранены.

```sh
python3 benchmarks/borrow-depth/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/borrow-depth/rendered1024
```

Оба режима читают borrowed HDR color. `linear` копирует depth в собственную R32F texture; `raw` читает исходную depth. Статическая сцена: 512 MultiMesh boxes, четыре SpotLight, общий shadow atlas, 24 real → 48 output. Три пары с чередованием порядка. 90 warmup + 240 observed quilt update intervals. Проверяются dispatch count, timestamp samples, runtime errors и PNG SHA256.

Для 24 источников 1024² устраняется 96 MiB собственного R32F payload; это расчёт выделения текстур, не измерение общего VRAM. Цена — повторное преобразование глубины в iterative gather. Quilt GPU time не включает capture; по нему отдельно нельзя заключить об общей скорости.

Ограничения: Forward+ Vulkan/MoltenVK; TAA/FSR2/MSAA/post effects и физическое устройство не проверены. Тест lifetime проверяет exact raw quilt при размерах источников 64/48/80, продолжающиеся dispatches, отсутствие пустого изображения и сохранность обоих borrowed RID после двойного release. Прямая depth имеет те же открытые вопросы lifetime и последующих изменений буферов, что direct color (#15633).


## Измеренные результаты

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, повторная серия `recheck1024/summary.json`: три пары, 240 наблюдаемых интервалов после 90 warmup на прогон. Linear-depth copy: 50.903 ± 0.997 ms; direct depth: 48.688 ± 0.934 ms (stddev между средними прогонов), изменение -4.35%. GPU synthesis+quilt: 12.539 → 11.094 ms (-11.52%). GPU среднее включает startup samples и не измеряет capture отдельно. CPU submission ~0.070 ms в обоих режимах. Каждая из шести записей имеет не менее 330 dispatches; saved PNG первой пары совпали побайтно, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`.

Начальная серия `rendered1024/` сохранена для аудита: linear-3 дал wall 155.75 ms при engine delta 51.70 ms. Причина не установлена; wall mean этой серии не используется для speedup claim. Повторная серия использует неизменённый код и настройки. Значения нельзя складывать с выигрышем color-copy из отдельной серии. На 512² новый depth path пока не измерен.
