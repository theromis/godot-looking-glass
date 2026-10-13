extends Node3D
## Independent cameras with a shared World3D. Rebuild by replacing the rig.
const Capture = preload("capture.gd")
const Synthesizer = preload("synthesizer.gd")
@export_range(1, 96) var total_views: int = 12
@export_range(1, 96) var real_views: int = 12
@export_range(1, 12) var columns: int = 4
@export var tile_size: Vector2i = Vector2i(192, 256)
## Optional camera render size, distinct from quilt tile size. Zero uses tile_size.
## Changing this also changes the projection aspect; set before ready.
@export var source_view_size: Vector2i = Vector2i.ZERO
@export_range(1.0, 80.0) var view_cone_degrees: float = 35.0
## Optional reference-style uniform angular sampling; default remains linear eyes.
@export var angular_view_sampling: bool = false
@export_range(1.0, 120.0) var vertical_fov: float = 35.0
@export_range(0.2, 50.0) var focus_distance: float = 6.0
## Diagnostic: keep camera spacing fixed while changing convergence distance.
## Zero preserves the default baseline derived from focus_distance.
var camera_span_reference_distance: float = 0.0
@export var near_clip: float = 0.1
@export var far_clip: float = 40.0
## Optional strictly increasing indices including both end views. Set before ready.
@export var custom_anchor_indices: PackedInt32Array = PackedInt32Array()
## Set before ready. Scene/material/light changes require request_update().
## Supported for compute synthesis; camera rig motion requests updates automatically.
@export var update_on_demand: bool = false
## Disable when an external output scheduler owns capture requests.
## Camera transforms still follow the rig; call request_update() explicitly.
@export var auto_update_on_transform: bool = true
## Opt-in: record quilt dispatch after the last capture, before frame submission.
@export var compose_in_capture_callback: bool = false
var requested_revision: int = 0
var completed_revision: int = 0
var _render_requested_revision: int = 0
var _render_completed_revision: int = 0
var _render_required_capture_counts: Array[int] = []
@export var synthesis: bool = false
## Compute output only. Clamps existing gamma-encoded output to normalized RGBA8.
## Set before ready; this does not apply HDR tonemapping or another gamma curve.
@export var quilt_rgba8: bool = false
## Optional externally owned RGBA8 storage texture. Owner must keep it alive
## until the rig is released; set before ready. Native diagnostic use only.
var external_quilt_target: RID
@export var shared_positional_shadows: bool = false
@export var measure_render_time: bool = false
@export var profile_synthesis: bool = false
@export_range(1, 4096) var profiling_sample_limit: int = 480
@export var borrow_source_color: bool = false
## Borrowing depth also borrows color; experimental Forward+ path.
@export var borrow_source_depth: bool = false
@export var disocclusion_rescue: bool = false
## Inverse-depth shader uses raw reverse-Z input; enables borrowed-depth request.
@export var inverse_depth_reprojection: bool = false
@export_enum("2:2", "4:4", "8:8") var reprojection_iterations: int = 8
@export_enum("8x8", "16x8", "16x16") var synthesis_workgroup: int = 0
var shared_shadow_api_available: bool = false
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var anchor_indices: Array[int] = []
var captures: Array = []
var camera_offsets: Array[Transform3D] = []
var last_rig_transform: Transform3D
var quilt_viewport: SubViewport
var gpu_quilt: Texture2DRD
var synthesizer: RefCounted
var quilt_texture: Texture2D:
    get:
        if synthesis and gpu_quilt != null:
            return gpu_quilt
        return quilt_viewport.get_texture() if quilt_viewport != null else null

func eye_at(index: int) -> float:
    var t: float = float(index) / float(total_views - 1) if total_views > 1 else 0.5
    var span_distance: float = camera_span_reference_distance if camera_span_reference_distance > 0.0 else focus_distance
    if angular_view_sampling:
        return span_distance * tan((2.0 * t - 1.0) * deg_to_rad(view_cone_degrees) * 0.5)
    return (2.0 * t - 1.0) * span_distance * tan(deg_to_rad(view_cone_degrees) * 0.5)

func get_source_view_size() -> Vector2i:
    return source_view_size if source_view_size != Vector2i.ZERO else tile_size

func _ready() -> void:
    if inverse_depth_reprojection:
        borrow_source_color = true
        borrow_source_depth = true
    total_views = clampi(total_views, 1, 96)
    real_views = clampi(real_views, 2 if total_views > 1 else 1, total_views)
    columns = clampi(columns, 1, total_views)
    assert(tile_size.x > 0 and tile_size.y > 0 and far_clip > near_clip)
    assert(get_source_view_size().x > 0 and get_source_view_size().y > 0)
    if not synthesis:
        real_views = total_views
    elif RenderingServer.get_rendering_device() == null:
        push_warning("Compute unavailable; using all-real GPU raster quilt.")
        synthesis = false
        real_views = total_views
    if update_on_demand and not synthesis:
        push_warning("On-demand updates require compute synthesis; using continuous rendering.")
        update_on_demand = false
    shared_shadow_api_available = RenderingServer.has_method("viewport_set_positional_shadow_atlas_shared_from")
    if shared_positional_shadows and not shared_shadow_api_available:
        push_warning("Shared positional shadows require the optional engine patch; using independent atlases.")
    anchor_indices = select_anchor_indices()
    for i in range(real_views):
        var index: int = anchor_indices[i]
        var viewport := SubViewport.new()
        viewport.size = get_source_view_size()
        if shared_positional_shadows:
            viewport.mesh_lod_threshold = 0.0
        viewport.world_3d = get_world_3d()
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        add_child(viewport)
        views.append(viewport)
        RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), measure_render_time)
        var camera := Camera3D.new()
        camera.keep_aspect = Camera3D.KEEP_HEIGHT
        viewport.add_child(camera)
        camera.current = true
        cameras.append(camera)
        var eye: float = eye_at(index)
        var height: float = 2.0 * near_clip * tan(deg_to_rad(vertical_fov) * 0.5)
        camera.set_frustum(height, Vector2(-eye * near_clip / focus_distance, 0), near_clip, far_clip)
        var offset := Transform3D(Basis.IDENTITY, Vector3(eye, 0, 0))
        camera_offsets.append(offset)
        camera.global_transform = global_transform * offset
        if synthesis:
            var capture = Capture.new(borrow_source_color or borrow_source_depth, borrow_source_depth)
            if compose_in_capture_callback and update_on_demand:
                capture.capture_completed = _dispatch_requested
            capture.near_clip = near_clip
            capture.far_clip = far_clip
            var compositor := Compositor.new()
            compositor.compositor_effects = [capture]
            capture.compositor_ref = weakref(compositor)
            camera.compositor = compositor
            captures.append(capture)
    if shared_positional_shadows and shared_shadow_api_available:
        for i in range(1, views.size()):
            RenderingServer.call("viewport_set_positional_shadow_atlas_shared_from", views[i].get_viewport_rid(), views[0].get_viewport_rid())
    quilt_viewport = SubViewport.new()
    quilt_viewport.size = Vector2i(columns * tile_size.x, ceili(float(total_views) / columns) * tile_size.y)
    quilt_viewport.disable_3d = true
    quilt_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if synthesis else SubViewport.UPDATE_ALWAYS
    add_child(quilt_viewport)
    # Canvas draws sample viewport textures on GPU. Bottom-left row is view zero.
    for i in range(0 if synthesis else total_views):
        var tile := TextureRect.new()
        tile.texture = views[_nearest_anchor(i)].get_texture()
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.position = Vector2((i % columns) * tile_size.x, (ceili(float(total_views) / columns) - 1 - i / columns) * tile_size.y)
        tile.size = Vector2(tile_size)
        tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        quilt_viewport.add_child(tile)
    last_rig_transform = global_transform
    if synthesis:
        gpu_quilt = Texture2DRD.new()
        synthesizer = Synthesizer.new()
        synthesizer.configure(self)
        RenderingServer.frame_post_draw.connect(_compose)
        if update_on_demand:
            request_update()

func custom_anchors_valid() -> bool:
    if custom_anchor_indices.size() != real_views or custom_anchor_indices.is_empty():
        return false
    if custom_anchor_indices[0] != 0 or custom_anchor_indices[-1] != total_views - 1:
        return false
    for i in range(1, custom_anchor_indices.size()):
        if custom_anchor_indices[i] <= custom_anchor_indices[i - 1]:
            return false
    return true

func select_anchor_indices() -> Array[int]:
    var result: Array[int] = []
    if synthesis and not custom_anchor_indices.is_empty() and custom_anchors_valid():
        for index in custom_anchor_indices:
            result.append(index)
        return result
    if synthesis and not custom_anchor_indices.is_empty():
        push_warning("Invalid custom anchors; using uniform anchors. Require real_views sorted unique indices including 0 and total_views-1.")
    for i in range(real_views):
        result.append(roundi(float(i) * (total_views - 1) / float(real_views - 1)) if real_views > 1 else 0)
    return result

func _nearest_anchor(index: int) -> int:
    var best: int = 0
    for j in range(anchor_indices.size()):
        if abs(anchor_indices[j] - index) < abs(anchor_indices[best] - index):
            best = j
    return best

func request_update() -> void:
    # An explicit scene revision avoids guessing whether camera-static means scene-static.
    if not update_on_demand or synthesizer == null:
        return
    requested_revision += 1
    RenderingServer.call_on_render_thread(_record_request.bind(requested_revision))
    for view in views:
        view.render_target_update_mode = SubViewport.UPDATE_ONCE

func _record_request(revision: int) -> void:
    # Only the render thread accesses capture versions and render-side request state.
    _render_required_capture_counts.clear()
    for capture in captures:
        _render_required_capture_counts.append(capture.capture_count)
    _render_requested_revision = revision

func _complete_request(revision: int) -> void:
    completed_revision = maxi(completed_revision,revision)

func _compose() -> void:
    if update_on_demand:
        if requested_revision > completed_revision:
            RenderingServer.call_on_render_thread(_dispatch_requested)
    else:
        RenderingServer.call_on_render_thread(synthesizer.dispatch)

func _dispatch_requested() -> void:
    if _render_requested_revision <= _render_completed_revision:
        return
    for i in range(captures.size()):
        if captures[i].capture_count <= _render_required_capture_counts[i]:
            return
    var revision: int = _render_requested_revision
    var before: int = synthesizer.dispatch_count
    synthesizer.dispatch()
    if synthesizer.dispatch_count > before:
        _render_completed_revision = revision
        _complete_request.call_deferred(revision)

func _exit_tree() -> void:
    if RenderingServer.frame_post_draw.is_connected(_compose):
        RenderingServer.frame_post_draw.disconnect(_compose)
    if synthesizer != null:
        RenderingServer.call_on_render_thread(synthesizer.release)

func _process(_delta: float) -> void:
    var current_transform: Transform3D = global_transform
    if current_transform == last_rig_transform:
        return
    last_rig_transform = current_transform
    for i in range(cameras.size()):
        cameras[i].global_transform = current_transform * camera_offsets[i]
    if update_on_demand and auto_update_on_transform:
        request_update()
