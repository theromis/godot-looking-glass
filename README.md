# Looking Glass Godot Lab

Самостоятельный исследовательский Godot 4 addon и демо: off-axis камеры, GPU quilt preview, экспериментальный GPU depth synthesis и Bridge detection. Код Unity/Looking Glass и SDK binaries в проект не перенесены.

Проверено исполнением на Godot 4.5.1, Apple M4, Vulkan Forward+ через MoltenVK. Проект находится в `/Users/roman/work/godot-looking-glass`; исходники движка пользователя `/Users/roman/work/godot` (4.8-dev) исследованы; добавлен отключаемый экспериментальный patch общих позиционных теней (см. `engine-patches/README.md`). Запуск на физическом Looking Glass не подтверждён: Bridge возвращает 0 калиброванных LKG устройств. Native GPU texture submit в Bridge ещё не реализован.

## Запуск

Откройте `project.godot` в Godot 4.5+ и нажмите F6/F5. По умолчанию 12 настоящих видов и quilt preview, оборудование не нужно. Первый import шейдеров обязателен перед command-line запуском.

```sh
GODOT_LG_BIN="/Users/roman/work/tools/Godot.app/Contents/MacOS/Godot"
"$GODOT_LG_BIN" --headless --path /Users/roman/work/godot-looking-glass --editor --import --quit
"$GODOT_LG_BIN" --path /Users/roman/work/godot-looking-glass --rendering-driver vulkan
# 12 output views, 4 real: экспериментальный compute
"$GODOT_LG_BIN" --path /Users/roman/work/godot-looking-glass --rendering-driver vulkan -- --views=12 --real=4 --tile=128
# Bridge device detection, без native optical output
"$GODOT_LG_BIN" --path /Users/roman/work/godot-looking-glass --rendering-driver vulkan -- --bridge
```

Аргументы после `--`: `--borrow-color` (экспериментально читать исходный HDR color без копии), `--rendered-benchmark` (samples по quilt updates; для сопоставимых captures используйте --static), `--objects=N` (0–4096 дополнительных одинаковых объектов), `--batch-objects` (объединить их в MultiMesh), `--no-viewport-timing` (benchmark без viewport timestamps), `--profile-passes` (подробные интервалы; нужен engine flag `--gpu-profile` перед `--`), `--views=N` (1–48), `--real=N` (включает synthesis; endpoints всегда real), `--tile=N` (square tile), `--static`, `--opaque`, `--positional-lights=N`, `--no-positional-shadows`, `--fixed-motion`, `--no-mesh-lod`, `--shared-shadows`, `--bridge`, `--calibration=/absolute/path/visual.json`, `--benchmark=res://benchmarks/run.json`, `--capture=res://benchmarks/run.png`. Без `--tile` тайлы 192×256. CLI сначала применяет views, затем real; используйте этот порядок. Перед запуском arbitrary scenes сконфигурируйте exports в `rig.gd`: cone/FOV/focus/near/far/grid/resolution. Для runtime смены конфигурации пересоздайте rig.

## Встраивание addon

Скопируйте только `addons/looking_glass` в свой Godot 4.5+ проект. Включение editor plugin в Project Settings → Plugins даёт тип LookingGlassRig. Можно создать rig из скрипта, установить параметры до add_child, расположить локальную ось -Z в сторону сцены. Фокусная плоскость находится на `focus_distance` впереди rig. Назначьте `rig.quilt_texture` своему TextureRect. Rig поддерживает перемещение/поворот; scale и нестандартные projection modes отдельно не поддержаны. Храните WorldEnvironment/scene в shared World3D.

All-real quilt собирается GPU Canvas draws. Compute использует CompositorEffect и main RenderingDevice. Compatibility renderer переключается на все настоящие виды. Постоянных CPU readbacks нет; сохранение PNG и GPU unit test делают разовое считывание.

## Статус функций

| Функция | Статус |
|---|---|
| Off-axis 1–48 views, non-square projection | Реализована, тест прошёл |
| GPU raster quilt, preview без LKG | Выполнено на Vulkan и Compatibility |
| GPU color/depth capture и two-source compute synthesis | Выполнено на Vulkan; экспериментально, есть occlusion/alpha artifacts |
| GPU timestamps / wall frame benchmarks / PNG captures | Выполнено; исходные результаты в benchmarks |
| Bridge orchestration, device detection, calibration geometry | Fixture и реальный Bridge проверены; 0 calibrated devices |
| Native Bridge GPU texture handoff / lenticular display output | Не реализовано |
| Adaptive anchors / temporal motion vectors / depth-aware hole fill | Архитектура и roadmap; не реализовано |
| Shared positional shadows (optional engine patch) | Исполнено на 4.8-dev; Omni/Spot, safe fallback; условия в engine-patches |
| Engine multiview backend | Исследован 4.8-dev source; не реализован |
| Native Metal demo | Инициализировался, затем не завершился; поддержка не подтверждена |

В качестве reference используйте all-real. Synthesis не восстанавливает hidden geometry; прозрачные поверхности не представлены в opaque depth, поэтому RGB/depth mismatch даёт ошибки. В compute-preview простая gamma, не полный Godot tone mapping. Оптическую калибровку native backend должен применить отдельно.

## Проверки и измерения

```sh
python3 /Users/roman/work/godot-looking-glass/tests/run_checks.py --godot /Users/roman/work/tools/Godot.app/Contents/MacOS/Godot
```

Suite проверяет focal plane, FOV, near/far disparity, 1/2/12/47/48 quilt dimensions, GPU analytic planar synthesis с двумя знаками смещения и Bridge HTTP fixture на порту 33335. Fixture автоматически останавливается; этот порт должен быть свободен. GPU test требует оконного Vulkan renderer. Логи содержат PASS; runner отклоняет ошибки даже если Godot вернул код 0.

На одной opaque static сцене 48 output/48 real: 35.817 ms/frame; 48 output/12 real: 16.420 ms/frame, quilt compute 0.631 ms GPU. Тайлы 128×128, 90 warmup + 240 frame samples. Это один локальный тест с потерей качества, не универсальный speedup. PSNR synthesized tiles против all-real 16.94 dB; includes transfer-function difference. См. [методику и ограничения](docs/performance-optimization.md).

## Документы

- [unity-plugin-analysis.md](docs/unity-plugin-analysis.md): download provenance, инвентарь, лицензии, source paths/classes/functions/lines, verified findings и hypotheses.
- [godot-architecture.md](docs/godot-architecture.md): варианты A–D, текущий pipeline, multiview ограничения движка и native interop.
- [performance-optimization.md](docs/performance-optimization.md): измеренные данные, tradeoffs и план benchmark campaign.
- [implementation-roadmap.md](docs/implementation-roadmap.md): выполненное, следующие этапы и критерии готовности.

Официальный архив/reference находится отдельно в `/Users/roman/work/looking-glass-reference`. Не включайте его в open-source release этого addon. Новый код лицензирован MIT; external reference implementations и установленные runtime libraries остаются под своими лицензиями. Исследование не является разрешением на копирование proprietary source.

После CPU-оптимизации (3 прогона до/после) отправка compute-команд занимает 0.0225 вместо 0.327 ms; контрольный quilt побайтно совпал. Существенное ускорение всей сцены этим изменением не установлено. Данные: `benchmarks/optimization/summary.json`.

GPU-проход synthesis+quilt дополнительно ускорен с 4.058 до 3.189 ms (−21.4%) на тайлах 512×512, 48 output/12 real views; три прогона до и после, PNG побайтно одинаковы. Рост FPS не подтверждён из-за нестабильного frame pacing. Сводка: `benchmarks/optimization/summary-gpu.json`.


Опциональный engine backend проверен на Godot 4.8-dev: общий atlas теней Omni/Spot. В сцене с 48 настоящими видами и четырьмя SpotLight время кадра снизилось с 32.964 до 21.983 ms (−33.3%, три пары прогонов, Apple M4); контрольный PNG идентичен. При 12 видах ускорение всей сцены не подтверждено. По умолчанию backend выключен; условия, сборка и fallback описаны в [engine-patches/README.md](engine-patches/README.md). Native multiview и общие directional shadows ещё не реализованы.

Дополнительная проверка scene preparation: 512 одинаковых объектов, 48 настоящих ракурсов, общий atlas. MultiMesh снизил сумму CPU-времени ракурсов с 2.480 до 1.332 ms (−46.3%), но время кадра осталось около 22.5 ms; ускорение FPS не подтверждено. PNG двух вариантов совпали побайтно. Методика и исходные данные: [benchmarks/scene-preparation/README.md](benchmarks/scene-preparation/README.md).

Измерение времени отдельных viewport теперь отключено по умолчанию в addon (`measure_render_time=false`) и включается демо для benchmark. Подробный GPU profiler — опциональный: [benchmarks/gpu-passes/README.md](benchmarks/gpu-passes/README.md). Timestamps заметно меняют нагрузку на Apple M4/MoltenVK; результаты профилирования нужно сравнивать с контрольным режимом.

На Apple M4/Vulkan в stress scene с 48 real views отключение viewport timestamps уменьшило wall frame time с 22.533 до 20.145 ms (−10.6%, три прогона каждого режима); PNG одинаковы. Подробные engine GPU markers оказались дорогими (~64 ms/frame), поэтому они предназначены для диагностики с обязательным control. Общие тени без viewport timings также проверены: 28.795 → 20.145 ms в этой stress scene.

Новый экспериментальный путь `--borrow-color` устраняет промежуточную HDR color copy, сохраняя собственную linear depth texture. На Apple M4, 24 real → 48 output, тайлы 1024², время обновления quilt снизилось с 52.205 до 49.656 ms (−4.88%, три прогона), PNG совпали побайтно; устранён 192 MiB texture payload. На 512² FPS-выигрыш не подтверждён, устранён 48 MiB payload. Это изменение addon, новый engine patch не требуется. Default copy path сохранён; TAA/FSR2/MSAA/post effects с borrowed input не проверены. [Методика и ограничения](benchmarks/borrow-color/README.md).


Экспериментальный `--borrow-depth` включает также direct HDR color и исключает отдельный захват/линеаризацию depth. `borrow_source_depth=false` по умолчанию. Raw reverse-Z преобразуется в linear depth внутри gather; для 24 источников 1024² устраняется 96 MiB собственной R32F texture allocation. Это calculated payload, не total VRAM. Тесты resize/ownership/exact quilt прошли на Godot 4.5.1 и экспериментальном 4.8. TAA/FSR2/MSAA/post effects не проверены; семантика использования engine-owned буферов после callback требует подтверждения. Команды и результаты: [benchmarks/borrow-depth/README.md](benchmarks/borrow-depth/README.md).

В повторной серии 24 real → 48 output, 1024²: direct depth снизил наблюдаемый update interval 50.90 → 48.69 ms (-4.35%, три пары). GPU synthesis+quilt 12.54 → 11.09 ms; PNG одинаковы. [Результаты и нестабильная первая серия](benchmarks/borrow-depth/README.md).

Проверены compute workgroups 8×8 / 16×8 / 16×16: GPU quilt 11.179 / 11.470 / 11.270 ms на M4, три повтора. Ускорение не подтверждено; default 8×8 сохранён. Selector `--workgroup=16x8` или `--workgroup=16x16` доступен для других GPU. [Данные и ограничения](benchmarks/workgroups/README.md).

Опциональный `--iterations=4` сокращает GPU synthesis+quilt 11.005 → 10.775 ms (−2.09%) в M4 benchmark; update interval 48.029 → 47.770 ms (−0.54%). Изменились 0.01197% synthesized pixels vs 8; exact equivalence нет. Default 8 сохранён, `--iterations=2` экспериментален. [Скорость и сравнение с 48 настоящими видами](benchmarks/iterations/README.md).

Экспериментальный `--rescue` восстанавливает часть невалидных depth correspondences, проверяя ±1/±2/±4 source texel гипотезы для того же target pixel. На M4 восстановлено 2.03% invalid mask, synthesized PSNR 22.757 → 22.843 dB; GPU quilt 10.997 → 11.364 ms. Ускорения нет, default off. [Результаты и ограничения](benchmarks/disocclusion/README.md).

Borrowed-buffer policy теперь автоматически возвращается к snapshot copy при TAA и дополнительных enabled compositor effects. 15 configurations × 3 capture modes проверены на 4.5.1 и 4.8; exact quilt с policy, включая reset и render scale transitions. MSAA/FXAA/FSR1/FSR2/glow/tonemap совпали в статической матрице. Quilt остаётся pre-postprocessing HDR; dynamic/jitter quality не подтверждено. [Матрица и ограничения](benchmarks/buffer-compat/README.md).

Quilt profiling выключено по умолчанию (`profile_synthesis=false`); benchmark включает его явно. --no-quilt-timing отключает measurement в benchmark. GPU/CPU buffers ограничены 480 samples по умолчанию. On/off M4 A/B: 47.6166 / 47.6215 ms, FPS выигрыш не подтверждён, PNG exact. [Измерения и тесты](benchmarks/quilt-profiling/README.md).

Опциональный `--inverse-depth` использует reverse-Z affine inverse depth и запрашивает raw capture. M4 A/B GPU quilt 11.346 / 11.316 ms; speedup не установлен относительно run variability. Изменились 0.017% synthesized pixels, PSNR vs baseline 88.875 dB. Default ordinary math сохранён. [Эксперимент и качество](benchmarks/inverse-depth/README.md).

Измерен real-view budget для 48 outputs / 1024²: 12/16/24/32 sources дали 33.310/37.999/47.782/58.813 ms и whole-quilt PSNR 18.521/21.782/25.768/27.778 dB. В этой сцене `--real=16` уменьшает interval на 20.47% vs 24, с потерей качества. Defaults не изменены; adaptive controller пока не реализован. [Speed/quality curve и rejected timing](benchmarks/view-budget/README.md).


## Nonuniform anchors: measured negative result

Added optional strictly increasing `custom_anchor_indices` (demo `--anchors=`), with validation and effective anchor telemetry. An offline selection of 24 cameras from the previous 16-view RGB errors worsened whole-quilt PSNR from 25.768 to 24.088 dB and increased squared error 47.21%; observed quilt-update intervals 48.317±0.425 versus 48.204±0.090 ms do not establish acceleration. Uniform remains the default; no runtime adaptive controller is implemented. See [benchmark details](benchmarks/anchor-placement/README.md).


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](benchmarks/depth-overhead/README.md).


## Compact GPU depth feedback

GPU reduction of the optional depth diagnostic now returns 768 bytes instead of 786,432 bytes for 48 views at 256². On current Godot 4.8-dev / Apple M4, three repeated async experiments reduced CPU decoding from 20.499±1.021 to 0.306±0.009 ms per callback (about 67×). Isolated GPU scopes 1.371±0.021 versus 1.365±0.043 ms show no measurable extra GPU cost; quilt update intervals remain 48.27 ms and callback latency about 97 ms. GPU totals match CPU sums exactly, all output PNGs match byte-for-byte, and all 15 regression checks pass. This reduces diagnostic CPU work, with no established FPS gain. Uniform view selection and addon defaults remain unchanged. See [implementation, measurements and reproduction](benchmarks/depth-reduction/README.md).


## Статичный quilt по запросу

Добавлен опциональный `update_on_demand` для compute quilt: ракурсы рендерятся и quilt собирается только при `request_update()`. Движение rig запрашивает обновление автоматически; изменения объектов, света, материалов и окружения приложение сообщает явно. На последнем Godot 4.8-dev / Apple M4, в трёх парах статичной сцены 24→48 с 1024² тайлами, интервал между process/presentation кадрами снизился с 47.408±0.296 до 16.535±0.121 мс. После прогрева сохранившийся quilt побитно совпал с continuous reference. В idle повторных source captures и compute dispatches нет; окно продолжает показывать сохранённую текстуру. Это экономия статичного режима, а не ускорение генерации новых ракурсов анимации. Самый первый кадр большой сцены отличался на 76 RGBA-компонентов с максимальной разницей 1/255; benchmark поэтому явно обновляет quilt перед измеряемым idle. Причина стартовой разницы не установлена, автоматический прогрев не реализован. Режим выключен по умолчанию и не меняет engine fork. См. [API, ограничения и измерения](benchmarks/on-demand/README.md).
