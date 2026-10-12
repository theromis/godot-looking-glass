extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var shared_shadows: bool="--shared-shadows" in OS.get_cmdline_user_args()
    if shared_shadows and not RenderingServer.has_method("viewport_set_positional_shadow_atlas_shared_from"):
        printerr("FAIL shared shadow engine API unavailable")
        quit(1)
        return
    if shared_shadows and ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling",true):
        printerr("FAIL shared shadows require full shadow caster project setting")
        quit(1)
        return
    var shadow_draw_calls: int=0
    var complex_scene: bool="--complex-scene" in OS.get_cmdline_user_args()
    var capture_compose: bool="--capture-compose" in OS.get_cmdline_user_args()
    var check_before_draw: bool=capture_compose or "--check-before-draw" in OS.get_cmdline_user_args()
    var first_draw_us: int=0
    var later_draw_us: int=0
    var adaptive_flush: bool="--adaptive-flush" in OS.get_cmdline_user_args()
    var validate_flush: bool="--validate-flush" in OS.get_cmdline_user_args()
    var flush_count: int=0
    var validation_count: int=0
    var uncapped: bool="--uncapped" in OS.get_cmdline_user_args()
    var large: bool="--large" in OS.get_cmdline_user_args()
    if check_before_draw and not (adaptive_flush and (validate_flush or capture_compose)):
        printerr("FAIL pre-draw shortcut requires explicit validation negative control")
        quit(1)
        return
    var dimensions: Vector2i=Vector2i(4092,4092) if large else Vector2i(704,684)
    var frame_count: int=8 if large else 24
    var real_views: int=66
    var duration_seconds: float=0
    var directory: String="res://benchmarks/hardware/live-transport"
    var surface_name: String=""
    var verify_surface: bool="--verify" in OS.get_cmdline_user_args()
    var shared_name: String=""
    var pipe_path: String=""
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--real-views="): real_views=argument.trim_prefix("--real-views=").to_int()
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
    if complex_scene:
        preload("res://tests/worker_scene_fixture.gd").add_details(scene,world.environment,box,material,"--no-shadows" not in OS.get_cmdline_user_args(),"--no-alpha-panel" not in OS.get_cmdline_user_args())
    var rig:=Rig.new()
    rig.total_views=66
    rig.real_views=real_views
    rig.shared_positional_shadows=shared_shadows
    rig.columns=11
    rig.tile_size=Vector2i(372,682) if large else Vector2i(64,114)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.compose_in_capture_callback=capture_compose
    rig.position.z=6
    rig.focus_distance=6
    rig.view_cone_degrees=30
    scene.add_child(rig)
    if not ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling",true):
        for view in rig.views: view.mesh_lod_threshold=0.0
    var readback_us: int=0
    var pipe_us: int=0
    var render_us: int=0
    var process_wait_us: int=0
    var force_draw_us: int=0
    var force_sync_us: int=0
    var ack_us: int=0
    var animation_started: int=Time.get_ticks_msec()
    var produced: int=0
    if duration_seconds>0: frame_count=10000
    for frame in range(frame_count):
        if duration_seconds>0 and float(Time.get_ticks_msec()-animation_started)/1000.0>=duration_seconds: break
        var animation_time: float=float(Time.get_ticks_msec()-animation_started)/1000.0
        box.rotation.y=animation_time*0.5 if uncapped else float(frame)*0.15
        var color_phase: int=int(animation_time*2.0) if uncapped else frame
        if complex_scene:
            box.position=Vector3(sin(animation_time*0.9)*0.85,0,0.3) if uncapped else Vector3(sin(float(frame)*0.5)*0.85,0,0.3)
        else:
            material.albedo_color=Color(0.95,0.3,0.05) if color_phase%2==0 else Color(0.05,0.9,0.95)
        var render_started: int=Time.get_ticks_usec()
        rig.request_update()
        for i in range(8):
            var stage_started: int=Time.get_ticks_usec()
            await process_frame
            process_wait_us+=Time.get_ticks_usec()-stage_started
            if check_before_draw and adaptive_flush and i>0 and rig.completed_revision==rig.requested_revision: break
            stage_started=Time.get_ticks_usec()
            RenderingServer.force_draw(false,1.0/60.0)
            var draw_elapsed: int=Time.get_ticks_usec()-stage_started
            force_draw_us+=draw_elapsed
            if i==0: first_draw_us+=draw_elapsed
            else: later_draw_us+=draw_elapsed
            stage_started=Time.get_ticks_usec()
            RenderingServer.force_sync()
            force_sync_us+=Time.get_ticks_usec()-stage_started
            flush_count+=1
            if adaptive_flush and rig.completed_revision==rig.requested_revision: break
        render_us+=Time.get_ticks_usec()-render_started
        if rig.completed_revision!=rig.requested_revision:
            printerr("FAIL live producer revision")
            quit(1)
            return
        for view in rig.views:
            shadow_draw_calls+=RenderingServer.viewport_get_render_info(view.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
        if validate_flush:
            # Copy first using the normal native path, then read its IOSurface.
            # Reference readback cannot flush missing work into the candidate.
            if pipe_writer==null or surface_name.is_empty():
                printerr("FAIL validation requires IOSurface transport")
                quit(1)
                return
            var copy_deadline: int=Time.get_ticks_msec()+2000
            while not pipe_writer.surface_ready() and Time.get_ticks_msec()<copy_deadline:
                await create_timer(0.005).timeout
            if not pipe_writer.publish_surface(frame+1,rig.synthesizer.quilt,false):
                printerr("FAIL validation source GPU copy")
                quit(1)
                return
            var candidate: PackedByteArray=pipe_writer.read_surface_pixels()
            if shared_shadows:
                _set_shadow_links(rig,false)
                RenderingServer.force_sync()
            if capture_compose:
                RenderingServer.call_on_render_thread(_set_capture_notifications.bind(rig,false))
                RenderingServer.force_sync()
            rig.request_update()
            for i in range(8):
                await process_frame
                RenderingServer.force_draw(false,1.0/60.0)
                RenderingServer.force_sync()
            var reference: Image=rig.quilt_texture.get_image()
            if candidate.is_empty() or reference==null or candidate!=reference.get_data():
                if shared_shadows:
                    Image.create_from_data(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8,candidate).save_png("res://benchmarks/hardware/shared-shadow-candidate.png")
                    reference.save_png("res://benchmarks/hardware/shared-shadow-reference.png")
                printerr("FAIL adaptive flush reference mismatch frame=",frame)
                quit(1)
                return
            if capture_compose:
                RenderingServer.call_on_render_thread(_set_capture_notifications.bind(rig,true))
                RenderingServer.force_sync()
            if shared_shadows:
                _set_shadow_links(rig,true)
                RenderingServer.force_sync()
            validation_count+=1
        if not surface_name.is_empty():
            var ack_started: int=Time.get_ticks_usec()
            var deadline: int=Time.get_ticks_msec()+2000
            while not pipe_writer.surface_ready() and Time.get_ticks_msec()<deadline:
                await create_timer(0.005).timeout
            ack_us+=Time.get_ticks_usec()-ack_started
            var started: int=Time.get_ticks_usec()
            if not validate_flush and not pipe_writer.publish_surface(frame+1,rig.synthesizer.quilt,verify_surface):
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
    print("PRODUCER mean_shadow_draw_calls=",float(shadow_draw_calls)/frame_count)
    print("PRODUCER mean_first_draw_ms=",float(first_draw_us)/(1000.0*frame_count)," mean_later_draw_ms=",float(later_draw_us)/(1000.0*frame_count))
    print("PRODUCER mean_process_wait_ms=",float(process_wait_us)/(1000.0*frame_count)," mean_force_draw_ms=",float(force_draw_us)/(1000.0*frame_count)," mean_force_sync_ms=",float(force_sync_us)/(1000.0*frame_count))
    print("PRODUCER adaptive_flush=",adaptive_flush," mean_flush_count=",float(flush_count)/frame_count," exact_reference_frames=",validation_count)
    print("PRODUCER mean_revision_flush_ms=",float(render_us)/(1000.0*frame_count)," mean_ack_wait_ms=",float(ack_us)/(1000.0*frame_count))
    print("SURFACE producer gpu_only=",not surface_name.is_empty() and not (verify_surface or validate_flush)," diagnostic_readback=",(verify_surface or validate_flush) if not surface_name.is_empty() else true)
    print("PASS live Godot producer frames=",frame_count," mean_readback_ms=",float(readback_us)/(1000.0*frame_count)," mean_pipe_write_ms=",float(pipe_us)/(1000.0*frame_count))
    quit()

func _set_capture_notifications(rig: Node3D, enabled: bool) -> void:
    # Validation reference uses the original post-draw composition schedule.
    for capture in rig.captures:
        capture.capture_completed=rig._dispatch_requested if enabled else Callable()

func _set_shadow_links(rig: Node3D, enabled: bool) -> void:
    for i in range(1,rig.views.size()):
        RenderingServer.call("viewport_set_positional_shadow_atlas_shared_from",rig.views[i].get_viewport_rid(),rig.views[0].get_viewport_rid() if enabled else RID())
