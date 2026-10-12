extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var scene := Node3D.new()
    root.add_child(scene)
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.1, 0.3, 0.6)
    var world := WorldEnvironment.new()
    world.environment = env
    scene.add_child(world)
    var mesh := MeshInstance3D.new()
    mesh.mesh = BoxMesh.new()
    scene.add_child(mesh)
    var rigs: Array = []
    for enabled in [false, true]:
        var rig := Rig.new()
        rig.total_views = 5
        rig.real_views = 2
        rig.tile_size = Vector2i(65, 67)
        rig.synthesis = true
        rig.profile_synthesis = enabled
        rig.profiling_sample_limit = 4
        rig.position.z = 6
        scene.add_child(rig)
        rigs.append(rig)
    for i in range(1600):
        await process_frame
        mesh.rotation.y = rigs[1].synthesizer.dispatch_count * 0.015
        if rigs[0].synthesizer.dispatch_count >= 140 and rigs[1].synthesizer.dispatch_count >= 140:
            break
    await process_frame
    var off = rigs[0].synthesizer
    var on = rigs[1].synthesizer
    print("PROFILE COUNTS ", on.timestamp_pairs, " GPU ", on.gpu_ms.size(), " CPU ", on.dispatch_cpu_ms.size())
    if not check(off.dispatch_count > 100 and on.dispatch_count > 100, "No actual synthesis"):
        return
    if not check(off.timestamp_pairs == 0 and off.gpu_ms.is_empty() and off.dispatch_cpu_ms.is_empty(), "Disabled profiling still records"):
        return
    if not check(on.timestamp_pairs > 100 and on.gpu_ms.size() == 4 and on.dispatch_cpu_ms.size() == 4, "Profiling ring limit not enforced or no samples"):
        return
    var a: Image = rigs[0].quilt_texture.get_image()
    var b: Image = rigs[1].quilt_texture.get_image()
    if not check(a != null and b != null and a.get_pixel(0,0).b > 0.01 and a.get_data() == b.get_data(), "Profiling changed or emptied output"):
        return
    for rig in rigs:
        rig.queue_free()
    for i in range(4):
        await process_frame
    print("PASS profiling: disabled records nothing; enabled bounded rings; exact nonempty quilt after >100 updates")
    quit()
func check(condition: bool, message: String) -> bool:
    if not condition:
        print("FAIL " + message)
        push_error(message)
        quit(1)
    return condition
