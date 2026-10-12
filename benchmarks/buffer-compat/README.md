# Borrowed-buffer compatibility and snapshot fallback

Проверяется эквивалентность snapshot в POST_TRANSPARENT, а не финальному viewport после TAA/upscaling/glow/tonemapping. Quilt по-прежнему использует pre-postprocessing HDR и simple gamma transfer. Эти тесты не подтверждают применение TAA/FSR2 к самому quilt или качество temporal reprojection.

## Выполненная матрица

Apple M4 / Forward+ Vulkan-MoltenVK; official 4.5.1 и custom 4.8-dev. Три rig с общим World3D, 5 output / 2 real, 256², spheres и boxes на разных глубинах. Сравнение raw RGBAH quilt, не только PNG. Все 15 конфигураций переключаются на существующих viewport, включая reconfiguration при неизменном размере и render scale 0.5/1.25.

| Configuration | Direct access without policy | With automatic policy |
|---|---|---|
| Baseline | Exact | Borrowed, exact |
| MSAA 2/4/8 | Exact | Borrowed, exact |
| TAA | Differs | Copied snapshot, exact |
| FXAA | Exact | Borrowed, exact |
| FSR1, scale 0.5 | Exact | Borrowed, exact |
| FSR2, scale 0.5 | Exact | Borrowed, exact |
| FSR2, scale 1.0 | Not in initial probe | Borrowed, exact |
| Bilinear scale 0.5/1.25 | Exact | Borrowed, exact |
| Glow, filmic tonemapping | Exact | Borrowed, exact |
| Extra POST_TRANSPARENT color modifier after capture | Differs | Copied snapshot, exact |
| Reset | Exact | Returns to borrowed, exact |

Final matrix проверяет default copy, borrowed color + linear-depth copy и borrowed color/depth. Проверяются nonempty output, advancing synthesis dispatches, exact equality, expected effective borrow flags, fallback reasons, buffer dimensions, RID changes и фактический FSR2 mode через RenderSceneBuffersRD. Initial probes сравнивали default copy и raw-depth borrowed path. All 9 regression checks прошли на обеих версиях. Файлы: validated-4.5/4.8.json/.log, checks-4.5/4.8.log; initial probe-4.5.json/.log и probe-4.8.json/probe-4.8-manual.log.

## Implementation

Capture хранит requested и effective borrow modes раздельно. На render callback `get_use_taa()` блокирует direct access; любой другой enabled effect в camera compositor также включает консервативный fallback (в том числе effect, который мог бы быть безопасен). WeakRef на compositor исключает ownership cycle. При переключении освобождаются только собственные textures, обновляются RID и пересобираются cached synthesis descriptor sets. После снятия blocker direct mode возвращается автоматически.

Если synthesis выбран для raw reverse-Z depth, fallback пишет raw depth в собственную R32F через capture_raw_depth.glsl. Shader interpretation остаётся постоянной при смене режима. Linear-depth mode использует прежний capture shader. Fallback pipeline подготавливается заранее, но fallback color/depth textures выделяются только когда нужны. Capture.release остаётся idempotent; borrowed RID не освобождаются.

Demo JSON различает запросы borrow_source_color/depth, effective_borrowed_color/depth_views, capture_fallback_reasons и calculated owned texture payload на основе фактических capture dimensions. Это не измерение total VRAM. Скорость после новой policy отдельно не измерялась; предыдущие benchmark цифры не переоценены.

## Reproduction

```sh
python3 tests/run_checks.py --godot /path/to/godot --driver vulkan
/path/to/godot --path . --rendering-driver vulkan --quit-after 3000 --script res://tests/test_buffer_compat.gd -- --output=res://benchmarks/buffer-compat/manual.json
/path/to/godot --path . --rendering-driver vulkan --quit-after 3000 --script res://tests/test_buffer_compat.gd -- --probe --output=res://benchmarks/buffer-compat/probe.json
```

`--probe` отключает policy только в тестовых Capture instances и регистрирует differences; это не проверка корректности production fallback. Matrix test отключает обычный render loop и вызывает force_draw(false, 1/60) + force_sync для устойчивости вне foreground macOS window. Sync и GPU readbacks используются только в тесте; время матрицы не является benchmark.

## Limitations and rejected probes

Initial test при viewport 96² / internal FSR2 48² на 4.5 вызвал errors в execute_gpu_job_compute_rd (uavMip >= mip_slice_rids.size()). FSR2 result этого probe не принят. Пробу повторили с 256² / internal 128² без errors; минимальный безопасный размер FSR2 не установлен, engine bug не исправлялся. probe-small.json сохранён.

Initial 4.8 run не завершился; sample показывает main loop/nanosleep и не доказывает GPU deadlock. После исправления typed-array test setup ограниченная retry дошла до FSR1 и остановилась по quit-after во время ожидания следующего draw. Эти логи не считаются passed matrix; final manual-draw tests завершились полностью без RID leak warnings.

Статическая матрица на одном GPU не гарантирует lifetime contract для всех renderer configurations. Moving objects, temporal jitter compensation, частицы/transparency, другие compositor callback combinations, Apple native Metal, другие GPU и физический Looking Glass остаются непроверенными. Engine-owned source всё ещё не является snapshot; policy закрывает подтверждённые hazards, а не предоставляет официальный API lifetime guarantee. Дискуссия: https://github.com/godotengine/godot-proposals/discussions/15633.
