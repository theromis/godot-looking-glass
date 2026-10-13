# Experimental addon package validation

Executed October 12, 2026 on Apple M4, Godot 4.8 c61fc0118 **editor** build with native Metal Forward+ and `GODOT_MTL_SYNC_MODE=none`.

Two archives were built using `tools/package_addon.py`. The macOS-arm64 variant contains our worker and GDExtension, statically linked MIT godot-cpp at revision `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`, with its license. It includes the corresponding own adapter sources but no Bridge SDK headers/runtime. The preview-only variant contains no native components. Both contain the addon, MIT license, English installation guide and demo.

`tools/check_addon_package.py` verified all per-file hashes, safe addon-relative archive paths, absence of SDK/cache/user-home paths, and installation into new temporary projects. No resources or `.godot/` cache were copied from the source project. The checker enabled the editor plugin, performed initial GLSL imports with a real editor build, then ran the demo. Executable permissions were restored from ZIP metadata.

| Archive | Editor import/plugin | No-hardware preview | Physical output lifecycle |
| --- | --- | --- | --- |
| macOS arm64 | Passed | Passed | 114/114 frames; clean SDK teardown, exit 0 |
| Preview only | Passed | Passed, no Bridge environment | Not applicable |

All executed stages exited 0 without Godot script/runtime errors. A second native archive generation from identical inputs produced the same SHA256. ZIP timestamps and file permissions are normalized. This does not imply reproducible native compilation across toolchains.

The native dylib uses an `@rpath` install name instead of a local build path. Packaging checks arm64 architecture, code-signature validity and only system/native library dependencies. Components are ad-hoc signed, not notarized; no developer identity is embedded. Native artifacts are ignored by Git and remain available locally in `dist/`.

The existing test engine was a template-release build and could not perform first-time imports; its initial isolated invocation emitted a missing global-script-cache error. A separate editor was built from the same source revision. The first editor link lacked the ZIP module in the minimal configuration; adding `module_zip_enabled=yes` completed the build. No engine source edits were needed. These setup attempts are not counted as successful package tests.

Records: [native ZIP](../benchmarks/hardware/addon-package-native.json), [preview ZIP](../benchmarks/hardware/addon-package-preview.json). Follow [installation instructions](addon-installation.md). The older source-checkout unavailable-device test also passed after moving default native paths into the addon directory and retaining the development build-directory fallback.

No new physical visual confirmation was collected. This is an experimental installable package, not a production synchronization guarantee. Hot-unplug, unsupported quilt grids, Windows/Linux hardware output, notarization and exported application bundling remain unqualified.

After capture-ownership changes, both packages were rebuilt and isolated-project checks repeated. The native run received 114/114 frames with clean SDK teardown; preview-only import and preview also passed. Records contain the updated archive hashes.
