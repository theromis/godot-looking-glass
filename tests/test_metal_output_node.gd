extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
const Output=preload("res://addons/looking_glass/metal_output.gd")
var box: MeshInstance3D
var output: Node
var done: bool=false
var error_seen: bool=false
func _initialize() -> void: run.call_deferred()
func _process(_delta: float) -> bool:
    if is_instance_valid(box):
        box.rotation.y=Time.get_ticks_msec()*0.0005
    return false
func run() -> void:
    var scene:=Node3D.new()
    root.add_child(scene)
    var environment:=WorldEnvironment.new()
    environment.environment=Environment.new()
    environment.environment.background_mode=Environment.BG_COLOR
    environment.environment.background_color=Color(0.2,0.4,0.7)
    scene.add_child(environment)
    box=MeshInstance3D.new()
    box.mesh=BoxMesh.new()
    var material:=StandardMaterial3D.new()
    material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color=Color(0.95,0.35,0.05)
    box.material_override=material
    scene.add_child(box)
    var rig:=Rig.new()
    rig.total_views=66
    rig.real_views=24
    rig.columns=11
    rig.tile_size=Vector2i(372,682)
    rig.position.z=6
    rig.focus_distance=6
    rig.view_cone_degrees=30
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.compose_in_capture_callback=true
    scene.add_child(rig)
    output=Output.new()
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--capture-hz="): output.max_capture_hz=clampf(argument.trim_prefix("--capture-hz=").to_float(),0,60)
    scene.add_child(output)
    output.failed.connect(func(reason: String): error_seen=true; printerr("FAIL output node ",reason))
    output.stopped.connect(func(_graceful: bool): done=true)
    if not output.start_output(rig): quit(1); return
    var ownership_passed: bool=not rig.auto_update_on_transform
    var show_seconds: float=10
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--show-seconds="): show_seconds=clampf(argument.trim_prefix("--show-seconds=").to_float(),2,40)
    await create_timer(show_seconds).timeout
    output.stop_output()
    var deadline: int=Time.get_ticks_msec()+5000
    while not done and Time.get_ticks_msec()<deadline: await process_frame
    var passed: bool=ownership_passed and rig.auto_update_on_transform and done and not error_seen and output.sdk_cleanup_passed and output.submitted_frames>5 and output.received_frames==output.submitted_frames
    if output.max_capture_hz>0:
        passed=passed and output.submitted_frames<=ceili(show_seconds*output.max_capture_hz)+1
    print("OUTPUT submitted=",output.submitted_frames," received=",output.received_frames," cleanup=",output.sdk_cleanup_passed)
    done=false
    if output.start_output(rig):
        output.stop_output()
        deadline=Time.get_ticks_msec()+5000
        while not done and Time.get_ticks_msec()<deadline: await process_frame
        passed=passed and done and not error_seen and output.sdk_cleanup_passed
        print("OUTPUT early_stop cleanup=",output.sdk_cleanup_passed)
    else:
        passed=false
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS managed Metal output node" if passed else "FAIL managed Metal output node")
    quit(0 if passed else 1)
