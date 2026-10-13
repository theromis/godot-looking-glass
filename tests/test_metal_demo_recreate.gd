extends SceneTree
const Demo=preload("res://demo/metal_output.gd")
var failed: bool=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var demo:=Demo.new()
    root.add_child(demo)
    demo.output.failed.connect(func(_reason: String): failed=true)
    demo._refresh()
    if demo.devices.is_empty(): printerr("FAIL recreate no device"); quit(1); return
    for cycle in range(4):
        demo._start()
        if not demo.output.is_output_active(): printerr("FAIL recreate start rejected"); quit(1); return
        var rig_ref:=weakref(demo.rig)
        var publisher_ref:=weakref(demo.output.get("_publisher"))
        var worker_pid: int=demo.output.get("_process_info").pid
        await create_timer(4).timeout
        var texture: RID=demo.rig.synthesizer.quilt
        demo.output.stop_output()
        var deadline: int=Time.get_ticks_msec()+5000
        while demo.output.is_output_active() and Time.get_ticks_msec()<deadline: await process_frame
        for frame in range(8): await process_frame
        var released: bool=rig_ref.get_ref()==null and publisher_ref.get_ref()==null and not RenderingServer.get_rendering_device().texture_is_valid(texture) and not OS.is_process_running(worker_pid)
        var valid: bool=not failed and released and not demo.output.is_output_active() and demo.output.worker_exit_code==0 and demo.output.sdk_cleanup_passed and demo.output.submitted_frames>5 and demo.output.submitted_frames==demo.output.received_frames
        printerr("RECREATE cycle=",cycle+1," submitted=",demo.output.submitted_frames," received=",demo.output.received_frames," resources_released=",released," valid=",valid)
        if not valid: quit(1); return
    demo.queue_free()
    for frame in range(4): await process_frame
    printerr("PASS demo rig recreation")
    quit()
