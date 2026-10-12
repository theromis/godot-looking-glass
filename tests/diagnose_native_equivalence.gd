extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
signal dumped
var rigs: Array = []
var destination: String = "res://benchmarks/native-bridge/equivalence-local"
func _initialize() -> void:
    run.call_deferred()
func frames(count: int) -> void:
    for i in range(count):
        await process_frame
        RenderingServer.force_draw(false, 1.0/60.0)
        RenderingServer.force_sync()
func dump_sources(stage: String) -> void:
    var rd := RenderingServer.get_rendering_device()
    for i in range(rigs.size()):
        for j in range(rigs[i].captures.size()):
            var c = rigs[i].captures[j]
            # Godot-owned buffers need not allow CPU readback. Snapshot through
            # sampled compute reads into owned, readable storage textures.
            var shader := rd.shader_create_from_spirv(load("res://addons/looking_glass/shaders/capture_raw_depth.glsl").get_spirv())
            var pipeline := rd.compute_pipeline_create(shader)
            var sampler := rd.sampler_create(RDSamplerState.new())
            var outputs: Array[RID] = []
            for format in [RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,RenderingDevice.DATA_FORMAT_R32_SFLOAT]:
                var f := RDTextureFormat.new()
                f.width=c.dimensions.x
                f.height=c.dimensions.y
                f.format=format
                f.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
                outputs.append(rd.texture_create(f,RDTextureView.new()))
            var uniforms: Array[RDUniform] = []
            var textures: Array[RID] = [c.color,c.depth,outputs[0],outputs[1]]
            for binding in range(4):
                var u := RDUniform.new()
                u.binding=binding
                u.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE if binding<2 else RenderingDevice.UNIFORM_TYPE_IMAGE
                if binding<2: u.add_id(sampler)
                u.add_id(textures[binding])
                uniforms.append(u)
            var set_rid := rd.uniform_set_create(uniforms,shader,0)
            var list := rd.compute_list_begin()
            rd.compute_list_bind_compute_pipeline(list,pipeline)
            rd.compute_list_bind_uniform_set(list,set_rid,0)
            rd.compute_list_dispatch(list,ceili(c.dimensions.x/8.0),ceili(c.dimensions.y/8.0),1)
            rd.compute_list_end()
            for k in range(2):
                var file := FileAccess.open(destination+"/"+stage+"-%d-%d-%s.bin" % [i,j,"color" if k==0 else "depth"],FileAccess.WRITE)
                var bytes := rd.texture_get_data(outputs[k],0)
                if bytes.is_empty():
                    push_error("Empty source diagnostic")
                    quit.call_deferred(1)
                file.store_buffer(bytes)
            for rid in [set_rid,pipeline,shader,sampler,outputs[0],outputs[1]]: rd.free_rid(rid)
    dumped.emit.call_deferred()
func snapshot(stage: String) -> void:
    RenderingServer.call_on_render_thread(dump_sources.bind(stage))
    await dumped
    for i in range(rigs.size()):
        var image: Image = rigs[i].quilt_texture.get_image()
        var file := FileAccess.open(destination+"/"+stage+"-%d-quilt.bin" % i,FileAccess.WRITE)
        file.store_buffer(image.get_data())
        for j in range(rigs[i].views.size()):
            var view_image: Image = rigs[i].views[j].get_texture().get_image()
            var view_file := FileAccess.open(destination+"/"+stage+"-%d-%d-viewport.bin" % [i,j],FileAccess.WRITE)
            view_file.store_buffer(view_image.get_data())
        print("SNAPSHOT ",stage," rig=",i," size=",image.get_size()," dispatches=",rigs[i].synthesizer.dispatch_count)
func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): destination=arg.trim_prefix("--output=")
    DirAccess.make_dir_recursive_absolute(destination)
    RenderingServer.set_render_loop_enabled(false)
    var scene := Node3D.new()
    root.add_child(scene)
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_COLOR
    world.environment.background_color = Color(0.12,0.25,0.4)
    world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_color = Color.WHITE
    scene.add_child(world)
    for i in range(3):
        var box := MeshInstance3D.new()
        box.mesh = BoxMesh.new()
        box.position = Vector3(i*0.7-0.7,0,-i)
        scene.add_child(box)
    if "--guard-viewport" in OS.get_cmdline_user_args():
        var guard := Rig.new()
        guard.total_views=5
        guard.real_views=2
        guard.tile_size=Vector2i(65,67)
        guard.synthesis=true
        guard.position.z=6
        scene.add_child(guard)
    for variant in range(9):
        var mode: int = variant%3
        var rig := Rig.new()
        rig.total_views=5
        rig.real_views=2
        rig.tile_size=Vector2i(65,67)
        rig.synthesis_workgroup=variant/3
        rig.synthesis=true
        rig.borrow_source_color=mode>0
        rig.borrow_source_depth=mode==2
        rig.position.z=6
        scene.add_child(rig)
        rigs.append(rig)
    await frames(120)
    for i in range(rigs.size()):
        print("CAMERA ",i," ",rigs[i].cameras[0].global_transform," projection=",rigs[i].cameras[0].get_camera_projection())
    await snapshot("settled")
    for rig in rigs:
        for view in rig.views: view.render_target_update_mode=SubViewport.UPDATE_DISABLED
    await frames(12)
    await snapshot("frozen")
    for rig in rigs: rig.queue_free()
    await frames(4)
    print("PASS diagnostic snapshots; equivalence is assessed separately")
    quit()
