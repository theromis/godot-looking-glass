extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
signal copy_complete(report: Dictionary)
func _initialize() -> void:
    run.call_deferred()
func receive(report: Dictionary) -> void:
    copy_complete.emit(report)
func fail(message: String) -> void:
    print("FAIL native Godot copy: ",message)
    quit(1)
func run() -> void:
    var status: int = GDExtensionManager.load_extension("res://native/bridge_metal/build/looking_glass_diagnostic.gdextension")
    if status not in [GDExtensionManager.LOAD_STATUS_OK,GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] or not ClassDB.class_exists("LookingGlassMetalDiagnostic"):
        fail("Optional diagnostic extension not loaded")
        return
    var diagnostic = ClassDB.instantiate("LookingGlassMetalDiagnostic")
    if RenderingServer.get_current_rendering_driver_name()!="metal":
        var report: Dictionary=diagnostic.copy_static_quilt(RID(),"",2,2,1.0)
        if not report.get("error","").contains("Native Metal required"):
            fail("Vulkan driver was not rejected")
            return
        print("PASS native extension rejects Vulkan handles before native access")
        quit()
        return
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
    var rig := Rig.new()
    rig.total_views=4
    rig.real_views=2
    rig.columns=2
    rig.tile_size=Vector2i(32,32)
    rig.synthesis=true
    rig.quilt_rgba8="--rgba8" in OS.get_cmdline_user_args()
    rig.update_on_demand=true
    rig.borrow_source_depth=true
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
    OS.set_environment("LG_FIXTURE_ACCEPT_QUILT","1")
    RenderingServer.call_on_render_thread(func():
        var report: Dictionary=diagnostic.copy_static_quilt(rig.synthesizer.quilt,"res://native/bridge_metal/build/fixture.dylib",2,2,1.0)
        receive.call_deferred(report)
    )
    var result: Dictionary=await copy_complete
    OS.unset_environment("LG_FIXTURE_ACCEPT_QUILT")
    var image: Image=rig.quilt_texture.get_image() # Unit-test-only readback.
    if not result.get("ok",false) or image==null or image.get_data()!=result.get("fixture_bytes",PackedByteArray()):
        fail(str(result.get("error","Copied pixels differ")))
        return
    var visible_colour: bool = false
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var colour: Color=image.get_pixel(x,y)
            visible_colour = visible_colour or maxf(colour.r,maxf(colour.g,colour.b))>0.01
    if image.get_size()!=Vector2i(64,64) or not visible_colour:
        fail("Empty/wrong-sized quilt cannot establish equivalence: size="+str(image.get_size())+" center="+str(image.get_pixel(16,48)))
        return
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS Godot 4.8 native Metal quilt -> SDK-fixture IOSurface: exact ","RGBA8" if rig.quilt_rgba8 else "RGBA16Float"," pixels, frozen post-frame producer fence, no physical output claim")
    quit()
