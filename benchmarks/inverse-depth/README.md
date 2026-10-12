# Direct inverse-depth reprojection

В raw reverse-Z perspective input `d`, near `n`, far `f`:

`z = n*f / (n + d*(f-n))`

`1/z = 1/f + d*(1/n - 1/f)`

Optional `--inverse-depth` / `rig.inverse_depth_reprojection=false` default выбирает отдельный shader, автоматически запрашивая borrowed raw depth/color. Коэффициенты inverse far и inverse near-minus-far вычисляются при configure и передаются в существующих 64-byte push constants. Synthesis не восстанавливает z при каждом depth lookup: хранит inverse depth, использует min(inverse_z,1000) вместо 1/max(z,0.001), сравнивает >= для nearest surface. Rescue variant тоже поддерживается. Number of iterations, residual thresholds, source sampling, gamma и hole fallback не меняются.

Это algebraic equivalence для positive finite perspective depth, не гарантия FP equivalence: округление коэффициентов/умножения меняет UV и equality used by early exit; возле sampling boundaries возможны отличия. Canonical ordinary shaders сохранены, inverse mode opt-in. Capture snapshot fallback при TAA/additional effects копирует raw depth, поэтому interpretation остаётся совместимой.

```sh
python3 benchmarks/inverse-depth/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/inverse-depth/rendered1024
python3 benchmarks/inverse-depth/quality.py benchmarks/inverse-depth/rendered1024
```

Quality.py требует NumPy/Pillow; локально bundled Python `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`. Shader variants генерируются generate_workgroups.py и заранее импортируются Godot.

A/B: Apple M4, Godot 4.8-dev, Vulkan/MoltenVK, 24 real → 48 output 1024², 512 static MultiMesh boxes, foreground bars/несколько глубин, четыре SpotLight shared atlas. Borrowed color/raw depth, current snapshot safety policy, profiling on, 8×8, 8 iterations, rescue off. Три пары с alternating order. 90 warmup + 240 observed update intervals. GPU quilt markers включены одинаково; GPU mean включает startup, не whole-frame GPU time. Saved PNG первой пары сравниваются численно на synthesized tiles и anchors; fresh 48-real reference использует тот же HDR→simple gamma transfer.

Analytic tests: inverse-depth planar shifts с zero/positive/negative disparity; recoverable layered depth case для rescue; near/far 0.01/5000. Эти тесты не доказывают FP identity всех изображений. Benchmark проверяет pixel fraction, MAE и PSNR, а также real-anchor equivalence.

Ограничения: одна статическая непрозрачная сцена/один GPU; curved/moving/transparency, extreme clip in real scenes, native Metal/другие GPU/physical Looking Glass не измерены. Combinations всех iteration/group/rescue variants не все отдельно выполнены. Shader compiler мог уже оптимизировать часть исходных делений; ускорение не предполагается заранее.


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
