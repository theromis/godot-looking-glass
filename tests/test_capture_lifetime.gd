extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
signal resource_checked(alive: bool)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var scene := Node3D.new()
    root.add_child(scene)
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_COLOR
    world.environment.background_color = Color(0.12, 0.25, 0.4)
    world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_color = Color.WHITE
    scene.add_child(world)
    for i in range(3):
        var box := MeshInstance3D.new()
        box.mesh = BoxMesh.new()
        box.position = Vector3(i * 0.7 - 0.7, 0, -i)
        scene.add_child(box)
    var rigs: Array = []
    for variant in range(9):
        var mode: int = variant % 3
        var rig := Rig.new()
        rig.total_views = 5
        rig.real_views = 2
        rig.tile_size = Vector2i(65, 67)
        rig.synthesis_workgroup = variant / 3
        rig.synthesis = true
        if "--custom-anchors" in OS.get_cmdline_user_args():
            rig.real_views = 3
            rig.custom_anchor_indices = PackedInt32Array([0, 1, 4])
        rig.borrow_source_color = mode > 0
        rig.borrow_source_depth = mode == 2
        rig.position.z = 6
        scene.add_child(rig)
        rigs.append(rig)
        if not rig.custom_anchor_indices.is_empty():
            if not check(rig.anchor_indices == [0, 1, 4] and rig.synthesizer.source_a == [0, 1, 1, 1, 2] and rig.synthesizer.source_b == [1, 2, 2, 2, 2], "Nonuniform source bracketing"):
                return
            for camera in rig.cameras:
                if not check(camera.unproject_position(Vector3(0, 0, 0)).distance_to(Vector2(rig.tile_size) * 0.5) < 0.01, "Nonuniform focus registration"):
                    return
    for dimension in [64, 49, 81]:
        var previous_dispatches: Array = rigs.map(func(r): return r.synthesizer.dispatch_count)
        for rig in rigs:
            for view in rig.views:
                view.size = Vector2i(dimension, dimension)
        for i in range(240):
            await process_frame
            var ready: bool = true
            for index in range(rigs.size()):
                ready = ready and rigs[index].captures.all(func(c): return c.dimensions == Vector2i(dimension, dimension)) and rigs[index].synthesizer.dispatch_count >= previous_dispatches[index] + 4
            if ready:
                break
        await RenderingServer.frame_post_draw
        for index in range(rigs.size()):
            var rig = rigs[index]
            if not check(rig.captures.all(func(c): return c.dimensions == Vector2i(dimension, dimension)), "Capture did not resize"):
                return
            if not check(rig.synthesizer.dispatch_count > previous_dispatches[index], "No synthesis dispatches; empty quilts cannot establish equivalence"):
                return
        var a: Image = rigs[0].quilt_texture.get_image()
        if not check(a != null and a.get_pixel(0, 0).b > 0.01, "Quilt is empty"):
            return
        for index in range(1, rigs.size()):
            var image: Image = rigs[index].quilt_texture.get_image()
            if not check(image != null and a.get_data() == image.get_data(), "Capture/workgroup variant differs after resize"):
                return
    var capture = rigs[8].captures[0]
    var source: RID = capture.color
    var source_depth: RID = capture.depth
    RenderingServer.call_on_render_thread(func():
        var rd := RenderingServer.get_rendering_device()
        capture.release()
        capture.release()
        _resource_result.call_deferred(rd.texture_is_valid(source) and rd.texture_is_valid(source_depth))
    )
    var alive: bool = await resource_checked
    if not check(alive, "Releasing capture freed Godot-owned source color"):
        return
    for rig in rigs:
        rig.queue_free()
    for i in range(4):
        await process_frame
    print("PASS capture/workgroup variants: 9 exact quilts, non-multiple output 65x67, resize 64/49/81, idempotent release, source ownership")
    quit()

func _resource_result(alive: bool) -> void:
    resource_checked.emit(alive)

func check(condition: bool, message: String) -> bool:
    if not condition:
        print("FAIL " + message)
        push_error("FAIL " + message)
        quit(1)
    return condition
