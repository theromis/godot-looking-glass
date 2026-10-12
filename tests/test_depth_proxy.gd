extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
const Probe = preload("res://tests/depth_probe.gd")
signal probe_complete(result: Dictionary)
var sample_grid_side: int = 64
var continuous_motion: bool = false
var output: String = "res://benchmarks/depth-proxy/custom48"
func _initialize() -> void:
    run.call_deferred()
func box(parent: Node3D, position: Vector3, size: Vector3, color: Color, sphere: bool = false) -> void:
    var node := MeshInstance3D.new()
    if sphere:
        var mesh := SphereMesh.new()
        mesh.radius = size.x * 0.5
        mesh.height = size.y
        node.mesh = mesh
    else:
        var mesh := BoxMesh.new()
        mesh.size = size
        node.mesh = mesh
    node.position = position
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    node.material_override = material
    parent.add_child(node)
func build_fixture(scene_name: String) -> Node3D:
    var scene := Node3D.new()
    root.add_child(scene)
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.025, 0.04, 0.09)
    var world := WorldEnvironment.new()
    world.environment = env
    scene.add_child(world)
    box(scene, Vector3(0,0,-3), Vector3(6,4,0.15), Color(0.15,0.55,0.35))
    if scene_name == "smooth":
        box(scene, Vector3(0.4,0,-0.5), Vector3(2,2,2), Color(0.85,0.25,0.12), true)
    if scene_name == "bars":
        box(scene, Vector3(-0.8,0,0.8), Vector3(1,1.5,1), Color(0.9,0.25,0.12))
        box(scene, Vector3(0.7,0,-1.5), Vector3(1.3,2.2,1), Color(0.1,0.65,0.95))
        for i in range(9):
            box(scene, Vector3(-1.6+i*0.4,0,2), Vector3(0.07,2,0.12), Color(0.95,0.8,0.15))
    if scene_name == "layers":
        for i in range(30):
            box(scene, Vector3(-1.6+(i%6)*0.64,-0.7+float((i/6)%2)*1.4,1.4-float(i/12)*1.6), Vector3(0.35,0.55,0.4), Color.from_hsv(float(i%7)/7,0.85,0.95), i%3==0)
    return scene

func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--grid="):
            sample_grid_side = int(arg.trim_prefix("--grid="))
            if sample_grid_side not in [64,128,256]:
                print("FAIL supported grid: 64,128,256")
                quit(1)
                return
        if arg == "--continuous-motion":
            continuous_motion = true
        if arg.begins_with("--output="):
            output = arg.trim_prefix("--output=")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    RenderingServer.set_render_loop_enabled(false)
    var reports: Array[Dictionary] = []
    for scene_name in ["smooth", "bars", "layers"]:
        var scene := build_fixture(scene_name)
        var rigs: Array = []
        for real_count in [16,48]:
            var rig := Rig.new()
            rig.total_views = 48
            rig.real_views = real_count
            rig.synthesis = true
            rig.borrow_source_depth = true
            rig.borrow_source_color = true
            rig.tile_size = Vector2i(256,256)
            rig.position.z = 6
            scene.add_child(rig)
            rigs.append(rig)
        for snapshot in range(3):
            var x: float = float(snapshot-1)*0.35
            var yaw: float = float(snapshot-1)*0.035
            for rig in rigs:
                rig.position = Vector3(x,0,6)
                rig.rotation.y = yaw
                rig._process(0)
            var before: Array = rigs.map(func(r): return r.synthesizer.dispatch_count)
            for frame in range(16):
                if continuous_motion:
                    # Actual camera updates between draws, then settle at the
                    # sampled pose so source/reference/probe describe one state.
                    var progress: float = float(frame + 1) / 16.0
                    for rig in rigs:
                        rig.position.x = x - 0.25 * (1.0-progress)
                        rig.rotation.y = yaw - 0.025 * (1.0-progress)
                        rig._process(0)
                await process_frame
                RenderingServer.force_draw(false,1.0/60.0)
                RenderingServer.force_sync()
            for settle in range(2):
                await process_frame
                RenderingServer.force_draw(false,1.0/60.0)
                RenderingServer.force_sync()
            for i in range(2):
                if rigs[i].synthesizer.dispatch_count < before[i]+8:
                    print("FAIL no quilt work")
                    quit(1)
                    return
                for capture in rigs[i].captures:
                    if not capture.borrow_depth or not capture.depth.is_valid():
                        print("FAIL missing raw borrowed depth")
                        quit(1)
                        return
            var name: String = scene_name+"-"+str(snapshot)
            for i in range(2):
                var image: Image = rigs[i].quilt_texture.get_image()
                if image == null or image.is_empty() or image.get_pixel(0,0).b < 0.01:
                    print("FAIL empty quilt")
                    quit(1)
                    return
                image.convert(Image.FORMAT_RGBA8)
                if image.save_png(output+"/"+name+("-synth.png" if i==0 else "-reference.png")) != OK:
                    print("FAIL cannot save capture")
                    quit(1)
                    return
            RenderingServer.call_on_render_thread(func():
                var result: Dictionary = Probe.new().measure(rigs[0],null,sample_grid_side)
                _probe_result.call_deferred(result)
            )
            var result: Dictionary = await probe_complete
            if result.has("error"):
                print("FAIL ",result.error)
                quit(1)
                return
            if result.readback_bytes != 12*sample_grid_side*sample_grid_side or result.rows.size()!=48:
                print("FAIL incomplete probe")
                quit(1)
                return
            for row in result.rows:
                for value in row.counts:
                    if value < 0 or value > sample_grid_side*sample_grid_side or (row.real and value != 0):
                        print("FAIL probe counters invalid")
                        quit(1)
                        return
            result["scene"]=scene_name
            result["snapshot"]=snapshot
            result["camera_x"]=x
            result["camera_yaw_radians"]=yaw
            result["name"]=name
            result["anchor_indices"]=rigs[0].anchor_indices
            result["dispatches"]=rigs[0].synthesizer.dispatch_count
            reports.append(result)
            print("PROBE ",name)
        for rig in rigs:
            rig.queue_free()
        for frame in range(4):
            await process_frame
            RenderingServer.force_sync()
        scene.queue_free()
        await process_frame
    var file := FileAccess.open(output+"/raw.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"godot":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"tile":256,"rows":reports,"motion":"Camera transforms updated for 16 successive draws per sample, then two settling draws; no temporal reconstruction or flicker test." if continuous_motion else "Three prescribed static snapshots along a translated/rotated camera path; no temporal reconstruction or flicker test.","continuous_motion":continuous_motion},"  "))
    RenderingServer.set_render_loop_enabled(true)
    print("PASS depth proxy: 9 snapshots, GPU counters bounded, real tiles excluded, grid ",sample_grid_side)
    quit()
func _probe_result(result: Dictionary) -> void:
    probe_complete.emit(result)
