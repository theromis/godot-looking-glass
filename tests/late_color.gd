extends CompositorEffect
var rd: RenderingDevice
var shader: RID
var pipeline: RID
func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color = true
    RenderingServer.call_on_render_thread(_initialize)
func _initialize() -> void:
    rd = RenderingServer.get_rendering_device()
    shader = rd.shader_create_from_spirv(load("res://tests/late_color.glsl").get_spirv())
    pipeline = rd.compute_pipeline_create(shader)
func _render_callback(type: int, data: RenderData) -> void:
    if rd == null or type != effect_callback_type:
        return
    var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers()
    var u := RDUniform.new()
    u.binding = 0
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u.add_id(buffers.get_color_layer(0))
    var uniforms: Array[RDUniform] = []
    uniforms.append(u)
    var list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, pipeline)
    rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(shader,0,uniforms),0)
    var size: Vector2i = buffers.get_internal_size()
    rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)
    rd.compute_list_end()
func release() -> void:
    rd.free_rid(pipeline)
    rd.free_rid(shader)
