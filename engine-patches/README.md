# Эксперимент: общий atlas позиционных теней

Патч к MIT-исходникам Godot, база `232e6b14abf6e590b41d60f11704e42de22bff72` (4.8-dev). Код Looking Glass/Unity не использован. Исходный checkout: `/Users/roman/work/godot`; patch сохранён отдельно для review и переноса.

Добавлен `RenderingServer.viewport_set_positional_shadow_atlas_shared_from(viewport, source)`. По умолчанию off. Пустой RID отключает sharing. Каждый viewport сохраняет владение собственным atlas; owner не передаётся. Источник всегда использует собственный atlas, цепочки и циклы не допускаются. Удалённый source RID автоматически вызывает fallback.

Условия фактического sharing проверяются каждый render:

- одинаковый, валидный scenario;
- у обеих камер `cull_mask == 0xFFFFF` (все 20 слоёв);
- `mesh_lod_threshold == 0` у обоих viewport;
- одинаковые atlas size и depth precision;
- tighter shadow caster culling отключён **при старте renderer**: `rendering/lights_and_shadows/tighter_shadow_caster_culling=false`.

Directional shadows, culling основной геометрии, Forward+ clusters и draw calls основных видов этим не объединяются. Atlas allocations зависят от camera coverage и настроек subdivision источника; качество и разрешение теней необходимо сравнивать. Сохранение отдельных fallback atlases означает, что освобождение их GPU памяти ещё не реализовано. Патч не обещает одинаковый shadow resolution для произвольных камер и конфигураций. Не является общим production API для любых SubViewport.

Исходники: `RendererViewport::_draw_3d`, `servers/rendering/renderer_viewport.cpp:334–350`; setter там же `:1391`; eligibility `RendererSceneCull::camera_can_share_positional_shadows`, `servers/rendering/renderer_scene_cull.cpp:157`; read-only `RenderingLightCuller::uses_full_shadow_casters`, `servers/rendering/rendering_light_culler.h:164`. Существующий механизм `shadow_atlas_update_light` и `InstanceLightData::last_version` предотвращает повторный draw неизменившейся shadow map внутри общего atlas; новая камера по-прежнему может вызвать allocation/reallocation.

## Сборка в этой среде

SCons установлен в отдельный venv `/Users/roman/work/tools/godot-build-venv`. Homebrew `/opt/homebrew/lib/libMoltenVK.a` подключён через symlink SDK-layout `/Users/roman/work/tools/mvk-sdk/macos-arm64/libMoltenVK.a`.

```sh
cd /Users/roman/work/godot
/Users/roman/work/tools/godot-build-venv/bin/scons \
  platform=macos target=template_release arch=arm64 disable_path_overrides=no \
  vulkan_sdk_path=/Users/roman/work/tools/mvk-sdk accesskit=no metal=no \
  modules_enabled_by_default=no module_gdscript_enabled=yes \
  module_text_server_fb_enabled=yes module_freetype_enabled=yes \
  module_godot_physics_3d_enabled=yes module_glslang_enabled=yes -j8
```

Это минимальный runtime, не editor. Shader resources проекта предварительно импортированы официальным Godot 4.5.1. Native Metal backend исключён; тестируется Vulkan/MoltenVK.

## Сравнение

```sh
cd /Users/roman/work/godot-looking-glass
python3 benchmarks/engine-shadows/run.py /Users/roman/work/godot/bin/godot.macos.template_release.arm64
python3 benchmarks/engine-shadows/summarize.py
/Users/roman/work/godot/bin/godot.macos.template_release.arm64 \
  --path benchmarks/engine-shadows/project --rendering-driver vulkan \
  --script res://tests/test_shared_shadows.gd
```

Runner создаёт отдельный project.godot с full caster culling; ресурсы addon/demo/tests linked, import cache copied. Три пары baseline/shared чередуются на одном бинарнике, одинаковые lighting/LOD/frame motion. Метрики: wall frame delta, сумма per-viewport GPU durations, сумма shadow draw calls. GPU sum не равна критическому пути всего кадра. PNG readback выполняется после измерений. Стандартный addon сохраняет отдельные atlases и tighter culling; для opt-in backend задайте `rig.shared_positional_shadows=true` до `_ready()` и startup setting выше.


## Результат исполнения

Сборка завершилась успешно (`benchmarks/optimization/engine-build-path.log`). Для 48 real views: 32.964 → 21.983 ms/frame (−33.3%), GPU viewport sum 31.890 → 18.913 ms (−40.7%), shadow draw calls 2112 → 44. Три пары прогонов на M4; PNG baseline/shared byte-identical. Для 12 views frame time не улучшился. Подробная методика и ограничения — `docs/performance-optimization.md`, JSON — `benchmarks/engine-shadows/v48-summary.json`.

GPU test с Omni/Spot, LOD/mask/chain fallback и освобождением owner прошёл. Projection/GPU synthesis/Bridge tests прошли на stock 4.5.1 и patched 4.8. Для 48-view сравнения runner принимает дополнительный аргумент `48`, summarize — аргумент `48`. Release templates не выполняют GDScript assert; тесты используют явные проверки с ненулевым exit code.

Stock 4.5.1 с `--shared-shadows` проверен отдельным запуском: API unavailable warning, корректный independent atlas fallback, benchmark завершён без errors (`stock-fallback.log/json`).

Лицензия исходников Godot и copyright notice: [GODOT-LICENSE.txt](GODOT-LICENSE.txt).
