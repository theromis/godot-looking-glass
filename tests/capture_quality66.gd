extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void:
    run.call_deferred()
func fail(message: String) -> void:
    print("FAIL quality 66: ",message)
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
    var rigs: Array=[]
    for budget in [12,24,36,66]:
        var rig := Rig.new()
        rig.total_views=66
        rig.real_views=budget
        rig.columns=11
        rig.tile_size=Vector2i(128,228)
        rig.synthesis=true
        rig.quilt_rgba8=true
        rig.update_on_demand=true
        rig.borrow_source_depth=true
        rig.view_cone_degrees=54
        rig.position.z=6
        scene.add_child(rig)
        rigs.append(rig)
    # Frozen output. Finish subsequent Godot frames so synthesis recorded by
    # frame_post_draw has been committed by RenderingDevice::swap_buffers.
    # Explicit refreshes warm renderer pipelines; not a production warmup policy.
    for i in range(120):
        for rig in rigs: rig.request_update()
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
        await create_timer(0.01).timeout
    for i in range(4):
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
    var directory: String="res://benchmarks/view-budget66"
    DirAccess.make_dir_recursive_absolute(directory)
    var configurations: Array=[]
    for rig in rigs:
        if rig.completed_revision!=rig.requested_revision or rig.synthesizer.dispatch_count<1:
            fail("Quilt revision incomplete")
            return
        var image: Image=rig.quilt_texture.get_image()
        if image==null or image.get_size()!=Vector2i(1408,1368):
            fail("Invalid image dimensions")
            return
        if image.save_png(directory+"/views-%d.png" % rig.real_views)!=OK:
            fail("Image save failed")
            return
        configurations.append({"real_views":rig.real_views,"anchors":rig.anchor_indices,"dispatches":rig.synthesizer.dispatch_count})
    var metadata := {"total_views":66,"columns":11,"rows":6,"tile_size":[128,228],"view_cone_degrees":54,"iterations":8,"borrowed_depth":true,"rgba8":true,"scene":"Opaque box and RGB spheres at multiple depths; no transparency or motion test","configurations":configurations}
    var file := FileAccess.open(directory+"/configurations.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(metadata,"  "))
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS quality 66: saved 12/24/36 anchor budgets and 66-real reference with identical shader output format")
    quit()
