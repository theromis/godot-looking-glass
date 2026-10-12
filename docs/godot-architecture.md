# Архитектура Godot 4

## Решение

Рекомендуется гибрид: самостоятельный addon на публичном Godot API, небольшой опциональный GDExtension для Bridge native interop и отдельный эксперимент с engine module для batch views. Сначала измерить all-real reference и качество compute synthesis. Изменения движка не нужны для текущего MVP.

Исполнен Godot 4.5.1 official `f62fdbde15035c5576dad93e586201f4d41ef0cb`, Apple M4, Forward+, Vulkan 1.2.283 через MoltenVK. Checkout пользователя `/Users/roman/work/godot`: 4.8.0-dev, commit `232e6b14abf6e590b41d60f11704e42de22bff72`; он исследован и изменён отдельным opt-in patch позиционных теней. Runtime собран; результаты его исполнения приведены отдельно в engine-patches/README.md и benchmarks/engine-shadows. Исполнение бинарника 4.5.1 не является тестом 4.8-dev. Ссылки на исходный multiview renderer относятся к указанному базовому commit; patch опубликован отдельно.

## Сравнение вариантов

| Вариант | Что доступно | Ограничения и цена | Вывод |
|---|---|---|---|
| A. GDExtension/SubViewport/RD | Реальные off-axis cameras, viewport textures, CompositorEffect depth/color, GPU quilt; native Bridge | Повторный culling, освещение и shadows по viewport; нет публичного arbitrary multi-camera batch | Лучший переносимый baseline; MVP делает это GDScript-ом, GDExtension пока не нужен |
| B. Custom renderer module | Union culling, общие shadow maps, массивы источников, тесное профилирование | Поддержка ABI/engine changes, риск каскадов и view-dependent эффектов | Следующий этап после доказательства bottleneck |
| C. Fork с multiview | Batch view masks и gl_ViewIndex на уровне raster pipeline | Godot scene renderer ограничен двумя видами, shader/UBO/SSR/SSIL/GI/sky assumptions; hardware caps | Исследовательский backend, не production default |
| D. Hybrid | Рабочий addon + опциональные native output и grouped renderer | Больше тестовых комбинаций | Рекомендуется; fallback на независимые viewport |

## Что действительно позволяет Godot

[Compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html) исполняет callback на render thread. [RenderSceneBuffersRD](https://docs.godotengine.org/en/stable/classes/class_renderscenebuffersrd.html) предоставляет color/depth layers. [Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) даёт asymmetric frustum. Texture RID RenderingServer и texture RID RenderingDevice — разные пространства; их нельзя произвольно смешивать. Для compute применяется основной RD и Texture2DRD; local RD используется только в изолированном GPU-тесте с submit/sync.

В checkout: depth/color methods bind в [render_scene_buffers_rd.cpp:65](</Users/roman/work/godot/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp:65>); `Camera3D::_get_camera_projection` и `Projection::set_frustum` в [camera_3d.cpp:285](</Users/roman/work/godot/scene/3d/camera_3d.cpp:285>), [projection.cpp:508](</Users/roman/work/godot/core/math/projection.cpp:508>). При KEEP_HEIGHT размер ближней плоскости задаётся как `2*near*tan(vertical_fov/2)`; projection internally умножает его на aspect. Фокусная плоскость на расстоянии F остаётся неподвижной при eye e и near-plane offset `-e*near/F`. Это проверено тестом на нес квадратных tiles 160×200.

## Путь MVP

`rig.gd`: создаёт shared World3D SubViewports, выбирает равномерные anchor indices с обоими концами view cone, параллельные камеры, off-axis projection. В all-real режиме каждый tile — TextureRect в quilt SubViewport: sampling и сборка полностью GPU, без `Image.get_image` на кадр. View 0 расположен снизу слева, rows bottom-to-top; пустые tiles последней строки чёрные. Экспортные параметры меняются до `_ready`; для смены count/size/mode нужно пересоздать rig. Camera offsets кэшируются, Transform камер обновляется только при изменении Transform rig.

`capture.gd`: POST_TRANSPARENT callback копирует HDR color и reverse-Z depth в принадлежащие addon RGBA16F/R32F textures. Это две GPU copies/compute writes на anchor; они нужны для устойчивого lifetime и чтения после всех источников. Captures сохраняют sequence number; composer ждёт одинаковый номер у всех источников. Viewports постоянно обновляются. Это обеспечивает coherence при текущей модели независимых always-update views; динамические viewport dependencies/recreation должны быть отдельно протестированы.

`synthesizer.gd`: после frame_post_draw ставит работу на render thread. Шейдер `synthesize.glsl` в одном dispatch на tile либо копирует настоящий ракурс, либо делает bounded inverse warp из двух соседних anchors (до 8 iterations/source, с точным fixed-point early exit при неизменной глубине). При двух совпадениях выбирает меньший linear eye depth; при отсутствии — unwarped source fallback, либо magenta при debug_holes. Выполняются bounds checks и residual <1 pixel. Uniform sets и push constants кэшируются; sets пересоздаются при изменении source texture RIDs, debug flag обновляется отдельно. Shared output RGBA16F quilt показывается Texture2DRD. Нет CPU readback в live loop; readback только при явном capture и в GPU-тесте. Резервный raster quilt в synthesis mode отключён, чтобы не собирать лишний quilt.

Это базовый GPU depth reprojection, а не полноценная реконструкция скрытых поверхностей. Inverse warp может сходиться к неверной поверхности или колебаться на discontinuity. Шейдер не содержит depth-aware hole fill, temporal history, adaptive sampling и per-view transparent pass; эти функции предлагаются ниже, а не заявлены реализованными. Color preview использует простую gamma 1/2.2, не Godot filmic tonemapping; сравнение цветов с all-real включает это различие. Вывод compute хранит display-encoded значения, которые нельзя передавать в native Bridge без согласования формата/transfer function.

## Целевой synthesis backend

Получать opaque color, linear depth, projection/inverse projection, source eye positions, optional motion vectors. Распределить anchor views по оценке worst disparity `|Δeye|*|1/z-1/F|/horizontal_slope`, depth edges, thin geometry, holes. Сначала uniform anchors, потом добавить самые трудные промежутки в пределах бюджета. Переключения сглаживать hysteresis; сохранять endpoints. GPU reduction передаёт малую delayed статистику, не изображения; можно выбрать фиксированный N без CPU feedback.

Предлагаемый multi-source resolve: forward splat из 2–4 соседних источников в target visibility depth + owner id, с отдельными pass для детерминированного nearest-depth выбора и color gather. Не писать float color конкурентно без ownership. Reverse-Z переводить через inverse projection, поддерживать jitter/oblique projections. Два разных anchors с совпадающей глубиной можно confidence blend, на edges — nearest-visible source. Выводить validity/confidence и hole ratio.

Hole fill — отдельный bounded pass: соседние валидные samples с близкой depth, предпочтительно background-side, запрет размазывания через foreground edges. Большие невидимые области обозначать invalid и добавлять настоящий anchor; hidden geometry нельзя восстановить достоверно только из depth. Temporal history требует motion vectors, reject camera cuts, object motion, depth mismatch, view-id remap; хранить history по view group и invalidate при смене калибровки/scene parameters.

Для прозрачности: all-real preset; либо opaque synthesis + отдельный transparent rendering для каждого target с reconstructed depth buffer, либо layered depth/weighted OIT с явной потерей точности. Частицы и отражения могут зависеть от camera view; reprojected RGB не пересчитывает BRDF и сортировку. Shadows можно переиспользовать только при union coverage; cascade splits и contact shadows нужны отдельным benchmark сценам.

## Native Bridge и калибровка

`bridge_client.gd` реализует HTTP PUT control plane: orchestration, calibrated device filtering, calibration unwrap, near-camera geometry, graceful отсутствие сервиса, session close. Demo `--bridge` выполняет автоматическое обнаружение, `--calibration=/path/visual.json` задаёт ручной fallback. Lens pitch/slope/center не используются для optical output: это работа будущего native backend. Device defaults не применяются автоматически к count/grid, чтобы не менять benchmark; их нужно подключить до production preset.

На машине установлен Bridge 2.6.3 с `/Applications/Looking Glass Bridge 2.6.3.app/Contents/MacOS/libbridge_inproc.dylib` и runtime headers. Live HTTP session и list прошли; сервис вернул обычный thirdparty monitor без calibration. После фильтрации найдено 0 калиброванных LKG-устройств. Hardware rendering не проверен.

Публичный native header samples содержит Metal window/IOSurface texture/draw APIs: [bridge.h:372](</Users/roman/work/looking-glass-reference/bridge-sdk-samples/BridgeRuntime/bridge.h:372>) (372–380); OpenGL quilt APIs также доступны. На macOS native Metal backend перспективнее MoltenVK→OpenGL. В checkout Godot `get_driver_resource` публично bound ([rendering_device.cpp:9484](</Users/roman/work/godot/servers/rendering/rendering_device.cpp:9484>)), Metal logical device и texture возвращаются как native pointers ([rendering_device_driver_metal.cpp:2545](</Users/roman/work/godot/drivers/metal/rendering_device_driver_metal.cpp:2545>)). Это позволяет предложить небольшой Objective-C++ GDExtension; наличие handle не решает resource usage, IOSurface exportability, retention, queue completion, SDK color formats и владение texture. Сначала SDK-created IOSurface texture + GPU copy, далее исследовать прямое sharing. Никогда не передавать VkImage в API, ожидающий MTLTexture или GLuint. Windows аналогично проверять DX sharing; Vulkan path требует interop staging/native external-memory API, которого в исследованном Bridge header нет.

Native texture submit adapter не реализован: без connected hardware невозможно подтвердить correctness interlacing, view order, synchronization и optics. Header/API доступны; препятствие теперь не скачивание SDK, а реализация backend и hardware validation. HTTP API не следует выдавать за передачу live GPU texture.

## Multiview в предоставленном движке

`MAX_RENDER_VIEWS=2`: [renderer_scene_render.h:50](</Users/roman/work/godot/servers/rendering/renderer_scene_render.h:50>). Fixed-size view arrays в [render_scene_data_rd.h:58](</Users/roman/work/godot/servers/rendering/renderer_rd/storage_rd/render_scene_data_rd.h:58>), UBO arrays в том же файле:129. Vulkan driver query `maxMultiviewViewCount` и view masks уже присутствует; render-pass mask `(1 << p_view_count)-1`: [rendering_device_driver_vulkan.cpp:5461](</Users/roman/work/godot/drivers/vulkan/rendering_device_driver_vulkan.cpp:5461>). Значение 32 требует отдельного исправления shift, 48 нельзя выразить одним 32-bit mask. Batch sizes 2/4/8 выбирать по caps и профилю GPU, а не предполагать один проход на 48.

Необходимы dynamic/per-group matrix buffers, shader indexing, scene view-count interface, union/per-group culling, forward light clusters, sky/GI/SSR/SSIL/motion-vector arrays, transparent sorting и renderer tests. Просто изменить MAX_RENDER_VIEWS на 48 небезопасно. Драйверную поддержку надо отделять от поддержки произвольного multiview всей сцены.

[Спецификация Khronos VkRenderPassMultiviewCreateInfo](https://docs.vulkan.org/refpages/latest/refpages/source/VkRenderPassMultiviewCreateInfo.html) определяет 32-bit view masks, broadcast draws по слоям attachments и ограничение highest view bit по maxMultiviewViewCount. Поэтому 48 видов требуют нескольких групп; наличие multiview само по себе не обещает уменьшения raster work.


## Исполненный opt-in engine experiment

Shared positional shadow atlas API добавлен в Godot 4.8-dev и проверен Vulkan/MoltenVK runtime. Это ограниченный engine backend для повторного использования Omni/Spot shadows, а не batch geometry renderer. Rig использует API через `has_method`/`call`, сохраняя совместимость со stock Godot. Условия: общий scenario, all-layer cameras, full caster culling, нулевой mesh LOD, одинаковый atlas size/precision; source lifetime проверяется на render thread. Directional shadows остаются отдельными. Source paths/functions/lines, build и параметры — `engine-patches/README.md`; измерения — `docs/performance-optimization.md`. Выигрыш доказан для конкретного 48-view shadow workload, не для всех сцен.

### Экспериментальный direct HDR color input

Rig export borrow_source_color (default false) передаётся Capture constructor до render-thread initialize. Copy path сохраняет две собственные textures; borrowed path удерживает RenderSceneBuffersRD ref и берёт его color layer RID, создавая только собственную depth texture и depth-only compute pipeline. Synthesizer принимает тот же color/depth interface, обновляет cached uniform sets при изменении RID. Release не освобождает borrowed texture, идемпотентен; resize sources проверен исполнением.

Capture frame id теперь общий RD frame-slot index + 1, вместо независимого числа callback. Первоначальное рассогласование старых counters не было доказано, изменение одинаково в baseline/borrow. Режимы render effects, меняющие source color после POST_TRANSPARENT, требуют snapshot copy либо переноса consume point; borrowed optimization остаётся opt-in. Ни texture ownership, ни frame id не гарантируют эквивалентность при произвольных дополнительных effects.


## Экспериментальный borrowed depth

`rig.borrow_source_depth` передаётся Capture до initialization и выбирает отдельный `synthesize_raw_depth.glsl` с near/far push constants. Capture удерживает buffer_owner, обновляет обе ссылки в POST_TRANSPARENT, не создаёт собственных color/depth textures и не отправляет capture compute. Default capture и synthesis shaders сохранены. После resize RID refresh пересобирает cached synthesis uniform sets. Release идемпотентен и не освобождает borrowed RID. Тест сравнивает exact raw quilt для default copy, borrowed color и borrowed color+depth при размерах источников 64/48/80. Это проверка конкретного Forward+ Vulkan сценария, не гарантия snapshot/lifetime при произвольных renderer features.


Compute local size задаётся `synthesis_workgroup` (0=8×8, 1=16×8, 2=16×16). При initialization выбирается заранее импортированный GLSL variant; dispatch grid вычисляется из того же Vector2i. Shader bounds check сохраняется. Canonical 8×8 shaders служат источником для `shaders/generate_workgroups.py`; variants отличаются только layout local size. Тест сравнивает все 9 capture/workgroup combinations на output tile 65×67. Default 8×8 сохранён после измерений M4.


`reprojection_iterations` (2/4/8, default 8) выбирает статически скомпилированный shader variant. CPU dispatch grid и push constant layout не меняются. Вариант генерируется изменением только gather loop limit; exact fixed-point exit, residual validity и fallback одинаковы. Это quality/performance knob, не гарантия изображения, эквивалентного 8. GPU tests проверяют analytic planar shifts для 2/4/8; benchmark дополнительно сравнивает с 48-real reference.


## Ограниченный depth-hypothesis rescue

Opt-in `disocclusion_rescue` выбирает отдельный shader, baseline неизменён. После двух failed gathers шесть горизонтальных seed offsets каждого source дают depth hypotheses; landing UV проверяется фактической depth и forward residual <0.5 pixel. Ближайшая валидная поверхность выбирается без чтения соседних output pixels и без scatter writes. Unseen geometry не восстанавливается. Debug holes до/после показывают invalid correspondence mask; quality сравнивается с fresh all-real quilt. Общий PSNR слегка вырос в measured scene, стоимость GPU +3.34%, default off.


## Borrowed-buffer compatibility fallback

Проверены 15 renderer configurations на Apple M4/Vulkan, Godot 4.5.1 и 4.8: baseline, MSAA 2/4/8, TAA, FXAA, FSR1 0.5, FSR2 0.5/1, bilinear scale 0.5/1.25, glow, filmic tonemap, дополнительный compositor, reset. Финальная матрица сравнивает три capture modes и raw RGBAH quilt: default copy, borrowed color, borrowed color+depth. Все результаты exact с production policy, все девять regression checks прошли на обеих версиях.

Direct color без fallback отличается при TAA и другом color-modifying POST_TRANSPARENT effect после capture. Capture автоматически переключает color/depth на собственный snapshot при TAA или любом дополнительном enabled compositor effect и возвращает direct access после снятия blocker. Raw-depth fallback копирует reverse-Z в R32F, сохраняя interpretation synthesis shader. Descriptor cache обновляется по RID; освобождаются только собственные textures. WeakRef на compositor не создаёт ownership cycle.

MSAA, FXAA, FSR1/FSR2, scaling, glow и tonemap сохранили equivalence в проверенных configurations. Это equivalence POST_TRANSPARENT snapshot: финальная TAA/FSR2/glow/tonemap output не включается в quilt, jitter compensation и dynamic quality ещё не проверены. Тест использует manual draw и sync только для проверки, не benchmark. Скорость новой policy отдельно не измерялась. Demo report теперь содержит effective borrow counts, fallback reasons и owned payload по фактическим dimensions.

Первый FSR2 probe на internal 48² вызвал engine uavMip errors, результат rejected. На internal 128² повтор выполнен без errors; engine issue не исправлен и minimum supported size не установлен. Native Metal, другие GPU, physical Looking Glass и motion/particles/transparency остаются непроверенными. Подробные команды и JSON/log: benchmarks/buffer-compat/README.md.


`profile_synthesis=false` default: synthesis dispatch не отправляет LG quilt timestamps, не сканирует timestamp results и не enqueue sample recording callbacks. Demo benchmark/--profile-quilt/--profile-passes явно включает measurement; --no-quilt-timing отключает. `profiling_sample_limit` (default 480, 1..4096) ограничивает GPU/CPU arrays, обновляемые кольцевым способом. GPU timestamps требуют обычного RD frame progression; correctness test сравнивает moving-object output с profiling on/off и ждёт actual dispatch updates. Duration без measurement — null, не zero.


Inverse-depth experiment: `inverse_depth_reprojection` автоматически запрашивает raw-depth capture и выбирает synthesize_raw_depth_inverse[_rescue] shader. Packed clip.zw содержат 1/far и 1/near-1/far; nearest source сравнивается по greater inverse depth. Fallback raw depth interpretation сохраняется при TAA/compositor snapshot mode. FP differences измерены, exact equality не гарантируется. Speedup на M4 не установлен, default false.


## Whole-interval anchor selection

An offline dynamic-programming tool evaluates the summed error of every intermediate view, with 24 anchors and a maximum gap of three. The independently rendered selected quilt matches predicted RGB squared error exactly and reduces it 6.209% in the tested static scene (whole-quilt PSNR 25.768 → 26.046 dB). Update intervals 48.221±1.813 versus 47.309±0.324 ms do not establish acceleration. Five GPU cost captures and three pairs of validation runs were executed on custom Godot 4.8; the solver matches exhaustive search in its tests. Rendering code/defaults are unchanged, and reference-assisted offline selection is not runtime adaptation. See [measurements and reproduction](../benchmarks/interval-placement/README.md).


## Depth-only proxy validation

Added a separate GPU diagnostic and three fixtures at nine camera poses, with full-real references, actual camera updates, and 64²/128²/256² probe grids. GPU counters match analytical plane shifts on official Godot 4.5.1 and custom 4.8; all 15 regressions passed on both. Pooled correlations overstate within-pose prediction. At 256², centered Spearman is 0.449 for both-source failures and 0.467 for depth edges, versus 0.429 for anchor distance. Dense sampling helps but no reliable adaptive selection or speed gain is demonstrated. The normal addon render path remains unchanged. See [raw results, validation and limitations](../benchmarks/depth-proxy/README.md).


## Direct depth-guided selection: negative validation

At fixed 24-real/48-output views, selecting anchors by both-invalid counts increases summed RGB squared error 12.14%, and selecting by depth-edge counts increases it 43.72%, across three fixtures/nine poses. A separately labeled reference oracle reduces it 17.14%. Frozen depth selection never reads colors/reference; independent renders match predicted errors exactly and all real tiles match their reference. Official Godot 4.5.1 reproduces the conclusion. Uniform remains default; no runtime adaptive controller or speedup is claimed. The offline candidate grids still require depth from all candidate view positions. See [protocol, tests and raw results](../benchmarks/depth-selection/README.md).


## Depth-probe cost on current 4.8-dev

Persistent probe resources and async diagnostic feedback are measured only on the newest local 4.8 build. Encoder-boundary GPU scopes minus empty calibration are 0.519/0.809/1.376 ms for 64²/128²/256² across the full quilt. At 256² every 16 updates, sync feedback blocks/processes 87.39±7.83 ms per request; async CPU decoding costs 19.94±1.42 ms with 110.92±12.36 ms delivery latency. Full-frame effects are inconclusive because of run variation and two rejected sparse wall/engine anomalies. Normal addon defaults remain unchanged. Simple timestamps inside a shared Metal compute encoder do not isolate passes on the observed MoltenVK path; earlier marker intervals should not alone support pure-kernel causal claims. All 15 regressions and persistent-resource analytic checks passed on current 4.8. See [measurement method, raw data and limits](../benchmarks/depth-overhead/README.md).


## Статичный quilt по запросу

Добавлен опциональный `update_on_demand` для compute quilt: ракурсы рендерятся и quilt собирается только при `request_update()`. Движение rig запрашивает обновление автоматически; изменения объектов, света, материалов и окружения приложение сообщает явно. На последнем Godot 4.8-dev / Apple M4, в трёх парах статичной сцены 24→48 с 1024² тайлами, интервал между process/presentation кадрами снизился с 47.408±0.296 до 16.535±0.121 мс. После прогрева сохранившийся quilt побитно совпал с continuous reference. В idle повторных source captures и compute dispatches нет; окно продолжает показывать сохранённую текстуру. Это экономия статичного режима, а не ускорение генерации новых ракурсов анимации. Самый первый кадр большой сцены отличался на 76 RGBA-компонентов с максимальной разницей 1/255; benchmark поэтому явно обновляет quilt перед измеряемым idle. Причина стартовой разницы не установлена, автоматический прогрев не реализован. Режим выключен по умолчанию и не меняет engine fork. См. [API, ограничения и измерения](../benchmarks/on-demand/README.md).
