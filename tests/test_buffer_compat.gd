extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
var rows: Array = []
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    print("COMPAT START")
    RenderingServer.set_render_loop_enabled(false)
    var scene := Node3D.new()
    root.add_child(scene)
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.12, 0.25, 0.4)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    var world := WorldEnvironment.new()
    world.environment = env
    scene.add_child(world)
    for i in range(5):
        var mesh := MeshInstance3D.new()
        mesh.mesh = SphereMesh.new() if i % 2 == 0 else BoxMesh.new()
        mesh.position = Vector3(i * 0.55 - 1.1, i * 0.08, -i * 0.7)
        scene.add_child(mesh)
    var probe: bool = "--probe" in OS.get_cmdline_user_args()
    var rigs: Array = []
    var late_effects: Array = []
    for mode in range(3):
        var rig := Rig.new()
        rig.total_views = 5
        rig.real_views = 2
        rig.tile_size = Vector2i(256, 256)
        rig.synthesis = true
        rig.borrow_source_color = mode > 0
        rig.borrow_source_depth = mode == 2
        rig.position.z = 6
        scene.add_child(rig)
        for capture in rig.captures:
            capture.borrow_safety_enabled = not probe
        rigs.append(rig)
        for camera in rig.cameras:
            late_effects.append(preload("res://tests/late_color.gd").new())
    var previous_color := RID()
    for name in ["baseline", "msaa2", "msaa4", "msaa8", "taa", "fxaa", "fsr1", "fsr2", "fsr2_native", "scale_half", "scale_up", "glow", "tonemap", "late_compositor", "reset"]:
        env.glow_enabled = name == "glow"
        env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if name == "tonemap" else Environment.TONE_MAPPER_LINEAR
        var before: Array = rigs.map(func(r): return r.synthesizer.dispatch_count)
        for rig_index in range(rigs.size()):
            var rig = rigs[rig_index]
            for camera_index in range(rig.cameras.size()):
                var effects: Array[CompositorEffect] = []
                effects.append(rig.captures[camera_index])
                if name == "late_compositor":
                    effects.append(late_effects[rig_index * 2 + camera_index])
                rig.cameras[camera_index].compositor.compositor_effects = effects
            for view in rig.views:
                view.msaa_3d = {"msaa2":Viewport.MSAA_2X,"msaa4":Viewport.MSAA_4X,"msaa8":Viewport.MSAA_8X}.get(name, Viewport.MSAA_DISABLED)
                view.use_taa = name == "taa"
                view.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if name == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
                view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if name in ["fsr2", "fsr2_native"] else (Viewport.SCALING_3D_MODE_FSR if name == "fsr1" else Viewport.SCALING_3D_MODE_BILINEAR)
                view.scaling_3d_scale = 0.5 if name in ["scale_half","fsr1","fsr2"] else (1.25 if name == "scale_up" else 1.0)
        for i in range(40):
            await process_frame
            RenderingServer.force_draw(false, 1.0 / 60.0)
            RenderingServer.force_sync()
        var a: Image = rigs[0].quilt_texture.get_image()
        var b: Image = rigs[1].quilt_texture.get_image()
        var c: Image = rigs[2].quilt_texture.get_image()
        if a == null or b == null or a.get_pixel(0,0).b < 0.01:
            push_error("Empty compatibility output")
            quit(1)
            return
        for i in range(3):
            if rigs[i].synthesizer.dispatch_count <= before[i]:
                push_error("No compatibility dispatches")
                quit(1)
                return
        var row: Dictionary = {"case":name, "exact":a.get_data()==b.get_data() and c != null and a.get_data()==c.get_data(), "dimensions":str(rigs[2].captures[0].dimensions), "dispatches":rigs[1].synthesizer.dispatch_count}
        row["color_rid_changed"] = previous_color.is_valid() and previous_color != rigs[2].captures[0].color
        previous_color = rigs[2].captures[0].color
        var owner = rigs[2].captures[0].buffer_owner
        row["observed_scaling_mode"] = owner.get_scaling_3d_mode() if owner != null else -1
        row["observed_msaa"] = owner.get_msaa_3d() if owner != null else -1
        if name in ["fsr2", "fsr2_native"] and owner != null and row["observed_scaling_mode"] != RenderingServer.VIEWPORT_SCALING_3D_MODE_FSR2:
            push_error("FSR2 was not actually active")
            quit(1)
            return
        row["borrow_color"] = rigs[2].captures[0].borrow_color
        row["borrow_depth"] = rigs[2].captures[0].borrow_depth
        row["fallback_reason"] = rigs[2].captures[0].fallback_reason
        row["color_only_borrowed"] = rigs[1].captures[0].borrow_color
        row["color_only_fallback_reason"] = rigs[1].captures[0].fallback_reason
        if not probe:
            var unsafe: bool = name in ["taa", "late_compositor"]
            if not row["exact"] or row["borrow_color"] == unsafe or row["borrow_depth"] == unsafe or row["color_only_borrowed"] == unsafe:
                push_error("Compatibility policy mismatch: " + JSON.stringify(row))
                quit(1)
                return
        rows.append(row)
        print("COMPAT ", JSON.stringify(row))
    var path: String = "res://benchmarks/buffer-compat/probe.json"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):
            path = arg.trim_prefix("--output=")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"godot":Engine.get_version_info(),"probe":probe,"rows":rows}, "  "))
    for rig in rigs:
        rig.queue_free()
    for i in range(4):
        await process_frame
    RenderingServer.call_on_render_thread(func():
        for effect in late_effects:
            effect.release()
    )
    for i in range(2):
        await process_frame
    print("PASS compatibility matrix: policy validated unless --probe")
    RenderingServer.set_render_loop_enabled(true)
    quit()
