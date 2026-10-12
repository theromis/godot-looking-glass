# Disocclusion correspondence rescue

```sh
python3 benchmarks/disocclusion/run.py --godot /Users/roman/work/godot-theromis-shadow-atlas-pr/bin/godot.macos.template_release.arm64 --tile 1024 --rendered --results-dir benchmarks/disocclusion/rendered1024
python3 benchmarks/disocclusion/quality.py benchmarks/disocclusion/rendered1024
```

The quality script requires Pillow/NumPy; local bundled Python: `/Users/roman/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`.

Opt-in `--rescue`; rig `disocclusion_rescue=false` by default. Separate canonical shaders `synthesize_rescue.glsl` and `synthesize_raw_depth_rescue.glsl`; baseline unchanged. Generated variants support existing workgroup and iteration selectors.

Algorithm: only when both initial gathers fail, test depth at horizontal source UV offsets ±1/±2/±4 texels independently for both sources. Each depth hypothesis computes the source landing UV for the original target pixel. Check actual depth there and forward residual <0.5 output pixel. Choose the nearest valid surface. If none is valid, retain the previous unwarped fallback or debug magenta. This is not neighboring-color smearing and cannot recover surfaces hidden in both sources. Limited search can miss a layer; projection agreement does not guarantee physical target visibility or temporal stability.

Scene: static opaque, 512 MultiMesh boxes, foreground bars/multiple depths, 4 SpotLights sharing an atlas, 24 real → 48 output, 1024², borrowed color/depth, 8 iterations and 8×8 groups. Three alternating baseline/rescue pairs; 90 warmup + 240 observed intervals. GPU quilt mean includes startup and markers, not whole-frame GPU time.

Additional captures: fresh 48-real reference with identical HDR→gamma transfer, and two debug-hole quilts. Magenta marks both gathers invalid before/after rescue, not ground-truth disocclusion. The scene has no exact-magenta materials. RGB MAE/PSNR and changed-pixel fractions are computed separately for synthesized tiles and real anchors. Recovered-correspondence masks compare baseline/rescue PSNR against independent all-real output. Fewer magenta pixels alone do not prove improvement.

Limitations: one scene/GPU; motion, curved geometry, particles/transparency, MSAA/TAA/FSR2/post effects and physical Looking Glass untested. Arbitrary cone/clipping/radius settings were not explored. No new engine patch.


## Measured results

Apple M4, Godot 4.8-dev/Vulkan-MoltenVK, 24 → 48, 1024², three pairs:

- Synthesis+quilt GPU time: baseline 10.997 ± 0.033 ms → rescue 11.364 ± 0.021 ms, +3.34%. Standard deviation of three run means.
- Observed update interval: 48.019 ± 0.184 → 48.188 ± 0.057 ms, +0.35%. No speedup.
- Invalid two-source correspondences: 681614 → 667752 of 25165824 synthesized pixels. Recovered 13862 (2.03% of the initial invalid mask), with no new holes.
- Recovered-mask PSNR against all-real: 6.928 → 18.624 dB. Overall synthesized PSNR: 22.757 → 22.843 dB; RGB MAE 2.332 → 2.292 in 8-bit units.
- Real anchors exact; changed pixels outside the baseline hole mask = 0. Baseline PNG SHA matches the earlier 8-iteration benchmark.

Conclusion: small measured quality improvement at additional GPU cost. Opt-in `--rescue`, default false. Limited correspondence search does not eliminate all disocclusions. This static test cannot establish freedom from temporal flicker/foreground bleeding elsewhere. Raw JSON/log/PNG retained; no wall anomalies at ratio>1.5.

Eight regressions passed on 4.5.1 and 4.8: projection, planar 8/2/4, synthetic recoverable layers on linear/reverse-Z depth, capture/workgroup lifetime, Bridge fixture. Synthetic source depths 2/3/6 occupy neighboring strips: baseline oscillates 2↔6, while hypothesis 3 recovers the analytically known source pixel. Not every generated rescue/group/iteration combination was executed; performance/quality measured at 8×8/8.

Method: benchmarks/disocclusion/README.md.
