# Устранение промежуточной HDR color copy

Новый опциональный путь addon: `borrow_source_color=true` / demo `--borrow-color`. Compositor получает Godot-owned color RID через `RenderSceneBuffersRD.get_color_layer(0)` и передаёт его синтезу непосредственно. Compute capture сохраняет только linear depth в собственную R32F-текстуру; HDR color не копируется в дополнительную RGBA16F-текстуру.

Godot-owned RID никогда не освобождается addon. Capture удерживает RenderSceneBuffersRD owner и обновляет color RID при каждом callback; существующий uniform cache синтеза пересоздаётся при изменении source RID. Освобождение capture идемпотентно, очищает только собственные ресурсы и прекращает новые callbacks. Default остаётся copy path; borrowed mode экспериментален.

```sh
python3 /Users/roman/work/godot-looking-glass/benchmarks/borrow-color/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64
python3 /Users/roman/work/godot-looking-glass/benchmarks/borrow-color/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile=1024 --rendered --results-dir=/Users/roman/work/godot-looking-glass/benchmarks/borrow-color/rendered1024
```

Перед запуском импортируйте новый shader через официальный editor, как описано в основном README. Runner создаёт изолированный project; исходники addon/demo/tests подключаются symlink. Требуется runtime с shared-shadow patch. Запуски последовательные, три повтора каждого режима, порядок copy/borrow чередуется; 90 warmup + 240 samples. Не запускайте постороннюю GPU-нагрузку. Повторный запуск перезаписывает соответствующие результаты.

512²: 48 output / 24 real, 512 MultiMesh boxes плюс движущийся caster, четыре SpotLight; viewport timestamps выключены. Wall frame copy 16.712 ± 0.079 ms, borrow 16.643 ± 0.039 ms. Разница слишком мала для утверждения устойчивого FPS-выигрыша; scheduling около 16.7 ms ограничивает этот workload. PNG побайтно одинаковы: `9be0a98db198e7910cd51fde2af71d7dbbd51e66a7782e2e3eb81cdac5b443bf`. Во всех шести прогонах выполнено 330 quilt dispatches.

Устранено 24 × 512 × 512 × 8 = 50,331,648 bytes = 48 MiB собственного color texture payload. Это вычисленная экономия промежуточных RGBA16F allocations, а не измерение общей VRAM/residency. В 1024² конфигурации соответствующий payload — 192 MiB. Перевод reverse-Z в linear depth остаётся отдельным compute pass; depth copy не устранена. GPU-time quilt pass исключает capture и включает собственные два timestamps; baseline и borrow используют их одинаково. Значение GPU-time в текущем sampler включает startup samples, поэтому не используется как отдельное доказательство ускорения capture.

## Валидность измерений

Первые шесть прогонов отклонены: ошибка типизации массива в новой версии capture вызвала runtime error GDScript, скрытый minimal template_release; compute_dispatches=0. Они сохранены в `discarded/` и не участвуют в summary. Ошибка исправлена; runner требует compute work и timestamp samples. Тест теперь отвергает два одинаковых пустых quilt.

Обычный 1024² process-call benchmark отклонён (`tile1024/`): на 330 process calls было только 199 quilt dispatches и 195 timestamp samples. Число шагов логики не эквивалентно числу rendered outputs. Stack sample не доказал shader/GPU deadlock; процесс завершился и сохранил JSON/PNG. Из этих данных нельзя заявлять FPS-результат copy/borrow.

`--rendered-benchmark` собирает samples только при наблюдаемом увеличении успешных quilt dispatches. Wall metric — интервал между наблюдаемыми обновлениями quilt, включая scheduling/presentation; это не hardware GPU critical path. `--rendered` в runner также фиксирует сцену через --static, чтобы число process calls не меняло геометрию в контрольных изображениях. Поэтому 512² dynamic и 1024² static результаты не следует сравнивать между собой как scaling curve. Прогон с недостаточным числом samples или compute work считается ошибкой.

Общий номер capture теперь берётся из стабильного внутри render draw RD slot index вместо независимых callback counters; это изменение одинаково в copy/borrow. Само наличие старого startup рассогласования не было доказано: первый отказ вызван ошибкой типизации нового кода.

## Проверки и ограничения

Executed GPU test `test_capture_lifetime.gd`: реальное увеличение dispatch_count, непустой quilt, exact floating-point quilt при размерах источников 64/48/80, resize buffers, двойной release, сохранность Godot-owned texture после release. Проверено на официальном Godot 4.5.1 и experimental 4.8-dev; итоговые logs сохранены в lifetime-stock.log/lifetime.log и общем test runner.

Не доказана эквивалентность при TAA, FSR2, MSAA, glow или дополнительных post-transparent effects. Если color меняется после POST_TRANSPARENT callback, borrowed input может отличаться от snapshot copy. Default copy path сохранён, автоматического fallback по этим эффектам пока нет. Borrowed mode требует контроля renderer configuration; не включайте его для таких эффектов без отдельного сравнения качества. Native Metal, Compatibility и физический Looking Glass с этим путем не проверены.

Source reference: Godot forward_clustered/render_forward_clustered.cpp:2541 вызывает POST_TRANSPARENT compositor, :2555 начинает FSR2, :2623 TAA, :2632 tonemap. Получение color не означает snapshot после этих эффектов. Это ограничение direct source reuse, а не основание копировать engine buffers без учёта времени жизни.

## Тяжёлый режим: выполненный результат

1024², 48 output / 24 real, статичная сцена с 512 MultiMesh boxes и четырьмя SpotLight; по три прогона с 240 samples успешных quilt updates после 90 warmup.

| Режим | Wall quilt-update interval, ms | Run stddev, ms | Собственный HDR copy payload |
|---|---:|---:|---:|
| Copy | 52.205 | 0.057 | 192 MiB |
| Borrow | 49.656 | 0.121 | 0 |

Время обновления quilt уменьшилось на 4.88%. Это throughput всей конфигурации с scheduling, а не изолированное GPU-время capture. Quilt compute pass сам по себе не ускорился: mean 12.253 / 12.359 ms; экономия находится вне этого прохода. Нельзя переносить этот процент на все scenes/GPU или на обычные тайлы 128².

PNG copy/borrow побайтно одинаковы: SHA256 `0adf86c51333aea46d72e0cef05a1d21f71ba568e949653936b9d3a9ccc2e0ba`. Исходные JSON/log/PNG и mean/stddev — rendered1024/. Проверенная версия движка и binary SHA256 записаны в каждом JSON/summary.
