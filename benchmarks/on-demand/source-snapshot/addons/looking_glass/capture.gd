extends CompositorEffect
var requested_borrow_color: bool = false
var requested_borrow_depth: bool = false
var borrow_color: bool = false
var borrow_depth: bool = false
# Probe-only override; production defaults to snapshot fallback for known hazards.
var borrow_safety_enabled: bool = true
var fallback_reason: String = ""
var compositor_ref: WeakRef
var buffer_owner: RenderSceneBuffersRD
var near_clip: float = 0.1
var far_clip: float = 40.0
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var depth_shader: RID
var depth_pipeline: RID
var sampler: RID
var color: RID
var depth: RID
var dimensions := Vector2i.ZERO
var capture_count: int = 0
var frame: int = 0
var released: bool = false
func _init(use_borrowed_color: bool = false, use_borrowed_depth: bool = false) -> void:
    requested_borrow_depth = use_borrowed_depth
    requested_borrow_color = use_borrowed_color or use_borrowed_depth
    borrow_color = requested_borrow_color
    borrow_depth = requested_borrow_depth
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color = true
    access_resolved_depth = true
    RenderingServer.call_on_render_thread(_initialize)
func _initialize() -> void:
    if released:
        return
    rd = RenderingServer.get_rendering_device()
    if rd == null:
        return
    var path: String = "res://addons/looking_glass/shaders/capture_raw_depth.glsl" if requested_borrow_depth else "res://addons/looking_glass/shaders/capture.glsl"
    shader = rd.shader_create_from_spirv(load(path).get_spirv())
    pipeline = rd.compute_pipeline_create(shader)
    sampler = rd.sampler_create(RDSamplerState.new())
    if requested_borrow_color and not requested_borrow_depth:
        depth_shader = rd.shader_create_from_spirv(load("res://addons/looking_glass/shaders/capture_depth.glsl").get_spirv())
        depth_pipeline = rd.compute_pipeline_create(depth_shader)
func _borrow_blocker(buffers: RenderSceneBuffersRD) -> String:
    if buffers.get_use_taa():
        return "taa_after_capture"
    var compositor: Compositor = compositor_ref.get_ref() as Compositor if compositor_ref != null else null
    if compositor == null:
        return "compositor_owner_unavailable"
    for effect in compositor.compositor_effects:
        if effect != null and effect != self and effect.enabled:
            return "additional_compositor_effect"
    return ""
func _select_mode(buffers: RenderSceneBuffersRD) -> void:
    fallback_reason = _borrow_blocker(buffers) if requested_borrow_color and borrow_safety_enabled else ""
    var next_color: bool = requested_borrow_color and fallback_reason == ""
    var next_depth: bool = requested_borrow_depth and fallback_reason == ""
    if next_color == borrow_color and next_depth == borrow_depth:
        return
    if color.is_valid() and not borrow_color:
        rd.free_rid(color)
    if depth.is_valid() and not borrow_depth:
        rd.free_rid(depth)
    color = RID()
    depth = RID()
    buffer_owner = null
    dimensions = Vector2i.ZERO
    borrow_color = next_color
    borrow_depth = next_depth
func _texture(format: int, size: Vector2i) -> RID:
    var f := RDTextureFormat.new()
    f.width = size.x
    f.height = size.y
    f.format = format
    f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    return rd.texture_create(f, RDTextureView.new())
func _render_callback(type: int, data: RenderData) -> void:
    if released or rd == null or type != effect_callback_type:
        return
    var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers()
    var size: Vector2i = buffers.get_internal_size()
    if size == Vector2i.ZERO:
        return
    _select_mode(buffers)
    if size != dimensions:
        if color.is_valid() and not borrow_color:
            rd.free_rid(color)
        if depth.is_valid() and not borrow_depth:
            rd.free_rid(depth)
        if not borrow_color:
            color = _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
        if not borrow_depth:
            depth = _texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, size)
        dimensions = size
    if borrow_color:
        buffer_owner = buffers
        color = buffers.get_color_layer(0)
    if borrow_depth:
        depth = buffers.get_depth_layer(0)
        capture_count += 1
        frame = int(rd.get_captured_timestamps_frame()) + 1
        return
    var textures: Array = [buffers.get_depth_layer(0), depth] if borrow_color else [buffers.get_color_layer(0), buffers.get_depth_layer(0), color, depth]
    var sampled_count: int = 1 if borrow_color else 2
    var uniforms: Array[RDUniform] = []
    for i in range(textures.size()):
        var u := RDUniform.new()
        u.binding = i
        u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE if i < sampled_count else RenderingDevice.UNIFORM_TYPE_IMAGE
        if i < sampled_count:
            u.add_id(sampler)
        u.add_id(textures[i])
        uniforms.append(u)
    var active_shader: RID = depth_shader if borrow_color else shader
    var active_pipeline: RID = depth_pipeline if borrow_color else pipeline
    var set_rid: RID = UniformSetCacheRD.get_cache(active_shader, 0, uniforms)
    var list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, active_pipeline)
    rd.compute_list_bind_uniform_set(list, set_rid, 0)
    if not requested_borrow_depth:
        rd.compute_list_set_push_constant(list, PackedFloat32Array([near_clip, far_clip, 0, 0]).to_byte_array(), 16)
    rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
    rd.compute_list_end()
    capture_count += 1
    frame = int(rd.get_captured_timestamps_frame()) + 1
func release() -> void:
    if released:
        return
    released = true
    if rd == null:
        return
    if color.is_valid() and not borrow_color:
        rd.free_rid(color)
    if depth.is_valid() and not borrow_depth:
        rd.free_rid(depth)
    for rid in [pipeline, shader, depth_pipeline, depth_shader, sampler]:
        if rid.is_valid():
            rd.free_rid(rid)
    color = RID()
    depth = RID()
    pipeline = RID()
    shader = RID()
    buffer_owner = null
    compositor_ref = null
