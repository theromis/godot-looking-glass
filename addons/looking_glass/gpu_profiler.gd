extends RefCounted
## Diagnostic only: adjacent engine timestamps, not a vendor GPU counter profiler.
var mutex := Mutex.new()
var last_frame: int = -1
var frame_count: int = 0
var interval_totals: Dictionary = {}
var viewport_totals: Dictionary = {}
var span_total_ms: float = 0.0
var example: Array = []
var viewport_roles: Dictionary = {}

func configure(rig: Node3D, main_viewport: Viewport) -> void:
    for view in rig.views:
        viewport_roles[str(view.get_viewport_rid().get_id())] = "anchors"
    viewport_roles[str(rig.quilt_viewport.get_viewport_rid().get_id())] = "quilt"
    viewport_roles[str(main_viewport.get_viewport_rid().get_id())] = "main"
    RenderingServer.viewport_set_measure_render_time(rig.quilt_viewport.get_viewport_rid(), true)
    RenderingServer.viewport_set_measure_render_time(main_viewport.get_viewport_rid(), true)

func collect() -> void:
    var rd := RenderingServer.get_rendering_device()
    if rd == null:
        return
    var frame: int = rd.get_captured_timestamps_frame()
    if frame == last_frame:
        return
    last_frame = frame
    var count: int = rd.get_captured_timestamps_count()
    if count < 2:
        return
    var markers: Array = []
    for i in range(count):
        markers.append({"name": rd.get_captured_timestamp_name(i), "gpu_ns": rd.get_captured_timestamp_gpu_time(i), "cpu_us": rd.get_captured_timestamp_cpu_time(i)})
    var intervals: Dictionary = {}
    var viewports: Dictionary = {}
    var role: String = "outside_viewports"
    var starts: Dictionary = {}
    for i in range(count - 1):
        var name: String = markers[i].name
        if name.begins_with("vp_begin_"):
            var id := name.trim_prefix("vp_begin_")
            role = viewport_roles.get(id, "other_viewport")
            starts[id] = markers[i].gpu_ns
        elif name.begins_with("vp_end_"):
            var id := name.trim_prefix("vp_end_")
            if starts.has(id):
                var view_role: String = viewport_roles.get(id, "other_viewport")
                viewports[view_role] = viewports.get(view_role, 0.0) + float(markers[i].gpu_ns - starts[id]) / 1000000.0
            role = "outside_viewports"
        var duration: float = float(markers[i + 1].gpu_ns - markers[i].gpu_ns) / 1000000.0
        if duration < 0:
            continue
        var label: String = "viewport_begin" if name.begins_with("vp_begin_") else ("viewport_end" if name.begins_with("vp_end_") else name)
        var key := role + " / " + label
        intervals[key] = intervals.get(key, 0.0) + duration
    mutex.lock()
    frame_count += 1
    span_total_ms += float(markers[-1].gpu_ns - markers[0].gpu_ns) / 1000000.0
    for key in intervals:
        interval_totals[key] = interval_totals.get(key, 0.0) + intervals[key]
    for key in viewports:
        viewport_totals[key] = viewport_totals.get(key, 0.0) + viewports[key]
    if example.is_empty():
        example = markers
    mutex.unlock()

func report() -> Dictionary:
    mutex.lock()
    var means: Dictionary = {}
    var viewport_means: Dictionary = {}
    for key in interval_totals:
        means[key] = interval_totals[key] / maxi(frame_count, 1)
    for key in viewport_totals:
        viewport_means[key] = viewport_totals[key] / maxi(frame_count, 1)
    var result := {"frames": frame_count, "marker_span_mean_ms": span_total_ms / maxi(frame_count, 1), "adjacent_intervals_mean_ms": means, "viewport_spans_mean_ms": viewport_means, "example_markers": example.duplicate(true), "interpretation": "Intervals between adjacent engine GPU markers, aggregated by viewport role; may include barriers, transitions and idle time. Profile changes workload. Not hardware counters or proof of shader bottleneck."}
    mutex.unlock()
    return result
