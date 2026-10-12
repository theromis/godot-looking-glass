# Community announcement draft

Suggested venue: [Godot Forum — Resources / Plugins](https://forum.godotengine.org/c/resources/plugins/21). The repository is public; the link below is accessible without authentication. This file is a draft, not evidence that an announcement has been posted.

## Title

Looking Glass Godot Lab: GPU quilts and depth-based view synthesis (MIT)

## Post

I am building an experimental Godot 4 addon for light-field rendering and would welcome feedback from rendering developers and Looking Glass owners.

Repository: https://github.com/theromis/godot-looking-glass

The addon currently provides:

- Configurable off-axis cameras sharing one World3D, with real-view and synthesized-view budgets.
- GPU quilt composition and a preview that works without display hardware.
- Experimental two-source depth reprojection, optional bounded correspondence rescue, and explicit on-demand updates for static scenes.
- Looking Glass Bridge device detection and calibration parsing over HTTP.
- Reproducible benchmarks, image comparisons, tests, and an optional shared positional-shadow-atlas engine patch.

The latest Godot regression run passed 16 checks on a custom 4.8-dev Vulkan/MoltenVK build on Apple M4. The normal addon can run without the optional engine patch. Performance results are specific to documented scenes; some optimization experiments did not improve speed or quality.

**End-to-end Godot-to-display output is not implemented or validated yet.** Bridge HTTP detection is a control-plane feature, not GPU display submission. A separate one-shot Metal adapter passed real GPU/IOSurface tests against a test SDK implementation and loaded the installed SDK, but is not connected to Godot. Transparency, disocclusions and temporal stability still need work.

The addon code is MIT-licensed. No proprietary Unity plugin implementation or Bridge runtime binaries are included. Development uses Codex/LLM tools to generate and edit code, tests and documentation; reported measurements come from executed experiments.

I am especially interested in feedback on source-buffer lifetime, multi-view shadow reuse, depth-based visibility reconstruction, and tests on other GPUs or actual Looking Glass hardware. The README starts with a checklist separating completed experiments from unfinished work.

## Posting notes

- The public repository and working demo are the primary deliverables; do not describe the addon as complete hardware integration.
- Add a screenshot or short recording of the actual quilt preview when available. A preview is not a photo/video of physical display output.
- Use one forum topic rather than duplicating the announcement across categories. Review [forum guidelines](https://forum.godotengine.org/guidelines).
- For an Asset Store submission, first prepare and test an installable release. The [official FAQ](https://docs.godotengine.org/en/latest/community/asset_store/faq.html) allows functional alpha/beta releases and requires disclosure of AI-generated code/assets and how AI was used. Review the store's current submission requirements when submitting.
