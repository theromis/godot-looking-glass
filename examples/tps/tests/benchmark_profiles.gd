extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var settings: Node=root.get_node("Settings")
    settings.config_file.set_value("video","display_mode",Window.MODE_WINDOWED)
    settings.config_file.set_value("video","vsync",DisplayServer.VSYNC_DISABLED)
    settings.config_file.set_value("video","scale_filter",Viewport.SCALING_3D_MODE_BILINEAR)
    var controller: Node=root.get_node("LookingGlassGame")
    var profile: String="fast"
    var capture_hz: float=0.0
    var sample_seconds: float=8.0
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--profile="): profile=argument.trim_prefix("--profile=")
        if argument.begins_with("--seconds="): sample_seconds=clampf(argument.trim_prefix("--seconds=").to_float(),4,40)
        if argument.begins_with("--capture-hz="): capture_hz=argument.trim_prefix("--capture-hz=").to_float()
    controller.overlap_capture="--overlap" in OS.get_cmdline_user_args()
    controller.render_desktop_3d=not "--no-desktop-3d" in OS.get_cmdline_user_args()
    controller.async_gpu_copy="--async-copy" in OS.get_cmdline_user_args()
    controller.max_capture_hz=capture_hz
    controller.profile_name=profile
    var level: Node3D=load("res://level/level.tscn").instantiate()
    # Fix the random spawn choice so every profile sees the same geometry.
    var spawn_points: Node3D=level.get_node("PlayerSpawnpoints")
    var fixed_spawn: Transform3D=spawn_points.get_child(0).transform
    for marker in spawn_points.get_children(): marker.transform=fixed_spawn
    root.add_child(level)
    seed(12345)
    for frame in range(8): await process_frame
    if profile!="desktop" and not controller.start_output(): printerr("FAIL benchmark startup"); quit(1); return
    var camera: Camera3D=root.get_camera_3d()
    var rotation_node: Node3D=camera.get_parent().get_parent()
    var initial_rotation: float=rotation_node.rotation.y
    var deadline: int=Time.get_ticks_msec()+15000
    while profile!="desktop" and controller.output.get("_state")!="running" and Time.get_ticks_msec()<deadline: await process_frame
    if profile!="desktop" and controller.output.get("_state")!="running": printerr("FAIL benchmark SDK readiness"); quit(1); return
    var warm_started: int=Time.get_ticks_msec()
    while Time.get_ticks_msec()-warm_started<4000:
        rotation_node.rotation.y=initial_rotation+0.15*sin((Time.get_ticks_msec()-warm_started)*0.001)
        await process_frame
    var submitted_start: int=controller.output.submitted_frames
    var call_start: int=controller.output.copy_call_usec
    var poll_start: int=controller.output.copy_poll_usec
    var latency_start: int=controller.output.copy_latency_usec
    var completed_start: int=controller.output.copy_completions
    controller.output.submission_intervals_usec.clear()
    controller.output.set("_last_submission_usec",0)
    var started: int=Time.get_ticks_usec()
    var previous: int=started
    var samples: Array[float]=[]
    while Time.get_ticks_usec()-started<int(sample_seconds*1000000):
        rotation_node.rotation.y=initial_rotation+0.15*sin((Time.get_ticks_usec()-started)*0.000001)
        await process_frame
        var now: int=Time.get_ticks_usec()
        samples.append((now-previous)*0.001)
        previous=now
    var elapsed: float=(previous-started)*0.000001
    var submitted: int=controller.output.submitted_frames-submitted_start
    var copy_count: int=controller.output.copy_completions-completed_start
    var call_mean_ms: float=(controller.output.copy_call_usec-call_start)*0.001/maxi(1,copy_count)
    var poll_mean_ms: float=(controller.output.copy_poll_usec-poll_start)*0.001/maxi(1,copy_count)
    var latency_mean_ms: float=(controller.output.copy_latency_usec-latency_start)*0.001/maxi(1,copy_count)
    var gaps: Array=controller.output.submission_intervals_usec.duplicate()
    gaps.sort()
    var gap_p95_ms: float=float(gaps[mini(gaps.size()-1,int(ceil(gaps.size()*0.95))-1)])*0.001 if not gaps.is_empty() else 0.0
    samples.sort()
    var mean: float=elapsed*1000/samples.size()
    var p95: float=samples[mini(samples.size()-1,int(ceil(samples.size()*0.95))-1)]
    await RenderingServer.frame_post_draw
    var transform_matches: bool=profile=="desktop" or controller.rig.global_transform.is_equal_approx(camera.global_transform)
    controller.stop_output()
    deadline=Time.get_ticks_msec()+5000
    while controller.output.is_output_active() and Time.get_ticks_msec()<deadline: await process_frame
    var valid: bool=transform_matches and not controller.error_seen and (profile=="desktop" or (controller.last_cleanup and controller.last_submitted==controller.last_received and submitted>0))
    valid=valid and (not root.disable_3d)
    printerr("BENCH ",JSON.stringify({"desktop_3d":controller.render_desktop_3d,"overlap":controller.overlap_capture,"submission_gap_p95_ms":gap_p95_ms,"async_copy":controller.async_gpu_copy,"copy_call_mean_ms":call_mean_ms,"copy_poll_mean_ms":poll_mean_ms,"copy_completion_wall_mean_ms":latency_mean_ms,"profile":profile,"capture_hz_limit":capture_hz,"engine_frames":samples.size(),"seconds":elapsed,"frame_mean_ms":mean,"frame_p95_ms":p95,"engine_frame_hz":samples.size()/elapsed,"submitted":submitted,"submission_hz":submitted/elapsed,"total_submitted":controller.last_submitted,"total_received":controller.last_received,"sdk_cleanup":controller.last_cleanup,"feature_passed":valid}))
    level.queue_free()
    for frame in range(60): await process_frame
    printerr("PASS TPS profile benchmark" if valid else "FAIL TPS profile benchmark")
    quit(0 if valid else 1)
