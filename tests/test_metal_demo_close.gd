extends SceneTree
const Demo=preload("res://demo/metal_output.gd")
var failed: bool=false
var close_requested: bool=false
var worker_pid: int=0
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var demo:=Demo.new()
    root.add_child(demo)
    demo.output.failed.connect(func(_reason: String): failed=true)
    demo._refresh()
    if demo.devices.is_empty(): printerr("FAIL close no device"); quit(1); return
    # The demo's own stopped handler executes first and requests normal exit.
    demo.output.stopped.connect(func(graceful: bool):
        var valid: bool=close_requested and graceful and not failed and not demo.output.is_output_active() and demo.output.worker_exit_code==0 and demo.output.sdk_cleanup_passed and demo.output.submitted_frames>5 and demo.output.submitted_frames==demo.output.received_frames and not OS.is_process_running(worker_pid)
        printerr("CLOSE submitted=",demo.output.submitted_frames," received=",demo.output.received_frames," cleanup=",demo.output.sdk_cleanup_passed," valid=",valid)
        printerr("PASS demo active close notification" if valid else "FAIL demo active close notification")
        quit(0 if valid else 1)
    )
    demo._start()
    if not demo.output.is_output_active(): printerr("FAIL close start rejected"); quit(1); return
    worker_pid=demo.output.get("_process_info").pid
    await create_timer(4).timeout
    close_requested=true
    # Exercise the same notification handler used by the native close button.
    # This is not an OS-level click or forced process termination.
    demo.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
