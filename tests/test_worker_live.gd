extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var adaptive_flush: bool="--adaptive-flush" in OS.get_cmdline_user_args()
    var validate_flush: bool="--validate-flush" in OS.get_cmdline_user_args()
    var flush_count: int=0
    var validation_count: int=0
    var uncapped: bool="--uncapped" in OS.get_cmdline_user_args()
    var large: bool="--large" in OS.get_cmdline_user_args()
    var dimensions: Vector2i=Vector2i(4092,4092) if large else Vector2i(704,684)
    var frame_count: int=8 if large else 24
    var duration_seconds: float=0
    var directory: String="res://benchmarks/hardware/live-transport"
    var surface_name: String=""
    var verify_surface: bool="--verify" in OS.get_cmdline_user_args()
    var shared_name: String=""
    var pipe_path: String=""
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--duration="): duration_seconds=argument.trim_prefix("--duration=").to_float()-15.0
        if argument.begins_with("--surface-name="): surface_name=argument.trim_prefix("--surface-name=")
        if argument.begins_with("--shm-name="): shared_name=argument.trim_prefix("--shm-name=")
        if argument.begins_with("--pipe-path="): pipe_path=argument.trim_prefix("--pipe-path=")
    DirAccess.make_dir_recursive_absolute(directory)
    var pipe_writer: RefCounted
    if not pipe_path.is_empty() or not shared_name.is_empty() or not surface_name.is_empty():
        GDExtensionManager.load_extension("res://native/bridge_metal/build/looking_glass_diagnostic.gdextension")
        pipe_writer=ClassDB.instantiate("LookingGlassMetalDiagnostic")
        if not surface_name.is_empty():
            if pipe_writer==null or not pipe_writer.open_surface_publisher(surface_name,dimensions.x,dimensions.y):
                printerr("FAIL surface publisher open")
                quit(1)
                return
        elif pipe_writer==null or not (pipe_writer.open_shared_frame(shared_name,dimensions.x,dimensions.y) if not shared_name.is_empty() else pipe_writer.open_frame_pipe(pipe_path)):
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
    rig.tile_size=Vector2i(372,682) if large else Vector2i(64,114)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.position.z=6
    rig.focus_distance=6
    rig.view_cone_degrees=30
    scene.add_child(rig)
    var readback_us: int=0
    var pipe_us: int=0
    var render_us: int=0
    var ack_us: int=0
    var animation_started: int=Time.get_ticks_msec()
    var produced: int=0
    if duration_seconds>0: frame_count=10000
    for frame in range(frame_count):
        if duration_seconds>0 and float(Time.get_ticks_msec()-animation_started)/1000.0>=duration_seconds: break
        var animation_time: float=float(Time.get_ticks_msec()-animation_started)/1000.0
        box.rotation.y=animation_time*0.5 if uncapped else float(frame)*0.15
        var color_phase: int=int(animation_time*2.0) if uncapped else frame
        material.albedo_color=Color(0.95,0.3,0.05) if color_phase%2==0 else Color(0.05,0.9,0.95)
        var render_started: int=Time.get_ticks_usec()
        rig.request_update()
        for i in range(8):
            await process_frame
            RenderingServer.force_draw(false,1.0/60.0)
            RenderingServer.force_sync()
            flush_count+=1
            if adaptive_flush and rig.completed_revision==rig.requested_revision: break
        render_us+=Time.get_ticks_usec()-render_started
        if rig.completed_revision!=rig.requested_revision:
            printerr("FAIL live producer revision")
            quit(1)
            return
        if validate_flush:
            # Diagnostic CPU readback only: compare early completion with a fresh
            # eight-flush capture of the identical frozen scene/material state.
            var candidate: Image=rig.quilt_texture.get_image()
            rig.request_update()
            for i in range(8):
                await process_frame
                RenderingServer.force_draw(false,1.0/60.0)
                RenderingServer.force_sync()
            var reference: Image=rig.quilt_texture.get_image()
            if candidate==null or reference==null or candidate.get_data()!=reference.get_data():
                printerr("FAIL adaptive flush reference mismatch frame=",frame)
                quit(1)
                return
            validation_count+=1
        if not surface_name.is_empty():
            var ack_started: int=Time.get_ticks_usec()
            var deadline: int=Time.get_ticks_msec()+2000
            while not pipe_writer.surface_ready() and Time.get_ticks_msec()<deadline:
                await create_timer(0.005).timeout
            ack_us+=Time.get_ticks_usec()-ack_started
            var started: int=Time.get_ticks_usec()
            if not pipe_writer.publish_surface(frame+1,rig.synthesizer.quilt,verify_surface):
                printerr("FAIL surface publish")
                quit(1)
                return
            pipe_us+=Time.get_ticks_usec()-started
        else:
            var started: int=Time.get_ticks_usec()
            var image: Image=rig.quilt_texture.get_image()
            readback_us+=Time.get_ticks_usec()-started
            if image==null or image.get_size()!=dimensions:
                quit(1)
                return
            if pipe_writer!=null:
                var pipe_started: int=Time.get_ticks_usec()
                var written: bool=pipe_writer.write_shared_frame(frame+1,image.get_data()) if not shared_name.is_empty() else pipe_writer.write_frame_pipe(frame+1,image.get_data(),dimensions.x,dimensions.y)
                if not written:
                    printerr("FAIL live producer pipe write")
                    quit(1)
                    return
                pipe_us+=Time.get_ticks_usec()-pipe_started
            else:
                var file:=FileAccess.open(directory+"/pending.tmp",FileAccess.WRITE)
                if file==null:
                    quit(1)
                    return
                file.store_32(0x4c475131)
                file.store_32(frame+1)
                file.store_32(dimensions.x)
                file.store_32(dimensions.y)
                file.store_buffer(image.get_data())
                file.close()
                if DirAccess.rename_absolute(directory+"/pending.tmp",directory+"/latest.bin")!=OK:
                    quit(1)
                    return
        produced+=1
        print("PRODUCER sequence=",frame+1)
        if not uncapped: await create_timer(0.4).timeout
    frame_count=produced
    print("PRODUCER animation_elapsed_seconds=",float(Time.get_ticks_msec()-animation_started)/1000.0)
    if not surface_name.is_empty():
        var deadline: int=Time.get_ticks_msec()+2000
        while not pipe_writer.surface_ready() and Time.get_ticks_msec()<deadline:
            await create_timer(0.005).timeout
        if not pipe_writer.surface_ready():
            printerr("FAIL final surface acknowledgment")
            quit(1)
            return
        pipe_writer.close_surface_publisher()
    if pipe_writer!=null:
        pipe_writer.close_frame_pipe()
        pipe_writer.close_shared_frame()
    scene.queue_free()
    for i in range(4): await process_frame
    print("PRODUCER adaptive_flush=",adaptive_flush," mean_flush_count=",float(flush_count)/frame_count," exact_reference_frames=",validation_count)
    print("PRODUCER mean_revision_flush_ms=",float(render_us)/(1000.0*frame_count)," mean_ack_wait_ms=",float(ack_us)/(1000.0*frame_count))
    print("SURFACE producer gpu_only=",not surface_name.is_empty() and not (verify_surface or validate_flush)," diagnostic_readback=",(verify_surface or validate_flush) if not surface_name.is_empty() else true)
    print("PASS live Godot producer frames=",frame_count," mean_readback_ms=",float(readback_us)/(1000.0*frame_count)," mean_pipe_write_ms=",float(pipe_us)/(1000.0*frame_count))
    quit()
