extends SceneTree
var views: Array[SubViewport] = []
var box: MeshInstance3D
var scene: Node3D
func _initialize() -> void:
    run.call_deferred()
func draw_calls() -> int:
    var count: int = 0
    for view in views:
        count += RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
    return count
func settle() -> int:
    var counts: Array[int] = []
    for i in range(12):
        box.rotation.y += 0.1
        await process_frame
        await RenderingServer.frame_post_draw
        if i >= 6:
            counts.append(draw_calls())
    counts.sort()
    return counts[counts.size()/2]
func run() -> void:
    if not check(RenderingServer.has_method("viewport_set_positional_shadow_atlas_shared_from"), "Patched engine required"):
        return
    if not check(not ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling"), "Launch with full caster culling disabled"):
        return
    scene = Node3D.new()
    root.add_child(scene)
    box = MeshInstance3D.new()
    box.mesh = BoxMesh.new()
    scene.add_child(box)
    var light := SpotLight3D.new()
    light.position = Vector3(0, 3, 3)
    light.spot_range = 12
    light.shadow_enabled = true
    scene.add_child(light)
    light.look_at(Vector3.ZERO, Vector3.UP)
    var omni := OmniLight3D.new()
    omni.position = Vector3(2, 2, 2)
    omni.omni_range = 10
    omni.shadow_enabled = true
    scene.add_child(omni)
    for i in range(3):
        var view := SubViewport.new()
        view.size = Vector2i(128, 128)
        view.world_3d = scene.get_world_3d()
        view.mesh_lod_threshold = 0
        view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        scene.add_child(view)
        var camera := Camera3D.new()
        view.add_child(camera)
        camera.position = Vector3(i * 0.1, 0, 5)
        camera.current = true
        views.append(view)
    var baseline: int = await settle()
    if not check(baseline > 0, "Scene must actually draw shadow casters"):
        return
    for i in range(1, views.size()):
        RenderingServer.call("viewport_set_positional_shadow_atlas_shared_from", views[i].get_viewport_rid(), views[0].get_viewport_rid())
    var shared: int = await settle()
    if not check(shared > 0 and shared < baseline, "Sharing must reduce measured shadow draw calls"):
        return
    # LOD mismatch is ineligible and restores the local atlas.
    views[1].mesh_lod_threshold = 1
    var incompatible: int = await settle()
    if not check(incompatible > shared, "LOD mismatch must fall back"):
        return
    views[1].mesh_lod_threshold = 0
    var camera: Camera3D = views[1].get_child(0)
    camera.cull_mask = 0x7FFFF
    var masked: int = await settle()
    if not check(masked > shared, "Partial camera masks must fall back"):
        return
    camera.cull_mask = 0xFFFFF
    RenderingServer.call("viewport_set_positional_shadow_atlas_shared_from", views[0].get_viewport_rid(), views[1].get_viewport_rid())
    var chained: int = await settle()
    if not check(chained >= baseline, "Sharing chains/cycles must fall back"):
        return
    RenderingServer.call("viewport_set_positional_shadow_atlas_shared_from", views[0].get_viewport_rid(), RID())
    # Owner is a RID reference, not a borrowed pointer; destruction must be safe.
    var owner: SubViewport = views.pop_front()
    owner.free()
    var freed: int = await settle()
    if not check(freed > 0, "Children must render independent shadows after owner destruction"):
        return
    print("PASS shared shadows: draws ", baseline, " -> ", shared, "; incompatible ", incompatible, "; masked ", masked, "; chain ", chained, "; freed owner ", freed)
    quit()

func check(condition: bool, message: String = "Test condition failed") -> bool:
    if not condition:
        push_error("FAIL " + message)
        quit(1)
    return condition
