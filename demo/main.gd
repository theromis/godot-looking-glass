extends Node3D
const Rig = preload("res://addons/looking_glass/rig.gd")
var rig: Node3D
var spinner: MeshInstance3D
var samples: Array[float] = []
var frames: int = 0
var warmup: int = 90
var measured_frames: int = 240
var label: Label
var benchmark_path: String = ""
var capture_path: String = ""
var transparent_object: MeshInstance3D
var show_transparency: bool = true
var static_scene: bool = false
var fixed_motion: bool = false
var positional_lights: int = 0
var gpu_anchor_samples: Array[float] = []
var shadow_draw_samples: Array[int] = []
var render_cpu_samples: Array[float] = []
var setup_cpu_samples: Array[float] = []
var scene_draw_samples: Array[int] = []
var stress_objects: int = 0
var batch_objects: bool = false
var profile_passes: bool = false
var gpu_profiler: RefCounted
var previous_tick_us: int = 0
var wall_samples: Array[float] = []
var rendered_benchmark: bool = false
var last_quilt_dispatch: int = 0
var last_quilt_tick_us: int = 0

func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    var detect_bridge: bool = false
    var calibration_path: String = ""
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.025, 0.03, 0.055)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    env.ambient_light_energy = 0.5
    var world := WorldEnvironment.new()
    world.environment = env
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-40, -25, 0)
    sun.shadow_enabled = true
    add_child(sun)
    _box(Vector3(0, -1.5, -1), Vector3(7, 0.2, 9), Color(0.18, 0.2, 0.28))
    spinner = _box(Vector3(-0.8, 0, 0.8), Vector3(1, 1.5, 1), Color(0.9, 0.25, 0.12))
    _box(Vector3(0.7, 0, -1.5), Vector3(1.3, 2.2, 1), Color(0.1, 0.65, 0.95))
    _box(Vector3(0, 0, -3.5), Vector3(3, 2, 0.2), Color(0.3, 0.8, 0.25))
    for i in range(7):
        _box(Vector3(-1.5 + i * 0.5, 0, 2), Vector3(0.07, 2, 0.12), Color(0.95, 0.8, 0.15))
    transparent_object = _box(Vector3(1.3, 0.2, 1.3), Vector3(1.1, 1.8, 0.15), Color(0.7, 0.3, 1, 0.35))
    transparent_object.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    rig = Rig.new()
    rig.position = Vector3(0, 0.1, 6)
    for arg in args:
        if arg.begins_with("--anchors="):
            for value in arg.trim_prefix("--anchors=").split(","):
                if not value.is_valid_int():
                    push_error("Invalid anchor index")
                    get_tree().quit(1)
                    return
                rig.custom_anchor_indices.append(int(value))
        if arg == "--on-demand":
            rig.update_on_demand = true
        if arg == "--rendered-benchmark":
            rendered_benchmark = true
        if arg == "--inverse-depth":
            rig.inverse_depth_reprojection = true
        if arg == "--rescue":
            rig.disocclusion_rescue = true
        if arg.begins_with("--iterations="):
            rig.reprojection_iterations = int(arg.trim_prefix("--iterations="))
            if rig.reprojection_iterations not in [2, 4, 8]:
                push_error("Invalid iterations; expected 2, 4 or 8")
                get_tree().quit(1)
                return
        if arg.begins_with("--workgroup="):
            rig.synthesis_workgroup = ["8x8", "16x8", "16x16"].find(arg.trim_prefix("--workgroup="))
            if rig.synthesis_workgroup < 0:
                push_error("Invalid workgroup; expected 8x8, 16x8 or 16x16")
                get_tree().quit(1)
                return
        if arg == "--borrow-depth":
            rig.borrow_source_depth = true
            rig.borrow_source_color = true
        if arg == "--borrow-color":
            rig.borrow_source_color = true
        if arg == "--profile-passes":
            profile_passes = true
        if arg.begins_with("--objects="):
            stress_objects = clampi(int(arg.split("=")[1]), 0, 4096)
        if arg == "--batch-objects":
            batch_objects = true
        if arg == "--bridge":
            detect_bridge = true
        if arg.begins_with("--calibration="):
            calibration_path = arg.trim_prefix("--calibration=")
        if arg.begins_with("--views="):
            rig.total_views = int(arg.split("=")[1])
            rig.real_views = rig.total_views
        if arg.begins_with("--real="):
            rig.real_views = int(arg.split("=")[1])
            rig.synthesis = true
        if arg.begins_with("--tile="):
            var v: int = int(arg.split("=")[1])
            rig.tile_size = Vector2i(v, v)
        if arg.begins_with("--benchmark="):
            benchmark_path = arg.trim_prefix("--benchmark=")
        if arg.begins_with("--capture="):
            capture_path = arg.trim_prefix("--capture=")
        if arg == "--shared-shadows":
            rig.shared_positional_shadows = true
        if arg == "--fixed-motion":
            fixed_motion = true
        if arg.begins_with("--positional-lights="):
            positional_lights = clampi(int(arg.split("=")[1]), 0, 8)
        if arg == "--static":
            static_scene = true
        if arg == "--opaque":
            show_transparency = false
    if positional_lights > 0:
        sun.shadow_enabled = false
        for i in range(positional_lights):
            var light := SpotLight3D.new()
            light.position = Vector3(-2.5 + float(i % 4) * 1.6, 3.0 + float(i / 4), 3.5)
            light.spot_range = 12.0
            light.spot_angle = 55.0
            light.light_energy = 1.5 / positional_lights
            light.shadow_enabled = "--no-positional-shadows" not in args
            add_child(light)
            light.look_at(Vector3(0, -0.5, -1), Vector3.UP)
    _add_stress_objects()
    transparent_object.visible = show_transparency
    if detect_bridge or calibration_path != "":
        var bridge = preload("res://addons/looking_glass/bridge_client.gd").new()
        add_child(bridge)
        if detect_bridge:
            var devices: Array[Dictionary] = await bridge.detect()
            print("BRIDGE ", devices.size(), " calibrated displays; ", bridge.last_error)
            if not devices.is_empty():
                bridge.apply_geometry(rig, devices[0])
            await bridge.close_session()
        if calibration_path != "":
            var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(calibration_path))
            if json is Dictionary:
                bridge.apply_geometry(rig, {"calibration": bridge.unwrap(json)})
        bridge.queue_free()
    rig.measure_render_time = benchmark_path != "" and "--no-viewport-timing" not in args
    rig.profile_synthesis = (benchmark_path != "" or profile_passes or "--profile-quilt" in args) and "--no-quilt-timing" not in args
    if not rig.custom_anchor_indices.is_empty() and (not rig.synthesis or not rig.custom_anchors_valid()):
        push_error("Anchors require synthesis and a sorted unique set matching --real, including 0 and last view")
        get_tree().quit(1)
        return
    if rig.update_on_demand and (not static_scene or not rig.synthesis or rendered_benchmark):
        push_error("Demo --on-demand requires --static and compute synthesis; benchmark samples process calls")
        get_tree().quit(1)
        return
    add_child(rig)
    if "--debug-holes" in args and rig.synthesis:
        rig.synthesizer.debug_holes = true
    if "--no-mesh-lod" in args:
        for view in rig.views:
            view.mesh_lod_threshold = 0.0
    if profile_passes:
        gpu_profiler = preload("res://addons/looking_glass/gpu_profiler.gd").new()
        gpu_profiler.configure(rig, get_viewport())
    var layer := CanvasLayer.new()
    add_child(layer)
    var preview := TextureRect.new()
    preview.position = Vector2(20, 60)
    preview.size = Vector2(1080, 630)
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.texture = rig.quilt_texture
    layer.add_child(preview)
    label = Label.new()
    label.position = Vector2(20, 16)
    layer.add_child(label)

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = pos
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    node.material_override = mat
    add_child(node)
    return node

func _add_stress_objects() -> void:
    if stress_objects == 0:
        return
    # Same shared geometry/material and deterministic transforms in both paths.
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.10, 0.10, 0.10)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.35, 0.55, 0.85)
    mesh.material = material
    var instances: MultiMesh
    if batch_objects:
        instances = MultiMesh.new()
        instances.transform_format = MultiMesh.TRANSFORM_3D
        instances.mesh = mesh
        instances.instance_count = stress_objects
        var batch := MultiMeshInstance3D.new()
        batch.multimesh = instances
        add_child(batch)
    for i in range(stress_objects):
        var pos := Vector3(-2.25 + (i % 16) * 0.30, -1.15 + ((i / 16) % 8) * 0.30, 1.5 - (i / 128) * 1.20)
        var transform := Transform3D(Basis.IDENTITY, pos)
        if batch_objects:
            instances.set_instance_transform(i, transform)
        else:
            var node := MeshInstance3D.new()
            node.mesh = mesh
            node.transform = transform
            add_child(node)

func _process(delta: float) -> void:
    var tick_us: int = Time.get_ticks_usec()
    var wall_ms: float = float(tick_us - previous_tick_us) / 1000.0
    previous_tick_us = tick_us
    if not static_scene:
        if fixed_motion:
            spinner.rotation.y = frames * 0.01
        else:
            spinner.rotation.y += delta * 0.35
    frames += 1
    var progress: int = frames
    var advanced: bool = true
    if rendered_benchmark and rig.synthesis:
        progress = rig.synthesizer.dispatch_count
        advanced = progress > last_quilt_dispatch
        if advanced:
            wall_ms = float(tick_us - last_quilt_tick_us) / 1000.0
            last_quilt_tick_us = tick_us
            last_quilt_dispatch = progress
    label.text = "Looking Glass Lab | %d views / %d real | %s | %.1f FPS" % [rig.total_views, rig.real_views, "experimental compute" if rig.synthesis else "raster quilt", Engine.get_frames_per_second()]
    if benchmark_path != "" and advanced and progress > warmup and progress <= warmup + measured_frames:
        samples.append(delta * 1000.0)
        wall_samples.append(wall_ms)
        if gpu_profiler != null:
            RenderingServer.call_on_render_thread(gpu_profiler.collect)
        var anchor_gpu: float = 0.0
        for view in rig.views:
            anchor_gpu += RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
        gpu_anchor_samples.append(anchor_gpu)
        var cpu_time: float = 0.0
        var scene_draws: int = 0
        for view in rig.views:
            cpu_time += RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid())
            scene_draws += RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
        render_cpu_samples.append(cpu_time)
        setup_cpu_samples.append(RenderingServer.get_frame_setup_time_cpu())
        scene_draw_samples.append(scene_draws)
        var shadow_draws: int = 0
        for view in rig.views:
            shadow_draws += RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
        shadow_draw_samples.append(shadow_draws)
    if advanced and progress >= warmup + measured_frames and (benchmark_path != "" or capture_path != ""):
        _finish.call_deferred()

func _finish() -> void:
    set_process(false)
    await RenderingServer.frame_post_draw
    if capture_path != "":
        var image: Image = rig.quilt_texture.get_image()
        if image != null and not image.is_empty():
            image.convert(Image.FORMAT_RGBA8)
            image.save_png(capture_path)
            print("CAPTURE ", capture_path, " ", image.get_size())
    if benchmark_path != "":
        samples.sort()
        var mean: float = 0.0
        for value in samples:
            mean += value
        mean /= samples.size()
        var report := {"godot": Engine.get_version_info(), "os": OS.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "views": rig.total_views, "real_views": rig.real_views, "tile": [rig.tile_size.x, rig.tile_size.y], "synthesis": rig.synthesis, "transparency": show_transparency, "warmup": warmup, "samples": samples.size(), "frame_mean_ms": mean, "frame_p50_ms": samples[samples.size()/2], "frame_p95_ms": samples[mini(samples.size()-1, int(samples.size()*0.95))], "compute_dispatches": rig.synthesizer.dispatch_count if rig.synthesis else 0, "metric": "engine process delta; includes engine, preview, scheduling; not isolated GPU time or independent wall-clock measurement"}
        var anchor_mean: float = 0.0
        for value in gpu_anchor_samples:
            anchor_mean += value
        report["update_on_demand"] = rig.update_on_demand
        report["requested_revision"] = rig.requested_revision
        report["completed_revision"] = rig.completed_revision
        report["source_capture_counts"] = rig.captures.map(func(c): return c.capture_count)
        report["shared_positional_shadows_requested"] = rig.shared_positional_shadows
        report["shared_shadow_api_available"] = rig.shared_shadow_api_available
        report["positional_lights"] = positional_lights
        var shadow_draw_mean: float = 0.0
        for value in shadow_draw_samples:
            shadow_draw_mean += value
        report["shadow_draw_calls_sum_mean"] = shadow_draw_mean / shadow_draw_samples.size()
        report["benchmark_sampling"] = "completed quilt updates" if rendered_benchmark and rig.synthesis else "process calls"
        report["process_calls"] = frames
        report["debug_holes"] = rig.synthesizer.debug_holes if rig.synthesis else false
        report["inverse_depth_reprojection"] = rig.synthesizer.inverse_depth if rig.synthesis else false
        report["disocclusion_rescue"] = rig.disocclusion_rescue
        report["reprojection_iterations"] = rig.synthesizer.iterations if rig.synthesis else 0
        report["synthesis_workgroup"] = ["8x8", "16x8", "16x16"][rig.synthesis_workgroup]
        report["borrow_source_depth"] = rig.borrow_source_depth
        report["owned_capture_depth_bytes"] = 0
        report["capture_fallback_reasons"] = []
        report["effective_borrowed_color_views"] = 0
        report["effective_borrowed_depth_views"] = 0
        report["borrow_source_color"] = rig.borrow_source_color
        report["owned_capture_color_bytes"] = 0
        for capture in rig.captures:
            var pixels: int = capture.dimensions.x * capture.dimensions.y
            report["owned_capture_color_bytes"] += 0 if capture.borrow_color else pixels * 8
            report["owned_capture_depth_bytes"] += 0 if capture.borrow_depth else pixels * 4
            report["effective_borrowed_color_views"] += int(capture.borrow_color)
            report["effective_borrowed_depth_views"] += int(capture.borrow_depth)
            if capture.fallback_reason != "" and capture.fallback_reason not in report["capture_fallback_reasons"]:
                report["capture_fallback_reasons"].append(capture.fallback_reason)
        report["quilt_profiling_enabled"] = rig.profile_synthesis
        report["quilt_profiling_sample_limit"] = rig.profiling_sample_limit
        report["quilt_timestamp_pairs"] = rig.synthesizer.timestamp_pairs if rig.synthesis else 0
        report["viewport_timing_enabled"] = rig.measure_render_time
        report["wall_frame_mean_ms"] = _mean(wall_samples)
        report["wall_metric"] = "Time.get_ticks_usec between observed quilt updates; includes scheduling/presentation" if rendered_benchmark and rig.synthesis else "Time.get_ticks_usec between consecutive process calls; includes scheduling and presentation"
        if gpu_profiler != null:
            report["gpu_pass_profile"] = gpu_profiler.report()
        report["stress_objects"] = stress_objects
        report["batch_objects"] = batch_objects
        report["anchor_indices"] = rig.anchor_indices
        report["anchor_cpu_sum_mean_ms"] = _mean(render_cpu_samples)
        report["frame_setup_cpu_mean_ms"] = _mean(setup_cpu_samples)
        report["scene_draw_calls_sum_mean"] = _mean(scene_draw_samples)
        report["cpu_metric"] = "anchor viewport render CPU sum and global frame setup separately; excludes script, quilt and main viewport"
        report["fixed_motion"] = fixed_motion
        report["anchor_gpu_sum_mean_ms"] = anchor_mean / gpu_anchor_samples.size()
        report["anchor_gpu_metric"] = "sum of engine per-viewport GPU durations, not total frame critical path"
        if rig.synthesis:
            var times: Array[float] = rig.synthesizer.gpu_ms
            var quilt_mean: float = 0.0
            for value in times:
                quilt_mean += value
            report["quilt_compute_gpu_mean_ms"] = quilt_mean / times.size() if not times.is_empty() else null
            report["quilt_timestamp_samples"] = times.size()
            var cpu_times: Array[float] = rig.synthesizer.dispatch_cpu_ms
            var cpu_mean: float = 0.0
            for value in cpu_times:
                cpu_mean += value
            report["quilt_submission_cpu_mean_ms"] = cpu_mean / cpu_times.size() if not cpu_times.is_empty() else null
            report["quilt_submission_cpu_samples"] = cpu_times.size()
        var file := FileAccess.open(benchmark_path, FileAccess.WRITE)
        if file:
            file.store_string(JSON.stringify(report, "  "))
        print(JSON.stringify(report))
    get_tree().quit()

func _mean(values: Array) -> float:
    var total: float = 0.0
    for value in values:
        total += float(value)
    return total / values.size() if not values.is_empty() else 0.0
