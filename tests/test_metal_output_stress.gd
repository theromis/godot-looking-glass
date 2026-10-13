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
    scene.add_child(output)
    output.failed.connect(func(reason: String): error_seen=true; printerr("FAIL output node ",reason))
    output.stopped.connect(func(_graceful: bool): done=true)
    output.duration_seconds=180
    var seconds: Array[float]=[4.0,4.0,4.0,4.0,4.0,120.0]
    var passed: bool=true
    for cycle in range(seconds.size()):
        done=false
        if not output.start_output(rig): passed=false; break
        printerr("CYCLE_BEGIN ",cycle+1)
        await create_timer(seconds[cycle]).timeout
        output.stop_output()
        var deadline: int=Time.get_ticks_msec()+5000
        while not done and Time.get_ticks_msec()<deadline: await process_frame
        var valid: bool=done and not error_seen and output.sdk_cleanup_passed and output.worker_exit_code==0 and output.submitted_frames>5 and output.received_frames==output.submitted_frames
        printerr("CYCLE_END ",cycle+1," submitted=",output.submitted_frames," received=",output.received_frames," cleanup=",output.sdk_cleanup_passed," valid=",valid)
        passed=passed and valid
        if not valid: break
        await create_timer(1).timeout
    scene.queue_free()
    for i in range(4): await process_frame
    printerr("PASS managed Metal lifecycle stress" if passed else "FAIL managed Metal lifecycle stress")
    quit(0 if passed else 1)
