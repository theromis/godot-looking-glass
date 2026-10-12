# Compute workgroups A/B/C

```sh
python3 benchmarks/workgroups/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/workgroups/rendered1024
```

Сравниваются 8×8 (64 invocation), 16×8 (128) и 16×16 (256). Меняется только shader local size и размер dispatch grid; алгоритм, capture mode и сцена одинаковы. Runtime selector: `--workgroup=8x8|16x8|16x16`, addon export `synthesis_workgroup`. Default остаётся 8×8 до оценки результатов и других GPU. GLSL variants импортируются заранее; compilation не включается в measured loop. После изменения canonical shaders выполнить `python3 addons/looking_glass/shaders/generate_workgroups.py` и Godot editor import.

Сцена: Apple M4, Godot 4.8-dev, Vulkan/MoltenVK, 24 real → 48 output, tile 1024², 512 static MultiMesh boxes, 4 SpotLight, shared shadow atlas, borrowed color+depth. Три повтора каждого режима; порядок циклически меняется: A/B/C, B/C/A, C/A/B. 90 warmup + 240 observed quilt update intervals. Два quilt GPU timestamps включены одинаково во всех вариантах; GPU mean включает startup samples и не означает полное GPU-время кадра. Saved PNG первой тройки сравниваются SHA256. JSON/log/PNG сохраняются; wall-clock аномалии не скрываются и требуют отдельного анализа.

Все четыре regression checks прошли на official 4.5.1 и experimental 4.8. Lifetime test проверяет 9 сочетаний capture/workgroup, exact raw quilt, output tile 65×67, resize источников 64/49/81 и сохранность borrowed resources после release. Это проверяет coverage частичной группы и отсутствие записи за границами тайла.

Результаты ограничены одной сценой и одним GPU. Larger groups могут менять occupancy, количество активных групп, register pressure и locality; ускорение не предполагается заранее. TAA/FSR2/MSAA/post effects и физический Looking Glass не проверены.


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
