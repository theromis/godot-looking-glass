# Projection and quilt ordering audit

Inspected on 2026-10-12 against the official LookingGlassCoreSDK example, revision `5f786480e8906396a06a442a18e9091ef9e0aa74`. Source was read externally for reference; no implementation was copied into this addon. The example's [license](https://github.com/Looking-Glass/LookingGlassCoreSDK/blob/5f786480e8906396a06a442a18e9091ef9e0aa74/ExampleProject/LICENSE) is MIT. It is a legacy Core/OpenGL example, not proof of the complete current Bridge/Metal optical contract.

## Off-axis projection

Official [`HoloPlayContext::setupVirtualCameraForView()`](https://github.com/Looking-Glass/LookingGlassCoreSDK/blob/5f786480e8906396a06a442a18e9091ef9e0aa74/ExampleProject/src/HoloPlayContext.cpp#L664) computes the negative view-matrix camera distance from size/FOV at line 673, per-view angle at 675–678, a tangent-derived offset at 680–682 and projection shear at 691–693. After accounting for camera-world versus view-matrix translation sign, this is the same off-axis convergence concept as addon `rig.gd:104–109`: translate the camera along X and offset its frustum by `-eye * near / focus`. It does not rotate every camera toward a common point.

`tests/test_rig.gd` passed on Godot 4.8: focal-plane registration, opposite near/far screen disparity, transformed-rig registration and quilt size for 1/2/12/47/48/66 views. The 66-view case uses focus 5.6, camera-span reference 6.0 and a 20° parameter. These are API geometry checks, not a complete optical calibration test.

One verified difference remains: the official example samples uniform angles and converts each with tangent; `rig.gd:62–65` samples uniform eye offsets across the tangent-derived endpoints. Endpoints agree when the same distance/cone is used, but interior views are not mathematically identical. No angular-spacing change has been adopted and its contribution to residual double images is unmeasured. The example also uses a 14° vertical FOV for its historical display/user-distance assumptions; our diagnostic uses 35°. That example value is not treated as universal.

The diagnostic decouples convergence from camera span. With a span-reference distance different from convergence distance, the parameter called view cone determines the reference baseline rather than the exact angle subtended at the new convergence plane. Device calibration is separate and unchanged.

## Quilt orientation

Official `HoloPlayContext::run()` packs X from view-index modulo columns and Y from view-index divided by columns at [`HoloPlayContext.cpp:231–245`](https://github.com/Looking-Glass/LookingGlassCoreSDK/blob/5f786480e8906396a06a442a18e9091ef9e0aa74/ExampleProject/src/HoloPlayContext.cpp#L231). Its OpenGL origin is bottom-left. Addon `synthesizer.gd:69–70` reverses the row index for top-origin image/storage coordinates. This matches the conceptual bottom-left-to-top-right tile sequence, but the platform image-origin/SDK mapping still needs physical checks rather than assuming numerical row equivalence.

At the connected preset, tile dimensions 372×682 give aspect approximately 0.54545, whereas device view aspect is 0.5625. The rig derives camera aspect from its SubViewport tile dimensions; the official example uses window aspect via `getWindowRatio()` at lines 352–355 and 689. This small framing/aspect difference has not been corrected or isolated as a source of ghosting.

## Physical grid diagnostic

`--projection-grid` replaces scene meshes/lights with unshaded white grid quads exactly on the convergence plane and two small markers: red at +0.5 world Z (near), blue at -0.5 (far) relative to that plane. At rig Z=6 and focus 5.6, the grid is at world Z=0.4. Equal depth offsets need not have equal screen disparity under perspective.

The test ran with 66 real views, 4092² quilt, 20° reference-cone parameter, fixed camera span reference 6.0 and unchanged device calibration. The user confirmed that the grid was stable/sharp and the markers had correct foreground/background depth. This rejects a gross convergence-registration failure or simple reversed depth ordering in this diagnostic; it does not eliminate view-spacing, aspect, optical crosstalk, viewer-position or calibration-accuracy issues. See [actual record](../benchmarks/hardware/projection-grid.json).

```sh
GODOT_MTL_SYNC_MODE=none "$GODOT" --path . --rendering-driver metal --script tests/test_bridge_direct_target.gd -- --large --real-views=66 --view-cone=20 --focus=5.6 --projection-grid
```

Next controlled candidates are official-style angular sampling, a display-aspect projection correction, or reduced scene depth around the registered plane. None is a verified fix or automatically enabled default.
