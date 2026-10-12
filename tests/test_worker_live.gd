extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var directory: String="res://benchmarks/hardware/live-transport"
    var pipe_path: String=""
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--pipe-path="): pipe_path=argument.trim_prefix("--pipe-path=")
    DirAccess.make_dir_recursive_absolute(directory)
    var pipe_writer: RefCounted
    if not pipe_path.is_empty():
        GDExtensionManager.load_extension("res://native/bridge_metal/build/looking_glass_diagnostic.gdextension")
        pipe_writer=ClassDB.instantiate("LookingGlassMetalDiagnostic")
        if pipe_writer==null or not pipe_writer.open_frame_pipe(pipe_path):
            printerr("FAIL live producer pipe open")
            quit(1)
            return
    var scene:=Node3D.new()
    root.add_child(scene)
    var world:=WorldEnvironment.new()
    world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR
    world.environment.background_color=Color(0.2,0.4,0.7)
    scene.add_child(world)
    var box:=MeshInstance3D.new()
    box.mesh=BoxMesh.new()
    var material:=StandardMaterial3D.new()
    material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    box.material_override=material
    scene.add_child(box)
    var rig:=Rig.new()
    rig.total_views=66
    rig.real_views=66
    rig.columns=11
    rig.tile_size=Vector2i(64,114)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.position.z=6
    rig.focus_distance=6
    rig.view_cone_degrees=30
    scene.add_child(rig)
    var readback_us: int=0
    for frame in range(24):
        box.rotation.y=float(frame)*0.15
        material.albedo_color=Color(0.95,0.3,0.05) if frame%2==0 else Color(0.05,0.9,0.95)
        rig.request_update()
        for i in range(8):
            await process_frame
            RenderingServer.force_draw(false,1.0/60.0)
            RenderingServer.force_sync()
        if rig.completed_revision!=rig.requested_revision:
            printerr("FAIL live producer revision")
            quit(1)
            return
        var started: int=Time.get_ticks_usec()
        var image: Image=rig.quilt_texture.get_image()
        readback_us+=Time.get_ticks_usec()-started
        if image==null or image.get_size()!=Vector2i(704,684):
            quit(1)
            return
        if pipe_writer!=null:
            if not pipe_writer.write_frame_pipe(frame+1,image.get_data()):
                printerr("FAIL live producer pipe write")
                quit(1)
                return
        else:
            var file:=FileAccess.open(directory+"/pending.tmp",FileAccess.WRITE)
            if file==null:
                quit(1)
                return
            file.store_32(0x4c475131)
            file.store_32(frame+1)
            file.store_32(704)
            file.store_32(684)
            file.store_buffer(image.get_data())
            file.close()
            if DirAccess.rename_absolute(directory+"/pending.tmp",directory+"/latest.bin")!=OK:
                quit(1)
                return
        print("PRODUCER sequence=",frame+1)
        await create_timer(0.4).timeout
    if pipe_writer!=null: pipe_writer.close_frame_pipe()
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS live Godot producer frames=24 mean_readback_ms=",float(readback_us)/24000.0)
    quit()
