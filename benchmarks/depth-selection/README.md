# Direct validation of depth-guided camera placement

**Negative result:** selecting real cameras using either tested depth-only cost worsens total RGB reconstruction error compared with uniform placement in these fixtures. Normal addon defaults and engine rendering code remain unchanged; automatic selection is not enabled.

## Fixed protocol

Apple M4, Vulkan Forward+, custom Godot 4.8-dev and official 4.5.1. Three unshaded opaque fixtures (`smooth`, `bars`, `layers`), each at three translated/rotated camera poses. 48 output views, 24 real cameras, 256² tiles, raw reverse-Z depth, ordinary eight-iteration synthesis. No shadows, transparency, MSAA/TAA, temporal reprojection or physical Looking Glass validation.

Both endpoints are real and the maximum index gap is three. Two policies are tested separately, without fitted weights or a combined model:

- `both_invalid`: sum of pixels with invalid reconstruction from both bracketing sources.
- `source_horizontal_depth_edge`: sum of depth-edge proxy counts across intermediate views.

The probe samples every output pixel on a 256² grid. Dynamic programming minimizes the sum of interval costs. Exact score ties prefer the layout with minimum squared deviation from corresponding uniform anchor indices; primary scores are never overridden by this preference. `protocol.json` records these choices. Uniform and an RGB-reference-assisted oracle are comparison policies. The oracle is optimal only for the measured additive RGB SSE model, 24 anchors and max gap three.

## Selection uses no colors or reference

`select_depth.py` reads only GPU counter JSON and creates a frozen depth-only selection. It never imports an image library or opens reference/color images. Its output was reproduced exactly in a temporary directory containing only `raw.json`, with no images available.

Only afterwards does `add_oracle.py` read colors and the all-real reference to build a separately labeled oracle and predict the RGB error of the already-frozen depth selections. The frozen selector file hash is retained. Adding oracle/evaluation metadata does not change either depth policy's anchor indices.

This is still an **offline** experiment. Five interleaved candidate capture grids provide every interval of length two or three, and collectively require depth at all candidate camera indices. The current harness renders complete views to obtain these buffers. It is not a demonstrated runtime method using only the final 24 cameras, and the capture/probe/readback cost has not been amortized or benchmarked.

## Verified results

Independent renders used the chosen anchors. All 24 real tiles match each version's own all-real reference exactly. The reference is unchanged between cost capture and validation. Actual whole-quilt squared RGB error matches the interval prediction exactly for all four policies at all nine poses, including the oracle. This validates the cost model/solver for these test conditions; it does not establish a general renderer contract.

The table shows **change in summed squared RGB error relative to uniform** on custom 4.8; negative is better. Each scene combines three poses, and the total combines all nine with the same pixel denominator.

| Scene | Both-invalid selection | Depth-edge selection | Reference oracle |
|---|---:|---:|---:|
| Smooth sphere | −6.22% | +2.37% | −34.58% |
| Foreground bars | +15.44% | +58.94% | −18.79% |
| Layered objects | +7.15% | +11.81% | −9.19% |
| All poses | **+12.14%** | **+43.72%** | **−17.14%** |

Both-invalid improves three poses and worsens six. Depth-edge improves one and worsens eight. The oracle improves all nine. Overall whole-quilt PSNR is 30.053 dB uniform, 29.556 dB both-invalid, 28.478 dB edge, 30.870 dB oracle. These totals weight scenes by their RGB error; inspect per-scene/per-pose records rather than treating them as a universal quality score.

The selected policies improve their own intended proxy objectives: aggregate both-invalid count decreases 25.732%, and edge count decreases 5.829%. Their RGB error nevertheless rises. Thus the solver successfully minimizes these proxies, but the proxies are insufficient as direct quality objectives here. This is stronger evidence than the earlier moderate proxy/error correlations.

Official 4.5.1 chooses identical depth-policy layouts. Its total RGB-error changes are +12.15%, +43.70%, and −17.10% for the oracle, reproducing the conclusion with renderer-version-specific references. Cross-version RGB pixels are not assumed identical. Each version's all-real reference also matches the preceding depth-proxy experiment, verifying that fixture extraction preserved the test scenes.

Possible explanations, **not isolated causal findings**: invalid correspondences include solver failures and off-screen samples, and do not measure color loss; fallback colors can be close to the correct image; valid correspondences can still produce visible error; depth-only edges do not encode color contrast. No learned estimator or adjusted weights were used to repair the result after seeing it.

## Files and tests

- `tests/test_depth_selection.gd`: candidate capture and separate validation renders, with actual camera transforms changing over sixteen draws and two settling draws per pose. No adaptive switching/flicker test is performed.
- `tests/test_depth_proxy.gd`: shared fixture generator, extracted without changing geometry/materials.
- `select_depth.py`, `add_oracle.py`, `evaluate.py`: strictly separated depth selection, reference oracle, and independent image validation.
- `benchmarks/interval-placement/optimize.py`: exact additive solver with optional uniform tie preference; three tests compare against exhaustive search, including ties, infeasibility and missing cost rejection.
- `costs48/`, `validation48/`, `costs45-debug/`, `validation45/`: PNGs, raw counts, anchors, actual submission counts and provenance. The `debug` folder name only identifies the official-engine capture run; it is valid data.

The final run wrapper was executed for an independent repeat on custom 4.8; all quilt PNG hashes and per-pose error records exactly match the first successful validation.

The first validation attempt rejected a JSON number-type mismatch before recording valid results. The harness now converts JSON camera indices to integers before comparing effective anchors. All reported results come from complete successful runs and exact pixel/error checks.

No frame-time gain is claimed. Extra candidate renders, synchronous texture/buffer readbacks, shader setup and CPU selection are diagnostic overhead. No production adaptive controller, new engine patch, Bridge/hardware behavior or transparency feature is added.

## Reproduce

Import the project's shaders using Godot first. From project root, with Python Pillow/NumPy for the oracle and image evaluation:

```sh
python3 benchmarks/depth-selection/run.py --godot path/to/godot --results-dir benchmarks/depth-selection/new-costs
python3 benchmarks/depth-selection/select_depth.py benchmarks/depth-selection/new-costs --output benchmarks/depth-selection/new-depth-only.json
python3 benchmarks/depth-selection/add_oracle.py benchmarks/depth-selection/new-costs --depth-selections benchmarks/depth-selection/new-depth-only.json --output benchmarks/depth-selection/new-selections.json
python3 benchmarks/depth-selection/run.py --godot path/to/godot --results-dir benchmarks/depth-selection/new-validation --selections benchmarks/depth-selection/new-selections.json
python3 benchmarks/depth-selection/evaluate.py benchmarks/depth-selection/new-validation --costs benchmarks/depth-selection/new-costs --selections benchmarks/depth-selection/new-selections.json
python3 benchmarks/interval-placement/test_optimize.py
```

The same executable/scene should be used for costs and validation. The renderer harness verifies actual synthesis work, sorted endpoints and camera budgets; the evaluator rejects differing real anchors, reference changes and any disagreement with predicted interval error.

## Consequence

Keep uniform placement as the default. There is measurable room to improve placement under the reference oracle, but these depth-only costs do not reliably find it, even on previously inspected fixtures. They may remain useful as auxiliary scene-complexity signals. Before a production policy, evaluate a conservative estimator that includes source-image/visibility evidence without a full reference, test genuinely new scenes, and measure candidate-acquisition and transition overhead. This experiment is not evidence that adaptation is impossible; it rejects these two direct selection objectives under the tested conditions.
