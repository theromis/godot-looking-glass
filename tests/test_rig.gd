extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    for count in [1, 2, 12, 47, 48, 66]:
        var rig = Rig.new()
        rig.total_views = count
        rig.real_views = count
        if count == 66:
            rig.focus_distance = 5.6
            rig.camera_span_reference_distance = 6.0
            rig.view_cone_degrees = 20.0
        rig.tile_size = Vector2i(160, 200)
        world.add_child(rig)
        if not check(rig.views.size() == count):
            return
        if not check(rig.anchor_indices[0] == 0):
            return
        if not check(rig.anchor_indices[-1] == count - 1):
            return
        var focus := Vector3(0, 0, -rig.focus_distance)
        var near := Vector3(0, 0, -rig.focus_distance * 0.5)
        var far := Vector3(0, 0, -rig.focus_distance * 1.5)
        for camera in rig.cameras:
            var projection: Projection = camera.get_camera_projection()
            if not check(abs(projection.y.y - 1.0 / tan(deg_to_rad(rig.vertical_fov) * 0.5)) < 0.001, "Vertical FOV must match non-square tiles"):
                return
            var pixel: Vector2 = camera.unproject_position(focus)
            if not check(pixel.distance_to(Vector2(rig.tile_size) * 0.5) < 0.01, "Focus plane must stay registered"):
                return
        if count > 1:
            var left: Camera3D = rig.cameras[0]
            var right: Camera3D = rig.cameras[-1]
            if not check(left.unproject_position(near).x > right.unproject_position(near).x):
                return
            if not check(left.unproject_position(far).x < right.unproject_position(far).x):
                return
        if not check(rig.quilt_viewport.size.x == rig.columns * 160):
            return
        rig.position = Vector3(2, 1, 3)
        rig.rotation = Vector3(0.1, 0.3, 0)
        rig._process(0.0)
        var moved_focus: Vector3 = rig.to_global(focus)
        for camera in rig.cameras:
            if not check(camera.unproject_position(moved_focus).distance_to(Vector2(rig.tile_size) * 0.5) < 0.01, "Moving rig must update cached camera transforms"):
                return
        rig.free()
    var custom = Rig.new()
    custom.total_views = 48
    custom.real_views = 4
    custom.synthesis = true
    custom.custom_anchor_indices = PackedInt32Array([0, 3, 35, 47])
    if not check(custom.custom_anchors_valid() and custom.select_anchor_indices() == [0, 3, 35, 47], "Custom anchors preserved"):
        return
    for invalid in [[0, 3, 3, 47], [0, 35, 3, 47], [1, 3, 35, 47], [0, 3, 35, 48], [0, 47]]:
        custom.custom_anchor_indices = PackedInt32Array(invalid)
        if not check(not custom.custom_anchors_valid(), "Reject invalid anchors"):
            return
    custom.free()
    print("PASS projection: 1/2/12/47/48/66 views; fixed-baseline focus registration, opposite near/far disparity, quilt sizes")
    quit()

func check(condition: bool, message: String = "Test condition failed") -> bool:
    if not condition:
        push_error("FAIL " + message)
        quit(1)
    return condition
