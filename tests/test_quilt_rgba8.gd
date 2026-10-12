extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void:
    run.call_deferred()
func fail(message: String) -> void:
    print("FAIL RGBA8 quilt: ",message)
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
    var rig := Rig.new()
    rig.total_views=66
    rig.real_views=2
    rig.columns=11
    rig.tile_size=Vector2i(16,16)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.borrow_source_depth=true
    rig.position.z=6
    scene.add_child(rig)
    var reference := Rig.new()
    reference.total_views=66
    reference.real_views=2
    reference.columns=11
    reference.tile_size=Vector2i(16,16)
    reference.synthesis=true
    reference.update_on_demand=true
    reference.borrow_source_depth=true
    reference.position.z=6
    scene.add_child(reference)
    # Frozen output. Finish subsequent Godot frames so synthesis recorded by
    # frame_post_draw has been committed by RenderingDevice::swap_buffers.
    # Explicit refreshes warm renderer pipelines; not a production warmup policy.
    for i in range(120):
        rig.request_update()
        reference.request_update()
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
    var image: Image=rig.quilt_texture.get_image() # Diagnostic-only readback.
    if image == null or image.get_format()!=Image.FORMAT_RGBA8 or image.get_data().size()!=176*96*4:
        fail("Invalid RGBA8 output")
        return
    var visible_colour: bool = false
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var colour: Color=image.get_pixel(x,y)
            visible_colour = visible_colour or maxf(colour.r,maxf(colour.g,colour.b))>0.01
    if image.get_size()!=Vector2i(176,96) or not visible_colour:
        fail("Empty/wrong-sized quilt cannot establish equivalence: size="+str(image.get_size())+" center="+str(image.get_pixel(16,48)))
        return
    var reference_image: Image=reference.quilt_texture.get_image()
    if reference_image == null or reference_image.get_size()!=image.get_size() or reference_image.get_format()!=Image.FORMAT_RGBAH:
        fail("Invalid float reference")
        return
    var max_error: float = 0
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var actual: Color=image.get_pixel(x,y)
            var expected: Color=reference_image.get_pixel(x,y)
            for channel in range(4):
                max_error=maxf(max_error,absf(actual[channel]-clampf(expected[channel],0,1)))
    # Float16 reference is rounded separately from UNORM8 output.
    if max_error>1.0/255.0:
        fail("RGBA8 differs from clamped float reference: "+str(max_error))
        return
    print("RGBA8 comparison max_error=",max_error," views=66 anchors=2 size=",image.get_size())
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS RGBA8 compute quilt: 66-view output matches clamped RGBA16Float within one byte, frozen on-demand captures and synthesis")
    quit()
