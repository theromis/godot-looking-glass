extends "res://demo/main.gd"
const DepthProbe = preload("res://tests/depth_probe.gd")
signal report_ready(report: Dictionary)
var probe: RefCounted
var reduce_gpu: bool = false
var reduction_exact: bool = true
var grid: int = 0
var period: int = 1
var synchronous_feedback: bool = false
var probe_dispatches: int = 0
var measured_dispatches: int = 0
var gpu_times: Array[float] = []
var submission_times: Array[float] = []
var readback_times: Array[float] = []
var readback_bytes: int = 0
var last_query_frame: int = -1
var last_probe_quilt: int = -1
var last_counts: Dictionary = {}
var asynchronous_feedback: bool = false
var pending_feedback: bool = false
var feedback_callbacks: int = 0
var feedback_latencies: Array[float] = []
var isolate_timer: bool = false
var blit_source: RID
var blit_dest: RID
var debug_feedback: bool = false
var configuration_error: String = ""

func _ready() -> void:
    super._ready()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--bench-warmup="):
            warmup = int(arg.trim_prefix("--bench-warmup="))
        if arg.begins_with("--bench-frames="):
            measured_frames = int(arg.trim_prefix("--bench-frames="))
        if arg == "--probe-isolate-timer":
            isolate_timer = true
        if arg == "--probe-reduce-gpu":
            reduce_gpu = true
        if arg == "--probe-async":
            asynchronous_feedback = true
        if arg.begins_with("--probe-grid="):
            grid = int(arg.trim_prefix("--probe-grid="))
        if arg.begins_with("--probe-period="):
            period = int(arg.trim_prefix("--probe-period="))
        if arg == "--probe-log-feedback":
            debug_feedback = true
        if arg == "--probe-sync":
            synchronous_feedback = true
    if grid not in [0,64,128,256] or period < 1 or not rig.synthesis or not rig.borrow_source_depth:
        print("FAIL probe benchmark configuration")
        get_tree().quit(1)
        return
    if grid > 0 or isolate_timer:
        probe = DepthProbe.new()
        RenderingServer.call_on_render_thread(func():
            if grid > 0:
                var error: Dictionary = probe.configure(rig,null,grid,reduce_gpu)
                if not error.is_empty(): configuration_error = str(error)
            if isolate_timer:
                var rd := RenderingServer.get_rendering_device()
                blit_source = rd.storage_buffer_create(4,PackedByteArray([0,0,0,0]))
                blit_dest = rd.storage_buffer_create(4,PackedByteArray([0,0,0,0]))
        )
        RenderingServer.frame_post_draw.connect(_probe_frame)

func _probe_frame() -> void:
    RenderingServer.call_on_render_thread(_probe_render)

func _collect_gpu() -> void:
    var rd := RenderingServer.get_rendering_device()
    var frame: int = rd.get_captured_timestamps_frame()
    if frame == last_query_frame: return
    last_query_frame = frame
    var start: int = -1
    var id: int = -1
    for i in range(rd.get_captured_timestamps_count()):
        var name: String = rd.get_captured_timestamp_name(i)
        if name.begins_with("LG depth begin "):
            id = int(name.trim_prefix("LG depth begin "))
            start = rd.get_captured_timestamp_gpu_time(i)
        elif name == "LG depth end" and start >= 0 and id > warmup and id <= warmup+measured_frames:
            gpu_times.append(float(rd.get_captured_timestamp_gpu_time(i)-start)/1000000.0)

func _probe_render() -> void:
    if configuration_error != "": return
    _collect_gpu()
    var id: int = rig.synthesizer.dispatch_count
    if id <= 0 or id == last_probe_quilt or id % period != 0: return
    last_probe_quilt = id
    var measured: bool = id > warmup and id <= warmup+measured_frames
    var rd := RenderingServer.get_rendering_device()
    rd.capture_timestamp("LG depth begin "+str(id))
    var before: int = Time.get_ticks_usec()
    if isolate_timer: rd.buffer_copy(blit_source,blit_dest,0,0,4)
    if grid > 0: probe.dispatch()
    var after: int = Time.get_ticks_usec()
    rd.capture_timestamp("LG depth end")
    if isolate_timer: rd.buffer_copy(blit_dest,blit_source,0,0,4)
    probe_dispatches += 1
    if measured:
        measured_dispatches += 1
        submission_times.append(float(after-before)/1000)
    if synchronous_feedback:
        if debug_feedback: print("FEEDBACK begin ",id)
        var read_start: int = Time.get_ticks_usec()
        last_counts = probe.read_counts()
        if debug_feedback: print("FEEDBACK end ",id," us ",Time.get_ticks_usec()-read_start)
        if measured: readback_times.append(float(Time.get_ticks_usec()-read_start)/1000)
        readback_bytes = last_counts.readback_bytes

    elif asynchronous_feedback and not pending_feedback:
        pending_feedback = true
        var issued: int = Time.get_ticks_usec()
        var status: Error = rd.buffer_get_data_async(probe.feedback_buffer(),func(data: PackedByteArray):
            var arrival: int = Time.get_ticks_usec()
            last_counts = probe.decode_counts(data)
            readback_bytes = data.size()
            feedback_callbacks += 1
            if measured:
                feedback_latencies.append(float(arrival-issued)/1000)
                readback_times.append(float(Time.get_ticks_usec()-arrival)/1000)
            pending_feedback = false
        )
        if status != OK:
            configuration_error = "Async buffer retrieval failed: "+str(status)
            pending_feedback = false

func _finish() -> void:
    set_process(false)
    if RenderingServer.frame_post_draw.is_connected(_probe_frame):
        RenderingServer.frame_post_draw.disconnect(_probe_frame)
    # Drain timestamp delivery without submitting additional probes.
    for i in range(4):
        await RenderingServer.frame_post_draw
        if grid > 0 or isolate_timer: RenderingServer.call_on_render_thread(_collect_gpu)
    for i in range(12):
        if not pending_feedback: break
        await RenderingServer.frame_post_draw
    RenderingServer.call_on_render_thread(func():
        if grid > 0 and last_counts.is_empty():
            last_counts = probe.read_counts() # Untimed validation readback.
            readback_bytes = last_counts.readback_bytes
        if grid > 0 and reduce_gpu:
            var compact: Dictionary = probe.read_counts()
            var blocks: Dictionary = probe.read_block_counts()
            reduction_exact = compact.rows == blocks.rows
            if not reduction_exact: configuration_error = "GPU reduction differs from CPU block sums"
        var report: Dictionary = {"gpu_reduction":reduce_gpu,"reduction_exact":reduction_exact,"grid":grid,"period":period,"synchronous_feedback":synchronous_feedback,"dispatches":probe_dispatches,"measured_dispatches":measured_dispatches,"gpu_ms":gpu_times,"submission_ms":submission_times,"feedback_ms":readback_times,"readback_bytes":readback_bytes,"validation_counts":last_counts,"configuration_error":configuration_error,"asynchronous_feedback":asynchronous_feedback,"pending_feedback":pending_feedback,"feedback_callbacks":feedback_callbacks,"feedback_latency_ms":feedback_latencies,"isolated_timer":isolate_timer,"kernel_measured_dispatches":measured_dispatches if grid>0 else 0,"timestamp_status":"Requires isolated-timer validation on MoltenVK"}
        if probe != null and grid > 0: probe.release()
        if blit_source.is_valid(): RenderingServer.get_rendering_device().free_rid(blit_source)
        if blit_dest.is_valid(): RenderingServer.get_rendering_device().free_rid(blit_dest)
        _deliver_report.call_deferred(report)
    )
    var report: Dictionary = await report_ready
    var file := FileAccess.open(benchmark_path+".probe.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    super._finish()

func _deliver_report(report: Dictionary) -> void:
    report_ready.emit(report)
