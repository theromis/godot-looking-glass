extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
signal render_result(value: Variant)
func receive(value: Variant) -> void:
    render_result.emit(value)
func _initialize() -> void:
    run.call_deferred()
func fail(message: String) -> void:
    print("FAIL direct Bridge target: ",message)
    quit(1)
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var lit: bool="--lit" in OS.get_cmdline_user_args()
    var scene := Node3D.new()
    root.add_child(scene)
    var world := WorldEnvironment.new()
    world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR
    world.environment.background_color=Color(0.2,0.4,0.7)
    scene.add_child(world)
    var box := MeshInstance3D.new()
    box.mesh=BoxMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color=Color(0.8,0.3,0.1)
    box.material_override=material
    scene.add_child(box)
    for i in range(3):
        var sphere := MeshInstance3D.new()
        sphere.mesh=SphereMesh.new()
        sphere.position=Vector3((i-1)*0.75,0.55,(i-1)*0.8)
        var sphere_material := StandardMaterial3D.new()
        sphere_material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
        sphere_material.albedo_color=[Color.RED,Color.GREEN,Color.BLUE][i]
        sphere.material_override=sphere_material
        scene.add_child(sphere)
    if lit:
        material.roughness=0.45
        world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
        world.environment.ambient_light_color=Color(0.45,0.55,0.7)
        world.environment.ambient_light_energy=0.3
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees=Vector3(-45,-35,0)
        sun.light_color=Color(1.0,0.9,0.8)
        sun.light_energy=1.2
        sun.shadow_enabled=true
        sun.light_angular_distance=2.0
        sun.shadow_blur=1.0
        sun.directional_shadow_max_distance=15.0
        scene.add_child(sun)
        var floor_mesh := MeshInstance3D.new()
        var floor_plane := PlaneMesh.new()
        floor_plane.size=Vector2(5,5)
        floor_mesh.mesh=floor_plane
        floor_mesh.position.y=-0.6
        var floor_material := StandardMaterial3D.new()
        floor_material.albedo_color=Color(0.5,0.52,0.55)
        floor_material.roughness=0.85
        floor_mesh.material_override=floor_material
        scene.add_child(floor_mesh)
    var fixture: bool="--fixture" in OS.get_cmdline_user_args()
    var runtime: String="res://native/bridge_metal/build/fixture.dylib" if fixture else OS.get_environment("BRIDGE_LIBRARY")
    var display: String="7" if fixture else OS.get_environment("BRIDGE_DISPLAY_INDEX")
    if runtime.is_empty() or display.is_empty() or not display.is_valid_int():
        fail("Set external BRIDGE_LIBRARY and explicit BRIDGE_DISPLAY_INDEX")
        return
    var status: int=GDExtensionManager.load_extension("res://native/bridge_metal/build/looking_glass_diagnostic.gdextension")
    if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]:
        fail("Diagnostic extension not loaded")
        return
    var diagnostic=ClassDB.instantiate("LookingGlassMetalDiagnostic")
    var cols: int=2 if fixture else 11
    var rows: int=2 if fixture else 6
    var large: bool="--large" in OS.get_cmdline_user_args()
    var tile := Vector2i(32,32) if fixture else (Vector2i(372,682) if large else Vector2i(64,114))
    var aspect: float=1.0 if fixture else 0.5625
    if fixture:
        OS.set_environment("LG_FIXTURE_ACCEPT_QUILT","1")
    var opened: Dictionary=diagnostic.begin_sequence(runtime,display.to_int(),cols,rows,aspect)
    if not opened.get("ok",false):
        fail(str(opened.get("error","Open failed")))
        return
    var prepared: Dictionary=diagnostic.prepare_direct_target(cols*tile.x,rows*tile.y)
    if not prepared.get("ok",false):
        fail(str(prepared.get("error","Allocation failed")))
        return
    RenderingServer.call_on_render_thread(func(): receive.call_deferred(diagnostic.import_direct_target()))
    var imported: RID=await render_result
    if not imported.is_valid():
        fail("Native import failed")
        return
    var rig := Rig.new()
    rig.external_quilt_target=imported
    rig.total_views=cols*rows
    var budget: int=cols*rows
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--real-views="):
            budget=int(argument.trim_prefix("--real-views="))
    if budget<2 or budget>cols*rows:
        fail("Real-view budget outside valid range")
        return
    rig.real_views=budget # Default remains the all-real optical baseline.
    rig.columns=cols
    rig.tile_size=tile
    if "--display-aspect" in OS.get_cmdline_user_args():
        # Connected portrait display aspect 9:16. Keep output quilt dimensions.
        rig.source_view_size=Vector2i(36,64) if fixture else Vector2i(378,672)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.borrow_source_depth=true
    var virtual_cone: float=54.0
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--view-cone="):
            virtual_cone=float(argument.trim_prefix("--view-cone="))
    if not is_finite(virtual_cone) or virtual_cone<1 or virtual_cone>80:
        fail("Invalid virtual camera cone")
        return
    rig.view_cone_degrees=virtual_cone
    rig.angular_view_sampling="--angular-sampling" in OS.get_cmdline_user_args()
    var focus: float=6.0
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--focus="):
            focus=float(argument.trim_prefix("--focus="))
    if not is_finite(focus) or focus<=rig.near_clip or focus>=rig.far_clip:
        fail("Invalid focus distance")
        return
    rig.focus_distance=focus
    rig.camera_span_reference_distance=6.0 # Isolate convergence from camera spacing.
    rig.position.z=6
    if "--projection-grid" in OS.get_cmdline_user_args():
        populate_projection_grid(scene,6.0-focus)
    scene.add_child(rig)
    # Frozen output. Finish subsequent Godot frames so synthesis recorded by
    # frame_post_draw has been committed by RenderingDevice::swap_buffers.
    # Explicit refreshes warm renderer pipelines; not a production warmup policy.
    for i in range(120):
        rig.request_update()
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
        await create_timer(0.01).timeout
    for i in range(4):
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
    var frozen_dispatches: int = rig.synthesizer.dispatch_count
    var frozen_captures: Array = rig.captures.map(func(c): return c.capture_count)
    for i in range(4):
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
    if rig.synthesizer.dispatch_count != frozen_dispatches or rig.captures.map(func(c): return c.capture_count)!=frozen_captures:
        fail("Source continued updating during frozen interval")
        return
    if rig.synthesizer.dispatch_count<1 or rig.completed_revision!=rig.requested_revision:
        fail("Static quilt did not finish latest explicit request")
        return
    for capture in rig.captures:
        if capture.dimensions!=rig.get_source_view_size():
            fail("Source capture dimensions differ from configured camera size")
            return
    print("Showing direct imported SDK quilt: real_views=",rig.real_views," total_views=",rig.total_views," tile=",tile," lit=",lit," virtual_cone=",virtual_cone," focus=",focus," angular_sampling=",rig.angular_view_sampling," camera_span_reference=6; no intermediate quilt blit")
    var report: Dictionary=diagnostic.submit_direct_target(0.0 if fixture else 20.0)
    if not report.get("ok",false):
        fail(str(report.get("error","Direct submission failed")))
        return
    if fixture:
        var image: Image=rig.quilt_texture.get_image() # Diagnostic-only readback.
        var bytes: PackedByteArray=diagnostic.read_fixture_output(runtime)
        if image == null or bytes.is_empty() or image.get_data()!=bytes:
            fail("Direct imported pixels differ from fixture")
            return
        var visible: bool=false
        for i in range(bytes.size()):
            if i%4!=3 and bytes[i]>10: visible=true
        if not visible:
            fail("Empty quilt cannot establish direct output")
            return
    scene.queue_free()
    for i in range(4): await process_frame
    RenderingServer.call_on_render_thread(func():
        diagnostic.release_direct_import()
        receive.call_deferred(true)
    )
    await render_result
    var closed: Dictionary=diagnostic.close_sequence()
    if not closed.get("ok",false):
        fail(str(closed.get("error","Close failed")))
        return
    if fixture: OS.unset_environment("LG_FIXTURE_ACCEPT_QUILT")
    print("PASS direct Bridge target: Godot compute writes imported SDK RGBA8 texture, no quilt blit, clean teardown; fixture="+str(fixture)+"")
    quit()

func populate_projection_grid(scene: Node3D, plane_z: float) -> void:
    # Grid geometry lies exactly on the convergence plane. No source blur/DOF.
    for child in scene.get_children():
        if child is MeshInstance3D or child is Light3D:
            child.free()
    var white := StandardMaterial3D.new()
    white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    white.albedo_color=Color(0.85,0.85,0.85)
    for i in range(-5,6):
        for vertical in [true,false]:
            var line := MeshInstance3D.new()
            var quad := QuadMesh.new()
            quad.size=Vector2(0.012,2.0) if vertical else Vector2(2.0,0.012)
            line.mesh=quad
            line.material_override=white
            line.position=Vector3(i*0.2,0,plane_z) if vertical else Vector3(0,i*0.2,plane_z)
            scene.add_child(line)
    for i in range(2):
        var marker := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius=0.18
        sphere.height=0.36
        marker.mesh=sphere
        marker.position=Vector3(-0.55 if i==0 else 0.55,0,plane_z+(0.5 if i==0 else -0.5))
        var material := StandardMaterial3D.new()
        material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color=Color.RED if i==0 else Color.BLUE
        marker.material_override=material
        scene.add_child(marker)
