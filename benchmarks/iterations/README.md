# Fixed reprojection iteration limits

```sh
python3 benchmarks/iterations/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/iterations/rendered1024
python3 benchmarks/iterations/quality.py benchmarks/iterations/rendered1024
```

Для quality.py нужны NumPy и Pillow; локально использован bundled Python `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. Bench runner использует стандартную библиотеку.

Варианты отличаются только константой предела gather loop 2/4/8; точный fixed-point early exit, residual validity threshold и hole fallback сохранены. Canonical 8 shader не меняется. Selector `--iterations=2|4|8`, addon `reprojection_iterations`. Default 8 сохранён; export enum и runtime CLI принимают 2/4/8; некорректное программное значение откатывается в synthesizer к 8. Shader variants генерируются `shaders/generate_workgroups.py` для сочетаний local size и iteration limit и импортируются Godot заранее.

Сцена скорости: Apple M4/Vulkan-MoltenVK, Godot 4.8-dev, 24 real → 48 output, 1024², 512 static MultiMesh boxes, foreground bars и объекты на разных глубинах, четыре SpotLight, shared atlas, borrowed color/depth, workgroup 8×8. Три повтора каждого режима, порядок 8/4/2, 4/2/8, 2/8/4. 90 warmup + 240 observed update intervals. Quilt GPU interval включает два timestamp markers; mean включает startup samples и не означает whole-frame GPU time. Wall/engine mismatches сохраняются и отмечаются, не фильтруются без объяснения.

Качество: saved PNG первой тройки сравниваются с 8 iterations и отдельным 48-real quilt. Все варианты и reference используют тот же linear HDR → simple gamma shader transfer; сравнение не включает native Godot tonemapping mismatch. Metrics RGB MAE в 8-bit units, PSNR, fraction changed pixels считаются отдельно по 24 synthesized tiles и 24 real anchors. Anchors определены равномерным выбором round(i*47/23); quilt имеет 4 columns и перевёрнутые rows. PNG compression/alpha не используются в numerical RGB quality metric. PSNR null при точном совпадении (бесконечный PSNR).

Это не perceptual/temporal quality score: scene opaque/static, curved geometry, частицы, motion, TAA/FSR2/MSAA и другие сцены не проверены. Даже хороший aggregate PSNR может скрывать дефекты на небольших границах. Default 8 не меняется на основе одной сцены.

Все шесть checks прошли на Godot 4.5.1 и 4.8: projection, analytic GPU для 8/2/4, capture lifetime/workgroup equivalence, Bridge fixture. GPU analytic check проверяет zero/positive/negative disparity на плоскости, где меньшее число итераций должно быть достаточно. Это не подтверждение сложных occlusion cases.


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
