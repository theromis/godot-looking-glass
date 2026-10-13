# Install the experimental Looking Glass addon

This is version 0.1.0-experimental, not a production release. GPU synthesis is experimental. Physical output currently requires macOS on Apple Silicon, native Metal, the separately installed Looking Glass Bridge runtime, and a supported 11×6 device quilt preset. The desktop center-camera preview works without Bridge. Windows/Linux hardware output, arbitrary device presets, automatic reconnect and exported application packaging are not qualified.

## Install into an existing project

1. Extract the ZIP into the Godot project root. It contains only `addons/looking_glass/`; keep that directory name because shader paths use it. Use an archive extractor that preserves executable permissions for `native/probe-persistent`.
2. Open the project with Godot 4.8 using Forward+. Let the editor import GLSL shaders. The GDExtension minimum API is 4.5, but this package was tested with Godot 4.8 only.
3. Optionally enable **Looking Glass Lab** under Project Settings → Plugins to expose `LookingGlassRig` and `LookingGlassMetalOutput` in the node dialog. The demo does not require enabling the editor plugin.
4. Open `addons/looking_glass/examples/metal_output.tscn` and run that scene. Desktop preview should animate immediately.
5. For physical output, configure the external Bridge library in the UI or through `BRIDGE_LIBRARY`, click **Discover displays**, select a supported device and click **Start**. Use **Stop** before removing the component.

Tested native Metal invocation from the project root:

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT_BINARY" --path . --rendering-driver metal \
  res://addons/looking_glass/examples/metal_output.tscn
```

Set `GODOT_BINARY` and `BRIDGE_LIBRARY` to your installations outside the project. The `none` setting changes Metal hazard tracking; it does not disable all synchronization. The demo uses 24 real views → 66 views, GPU RGBA8 quilt composition, a queried device aspect, and a conservative 30-degree cone. Output is bounded to 60 seconds per start; it can be restarted. Submitted/worker-copy counters are not physical display FPS.

## Native components and licensing

The macOS-arm64 package contains our worker and GDExtension, linked to MIT-licensed godot-cpp; its license is included. Bridge SDK headers and runtime binaries, proprietary Unity code, project caches and benchmark captures are excluded. Looking Glass Bridge must be obtained separately under its own terms. The SDK performs display calibration internally; public numeric preset/aspect/cone discovery does not expose serial numbers in the UI.

Native components are locally ad-hoc signed, not Apple Developer ID signed or notarized. A downloaded archive may require approval through normal macOS security controls. Do not disable Gatekeeper globally. The preview-only package contains no native binaries and can be used to try the scene without Bridge. Its demo Start action requires separate native builds.

The persistent SDK texture-consumption contract remains unverified. Bounded restart/memory tests passed on Apple M4, but hot-unplug and indefinite use are not guaranteed. See the source repository documentation for measured limits and synchronization details.

## Build the package from source

From the source repository root, build the native worker and extension using `native/bridge_metal/README.md`, with external SDK headers and godot-cpp. Then run:

```sh
python3 tools/package_addon.py --godot-cpp-license "$GODOT_CPP_LICENSE"
# No native dependencies required for this variant:
python3 tools/package_addon.py --preview-only
```

Archives are generated under `dist/`, which is excluded from Git. Each includes `PACKAGE.json` with per-file SHA256 checksums and explicit experimental status. Native sources are included for reference; rebuild them from the source repository with the documented external dependencies. Keep generated `.godot/` caches out of distributions.

To verify a package in a new temporary project, use a Godot **editor** build (a template-release executable cannot perform initial shader import):

```sh
python3 tools/check_addon_package.py \
  --package dist/looking-glass-godot-0.1.0-experimental-macos-arm64.zip \
  --godot-editor "$GODOT_EDITOR" --runtime "$BRIDGE_LIBRARY" \
  --output benchmarks/hardware/addon-package-native.json
```

For preview-only checks, select its ZIP and omit `--runtime`. The checker validates every manifest checksum, extracts only addon files, enables the editor plugin, imports shaders and runs the demo. It supplies the tested Metal hazard-tracking setting. No cache or resources from the source project are copied. ZIP entry timestamps and permissions are normalized so packaging identical inputs produces identical archives.
