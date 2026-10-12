extends RefCounted
var captures: Array
var indices: Array[int]
var eyes: Array[float] = []
var size: Vector2i
var columns: int
var count: int
var focus: float
var slope: float
var output: Texture2DRD
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var quilt: RID
var dispatch_count: int = 0
var debug_holes: bool = false
var released: bool = false
var gpu_ms: Array[float] = []
var dispatch_cpu_ms: Array[float] = []
var last_timestamp_frame: int = -1
var source_a: Array[int] = []
var source_b: Array[int] = []
var push_constants: Array[PackedByteArray] = []
var uniform_sets: Array[RID] = []
var bound_sources: Array[RID] = []
var cached_debug_holes: bool = false
var borrow_depth: bool = false
var workgroup := Vector2i(8, 8)
var profiling_enabled: bool = false
var profiling_sample_limit: int = 480
var timestamp_pairs: int = 0
var gpu_sample_cursor: int = 0
var cpu_sample_cursor: int = 0
var iterations: int = 8
var disocclusion_rescue: bool = false
var inverse_depth: bool = false

func configure(rig: Node3D) -> void:
    profiling_enabled = rig.profile_synthesis
    profiling_sample_limit = clampi(rig.profiling_sample_limit, 1, 4096)
    workgroup = [Vector2i(8, 8), Vector2i(16, 8), Vector2i(16, 16)][clampi(rig.synthesis_workgroup, 0, 2)]
    disocclusion_rescue = rig.disocclusion_rescue
    iterations = rig.reprojection_iterations if rig.reprojection_iterations in [2, 4, 8] else 8
    borrow_depth = rig.borrow_source_depth
    inverse_depth = rig.inverse_depth_reprojection and borrow_depth
    captures = rig.captures
    indices = rig.anchor_indices
    count = rig.total_views
    columns = rig.columns
    size = rig.tile_size
    focus = rig.focus_distance
    slope = 2.0 * tan(deg_to_rad(rig.vertical_fov) * 0.5) * float(size.x) / size.y
    output = rig.gpu_quilt
    for i in range(count):
        eyes.append(rig.eye_at(i))
    for i in range(count):
        var a: int = 0
        while a + 1 < indices.size() and indices[a + 1] <= i:
            a += 1
        var b: int = mini(a + 1, indices.size() - 1)
        source_a.append(a)
        source_b.append(b)
        var row: int = ceili(float(count) / columns) - 1 - i / columns
        push_constants.append(PackedFloat32Array([eyes[i], eyes[indices[a]], eyes[indices[b]], focus, size.x, size.y, (i % columns) * size.x, row * size.y, slope, 1.0 if indices[a] == i else 0.0, 0, 0]).to_byte_array())
    if borrow_depth:
        for i in range(count):
            push_constants[i].append_array(PackedFloat32Array([rig.near_clip, rig.far_clip, 1.0 / rig.far_clip if inverse_depth else 0, 1.0 / rig.near_clip - 1.0 / rig.far_clip if inverse_depth else 0]).to_byte_array())
    RenderingServer.call_on_render_thread(_initialize)

func _initialize() -> void:
    rd = RenderingServer.get_rendering_device()
    var path: String = "res://addons/looking_glass/shaders/synthesize_raw_depth" if borrow_depth else "res://addons/looking_glass/shaders/synthesize"
    if inverse_depth:
        path += "_inverse"
    if disocclusion_rescue:
        path += "_rescue"
    if iterations != 8:
        path += "_iterations%d" % iterations
    if workgroup != Vector2i(8, 8):
        path += "_%dx%d" % [workgroup.x, workgroup.y]
    shader = rd.shader_create_from_spirv(load(path + ".glsl").get_spirv())
    pipeline = rd.compute_pipeline_create(shader)
    var state := RDSamplerState.new()
    state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    sampler = rd.sampler_create(state)
    var f := RDTextureFormat.new()
    f.width = size.x * columns
    f.height = size.y * ceili(float(count) / columns)
    f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
    quilt = rd.texture_create(f, RDTextureView.new())
    rd.texture_clear(quilt, Color.BLACK, 0, 1, 0, 1)
    output.texture_rd_rid = quilt

func dispatch() -> void:
    if released or rd == null or captures.is_empty():
        return
    var frame: int = captures[0].frame
    if frame == 0:
        return
    for capture in captures:
        if capture.frame != frame or not capture.color.is_valid():
            return
    if profiling_enabled:
        var timestamp_frame: int = rd.get_captured_timestamps_frame()
        if timestamp_frame != last_timestamp_frame:
            last_timestamp_frame = timestamp_frame
            var start: int = -1
            for j in range(rd.get_captured_timestamps_count()):
                var name: String = rd.get_captured_timestamp_name(j)
                if name == "LG quilt begin":
                    start = rd.get_captured_timestamp_gpu_time(j)
                elif name == "LG quilt end" and start >= 0:
                    _record_gpu.call_deferred(float(rd.get_captured_timestamp_gpu_time(j) - start) / 1000000.0)
    var cpu_start: int = Time.get_ticks_usec() if profiling_enabled else 0
    if profiling_enabled:
        rd.capture_timestamp("LG quilt begin")
    _ensure_uniform_sets()
    if debug_holes != cached_debug_holes:
        cached_debug_holes = debug_holes
        for i in range(count):
            var bytes: PackedByteArray = push_constants[i]
            bytes.encode_float(40, 1.0 if debug_holes else 0.0)
            push_constants[i] = bytes
    var list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, pipeline)
    for i in range(count):
        rd.compute_list_bind_uniform_set(list, uniform_sets[i], 0)
        rd.compute_list_set_push_constant(list, push_constants[i], 64 if borrow_depth else 48)
        rd.compute_list_dispatch(list, ceili(float(size.x) / workgroup.x), ceili(float(size.y) / workgroup.y), 1)
    rd.compute_list_end()
    if profiling_enabled:
        rd.capture_timestamp("LG quilt end")
        timestamp_pairs += 1
    dispatch_count += 1
    if profiling_enabled and dispatch_count > 90:
        _record_cpu.call_deferred(float(Time.get_ticks_usec() - cpu_start) / 1000.0)

func release() -> void:
    released = true
    output.texture_rd_rid = RID()
    for capture in captures:
        capture.release()
    for rid in [quilt, pipeline, shader, sampler]:
        if rid.is_valid():
            rd.free_rid(rid)

func _record_gpu(value: float) -> void:
    if gpu_ms.size() < profiling_sample_limit:
        gpu_ms.append(value)
    else:
        gpu_ms[gpu_sample_cursor] = value
        gpu_sample_cursor = (gpu_sample_cursor + 1) % profiling_sample_limit

func _record_cpu(value: float) -> void:
    if dispatch_cpu_ms.size() < profiling_sample_limit:
        dispatch_cpu_ms.append(value)
    else:
        dispatch_cpu_ms[cpu_sample_cursor] = value
        cpu_sample_cursor = (cpu_sample_cursor + 1) % profiling_sample_limit

func _ensure_uniform_sets() -> void:
    var changed: bool = bound_sources.size() != captures.size() * 2
    if not changed:
        for j in range(captures.size()):
            if bound_sources[j * 2] != captures[j].color or bound_sources[j * 2 + 1] != captures[j].depth:
                changed = true
                break
    if not changed:
        return
    bound_sources.clear()
    for capture in captures:
        bound_sources.append(capture.color)
        bound_sources.append(capture.depth)
    uniform_sets.clear()
    for i in range(count):
        var a: int = source_a[i]
        var b: int = source_b[i]
        var uniforms: Array[RDUniform] = []
        var textures: Array[RID] = [captures[a].color, captures[a].depth, captures[b].color, captures[b].depth, quilt]
        for binding in range(5):
            var u := RDUniform.new()
            u.binding = binding
            u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if binding == 4 else RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
            if binding != 4:
                u.add_id(sampler)
            u.add_id(textures[binding])
            uniforms.append(u)
        uniform_sets.append(UniformSetCacheRD.get_cache(shader, 0, uniforms))
