# GPU pass intervals и накладные расходы timestamps

Diagnostic profiler для Godot RenderingDevice, без нового patch движка. Сцена: 48 real off-axis views 128², 512 одинаковых объектов через MultiMesh и исходный moving caster, четыре SpotLight, shared World3D; Apple M4, Vulkan/MoltenVK, patched Godot 4.8-dev.

```sh
python3 /Users/roman/work/godot-looking-glass/benchmarks/gpu-passes/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 /Users/roman/work/godot-looking-glass/benchmarks/gpu-passes/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --suite overhead
```

Каждый режим повторяется трижды, 90 warmup + 240 samples. Запуски последовательные; исключите постороннюю GPU-нагрузку. Нужны импортированные шейдеры основного проекта и экспериментальный runtime shared shadows. Runner создаёт изолированный project с full caster culling и query pool на 4096 markers. Повторный запуск перезаписывает результаты выбранного suite.

Основной suite:

- `control`: стандартные viewport begin/end timestamps, без подробных pass markers.
- `profile`: `--gpu-profile` перед `--` и `--profile-passes` после него; все pass markers + чтение RenderingDevice на render thread.
- `profile-half-resolution`: тот же profiler, тайлы 64².

Overhead suite:

- `timing-off`: shared shadows, begin/end timestamps выключены через `--no-viewport-timing`.
- `timing-off-independent`: отдельные атласы, timestamps выключены.
- `markers-only`: подробные engine markers без GDScript profiler; отделяет стоимость GPU capture от чтения результатов.

Время кадра измеряется отдельно через `Time.get_ticks_usec` между `_process` вызовами. Это включает scheduling/presentation и не является isolated GPU critical path. Старый engine delta сохранён отдельным полем для сравнения. GPU viewport values равны нулю при выключенных viewport timestamps и не означают нулевую GPU-нагрузку.

Profiler суммирует интервалы между соседними GPU markers, сгруппированные по viewport roles (`anchors`, `quilt`, `main`, `outside_viewports`). Метки начала/конца viewport измеряют полный span; эти spans пересекаются с pass intervals и не должны складываться с ними. Scope boundaries сохранены, чтобы не потерять интервалы. Один raw frame markers сохранён в каждом profile JSON. В исследованном запуске получено 1719 markers/frame и 240 уникальных timestamp frames. Сумма интервалов совпала с общим marker span (проверено).

## Что действительно измеряется

Интервал с именем opaque/transparent/depth/tonemap может включать transitions, barriers и idle time. Он не доказывает стоимость одного shader или отсутствие/наличие draw work. Timestamps меняют GPU command graph и сами имеют заметную стоимость на этом backend. Без vendor GPU capture нельзя считать профилированную разбивку breakdown обычного кадра.

Проверенные source references, Godot base `232e6b14abf6e590b41d60f11704e42de22bff72`:

- `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:2210`, `:2273`, `:2495`, `:2632`: depth, opaque, transparent и tonemap markers.
- `servers/rendering/renderer_viewport.cpp:357`, `:780`: viewport begin/end capture.
- `servers/rendering/storage/utilities.h:167`: RENDER_TIMESTAMP включается через capturing_timestamps.
- `main/main.cpp:1955`, `:3597`: CLI --gpu-profile включает print GPU profile.
- `servers/rendering/rendering_device.cpp:8955`: timestamp capture и лимит query pool; `:9086` и далее — чтение результатов.
- `servers/rendering/rendering_device_graph.cpp:395–406`: timestamp commands добавляют adjacency constraints к другим GPU commands.
- `drivers/vulkan/rendering_device_driver_vulkan.cpp:6894–6896`: vkCmdWriteTimestamp с VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT.

Из этих путей следует наличие дополнительных команд и ограничений порядка. Какая доля overhead вызвана query operations, MoltenVK, очередями или ограничением reorder — не установлено.

В addon `measure_render_time` теперь false по умолчанию. Демо включает его только для benchmark без --no-viewport-timing. Это самостоятельное выключение диагностики в обычном preview, а не изменение render algorithm или общего shadow patch. Quilt и main viewport measurement включает только подробный profiler. Native Metal, другие GPU и физический LKG здесь не проверены.

Итоговые численные результаты — `summary.json` и `overhead-summary.json`; исходные JSON/log/PNG сохранены рядом. Данные первого suite нельзя напрямую использовать для оценки эффекта shared shadows без инструментов: для этого предназначено отдельное сравнение timing-off/timing-off-independent.

## Выполненные результаты

Три прогона на режим. Приведён mean независимого wall-frame таймера; ± — межпрогонное sample standard deviation, не confidence interval.

| Режим | Wall frame ms |
|---|---:|
| Shared, viewport timestamps | 22.533 ± 0.152 |
| Shared, без viewport timestamps | 20.145 ± 0.127 |
| Independent shadows, без timestamps | 28.795 ± 0.224 |
| Все engine markers, без GDScript profiler | 64.161 ± 0.141 |
| Все markers + GDScript profiler | 65.019 ± 1.703 |
| Все markers + profiler, тайлы 64² | 64.429 ± 1.166 |

Отключение begin/end timestamps сокращает frame time на 10.6% в этой сцене. Shared shadows без этих измерений дают −30.0% frame time относительно отдельных атласов. Эти результаты относятся к новой stress scene; они не заменяют старые 32.96 → 21.98 ms из другой сцены.

PNG control/profile/timing-off/timing-off-independent/markers-only совпали побайтно: SHA256 `5c6e10f50008008b5e3c28d9ad17747a2227a5980335166a5aad6b7e552f07ba`. Одинаковое изображение подтверждено для данного workload и не гарантирует корректность на всех сценах.

Полный профилированный marker span: ~65 ms; anchor viewports ~60 ms, quilt ~0.25 ms, main ~0.38 ms. Эти числа относятся к сильно изменённой профилированием нагрузке. Конкретный unprofiled shader bottleneck не установлен. Самый полезный подтверждённый результат — убрать постоянную диагностику из обычного rendering path.

Регрессионные проверки projection/GPU synthesis/Bridge после изменения defaults прошли. Обычный capture-only preview проверен отдельно: без --benchmark статистика не собирается, viewport timestamps выключены.
