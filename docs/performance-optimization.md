# Производительность: измерения и проверяемые гипотезы

## Выполненные измерения

Apple M4, 10 GPU cores, macOS, Godot 4.5.1 official, Forward+, Vulkan 1.2.283/MoltenVK; дополнительно Compatibility/OpenGL. Окно 1152×720, тайлы 128×128, 4 columns, static boxes/thin occluders/shadows, alpha panel по столбцу. 90 кадров прогрева, 240 CPU frame samples. В каждом JSON указаны версия, GPU, драйвер, resolution, transparency и число real views; логи/PNG находятся в [benchmarks](../benchmarks).

| Запуск | Driver | Всего/real | Alpha | Mean frame ms | p95 ms | Σ viewport GPU ms | Quilt compute GPU ms |
|---|---|---|---|---|---|---|---|
| real12 | vulkan | 12/12 | да | 16.573 | 16.667 | 10.891 | — |
| synth12 | vulkan | 12/4 | да | 16.476 | 16.667 | 5.462 | 0.364 |
| real48 | vulkan | 48/48 | нет | 35.817 | 36.310 | 34.759 | — |
| synth48 | vulkan | 48/12 | нет | 16.420 | 16.987 | 10.254 | 0.631 |
| compatibility12 | opengl3 | 12/12 | да | 4.190 | 4.846 | 0.000 | — |

`frame_*` — wall delta `_process`, включает scheduling, engine и preview. `Σ viewport GPU` — сумма engine per-viewport durations; это не GPU critical path и не может безусловно складываться с прочими временами. Capture внутри viewport входит в эту сумму. Quilt compute — отдельные RD timestamps вокруг synthesis+composition, не вокруг всего frame. Текущие compute averages включают timestamp samples периода запуска/прогрева; CPU и viewport averages — после прогрева. В Compatibility GPU metric 0 означает отсутствие пригодного таймера, не бесплатный рендеринг.

На одинаковой opaque/static сцене 48/48 и 48/12 дали 35.817 и 16.420 мс/frame (~2.18× по wall time). Это одиночные последовательные прогоны, не статистически устойчивый результат для любого контента и не сравнение с Unity. Около 16.7 мс виден frame-pacing plateau; VSync setting отключён, но платформенное планирование окна может ограничивать throughput. Сравнение 12/12 и 12/4 не доказывает frame speedup, поскольку оба упираются примерно в этот plateau. Значения до удаления резервного raster quilt сохранены у synth12; более поздний synth48 уже отключает ненужный raster quilt. Это не строгая сравнительная пара 12/12 против 12/4.

Потеря качества существенна: [quality48.json](../benchmarks/quality48.json) сравнивает 36 synthesized tiles со статичным all-real reference: MAE 0.04330 в диапазоне 0–1, PSNR 16.94 dB. В сравнение входит различие gamma/HDR transfer, поэтому это диагностическая RGB-метрика, не оптическое качество. Ракурсы с thin occlusion и disocclusion имеют видимые ошибки; нельзя рекомендовать synthesis preset только по FPS.

Native Metal 3.2 и Forward+ инициализировались, но demo compute run не завершился за более чем 60 секунд; процесс остановлен, результат не подтверждён. Лог `metal-synth12.log` сохранён, JSON/PNG результата нет. Metal backend нельзя считать работающим на основании объявления SDK APIs. Проверенный Apple Silicon compute путь — Vulkan/MoltenVK. Compatibility fallback прошёл и автоматически выбрал все 12 real views; это другой renderer с другой стоимостью и качеством, не доказательство преимущества OpenGL для production.

## Воспроизведение

```sh
GODOT_LG_BIN="/Users/roman/work/tools/Godot.app/Contents/MacOS/Godot"
"$GODOT_LG_BIN" --headless --path /Users/roman/work/godot-looking-glass --editor --import --quit
"$GODOT_LG_BIN" --path /Users/roman/work/godot-looking-glass --rendering-driver vulkan -- --views=48 --tile=128 --static --opaque --benchmark=res://benchmarks/real48.json --capture=res://benchmarks/real48.png
"$GODOT_LG_BIN" --path /Users/roman/work/godot-looking-glass --rendering-driver vulkan -- --views=48 --real=12 --tile=128 --static --opaque --benchmark=res://benchmarks/synth48.json --capture=res://benchmarks/synth48.png
"$GODOT_LG_BIN" --headless --path /Users/roman/work/godot-looking-glass --script res://tests/compare_quilts.gd
```

Запускать последовательно, не параллельно; окно должно оставаться видимым и активным. Capture PNG выполняет разовый CPU readback после измерений. Для устойчивых выводов минимум 5 повторов в перемешанном порядке, одинаковый thermal/power state, одинаковые resolution, shadow/GI/MSAA, а также неограниченный frame pacing/отдельный GPU capture. Исключить первые кадры прогрева для всех GPU-метрик. Здесь полный такой campaign не выполнен.

## Матрица экспериментов

| Оптимизация | Возможная выгода | Цена/риск | Как проверять |
|---|---|---|---|
| VK_KHR_multiview / Vulkan 1.1 groups 2/4/8 | Меньше CPU submissions и повторной подготовки | Raster/vertex work остаётся; hardware caps, view mask 32 bits, union culling overdraw | Identical scene, count и pixels; CPU render-thread, vertex/fragment workload, GPU critical path |
| Shared shadow atlas и union culling | Меньше повторной работы SubViewport | Wider caster coverage, cascade resolution loss, incorrect edge visibility | Directional/spot/point scenes, shadow edges и края view cone |
| Texture arrays | Простая адресация и layer rendering | Memory size/layer limits, lifetime/barriers, geometry pipeline changes | Peak VRAM, bandwidth, GPU copies и per-group timing |
| Compute reprojection | Сокращение real scene draws | Holes, BRDF/reflection mismatch, bandwidth, quality loss | Same-size all-real reference, MAE/PSNR/edge mask/invalid ratio, opaque/alpha отдельно |
| Adaptive anchors | Больше real views в трудных местах | GPU reduction + feedback delay, popping, variable frame cost | Thin fences, depth range, rotating foreground; average/p95 и quality budget |
| Temporal reuse | Меньше real rendering для static regions | Motion vectors/history VRAM, ghosting, cuts | Moving objects, particles, disocclusion и camera teleports; reject/history metrics |
| Depth-aware hole filling | Лучше локальные disocclusions | Дополнительный pass, background smearing | Bounds on fill radius, invalid-before/after, foreground/background edge errors |
| Direct GPU Bridge handoff | Избежать readbacks | External resource exportability, fence/queue stall, copy formats | End-to-end latency, copies, GPU idle, native SDK capture; no CPU image transfer |
| Native Metal/IOSurface | Прямой Apple-native interop | SDK ownership, storage modes, synchronization; текущий запуск не подтверждён | Same scene vs MoltenVK; GPU timers, native output correctness и reconnect |

Не использовать графические features только потому, что они доступны. Для pixel-bound сцен GPU multiview может не дать выигрыша; для CPU-bound множества draw calls он перспективнее. Группы меньшего размера могут уменьшить overdraw и одновременно увеличить submissions.

## Память и копии

Текущий capture выделяет 12 байт/pixel/anchor (RGBA16F + R32F) плюс 8 байт/pixel/target для quilt. Для 24×640×800 sources и 48 targets это 344064000 байт (~328 MiB) только addon textures, без engine viewport attachments, shadows и history. MVP defaults существенно меньше. Production needs device VRAM budgets, downscaled depth, packed formats и pool allocation при смене preset; MSAA resolve и store/load на tile-based GPUs могут стать доминирующими.

В compute MVP source copies существуют: это осознанный безопасный lifetime baseline. Убирать их можно только при доказанном доступе к transient source RIDs до окончания frame и корректных dependencies. Main RD освобождает resources на render thread; submit/sync на main RD не используются. Local RD submit/sync есть только в GPU fixture. Считать вызов dispatch или CPU `_process` временем GPU ошибочно.

## Presets

`quality`: все target views настоящие, transparency и view-dependent shading корректнее; большой render cost. `balanced`: uniform sparse anchors, diagnostic hole ratio, moderate tile size; experimental. `performance`: меньше anchors и resolution; ещё больше occlusion errors. Эти presets — рекомендации по ручным CLI-настройкам числа anchors и resolution; именованные автоматические профили и адаптация сцены пока не реализованы. Публиковать production presets только после hardware и image-quality tests. По умолчанию demo — all-real 12 views.

## CPU-оптимизация addon (11 октября 2026)

Кэшированы neighbour indices, push constants и uniform sets; 240 объектов RDUniform больше не создаются в каждом кадре для 48 output views. Cached sets инвалидируются при смене source texture RIDs. Camera eye offsets также кэшированы, transform setters вызываются только при перемещении/повороте rig. GPU алгоритм и шейдер на этом этапе не менялись.

Три последовательных прогона до и три после, 48/12 views, static opaque, tile 128×128, Apple M4/Vulkan. CPU compute submission после 90 warmup: среднее 0.32686 → 0.02250 ms (−93.1%, экономия ~0.304 ms). Это время CPU отправки команд, не ускорение всего рендера в 14.5 раза. Frame mean 16.671 → 16.590 ms, GPU quilt 0.645 → 0.623 ms; различия GPU/frame находятся около межпрогонного разброса и не доказывают устойчивого улучшения FPS.

Контрольные PNG до/после побайтно одинаковы, SHA-256 `10e8a4445bdb63d80fc6ee6989a237c3e668e404323496885100f8e9a4afc155`. Regression suite прошёл, включая новый тест перемещения rig. JSON, логи и captures: `benchmarks/optimization/before-*`, `after-*`, [summary.json](../benchmarks/optimization/summary.json). Benchmark runner: `python3 benchmarks/optimization/run.py STAGE [TILE_SIZE]`.

## GPU-оптимизация точной сходимости

В `synthesize.glsl` добавлен exact fixed-point early exit. Если повторно прочитанная глубина равна использованной для расчёта UV, следующая UV будет точно такой же; дальнейшие iterations дают тот же результат. При несовпадении выполняется исходный поиск до 8 шагов. Bounds checks, residual threshold, multi-source выбор и fallback не изменены; новый approximate quality threshold не вводился.

Три прогона до и три финальных после, 48 output/12 real views, static opaque, tiles **512×512**, Apple M4/Vulkan. Compute GPU mean: **4.058 → 3.189 ms** (−21.4%, экономия ~0.868 ms). Межпрогонное sample standard deviation: 0.046 и 0.146 ms. Это ускорение synthesis+quilt pass, не всего приложения. Три промежуточных `gpu-after-*` прогона оставлены для прозрачности, но сводка использует `gpu-after-clean-*`, выполненные без одновременно запущенного regression suite.

Frame mean нестабилен: before runs 16.678/16.676/8.153 ms, финальные after 16.232/16.666/15.208 ms. По этим данным **ускорение FPS не подтверждено**; platform pacing/состояние окон влияет на wall metric. Требуется отдельный offscreen/uncapped benchmark для total critical path. Здесь выигрыш подтверждён для отдельного GPU pass по timestamps.

Контрольные PNG побайтно совпали: SHA-256 `fab878ac240682fab0a54913e8306e371de65a573c657bd93892713d73802722`. Сводка: [summary-gpu.json](../benchmarks/optimization/summary-gpu.json). Прежний шейдер сохранён как `benchmarks/optimization/baseline-synthesize.glsl.txt` для воспроизведения A/B после ручной подстановки и повторного import. Итоговый shader, projection/moved-rig checks, analytic GPU checks и Bridge fixture прошли regression suite.


## Эксперимент Godot engine: shared positional shadows

Собран и исполнен отдельный Godot **4.8-dev** runtime на базе `232e6b14abf6e590b41d60f11704e42de22bff72` с opt-in patch. Apple M4, Forward+, Vulkan **1.2.334** через Homebrew MoltenVK. Это другой бинарник/driver setup, поэтому сравнение выполнялось только внутри него, не против предыдущих чисел Godot 4.5.1.

По три чередующиеся пары baseline/shared для каждого view count. Сцена opaque, четыре SpotLight с тенями, движущийся caster с детерминированной rotation по frame number, тайлы 128×128, 90 warmup + 240 измеряемых frames. Tighter caster culling выключен, mesh LOD = 0 в **обоих** режимах. Нормальный addon по-прежнему сохраняет стандартные настройки; benchmark isolation runner создаёт отдельный project.godot.

| Метрика: среднее трёх прогонов | 12 views baseline | 12 views shared | 48 views baseline | 48 views shared |
|---|---:|---:|---:|---:|
| Wall frame mean, ms | 16.581 | 16.675 | 32.964 | 21.983 |
| Сумма viewport GPU durations, ms | 10.658 | 6.460 | 31.890 | 18.913 |
| Shadow draw calls/frame, сумма | 528 | 44 | 2112 | 44 |

Для **48 настоящих видов** wall frame time снизился на **33.3%**, GPU sum — на **40.7%**, shadow draw calls — на **97.9%**. Sample stdev между тремя frame means: 0.187/0.279 ms (baseline/shared); GPU sums: 0.145/0.118 ms. Это выигрыш в конкретной сцене на M4, не общий коэффициент для Looking Glass или сравнение с Unity. При 12 видах wall time не улучшился, несмотря на GPU savings ~39.4%; около 16.7 ms остаётся pacing plateau. Instrumentation и preview входят в wall time. Сумма viewport GPU durations не равна критическому GPU пути кадра.

Контрольные PNG baseline/shared побайтно одинаковы **для обоих view counts**. SHA-256 для 48 views: `9df4ac0e3a7ef7a49371d34f1a5b132e08eb4d7a750e8f27b5b729b9dee4ecbf`. Дополнительный negative image control с выключенными позиционными тенями дал 0 shadow draw calls и **629453 различающихся RGB channels**, MAE 0.002660, PSNR 44.085 dB. Таким образом сцена действительно реагирует на тени. Этот check не заменяет exhaustive quality tests при изменении coverage, allocation и subdivision.

Runtime test с **OmniLight + SpotLight**, тремя viewport и движущимся caster: 12 → 4 shadow draws; несовместимый LOD — 8, частичная mask — 8, цепочка/cycle — 12; после удаления owner — 8. Тест прошёл без render errors. Release-safe проверки явно возвращают exit code 1 при отказе; отдельный negative control со стандартным tighter culling завершился ожидаемо с кодом 1. Регрессионные тесты projection/GPU synthesis/Bridge прошли и на patched 4.8, и на official 4.5.1.

Данные: `benchmarks/engine-shadows/summary.json`, `v48-summary.json`, individual JSON/log/PNG, `test-shared-shadows.log`, `shadow-visibility.log`, `regression-4.8.log`, `regression-4.5.log`. Воспроизведение и ограничения: `engine-patches/README.md`. Directional cascades, union scene culling и native multiview не объединены. Отдельные fallback atlases остаются во владении viewport; снижение VRAM не измерялось.

## Scene preparation после объединения теней

Новый эксперимент: Apple M4, тот же patched Godot 4.8-dev runtime, Vulkan/MoltenVK; 48 настоящих ракурсов 128×128, четыре SpotLight, 512 дополнительных статичных BoxMesh и исходный движущийся caster. Все дополнительные объекты используют одну геометрию и материал в обоих режимах: сравнивается separate MeshInstance3D против одного MultiMeshInstance3D. Общие позиционные тени включены, tighter caster culling отключён, LOD=0. По три чередующихся прогона, 90 warmup + ровно 240 measured samples.

| Режим | Frame mean ms | CPU viewport sum ms | GPU viewport sum ms | Scene draws | Shadow draws |
|---|---:|---:|---:|---:|---:|
| Отдельные instances, 128² | 22.447 | 2.480 | 19.767 | 586 | 78 |
| MultiMesh, 128² | 22.594 | 1.332 | 19.916 | 490 | 48 |
| Отдельные instances, 64² | 22.468 | 2.472 | 19.879 | 586 | 78 |

MultiMesh уменьшает измеренную CPU-подготовку на 46.3%, но не ускоряет весь кадр в этом workload. Уменьшение площади тайла в четыре раза также не даёт ускорения. Эти наблюдения не доказывают конкретный GPU bottleneck: требуются отдельные timestamps проходов и GPU capture. Общий scene culling пока не реализован, его FPS-выигрыш не подтверждён.

Почему исходные 512 объектов не дают 512 draw calls на каждый ракурс: Forward+ уже группирует совместимые поверхности через instancing. В исследованном исходнике `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp:898–900` считает повторения совпадающих surface sort keys, `:608` использует repeat как instance_count, `:627` пропускает повторные элементы списка. Поэтому ручной MultiMesh здесь прежде всего сокращает число объектов при подготовке, а не сотни отдельных draw calls. MultiMesh теряет индивидуальный frustum culling; для большой сцены нужны пространственные группы.

PNG separate/MultiMesh побайтно одинаковы: SHA256 `5c6e10f50008008b5e3c28d9ad17747a2227a5980335166a5aad6b7e552f07ba`. CPU-метрики включают только anchor viewports; global frame setup записывается отдельно. Quilt и main viewport не включены в эти суммы. Время кадра — engine `_process(delta)`, а не независимый OS wall-clock profiler. Все счётчики могут добавлять overhead одинаково в сравниваемых режимах.

При сохранении кадра найден и исправлен дефект benchmark: `_finish()` теперь отключает `_process` до ожидания `frame_post_draw`, чтобы не собирать лишние samples и не двигать caster во время ожидания. Отвергнутые первые прогоны сохранены в `benchmarks/scene-preparation/discarded`; они пересекались с regression GPU test и не входят в сводку.

Данные и воспроизведение: `benchmarks/scene-preparation/summary.json`, individual JSON/log/PNG, `run.py`.

На той же сцене отдельно выполнены три чередующихся прогона 12/24 real → 48 output с MultiMesh. Frame mean: 16.173 / 16.554 ms против 22.594 ms all-real MultiMesh. CPU anchor sum: 0.750 / 1.060 ms; GPU anchor sum: 6.252 / 9.195 ms. Full-quilt PSNR относительно all-real: 16.902 / 21.268 dB, MAE: 0.04414 / 0.02477; includes gamma/tonemapping mismatch. Для этого workload 24 anchors — более разумный кандидат по качеству при близком времени кадра. Новое адаптивное размещение anchors не реализовано. Synthesis timing запускался отдельно после завершения instances suite; GPU regression tests не выполнялись одновременно.

В обычном preview сбор benchmark samples теперь отключён. Это предотвращает постоянные queries и неограниченное накопление arrays; отдельное ускорение FPS от этого изменения не измерено.

## Влияние GPU timestamps на измеряемую нагрузку

Выполнен отдельный GPU pass diagnostic через встроенные Godot markers и RenderingDevice, без нового engine patch. Новая stress scene: 48 real, 128², 512 MultiMesh boxes и moving caster, четыре SpotLight; Apple M4/Vulkan/MoltenVK, три повтора на режим. Время кадра теперь дополнительно измеряется по Time.get_ticks_usec, независимо от engine process delta.

Shared с viewport timestamps: 22.533 ms wall frame; shared без timestamps: 20.145 ms (−10.6%); independent atlas без timestamps: 28.795 ms. Shared atlas сохраняет выигрыш ~30.0% и без viewport timings. PNG всех полноразмерных режимов побайтно одинаковы. Это другая сцена относительно исходного engine-shadow benchmark, не переоценка его чисел.

Подробные engine markers увеличили frame time до 64.161 ms даже без GDScript collector; с collector 65.019 ms. Поэтому профиль с 1719 markers/frame нельзя считать breakdown обычного 20 ms кадра. Native timestamps сами меняют GPU workload: RenderingDeviceGraph::_add_command_to_graph, rendering_device_graph.cpp:395–406 добавляет adjacency constraints; Vulkan driver command_timestamp_write, rendering_device_driver_vulkan.cpp:6894–6896 использует vkCmdWriteTimestamp с BOTTOM_OF_PIPE. Разделение overhead между query operations, driver/MoltenVK и graph reorder не установлено.

В rig `measure_render_time=false` по умолчанию, demo включает его только для benchmark без --no-viewport-timing. Подробный diagnostic требует --gpu-profile перед -- и --profile-passes после --; query pool изолированного benchmark увеличен до 4096. Quilt/main отдельно измеряются только в этом diagnostic. Интервалы могут включать barriers/transitions/idle. GPU values 0 при выключенном timing означают отсутствие измерения.

Исходные JSON/log/PNG, raw markers одного frame, mean/stddev и команды: benchmarks/gpu-passes/README.md, summary.json, overhead-summary.json. Регрессионные тесты прошли после отключения постоянных viewport measurements. Для дальнейшего анализа необходим низкоинвазивный GPU capture; стоимость конкретного shader pass обычного кадра пока не доказана.

## Устранение собственной HDR color copy

Добавлен opt-in borrow_source_color / --borrow-color. В POST_TRANSPARENT capture HDR color RID Godot используется непосредственно; новый capture_depth.glsl сохраняет только линейную R32F depth. Собственная RGBA16F color texture не создаётся, imageStore color и texelFetch color в capture исключены. Compute depth pass остаётся; это сокращение copies/traffic, не устранение всех capture dispatches. Default — copy.

Apple M4/Vulkan, тот же patched Godot 4.8 runtime, shared shadows в обоих режимах, viewport timestamps выключены. Dynamic stress scene 512²: 48 output/24 real, три прогона copy/borrow, 90 warmup + 240 process samples, по 330 compute dispatches. Wall frame 16.712 / 16.643 ms: FPS-выигрыш не подтверждён; PNG exact, eliminated texture payload 48 MiB.

Static stress scene 1024²: samples по successful quilt updates, по три прогона, 90 warmup + 240 samples. Wall interval 52.205 ± 0.057 → 49.656 ± 0.121 ms, −4.88%. Это интервал обновления quilt с scheduling/presentation, не GPU-only duration. PNG exact, eliminated texture payload 192 MiB (24×1024²×8 bytes). Общая VRAM/residency не измерена. Quilt compute mean 12.253 / 12.359 ms не показывает ускорения самого synthesis pass; выигрыш конфигурации от устранения color copy находится вне него.

Два режима имеют разные сцены dynamic/static и способы sampling, их нельзя использовать как единую scaling curve. Непрошедший process-call 1024² run сохранён отдельно: 330 process calls / 199 dispatches; из него performance conclusion не делается. Первые shader-copy прогоны с нулевыми dispatches также сохранены как discarded (ошибка типизации нового массива, исправлена). Новый runner отвергает отсутствие compute work/GPU samples и неполную выборку.

Тест реальных copy/borrow quilt требует непустой результат и увеличение dispatch_count, сравнивает float quilt при source sizes 64/48/80, проверяет double release и сохранность engine-owned color. Все четыре regression checks выполнены на official 4.5.1 и patched 4.8. Capture сохраняет owner ref, обновляет borrowed RID на каждом callback, не освобождает engine-owned RID. Borrowed mode не проверен при TAA/FSR2/MSAA/glow/других post-transparent effects; эти проходы могут изменить color после snapshot point, default copy оставлен.

Код: addons/looking_glass/capture.gd, shaders/capture_depth.glsl, rig.gd; тест tests/test_capture_lifetime.gd. Источники данных и команды: benchmarks/borrow-color/README.md, summary.json, rendered1024/summary.json. Изменений Godot engine для этой оптимизации нет.


## Удаление промежуточной depth copy

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, повторная серия `recheck1024/summary.json`: три пары, 240 наблюдаемых интервалов после 90 warmup на прогон. Linear-depth copy: 50.903 ± 0.997 ms; direct depth: 48.688 ± 0.934 ms (stddev между средними прогонов), изменение -4.35%. GPU synthesis+quilt: 12.539 → 11.094 ms (-11.52%). GPU среднее включает startup samples и не измеряет capture отдельно. CPU submission ~0.070 ms в обоих режимах. Каждая из шести записей имеет не менее 330 dispatches; saved PNG первой пары совпали побайтно, SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`.

Начальная серия `rendered1024/` сохранена для аудита: linear-3 дал wall 155.75 ms при engine delta 51.70 ms. Причина не установлена; wall mean этой серии не используется для speedup claim. Повторная серия использует неизменённый код и настройки. Значения нельзя складывать с выигрышем color-copy из отдельной серии. На 512² новый depth path пока не измерен.

Реализация: capture.gd, synthesize_raw_depth.glsl, synthesizer.gd; opt-in `--borrow-depth` также включает borrowed color. Устранён дополнительный 96 MiB R32F payload, не измерение total VRAM. Lifetime/resize/equivalence tests прошли на 4.5.1 и 4.8. TAA/FSR2/MSAA/post effects и физический дисплей не проверены. Методика: benchmarks/borrow-depth/README.md.


## Проверка размеров compute-групп


## Результаты Apple M4

Три повтора каждого варианта, 24 → 48 views, tile 1024². GPU synthesis+quilt (mean ± stddev между средними прогонов):

| Local size | GPU ms | Изменение относительно 8×8 |
|---|---:|---:|
| 8×8 | 11.179 ± 0.127 | baseline |
| 16×8 | 11.470 ± 0.043 | +2.61% |
| 16×16 | 11.270 ± 0.257 | +0.82% |

Вывод: ускорение большими группами не подтверждено; default 8×8 сохранён. 16×16 находится близко к baseline с перекрывающимся разбросом. Нельзя заключить, что эти результаты действуют для других GPU или сцен.

Wall mean: 8×8 49.152 ms, 16×8 49.331 ms. В 16×16-1 wall оказался 96.796 ms при engine delta 47.351 ms; причина неизвестна. Все данные сохранены, аномалия отмечена в summary.json. Mean wall 16×16 нельзя использовать для заявления о замедлении kernel. Повторять серию ради поиска выигрышного результата не требуется: GPU-интервал не показывает ожидаемого ускорения.

Все девять прогонов валидны по dispatch/sample count, saved PNG первой тройки совпали SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Данные: rendered1024/summary.json, отдельные JSON/log/PNG. Default не изменён; selector оставлен для измерений на других GPU.

Методика: benchmarks/workgroups/README.md.


## Предел reprojection iterations


## Измеренный результат

Apple M4, три повтора:

| Iterations | GPU quilt ms (mean ± run stddev) | Update interval ms | Changed synthesized pixels vs 8 | PSNR vs 48 real views |
|---|---:|---:|---:|---:|
| 8 | 11.005 ± 0.053 | 48.029 | baseline | 22.757 dB |
| 4 | 10.775 ± 0.069 | 47.770 | 0.01197% | 22.757 dB |
| 2 | 10.726 ± 0.032 | 47.723 | 0.34439% | 22.619 dB |

4 уменьшает GPU interval на 2.09%, update interval на 0.54%. 2 уменьшает GPU interval на 2.54%, update interval на 0.64%. Это малый выигрыш в конкретной сцене, не существенное универсальное FPS ускорение. 4 не является exact replacement: saved PNG отличаются, хотя aggregate error мал. PSNR vs 8: 52.920 dB для 4 и 36.971 dB для 2. Пиксели всех настоящих anchors совпали точно между вариантами и independent 48-real reference. Wall/engine ratio >1.5 в этой серии не обнаружен.

8 baseline также отличается от all-real: synthesized PSNR 22.757 dB; дальнейшее улучшение качества должно работать с visibility/disocclusions, а не считать 8-loop output ground truth. Причины всех конкретных ошибок отдельно не локализованы.

Default 8 сохранён. `--iterations=4` — optional quality/performance tradeoff; `--iterations=2` — более агрессивный эксперимент. Скорость других сцен, temporal stability и curved geometry не измерены. Данные: rendered1024/summary.json, quality.json и reference JSON/PNG. Ничего не пушилось; engine code не изменён.

Методика: benchmarks/iterations/README.md.


## Измеренные результаты

Apple M4, Godot 4.8-dev/Vulkan-MoltenVK, 24 → 48, 1024², три пары:

- GPU synthesis+quilt: baseline 10.997 ± 0.033 ms → rescue 11.364 ± 0.021 ms, +3.34%. Stddev между средними трёх прогонов.
- Observed update interval: 48.019 ± 0.184 → 48.188 ± 0.057 ms, +0.35%. Ускорения нет.
- Invalid two-source correspondences: 681614 → 667752 из 25165824 synthesized pixels. Восстановлены 13862 (2.03% исходной invalid mask); новых дыр нет.
- На recovered mask PSNR относительно all-real: 6.928 → 18.624 dB. Overall synthesized PSNR: 22.757 → 22.843 dB, RGB MAE 2.332 → 2.292 в 8-bit units.
- Real anchors exact, changed pixels outside baseline hole mask = 0. Baseline PNG SHA совпадает с предыдущим 8-iteration benchmark.

Вывод: небольшой измеренный quality improvement, дополнительная GPU стоимость. Opt-in `--rescue`, default false. Это ограниченный correspondence search; нельзя считать устранёнными все disocclusions. Статическая проверка не устанавливает отсутствие temporal flicker/foreground bleeding в других сценах. Все исходные JSON/log/PNG сохранены, wall anomalies по проверке ratio>1.5 не обнаружены.

Восемь regression checks прошли на 4.5.1 и 4.8: projection, planar 8/2/4, synthetic recoverable depth-layer case на linear и reverse-Z depth, capture/workgroup lifetime, Bridge fixture. Synthetic case имеет source depth 2/3/6 на соседних полосах, где baseline зацикливается 2↔6, а дополнительная гипотеза 3 возвращает аналитически известный source pixel. Generated rescue workgroup/iteration combinations не все отдельно прогонялись; performance и quality измерены на 8×8/8.

Методика: benchmarks/disocclusion/README.md.


## Borrowed-buffer compatibility fallback

Проверены 15 renderer configurations на Apple M4/Vulkan, Godot 4.5.1 и 4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, дополнительный compositor, reset. Финальная матрица сравнивает три capture modes и raw RGBAH quilt: default copy, borrowed color, borrowed color+depth. Все результаты exact с production policy, все девять regression checks прошли на обеих версиях.

Direct color без fallback отличается при TAA и другом color-modifying POST_TRANSPARENT effect после capture. Capture автоматически переключает color/depth на собственный snapshot при TAA или любом дополнительном enabled compositor effect и возвращает direct access после снятия blocker. Raw-depth fallback копирует reverse-Z в R32F, сохраняя interpretation synthesis shader. Descriptor cache обновляется по RID; освобождаются только собственные textures. WeakRef на compositor не создаёт ownership cycle.

MSAA, FXAA, FSR1/FSR2, scaling, glow и tonemap сохранили equivalence в проверенных configurations. Это equivalence POST_TRANSPARENT snapshot: финальная TAA/FSR2/glow/tonemap output не включается в quilt, jitter compensation и dynamic quality ещё не проверены. Тест использует manual draw и sync только для проверки, не benchmark. Скорость новой policy отдельно не измерялась. Demo report теперь содержит effective borrow counts, fallback reasons и owned payload по фактическим dimensions.

Первый FSR2 probe на internal 48² вызвал engine uavMip errors, результат rejected. На internal 128² повтор выполнен без errors; engine issue не исправлен и minimum supported size не установлен. Native Metal, другие GPU, physical Looking Glass и motion/particles/transparency остаются непроверенными. Подробные команды и JSON/log: benchmarks/buffer-compat/README.md.


## Optional bounded quilt profiling


## Measured result

Apple M4 / Godot 4.8-dev / Vulkan-MoltenVK, 24 real → 48 output, 1024², три пары:

| Quilt profiling | Observed update interval ms | Run stddev ms | Recorded GPU/CPU samples |
|---|---:|---:|---|
| on | 47.6166 | 0.0835 | 327 GPU / 240 CPU per run |
| off | 47.6215 | 0.0460 | 0 / 0 |

Выигрыш времени обновления не подтверждён: разница +0.0049 ms меньше разброса. Каждый прогон имеет 240 measured samples и 331 dispatches. On-mode отправил 331 marker pairs; off-mode 0. Off-mode GPU/CPU submission durations null, а не нулевое время работы. Saved PNG первой пары exact SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Wall/engine ratio>1.5 anomalies не обнаружены.

Default profiling off устраняет ненужную инструментальную работу и постоянное накопление samples в ordinary preview; этот результат не означает FPS ускорения на данной сцене. В profiling mode bounded ring test с limit=4 подтвердил сохранение ровно четырёх GPU/CPU samples после не менее 140 actual quilt updates и exact output на движущемся объекте.

Данные: rendered1024/summary.json, per-run JSON/log/PNG, checks-4.5/4.8.log. Предыдущие viewport timestamps измерения (+1719 native markers) относятся к другой нагрузке и не складываются с этим on/off результатом.

Методика: benchmarks/quilt-profiling/README.md.


## Результат

В повторной серии три пары Apple M4 / 24 real → 48 output / 1024²:

| Arithmetic | GPU quilt ms, mean ± run stddev | Observed update interval ms, mean ± run stddev |
|---|---:|---:|
| Ordinary | 11.346 ± 0.238 | 49.646 ± 1.131 |
| Inverse depth | 11.316 ± 0.290 | 49.173 ± 1.002 |

Разницы GPU и update interval меньше межпрогонного разброса; устойчивый speedup не установлен. Source-level сокращение делений само по себе не доказывает снижение GPU стоимости; actual shader compiler output/причина результата не исследованы. Default ordinary shader сохранён, inverse mode opt-in.

Численное качество: 0.017019% synthesized pixels изменились vs baseline; RGB MAE 0.0000831 в 8-bit units, PSNR 88.875 dB vs baseline. PSNR vs fresh 48-real: ordinary 22.75720885 / inverse 22.75720883 dB. Real anchors exact. Это PNG RGB, не HDR identity и не perceptual/temporal guarantee.

Initial `rendered1024/` baseline process timed out after 180 s без valid JSON/PNG; результат не включён. Причина timeout не установлена. Smoke tests ordinary на official 4.5.1 и inverse на custom 4.8 выполнили по 331 dispatches. Fresh повторная серия `recheck1024/` завершилась, wall/engine ratio>1.5 anomalies отсутствуют; все шесть records имеют 240 samples и >=330 dispatches.

Все 13 regression checks прошли на 4.5.1 и 4.8. Shader variants с другими groups/iterations и dynamic inverse-depth quality не все проверены; default не изменён. Данные: recheck1024/summary.json, quality.json, reference JSON/PNG, per-run JSON/log/PNG и checks-4.5/4.8.log.

Методика: benchmarks/inverse-depth/README.md.


## Real-view budget curve


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

Методика: benchmarks/view-budget/README.md.


## Nonuniform anchors: measured negative result

Added optional strictly increasing `custom_anchor_indices` (demo `--anchors=`), with validation and effective anchor telemetry. An offline selection of 24 cameras from the previous 16-view RGB errors worsened whole-quilt PSNR from 25.768 to 24.088 dB and increased squared error 47.21%; observed quilt-update intervals 48.317±0.425 versus 48.204±0.090 ms do not establish acceleration. Uniform remains the default; no runtime adaptive controller is implemented. See [benchmark details](../benchmarks/anchor-placement/README.md).


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](../benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](../benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](../benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](../benchmarks/depth-overhead/README.md).


## Compact GPU depth feedback

GPU reduction of the optional depth diagnostic now returns 768 bytes instead of 786,432 bytes for 48 views at 256². On current Godot 4.8-dev / Apple M4, three repeated async experiments reduced CPU decoding from 20.499±1.021 to 0.306±0.009 ms per callback (about 67×). Isolated GPU scopes 1.371±0.021 versus 1.365±0.043 ms show no measurable extra GPU cost; quilt update intervals remain 48.27 ms and callback latency about 97 ms. GPU totals match CPU sums exactly, all output PNGs match byte-for-byte, and all 15 regression checks pass. This reduces diagnostic CPU work, with no established FPS gain. Uniform view selection and addon defaults remain unchanged. See [implementation, measurements and reproduction](../benchmarks/depth-reduction/README.md).


## Статичный quilt по запросу

Добавлен опциональный `update_on_demand` для compute quilt: ракурсы рендерятся и quilt собирается только при `request_update()`. Движение rig запрашивает обновление автоматически; изменения объектов, света, материалов и окружения приложение сообщает явно. На последнем Godot 4.8-dev / Apple M4, в трёх парах статичной сцены 24→48 с 1024² тайлами, интервал между process/presentation кадрами снизился с 47.408±0.296 до 16.535±0.121 мс. После прогрева сохранившийся quilt побитно совпал с continuous reference. В idle повторных source captures и compute dispatches нет; окно продолжает показывать сохранённую текстуру. Это экономия статичного режима, а не ускорение генерации новых ракурсов анимации. Самый первый кадр большой сцены отличался на 76 RGBA-компонентов с максимальной разницей 1/255; benchmark поэтому явно обновляет quilt перед измеряемым idle. Причина стартовой разницы не установлена, автоматический прогрев не реализован. Режим выключен по умолчанию и не меняет engine fork. См. [API, ограничения и измерения](../benchmarks/on-demand/README.md).
