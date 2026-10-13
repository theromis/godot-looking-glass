extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
const Output=preload("res://addons/looking_glass/metal_output.gd")
var done: bool=false
var failure_seen: bool=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var scene:=Node3D.new()
    root.add_child(scene)
    var rig:=Rig.new()
    rig.total_views=66
    rig.real_views=24
    rig.columns=11
    rig.tile_size=Vector2i(64,114)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.compose_in_capture_callback=true
    scene.add_child(rig)
    var output:=Output.new()
    output.display_index=2147483647 # Deliberately invalid; must never reach SDK window creation.
    scene.add_child(output)
    output.failed.connect(func(_reason: String): failure_seen=true)
    output.stopped.connect(func(_graceful: bool): done=true)
    if not output.start_output(rig): quit(1); return
    var deadline: int=Time.get_ticks_msec()+10000
    while not done and Time.get_ticks_msec()<deadline: await process_frame
    var passed: bool=done and failure_seen and output.worker_exit_code==1 and output.worker_status=="Display not detected by Bridge" and not output.is_output_active()
    print("UNAVAILABLE exit=",output.worker_exit_code," handled=",failure_seen)
    scene.queue_free()
    for i in range(4): await process_frame
    print("PASS unavailable display handled" if passed else "FAIL unavailable display handled")
    quit(0 if passed else 1)
