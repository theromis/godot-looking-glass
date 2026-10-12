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
    var tile := Vector2i(32,32) if fixture else Vector2i(64,114)
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
    rig.real_views=cols*rows # Optical baseline: no synthesized views.
    rig.columns=cols
    rig.tile_size=tile
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
    print("Showing direct imported SDK quilt; no intermediate quilt blit")
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
