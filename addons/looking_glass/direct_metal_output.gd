extends "metal_output.gd"
## Experimental in-process persistent SDK target. Consumer completion is unknown.
## Discovery still uses the one-shot helper; no streaming worker is launched.
var _display_aspect: float=0.0
func configure_rig_for_display(rig: Node3D, device: Dictionary, use_nominal_cone: bool=false) -> bool:
    var ok: bool=super.configure_rig_for_display(rig,device,use_nominal_cone)
    if ok: _display_aspect=device.aspect
    return ok

var _previous_quilt: RID
var _previous_owns_quilt: bool
var _imported: bool=false
var _started_usec: int=0
var _direct_cleanup_pending: bool=false

func start_output(rig: Node3D) -> bool:
    if _state!="idle": return false
    if OS.get_name()!="macOS" or RenderingServer.get_current_rendering_driver_name()!="metal":
        failed.emit("Native Metal on macOS required")
        return false
    if not rig.synthesis or not rig.quilt_rgba8 or not rig.update_on_demand or not rig.compose_in_capture_callback or rig.synthesizer==null:
        failed.emit("RGBA8 on-demand capture-stage synthesis required")
        return false
    if rig.external_quilt_target.is_valid():
        failed.emit("Rig already has an external target")
        return false
    var runtime: String=bridge_library if not bridge_library.is_empty() else OS.get_environment("BRIDGE_LIBRARY")
    if runtime.is_empty() or display_index<0:
        failed.emit("External Bridge runtime and detected display index required")
        return false
    if not ClassDB.class_exists("LookingGlassMetalDiagnostic"):
        GDExtensionManager.load_extension(_resolved_extension_path())
    if not ClassDB.class_exists("LookingGlassMetalDiagnostic"):
        failed.emit("Build the diagnostic extension")
        return false
    _publisher=ClassDB.instantiate("LookingGlassMetalDiagnostic")
    if not _publisher.has_method("update_direct_target_experimental"):
        _publisher=null
        failed.emit("Rebuild extension for direct output")
        return false
    var opened: Dictionary=_publisher.begin_sequence(runtime,display_index,rig.columns,ceili(float(rig.total_views)/rig.columns),(_display_aspect if _display_aspect>0 else float(rig.get_source_view_size().x)/rig.get_source_view_size().y))
    if not opened.get("ok",false):
        failed.emit(str(opened.get("error","SDK open failed")))
        _publisher=null
        return false
    var dimensions: Vector2i=rig.tile_size*Vector2i(rig.columns,ceili(float(rig.total_views)/rig.columns))
    var prepared: Dictionary=_publisher.prepare_direct_target(dimensions.x,dimensions.y)
    if not prepared.get("ok",false):
        _publisher.close_sequence()
        failed.emit(str(prepared.get("error","Target allocation failed")))
        _publisher=null
        return false
    _rig=rig
    _saved_auto_update_on_transform=rig.auto_update_on_transform
    rig.auto_update_on_transform=false
    submitted_frames=0
    received_frames=0 # Direct draw success count; not a worker ACK or panel fence.
    sdk_cleanup_passed=false
    copy_call_usec=0
    copy_poll_usec=0
    copy_latency_usec=0
    copy_completions=0
    submission_intervals_usec.clear()
    _last_submission_usec=0
    _revision=0
    _next_capture_usec=0
    _direct_cleanup_pending=false
    _state="starting"
    RenderingServer.call_on_render_thread(_attach_target)
    return true

func _attach_target() -> void:
    var target: RID=_publisher.import_direct_target()
    var valid: bool=target.is_valid() and is_instance_valid(_rig) and not _rig.synthesizer.released
    if valid:
        var synth: RefCounted=_rig.synthesizer
        _previous_quilt=synth.quilt
        _previous_owns_quilt=synth.owns_quilt
        synth.quilt=target
        synth.owns_quilt=false
        synth.bound_sources.clear()
        synth.uniform_sets.clear()
        synth.output.texture_rd_rid=target
        _imported=true
    _target_attached.call_deferred(valid)

func _target_attached(valid: bool) -> void:
    if not valid:
        failed.emit("Direct texture import failed")
        stop_output()
        return
    if _state=="stopping": return
    _state="running"
    _started_usec=Time.get_ticks_usec()
    # Discard startup capture revision and require a new imported-target capture.
    _rig.request_update()
    _revision=_rig.requested_revision
    started.emit()

func _process(_delta: float) -> void:
    if _state=="idle" or _direct_cleanup_pending: return
    if _state=="stopping":
        # Let the last requested capture finish before disconnecting its target.
        if is_instance_valid(_rig) and _revision>0 and _rig.completed_revision<_revision: return
        _direct_cleanup_pending=true
        RenderingServer.call_on_render_thread(_detach_target)
        return
    if _state!="running": return
    if not is_instance_valid(_rig) or _rig.synthesizer.released:
        failed.emit("Direct output rig removed")
        stop_output()
        return
    if Time.get_ticks_usec()-_started_usec>=duration_seconds*1000000:
        stop_output()
        return
    if _revision>0 and _rig.completed_revision>=_revision:
        var started_call: int=Time.get_ticks_usec()
        var report: Dictionary=_publisher.update_direct_target_experimental()
        var elapsed: int=Time.get_ticks_usec()-started_call
        copy_call_usec+=elapsed # API wall time, no copy is performed.
        copy_latency_usec+=elapsed
        copy_completions+=1
        if not report.get("ok",false):
            failed.emit(str(report.get("error","Direct draw failed")))
            stop_output()
            return
        _record_submission()
        received_frames=submitted_frames
        _revision=0
    if _revision==0 and Time.get_ticks_usec()>=_next_capture_usec:
        _rig.request_update()
        _revision=_rig.requested_revision
        var rate: float=clampf(max_capture_hz,0,60) if is_finite(max_capture_hz) else 0
        _next_capture_usec=Time.get_ticks_usec()+ceili(1000000/rate) if rate>0 else 0

func stop_output() -> void:
    if _state!="idle": _state="stopping"

func _detach_target() -> void:
    if _imported and is_instance_valid(_rig) and not _rig.synthesizer.released:
        var synth: RefCounted=_rig.synthesizer
        synth.quilt=_previous_quilt
        synth.owns_quilt=_previous_owns_quilt
        synth.bound_sources.clear()
        synth.uniform_sets.clear()
        synth.output.texture_rd_rid=_previous_quilt
    elif _imported and _previous_owns_quilt and _previous_quilt.is_valid():
        RenderingServer.get_rendering_device().free_rid(_previous_quilt)
    _publisher.release_direct_import()
    _imported=false
    _previous_quilt=RID()
    _target_detached.call_deferred()

func _target_detached() -> void:
    var producer_done: bool=_publisher.wait_for_native_producer()
    var report: Dictionary=_publisher.close_sequence()
    sdk_cleanup_passed=producer_done and report.get("ok",false)
    if not sdk_cleanup_passed: failed.emit(str(report.get("error","Direct cleanup failed")))
    if is_instance_valid(_rig): _rig.auto_update_on_transform=_saved_auto_update_on_transform
    _rig=null
    _publisher=null
    _state="idle"
    _direct_cleanup_pending=false
    stopped.emit(sdk_cleanup_passed)

func _exit_tree() -> void:
    # Shared inherited worker cleanup is inappropriate for an imported SDK target.
    # Applications must await stopped before removing this experimental component.
    if _state!="idle":
        push_error("Stop direct output and await stopped before removing it")
