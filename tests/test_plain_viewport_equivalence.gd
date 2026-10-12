# With --frustum alone: standalone reproduction without addons or compute.
extends SceneTree
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var scene := Node3D.new()
    root.add_child(scene)
    var world := WorldEnvironment.new()
    world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR
    world.environment.background_color=Color(0.12,0.25,0.4)
    world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_color=Color.WHITE
    scene.add_child(world)
    for i in range(3):
        var box := MeshInstance3D.new()
        box.mesh=BoxMesh.new()
        box.position=Vector3(i*0.7-0.7,0,-i)
        scene.add_child(box)
    var views: Array[SubViewport] = []
    for i in range(6):
        var view := SubViewport.new()
        view.size=Vector2i(65,67)
        view.world_3d=scene.get_world_3d()
        view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        root.add_child(view)
        var camera := Camera3D.new()
        if "--frustum" in OS.get_cmdline_user_args():
            var eye: float = (1.0 if i%2 else -1.0)*6.0*tan(deg_to_rad(35.0)*0.5)
            camera.position.x=eye
            camera.set_frustum(0.2*tan(deg_to_rad(35.0)*0.5),Vector2(-eye*0.1/6.0,0),0.1,40.0)
        view.add_child(camera)
        camera.current=true
        camera.position.z=6
        if "--capture" in OS.get_cmdline_user_args():
            var capture = load("res://addons/looking_glass/capture.gd").new()
            var compositor := Compositor.new()
            compositor.compositor_effects=[capture]
            capture.compositor_ref=weakref(compositor)
            camera.compositor=compositor
        views.append(view)
    if "--compute-tail" in OS.get_cmdline_user_args():
        var rig = load("res://addons/looking_glass/rig.gd").new()
        rig.total_views=5
        rig.real_views=2
        rig.tile_size=Vector2i(65,67)
        rig.synthesis=true
        rig.position.z=6
        scene.add_child(rig)
    for i in range(120):
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
    var images: Array[Image] = []
    for i in range(views.size()):
        var image := views[i].get_texture().get_image()
        if image == null or image.get_data().is_empty():
            print("FAIL empty viewport")
            quit(1)
            return
        images.append(image)
        print("VIEW ",i," objects=",views[i].get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
    print("FIRST matches opposite=",images[0].get_data()==images[1].get_data())
    var matches: bool = images[0].get_data()==images[2].get_data() and images[0].get_data()==images[4].get_data()
    matches = matches and images[1].get_data()==images[3].get_data() and images[1].get_data()==images[5].get_data()
    if "--frustum" in OS.get_cmdline_user_args():
        matches = matches and images[0].get_data()!=images[1].get_data()
    print("PLAIN equivalent=",matches," later_pair=",images[2].get_data()==images[4].get_data())
    if "--capture" in OS.get_cmdline_user_args():
        RenderingServer.call_on_render_thread(func():
            for view in views:
                view.get_child(0).compositor.compositor_effects[0].release()
        )
        RenderingServer.force_sync()
    for view in views: view.queue_free()
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS plain viewports equivalent" if matches else "FAIL plain viewports differ")
    quit(0 if matches else 1)
