extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void:
    run.call_deferred()
func fail(message: String) -> void:
    print("FAIL real Bridge sequence: ",message)
    quit(1)
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
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
    material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color=Color(0.8,0.3,0.1)
    box.material_override=material
    scene.add_child(box)
    for i in range(3):
        var sphere := MeshInstance3D.new()
        sphere.mesh=SphereMesh.new()
        sphere.position=Vector3((i-1)*0.75,0.55,(i-1)*0.8)
        var sphere_material := StandardMaterial3D.new()
        sphere_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        sphere_material.albedo_color=[Color.RED,Color.GREEN,Color.BLUE][i]
        sphere.material_override=sphere_material
        scene.add_child(sphere)
    var translucent: bool="--transparency" in OS.get_cmdline_user_args()
    if translucent:
        var glass := MeshInstance3D.new()
        var pane := QuadMesh.new()
        pane.size=Vector2(1.4,1.5)
        glass.mesh=pane
        glass.position=Vector3(0,0.35,1.1)
        var tint := StandardMaterial3D.new()
        tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
        tint.albedo_color=Color(0.1,0.9,0.9,0.35)
        glass.material_override=tint
        scene.add_child(glass)
    var rig := Rig.new()
    rig.total_views=66
    var budget: int=66
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--real-views="):
            budget=int(argument.trim_prefix("--real-views="))
    if budget<2 or budget>66:
        fail("Invalid real-view budget")
        return
    rig.real_views=budget # Default remains the all-real optical baseline.
    rig.columns=11
    rig.tile_size=Vector2i(64,114)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.borrow_source_depth=true
    rig.view_cone_degrees=54
    rig.position.z=6
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
    var runtime: String=OS.get_environment("BRIDGE_LIBRARY")
    var display: String=OS.get_environment("BRIDGE_DISPLAY_INDEX")
    if runtime.is_empty() or display.is_empty() or not display.is_valid_int():
        fail("Set external BRIDGE_LIBRARY and explicit BRIDGE_DISPLAY_INDEX")
        return
    var status: int=GDExtensionManager.load_extension("res://native/bridge_metal/build/looking_glass_diagnostic.gdextension")
    if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]:
        fail("Diagnostic extension not loaded")
        return
    var diagnostic=ClassDB.instantiate("LookingGlassMetalDiagnostic")
    var report: Dictionary=diagnostic.begin_sequence(runtime,display.to_int(),11,6,0.5625)
    if not report.get("ok",false):
        fail(str(report.get("error","Cannot open sequence")))
        return
    # Render and copy each pose once. SDK textures remain immutable until close.
    for frame in range(8):
        box.position.x=0.7*sin(float(frame)*TAU/8.0)
        box.rotation.y=float(frame)*TAU/8.0
        rig.request_update()
        for i in range(8):
            await process_frame
            RenderingServer.force_draw(false,1.0/60.0)
            RenderingServer.force_sync()
        if rig.completed_revision!=rig.requested_revision:
            diagnostic.close_sequence()
            fail("Pose did not finish requested revision")
            return
        var before: int=rig.synthesizer.dispatch_count
        var before_captures: Array=rig.captures.map(func(c): return c.capture_count)
        for i in range(4):
            await process_frame
            RenderingServer.force_draw(false,1.0/60.0)
            RenderingServer.force_sync()
        if rig.synthesizer.dispatch_count!=before or rig.captures.map(func(c): return c.capture_count)!=before_captures:
            diagnostic.close_sequence()
            fail("Pose quilt was not frozen")
            return
        report=diagnostic.capture_sequence_frame(rig.synthesizer.quilt)
        if not report.get("ok",false):
            diagnostic.close_sequence()
            fail(str(report.get("error","Capture failed")))
            return
    print("Showing 8 immutable Godot poses for 20 seconds; real_views=",budget," transparency=",translucent,"; orange box moves and rotates; no CPU quilt readback")
    report=diagnostic.play_sequence(20.0)
    var closed: Dictionary=diagnostic.close_sequence()
    if not report.get("ok",false) or not closed.get("ok",false):
        fail(str(report.get("error",closed.get("error","Playback failed"))))
        return
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS real Bridge sequence API: eight immutable GPU-only quilt copies, bounded playback and release; no continuous-streaming claim")
    quit()
