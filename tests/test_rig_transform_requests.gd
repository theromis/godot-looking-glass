extends SceneTree
const Rig=preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var rig:=Rig.new()
    rig.total_views=4
    rig.real_views=2
    rig.columns=2
    rig.tile_size=Vector2i(32,64)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.compose_in_capture_callback=true
    rig.auto_update_on_transform=false
    root.add_child(rig)
    var deadline: int=Time.get_ticks_msec()+5000
    while rig.completed_revision<rig.requested_revision and Time.get_ticks_msec()<deadline: await process_frame
    var revision: int=rig.requested_revision
    rig.position.x=0.2
    for frame in range(4): await process_frame
    var valid: bool=revision>0 and rig.completed_revision>=revision and rig.requested_revision==revision and rig.cameras[0].global_transform.is_equal_approx(rig.global_transform*rig.camera_offsets[0])
    rig.request_update()
    deadline=Time.get_ticks_msec()+5000
    while rig.completed_revision<rig.requested_revision and Time.get_ticks_msec()<deadline: await process_frame
    valid=valid and rig.completed_revision==revision+1
    rig.auto_update_on_transform=true
    rig.position.x=0.4
    for frame in range(4): await process_frame
    valid=valid and rig.requested_revision>revision+1
    rig.queue_free()
    for frame in range(8): await process_frame
    printerr("PASS external capture request ownership" if valid else "FAIL external capture request ownership")
    quit(0 if valid else 1)
