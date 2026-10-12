extends RefCounted
## Diagnostic. Persistent mode excludes shader creation; readback synchronizes GPU.
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID
var buffer: RID
var groups: int
var blocks_per_view: int
var samples_side: int
var configured_rig: Node3D
var sets: Array[RID] = []
var bound_depth: Array[RID] = []
var constants: Array[PackedByteArray] = []

func configure(rig: Node3D, local_device: RenderingDevice = null, grid: int = 64) -> Dictionary:
    if grid < 8 or grid > 256 or grid % 8 != 0:
        return {"error":"Grid must be a multiple of 8 in [8,256]"}
    if rig.synthesizer.push_constants.size() != rig.total_views:
        return {"error":"Incomplete synthesis configuration"}
    for pc in rig.synthesizer.push_constants:
        if pc.size() != 64:
            return {"error":"Depth probe requires raw reverse-Z synthesis push constants"}
    if shader.is_valid():
        release()
    samples_side = grid
    constants.clear()
    bound_depth.clear()
    rd = local_device if local_device != null else RenderingServer.get_rendering_device()
    shader = rd.shader_create_from_spirv(preload("res://tests/depth_proxy.glsl").get_spirv())
    pipeline = rd.compute_pipeline_create(shader)
    var state := RDSamplerState.new()
    state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    sampler = rd.sampler_create(state)
    # Four uint counters per workgroup; configurable offline sample density.
    groups = samples_side / 8
    blocks_per_view = groups * groups
    buffer = rd.storage_buffer_create(rig.total_views * blocks_per_view * 16)
    configured_rig = rig
    for i in range(rig.total_views):
        var pc: PackedByteArray = rig.synthesizer.push_constants[i].duplicate()
        pc.append_array(PackedFloat32Array([samples_side, samples_side, i, 0]).to_byte_array())
        constants.append(pc)
    return {}

func _ensure_sets() -> void:
    var depths: Array[RID] = []
    for capture in configured_rig.captures:
        depths.append(capture.depth)
    if depths == bound_depth and not sets.is_empty():
        return
    for uniform_set in sets:
        if rd.uniform_set_is_valid(uniform_set):
            rd.free_rid(uniform_set)
    sets.clear()
    bound_depth = depths
    for i in range(configured_rig.total_views):
        var a: int = configured_rig.synthesizer.source_a[i]
        var b: int = configured_rig.synthesizer.source_b[i]
        var uniforms: Array[RDUniform] = []
        for binding in range(3):
            var u := RDUniform.new()
            u.binding = binding
            u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if binding == 2 else RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
            if binding < 2:
                u.add_id(sampler)
            u.add_id(buffer if binding == 2 else bound_depth[a if binding == 0 else b])
            uniforms.append(u)
        sets.append(rd.uniform_set_create(uniforms, shader, 0))

func dispatch() -> void:
    _ensure_sets()
    var list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, pipeline)
    for i in range(configured_rig.total_views):
        rd.compute_list_bind_uniform_set(list, sets[i], 0)
        rd.compute_list_set_push_constant(list, constants[i], 80)
        rd.compute_list_dispatch(list, groups, groups, 1)
    rd.compute_list_end()

func read_counts() -> Dictionary:
    var data: PackedByteArray = rd.buffer_get_data(buffer)
    return decode_counts(data)

func decode_counts(data: PackedByteArray) -> Dictionary:
    var rows: Array[Dictionary] = []
    for i in range(configured_rig.total_views):
        var counts: Array[int] = [0,0,0,0]
        for block in range(blocks_per_view):
            for metric in range(4):
                counts[metric] += data.decode_u32((i * blocks_per_view + block) * 16 + metric * 4)
        rows.append({"view":i,"real":configured_rig.anchor_indices.has(i),"counts":counts,"samples":samples_side*samples_side,"a":configured_rig.anchor_indices[configured_rig.synthesizer.source_a[i]],"b":configured_rig.anchor_indices[configured_rig.synthesizer.source_b[i]]})
    return {"rows":rows,"readback_bytes":data.size(),"metrics":["both_invalid","one_invalid","source_horizontal_depth_edge","valid_depth_disagreement"],"sample_grid":[samples_side,samples_side]}

func release() -> void:
    for uniform_set in sets:
        if rd.uniform_set_is_valid(uniform_set):
            rd.free_rid(uniform_set)
    sets.clear()
    for rid in [buffer, sampler, pipeline, shader]:
        if rid.is_valid():
            rd.free_rid(rid)
    buffer=RID()
    sampler=RID()
    pipeline=RID()
    shader=RID()

func measure(rig: Node3D, local_device: RenderingDevice = null, grid: int = 64) -> Dictionary:
    var error: Dictionary = configure(rig, local_device, grid)
    if not error.is_empty():
        return error
    dispatch()
    if local_device != null:
        rd.submit()
        rd.sync()
    var result: Dictionary = read_counts()
    release()
    return result
