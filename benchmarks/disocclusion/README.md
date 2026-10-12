# Disocclusion correspondence rescue

```sh
python3 benchmarks/disocclusion/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/disocclusion/rendered1024
python3 benchmarks/disocclusion/quality.py benchmarks/disocclusion/rendered1024
```

Quality script требует Pillow/NumPy; локально bundled Python `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`.

Opt-in `--rescue` / rig `disocclusion_rescue=false` default. Отдельные canonical shaders `synthesize_rescue.glsl` и `synthesize_raw_depth_rescue.glsl`; baseline не менялся. Generated variants поддерживают существующие workgroup и iteration selectors.

Алгоритм: только если оба исходных gather невалидны, пробовать depth при source UV offsets ±1/±2/±4 texel по горизонтали, отдельно для двух источников. Каждая depth-гипотеза вычисляет source landing UV для исходного target pixel. Проверить фактическую depth в landing UV и forward residual <0.5 output pixel. Среди валидных гипотез выбрать ближайшую поверхность. Если валидных гипотез нет, прежний unwarped fallback или debug magenta. Это не соседнее размазывание цвета и не восстановление невидимых в обоих источниках поверхностей. Неполный поиск может пропустить правильный слой; совпадение проекции не гарантирует физическую target visibility и стабильность во времени.

Сцена: static opaque, 512 MultiMesh boxes, foreground bars/несколько глубин, 4 SpotLight shared atlas, 24 real → 48 output, 1024², borrowed color/depth, 8 iterations и 8×8 groups. Три пары baseline/rescue с чередованием порядка, 90 warmup + 240 measured observed intervals. Quilt GPU mean включает startup samples и markers, не full-frame GPU time.

Дополнительно: fresh 48-real reference с тем же HDR→gamma transfer, два debug-hole quilt. Debug magenta означает оба gather невалидны (до/после rescue соответственно), а не ground-truth disocclusion. Нет exact-magenta materials в тестовой сцене. Quality RGB MAE/PSNR и changed pixel fraction считаются отдельно на synthesized tiles и real anchors. На маске восстановленных соответствий сравнивается PSNR baseline/rescue vs independent all-real. Снижение числа magenta pixels само по себе не доказывает улучшение.

Ограничения: одна сцена/один GPU; motion, curved geometry, particles/transparency, MSAA/TAA/FSR2/post effects и физический Looking Glass не проверены. Произвольные параметры view cone/depth clipping/radius не исследованы. Нового engine patch нет.


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
