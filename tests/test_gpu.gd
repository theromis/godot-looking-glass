extends SceneTree
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
    if not check(rd != null, "Requires a windowed RD renderer"):
        return
    var iterations: int = 8
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--iterations="):
            iterations = int(arg.trim_prefix("--iterations="))
    var inverse_depth: bool = "--inverse-depth" in OS.get_cmdline_user_args()
    var near_clip: float = 0.1
    var far_clip: float = 40.0
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--clip="):
            var clip: PackedStringArray = arg.trim_prefix("--clip=").split(",")
            near_clip = float(clip[0])
            far_clip = float(clip[1])
    var raw_depth: bool = "--raw-depth" in OS.get_cmdline_user_args() or inverse_depth
    var rescue: bool = "--rescue-test" in OS.get_cmdline_user_args()
    var path: String = "res://addons/looking_glass/shaders/synthesize"
    if raw_depth:
        path += "_raw_depth"
    if inverse_depth:
        path += "_inverse"
    if rescue:
        path += "_rescue"
    if iterations != 8:
        path += "_iterations%d" % iterations
    var shader: RID = rd.shader_create_from_spirv(load(path + ".glsl").get_spirv())
    var pipeline: RID = rd.compute_pipeline_create(shader)
    var sampler: RID = rd.sampler_create(RDSamplerState.new())
    var colors := PackedFloat32Array()
    var depths := PackedFloat32Array()
    for y in range(32):
        for x in range(32):
            colors.append_array(PackedFloat32Array([float(x) / 31, 0.25, 0.5, 1]))
            var z: float = (2.0 if x < 16 else (3.0 if x < 18 else 6.0)) if rescue else 3.0
            depths.append((near_clip * far_clip / z - near_clip) / (far_clip - near_clip) if raw_depth else z)
    var format := RDTextureFormat.new()
    format.width = 32
    format.height = 32
    format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    var color: RID = rd.texture_create(format, RDTextureView.new(), [colors.to_byte_array()])
    format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
    var depth: RID = rd.texture_create(format, RDTextureView.new(), [depths.to_byte_array()])
    format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    var output: RID = rd.texture_create(format, RDTextureView.new())
    var uniforms: Array[RDUniform] = []
    for i in range(5):
        var uniform := RDUniform.new()
        uniform.binding = i
        uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if i == 4 else RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        if i < 4:
            uniform.add_id(sampler)
        uniform.add_id([color, depth, color, depth, output][i])
        uniforms.append(uniform)
    var set_rid: RID = rd.uniform_set_create(uniforms, shader, 0)
    for target_eye in ([0.25] if rescue else [0.0, 0.25, -0.25]):
        var list: int = rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(list, pipeline)
        rd.compute_list_bind_uniform_set(list, set_rid, 0)
        var pc := PackedFloat32Array([target_eye, 0, 0, 6, 32, 32, 0, 0, 1, 0, 0, 0])
        if raw_depth:
            pc.append_array(PackedFloat32Array([near_clip, far_clip, 1.0/far_clip if inverse_depth else 0, 1.0/near_clip-1.0/far_clip if inverse_depth else 0]))
        rd.compute_list_set_push_constant(list, pc.to_byte_array(), 64 if raw_depth else 48)
        rd.compute_list_dispatch(list, 4, 4, 1)
        rd.compute_list_end()
        rd.submit()
        rd.sync()
        var image := Image.create_from_data(32, 32, false, Image.FORMAT_RGBAH, rd.texture_get_data(output, 0))
        var x: int = 15 if rescue else 16
        var expected_x: int = 16 if rescue else floori((float(x) + 0.5) + target_eye * (1.0 / 3.0 - 1.0 / 6.0) * 32.0)
        var expected: float = pow(float(expected_x) / 31.0, 1.0 / 2.2)
        if not check(abs(image.get_pixel(x, 16).r - expected) < 0.002, "Planar reprojection disagrees with analytic shift"):
            return
    for rid in [set_rid, output, depth, color, pipeline, shader, sampler]:
        rd.free_rid(rid)
    rd.free()
    print("PASS GPU compute: analytic correspondence (seed rescue if enabled)")
    quit()

func check(condition: bool, message: String = "Test condition failed") -> bool:
    if not condition:
        push_error("FAIL " + message)
        quit(1)
    return condition
