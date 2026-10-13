extends Node
## Experimental bounded native Metal output. SDK synchronization is not production-qualified.
signal started
signal failed(reason: String)
signal stopped(graceful: bool)
@export_file var worker_path: String="res://addons/looking_glass/native/probe-persistent"
@export_file var extension_path: String="res://addons/looking_glass/native/looking_glass_diagnostic.gdextension"
@export var bridge_library: String=""
## -1 selects the first display currently reported by Bridge.
@export var display_index: int=-1
@export_range(20,600) var duration_seconds: int=60
var submitted_frames: int=0
var received_frames: int=0
var sdk_cleanup_passed: bool=false
var worker_exit_code: int=-1
var worker_status: String=""
var _rig: Node3D
var _publisher: RefCounted
var _process_info: Dictionary={}
var _name: String=""
var _state: String="idle"
var _deadline: int=0
var _revision: int=0
var _publisher_open: bool=false
var _sdk_ready: bool=false
var _ipc_ready: bool=false
var _stdout: String=""
var _stop_sent: bool=false

## Source checkouts retain the external native build directory as a fallback.
func _resolved_worker_path() -> String:
    if worker_path=="res://addons/looking_glass/native/probe-persistent" and not FileAccess.file_exists(worker_path):
        return "res://native/bridge_metal/build/probe-persistent"
    return worker_path

func _resolved_extension_path() -> String:
    if extension_path=="res://addons/looking_glass/native/looking_glass_diagnostic.gdextension" and not FileAccess.file_exists(extension_path):
        return "res://native/bridge_metal/build/looking_glass_diagnostic.gdextension"
    return extension_path

## Explicit setup query; blocks while SDK initializes. Do not call every frame.
## Only allowlisted numeric settings leave the SDK process.
func discover_displays() -> Array[Dictionary]:
    var devices: Array[Dictionary]=[]
    if _state!="idle": return devices
    var runtime: String=bridge_library if not bridge_library.is_empty() else OS.get_environment("BRIDGE_LIBRARY")
    if runtime.is_empty() or not FileAccess.file_exists(runtime) or not FileAccess.file_exists(_resolved_worker_path()): return devices
    var output: Array=[]
    var code: int=OS.execute(ProjectSettings.globalize_path(_resolved_worker_path()),PackedStringArray([runtime,"--list-displays"]),output,false)
    if code!=0: return devices
    for line in str(output[0]).split("\n"):
        if not line.begins_with("LG_DEVICE "): continue
        var fields:=line.strip_edges().split(" ",false)
        if fields.size()!=8: continue
        devices.append({"index":fields[1].to_int(),"width":fields[2].to_int(),"height":fields[3].to_int(),"columns":fields[4].to_int(),"rows":fields[5].to_int(),"aspect":fields[6].to_float(),"view_cone":fields[7].to_float()})
    return devices

## Configure before adding the rig to the scene tree. Optical comfort may
## require a smaller cone than the device's nominal cone.
func configure_rig_for_display(rig: Node3D, device: Dictionary, use_nominal_cone: bool=false) -> bool:
    if rig.is_inside_tree() or device.get("width",0)!=4092 or device.get("height",0)!=4092 or device.get("columns",0)!=11 or device.get("rows",0)!=6: return false
    var aspect: float=device.get("aspect",0.0)
    if not is_finite(aspect) or aspect<=0: return false
    display_index=device.index
    rig.total_views=66
    rig.columns=11
    rig.tile_size=Vector2i(372,682)
    rig.source_view_size=Vector2i(maxi(1,roundi(682*aspect)),682)
    rig.synthesis=true
    rig.quilt_rgba8=true
    rig.update_on_demand=true
    rig.compose_in_capture_callback=true
    if use_nominal_cone: rig.view_cone_degrees=clampf(device.view_cone,1.0,80.0)
    return true

func start_output(rig: Node3D) -> bool:
    if _state!="idle": return false
    if OS.get_name()!="macOS" or RenderingServer.get_current_rendering_driver_name()!="metal":
        failed.emit("Native Metal on macOS is required")
        return false
    if not rig.synthesis or not rig.quilt_rgba8 or not rig.update_on_demand or not rig.compose_in_capture_callback:
        failed.emit("Rig requires RGBA8 compute output, on-demand updates and capture-stage composition")
        return false
    var dimensions: Vector2i=rig.tile_size*Vector2i(rig.columns,ceili(float(rig.total_views)/rig.columns))
    if rig.total_views!=66 or rig.columns!=11 or dimensions not in [Vector2i(4092,4092),Vector2i(704,684)]:
        failed.emit("Worker currently supports only the 66-view 11x6 small/4K presets")
        return false
    var runtime: String=bridge_library if not bridge_library.is_empty() else OS.get_environment("BRIDGE_LIBRARY")
    if runtime.is_empty() or not FileAccess.file_exists(runtime) or not FileAccess.file_exists(_resolved_worker_path()):
        failed.emit("Configure a built worker and external Bridge library")
        return false
    if not ClassDB.class_exists("LookingGlassMetalDiagnostic"):
        GDExtensionManager.load_extension(_resolved_extension_path())
    if not ClassDB.class_exists("LookingGlassMetalDiagnostic"):
        failed.emit("Build the native diagnostic extension first")
        return false
    _publisher=ClassDB.instantiate("LookingGlassMetalDiagnostic")
    _name=_publisher.reserve_surface_name()
    var arguments:=PackedStringArray([runtime,str(display_index),"--experimental-reuse","--live-surface="+_name,"--uncapped","--duration="+str(duration_seconds),"--control-stdin"])
    if dimensions==Vector2i(4092,4092): arguments.append("--large")
    _process_info=OS.execute_with_pipe(ProjectSettings.globalize_path(_resolved_worker_path()),arguments,false)
    if _process_info.is_empty():
        _publisher.cleanup_owned_surface_transport()
        _publisher=null
        failed.emit("Worker launch failed")
        return false
    _rig=rig
    _state="starting"
    _deadline=Time.get_ticks_msec()+10000
    submitted_frames=0
    received_frames=0
    sdk_cleanup_passed=false
    worker_exit_code=-1
    worker_status=""
    _revision=0
    _stdout=""
    _stop_sent=false
    _sdk_ready=false
    _ipc_ready=false
    _publisher_open=false
    return true

func is_output_active() -> bool:
    return _state!="idle"

func stop_output() -> void:
    if _state in ["idle","stopping"]: return
    _state="stopping"
    _deadline=Time.get_ticks_msec()+3000
    _stop_sent=false

func _drain() -> void:
    var stream: FileAccess=_process_info.stdio
    var available: int=mini(stream.get_length(),65536)
    if available>0: _stdout+=stream.get_buffer(available).get_string_from_utf8()
    while "\n" in _stdout:
        var end: int=_stdout.find("\n")
        var line: String=_stdout.substr(0,end).strip_edges()
        _stdout=_stdout.substr(end+1)
        if line=="SURFACE ready": _ipc_ready=true
        if line=="SURFACE sdk_ready": _sdk_ready=true
        if line.begins_with("live_sequence="): received_frames=line.trim_prefix("live_sequence=").to_int()
        if line.begins_with("persistent_updates="): worker_status=line
        if line.begins_with("SURFACE port "): worker_status="IPC endpoint setup failed"
        if "sdk_calls_ok=1 release=1 shutdown=1" in line: sdk_cleanup_passed=true
    # Drain SDK diagnostics without publishing serial/calibration data.
    var errors: FileAccess=_process_info.stderr
    var count: int=mini(errors.get_length(),65536)
    if count>0:
        var diagnostic: String=errors.get_buffer(count).get_string_from_utf8()
        if "DISPLAY unsupported preset" in diagnostic: worker_status="Display quilt preset is not supported by this worker"
        if "DISPLAY unavailable" in diagnostic: worker_status="Display not detected by Bridge"
        if "METAL device unavailable" in diagnostic: worker_status="Metal device unavailable"
        if "SURFACE port" in diagnostic: worker_status="IPC endpoint setup failed"
    if _stdout.length()>8192: _stdout=""

func _process(_delta: float) -> void:
    if _state=="idle": return
    if not is_instance_valid(_rig) and _state!="stopping":
        failed.emit("Output rig was removed")
        stop_output()
    _drain()
    if not OS.is_process_running(_process_info.pid):
        _drain()
        worker_exit_code=OS.get_process_exit_code(_process_info.pid)
        var graceful: bool=sdk_cleanup_passed and received_frames==submitted_frames
        if not graceful: failed.emit("Worker exited: code=%d publisher=%s sdk=%s status=%s"%[worker_exit_code,_publisher_open,_sdk_ready,worker_status])
        _finish(graceful)
        return
    if _state=="stopping" and not _stop_sent and (not _publisher_open or _publisher.surface_ready()):
        _process_info.stdio.store_buffer("q".to_utf8_buffer())
        _stop_sent=true
    if _state in ["starting","stopping"] and Time.get_ticks_msec()>_deadline:
        failed.emit("Worker startup/stop timed out")
        OS.kill(_process_info.pid)
        _finish(false)
        return
    if _state=="starting" and _ipc_ready and _sdk_ready and not _publisher_open:
        var dimensions: Vector2i=_rig.tile_size*Vector2i(11,6)
        _publisher_open=_publisher.open_surface_publisher(_name,dimensions.x,dimensions.y)
        if not _publisher_open:
            failed.emit("GPU source import failed")
            stop_output()
    if _state=="starting" and _publisher_open and _sdk_ready:
        _state="running"
        started.emit()
    if _state!="running": return
    if not is_instance_valid(_rig) or _rig.synthesizer==null:
        failed.emit("Output rig was removed")
        stop_output()
        return
    if _revision>0 and _rig.completed_revision>=_revision and _publisher.surface_ready():
        if not _publisher.publish_surface(submitted_frames+1,_rig.synthesizer.quilt,false):
            failed.emit("GPU publication failed")
            stop_output()
            return
        submitted_frames+=1
        _revision=0
    if _revision==0 and _publisher.surface_ready():
        _rig.request_update()
        _revision=_rig.requested_revision

func _finish(graceful: bool) -> void:
    _process_info.clear()
    _publisher.cleanup_owned_surface_transport()
    _publisher=null
    _rig=null
    _state="idle"
    stopped.emit(graceful)

func _exit_tree() -> void:
    # Prefer explicit stop_output() and await stopped before freeing the node.
    if _state!="idle":
        if OS.is_process_running(_process_info.pid): OS.kill(_process_info.pid)
        _finish(false)
