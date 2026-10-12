# План реализации и статус

## Этап 0 — provenance и licensing: выполнен

Публичный официальный ZIP скачан, headers и SHA-256 сохранены, все 5217 файлов совпали. Unitypackage безопасно распакован отдельно. Инвентарь и line-level анализ готовы. Новый Godot addon не включает proprietary source, Unity Companion code или SDK binaries.

## Этап 1 — исполняемый baseline: выполнен на Godot 4.5.1

Shared World3D, 1–48 off-axis cameras, configurable grid/resolution/cone/focus, GPU raster quilt, preview без LKG, сцена с несколькими глубинами, тонкими перекрытиями, directional shadows и alpha panel. Автотест подтверждает focal registration, знак near/far disparity, вертикальный FOV для non-square tiles, размеры quilt для 1/2/12/47/48 views. Vulkan Apple M4 запуск и PNG capture выполнены.

## Этап 2 — экспериментальный synthesis: выполнен с ограничениями

POST_TRANSPARENT HDR/depth capture, два соседних источника, bounded inverse warp, visibility by minimum eye depth, GPU quilt и timestamp instrumentation. GPU-тест синтетической плоскости проверяет нулевое/положительное/отрицательное смещение против аналитической формулы. Demo capture выполнен. На сложной сцене есть видимые occlusion/transparent artifacts; режим выключен по умолчанию. Это экспериментальный MVP, не завершённый алгоритм disocclusion.

## Этап 3 — Bridge control plane: выполнен

HTTP client, automatic detection при `--bridge`, calibration unwrap/geometry, ручной visual.json, фильтрация обычных мониторов, session close. Протокольный fixture выполнен; live Bridge 2.6.3 отвечает и сообщает 0 calibrated LKG devices. В окружении установлен native SDK; библиотека не копировалась.

## Этап 4 — качество и native output: не выполнен

1. Depth-aware hole fill с validity map, GPU coverage statistics, quality comparisons с all-real в opaque сценах.
2. Захват opaque color отдельно от прозрачности, production transparency preset и диагностика view-dependent shading.
3. Objective-C++ Metal Bridge GDExtension: SDK dynamic loading, SDK-created IOSurface output, GPU copy и явная queue synchronization, version checks, ownership teardown.
4. Подключённый Looking Glass: calibration match по serial/device id, defaults quilt, view orientation, lenticular quality, frame pacing/latency, reconnect и multi-display selection.

Критерий готовности native output: калиброванный реальный дисплей показывает известный тест ракурсов, нет stale/tearing frames, подтверждены GPU copies/fences, процесс корректно переживает disconnect и shutdown. Сейчас это не проверено.

## Этап 5 — адаптивность и temporal: не выполнен

GPU tile disparity/edge/holes statistics, budgeted anchors с hysteresis, motion vectors с rejection, history remap. Нужны motion-vector capture и тесты animated geometry/particles/camera cuts. Нельзя принимать уменьшение числа real views за доказательство ускорения или качества.

## Этап 6 — опциональный engine backend: эксперимент позиционных теней

В Godot 4.8-dev checkout уже есть Vulkan driver multiview, но scene renderer ограничен 2 views. Сначала module прототип для групп 2/4/8 и union culling, затем расширение scene UBO/shaders/effects. Измерить против одинакового addon baseline. Engine fork только при подтверждённом выигрыше и принятой стоимости сопровождения. В checkout добавлен opt-in API shared positional shadow atlas; patch и условия применения: `engine-patches/README.md`. Union culling и native batch views пока не реализованы.

## Оставшиеся ограничения

Нет физического calibrated LKG по ответу Bridge; optical/native output не тестировался. Нет редактора Unity и сравнения Unity/Godot на одинаковой сцене. Минимальный runtime Godot 4.8-dev собран для Vulkan/MoltenVK; native Metal этим бинарником не проверяется. Нет Windows/Linux GPU и драйверного capture RenderDoc/Xcode. All-real обходной путь для отсутствующего RD выполнен и проверен в Compatibility renderer. Нет adaptive scheduler, temporal history, depth-aware fill, экспортного native backend и per-view transparent overlay. GPU timestamps доступны для compositor quilt; engine per-viewport times суммируются и не равны total GPU critical path.

## Выполненные оптимизации addon

Кэширование RD uniform sets, push constants и camera offsets; invalidation при смене source texture RIDs; обновление camera transforms только при движении rig. Дополнительно shader gather прекращает iterations при точном depth fixed point, сохраняя максимум 8 для несошедшихся пикселей. Сравнительные прогоны CPU и GPU, побайтная проверка quilt и regression suite сохранены в `benchmarks/optimization`; результаты описаны в performance-optimization.md. Addon-оптимизации не реализуют union culling/native engine multiview. Отдельный эксперимент shared positional shadows находится в engine-patches.


## Проверенный результат engine эксперимента

Runtime 4.8-dev собран и исполнен. Для 48 real views с четырьмя SpotLight shared atlas дал −33.3% wall frame time и −40.7% viewport GPU sum, при идентичных контрольных PNG; три пары прогонов. Omni/Spot runtime tests проверили LOD/mask/chain/owner-free fallback. Stock/patched regression suites прошли. До production применения требуются allocation/coverage stress tests, изменяющиеся masks/worlds, crowded lights, transparency, XR и несколько разных GPU; directional shadow reuse и native multiview требуют отдельной архитектуры.

Дополнительный этап измерений выполнен: stress scene с 512 одинаковыми объектами, отдельные instances/MultiMesh, pixel-cost control и 12/24-anchor synthesis. CPU-подготовка с MultiMesh ниже, общий FPS не ускоряется; уменьшение числа настоящих ракурсов помогает в этом workload с измеримой потерей качества. Общий engine culling не реализован: текущие измерения не показывают, что он снимет основной bottleneck. Следующий шаг — GPU pass profiling для 48-real сцены и устранение различий tonemapping перед оценкой/adaptive synthesis. См. benchmarks/scene-preparation/README.md.

GPU pass diagnostic выполнен. Обнаружено сильное влияние timestamps на M4/MoltenVK; они отключены в обычном addon по умолчанию. Измерено −10.6% wall frame time от отключения viewport timings в новой stress scene; shared shadows без timings также проверены (28.795 → 20.145 ms). Новый engine patch не нужен для этой оптимизации. Подробный marker profiler реализован как optional diagnostic, не использован для утверждения unprofiled shader bottleneck. Следующий исследовательский этап — capture без массовых timestamp queries.

Реализован и измерен opt-in direct HDR color input в addon: source color RID вместо собственной color copy, linear depth capture сохранён. 1024²/24 real → 48 output: −4.88% quilt-update wall interval в static stress scene, 192 MiB calculated texture payload устранено, PNG exact. 512²: FPS gain не подтверждён, 48 MiB payload устранено. Важные lifetime/resize/непустой-synthesis проверки добавлены к suite; пройдены 4.5.1 и 4.8. TAA/FSR2/MSAA/другие post effects требуют отдельной проверки и возможного автоматического snapshot fallback; default copy path сохранён. Новый engine patch не нужен.


Borrowed-depth MVP реализован через существующий RenderingDevice API без engine patch. Следующие проверки: MSAA depth resolve, TAA/FSR2, изменение render scale и near/far во время работы, lifetime при пересоздании буферов без изменения размера. До этих проверок direct color/depth остаётся opt-in; automated renderer-feature fallback не реализован.


Iteration-limit эксперимент завершён: 4 даёт около 2.09% GPU quilt / 0.54% update interval в одной сцене, default 8 сохранён. Следующие quality checks: curved surfaces, тонкие перекрытия, motion/temporal flicker, частицы/transparency. All-real reference показал PSNR 22.757 dB для synthesized baseline; приоритет дальнейшего исследования — visibility/disocclusion reconstruction, не автоматическое переключение всех сцен на 2 iterations.


Depth-hypothesis rescue MVP реализован и выполнен: восстановлено 2.03% failed two-source correspondences в одном static benchmark, GPU +3.34%, default off. До рекомендации для production нужны curved/moving/transparency scenes, качество на boundaries, широкий диапазон camera baseline, проверка false-positive visibility и temporal flicker. Дальнейшие варианты: дополнительные anchor sources, forward depth visibility buffer или depth hierarchy; они не реализованы и их выигрыш не доказан.


## Borrowed-buffer compatibility fallback

Проверены 15 renderer configurations на Apple M4/Vulkan, Godot 4.5.1 и 4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, дополнительный compositor, reset. Финальная матрица сравнивает три capture modes и raw RGBAH quilt: default copy, borrowed color, borrowed color+depth. Все результаты exact с production policy, все девять regression checks прошли на обеих версиях.

Direct color без fallback отличается при TAA и другом color-modifying POST_TRANSPARENT effect после capture. Capture автоматически переключает color/depth на собственный snapshot при TAA или любом дополнительном enabled compositor effect и возвращает direct access после снятия blocker. Raw-depth fallback копирует reverse-Z в R32F, сохраняя interpretation synthesis shader. Descriptor cache обновляется по RID; освобождаются только собственные textures. WeakRef на compositor не создаёт ownership cycle.

MSAA, FXAA, FSR1/FSR2, scaling, glow и tonemap сохранили equivalence в проверенных configurations. Это equivalence POST_TRANSPARENT snapshot: финальная TAA/FSR2/glow/tonemap output не включается в quilt, jitter compensation и dynamic quality ещё не проверены. Тест использует manual draw и sync только для проверки, не benchmark. Скорость новой policy отдельно не измерялась. Demo report теперь содержит effective borrow counts, fallback reasons и owned payload по фактическим dimensions.

Первый FSR2 probe на internal 48² вызвал engine uavMip errors, результат rejected. На internal 128² повтор выполнен без errors; engine issue не исправлен и minimum supported size не установлен. Native Metal, другие GPU, physical Looking Glass и motion/particles/transparency остаются непроверенными. Подробные команды и JSON/log: benchmarks/buffer-compat/README.md.


Quilt instrumentation вынесена в opt-in; samples bounded. A/B 24→48 1024²: 47.6166 ms on / 47.6215 off, FPS gain не подтверждён, PNG exact. Следующие оптимизации следует выбирать по новой измеренной нагрузке; только удалением оставшихся двух markers заметного ускорения в этой сцене не получено. Resize/profiling tests теперь ждут actual quilt updates вместо фиксированных process-call counts.


Inverse-depth math эксперимент выполнен: GPU 11.346 → 11.316 ms при stddev 0.238/0.290; speedup не подтверждён. Image PSNR vs baseline 88.875 dB; default ordinary оставлен. Further tuning этой формулы без профиля не является приоритетом. Следующие крупные кандидаты: real-view count/placement и GPU pixel workload; нужны quality/performance measurements, прежде чем автоматизировать выбор.


Real-count curve получена для 12/16/24/32 → 48: явный speed/quality tradeoff. Per-view SSE/MAE сохранены для следующего fixed-budget anchor-placement эксперимента. Перед adaptive runtime нужны proxy-quality без полного GT, стабильность при motion и hysteresis/rebuild strategy. Current --real setting уже позволяет применить измеренный бюджет; automatic controller не реализован.


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
