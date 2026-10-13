extends Node
## Optional output follows the current gameplay/menu camera without replacing it.
const Rig=preload("res://addons/looking_glass/rig.gd")
const DirectOutput=preload("res://addons/looking_glass/direct_metal_output.gd")
const Output=preload("res://addons/looking_glass/metal_output.gd")
var output_mode: String="direct"
var output: Node
var rig: Node3D
var source_camera: Camera3D
var status: Label
var closing: bool=false
var error_seen: bool=false
var last_cleanup: bool=false
var last_submitted: int=0
var last_received: int=0
const PROFILES={
    "original":{"views":24,"size":Vector2i(384,682),"iterations":8,"atlas":2048,"effects":true,"auto_requests":true},
    "quality":{"views":24,"size":Vector2i(384,682),"iterations":8,"atlas":2048,"effects":true,"auto_requests":false},
    "balanced":{"views":12,"size":Vector2i(256,455),"iterations":4,"atlas":512,"effects":false,"auto_requests":false},
    "fast":{"views":8,"size":Vector2i(192,341),"iterations":4,"atlas":0,"effects":false,"auto_requests":false},
}
var profile_name: String="fast"
var async_gpu_copy: bool=false
var overlap_capture: bool=true
var render_desktop_3d: bool=false
var _saved_desktop_disable_3d: bool=false
var _desktop_overridden: bool=false
var max_capture_hz: float=0.0
var real_views: int=8
var cone_degrees: float=10.0
var focus_distance: float=2.4
func _ready() -> void:
    process_priority=100
    get_tree().auto_accept_quit=false
    output=DirectOutput.new() if output_mode=="direct" else Output.new()
    output.process_priority=300
    output.duration_seconds=60
    add_child(output)
    output.started.connect(func(): status.text="Looking Glass active (%s) — F4 Stop / Shift+F4 profile"%profile_name)
    output.failed.connect(func(reason: String): error_seen=true; status.text="Looking Glass: "+reason)
    output.stopped.connect(_stopped)
    var layer:=CanvasLayer.new()
    layer.layer=20
    add_child(layer)
    status=Label.new()
    status.position=Vector2(12,70)
    status.text="Looking Glass: %s — F4 Start / Stop, Shift+F4 profile"%profile_name
    status.mouse_filter=Control.MOUSE_FILTER_IGNORE
    layer.add_child(status)

func start_output() -> bool:
    if output.is_output_active() or closing: return false
    if (output_mode=="direct")!=(output.get_script()==DirectOutput):
        output.free()
        output=DirectOutput.new() if output_mode=="direct" else Output.new()
        output.process_priority=300
        output.duration_seconds=60
        add_child(output)
        output.started.connect(func(): status.text="Looking Glass active (%s/%s)"%[output_mode,profile_name])
        output.failed.connect(func(reason: String): error_seen=true; status.text="Looking Glass: "+reason)
        output.stopped.connect(_stopped)
    source_camera=get_viewport().get_camera_3d()
    if source_camera==null: status.text="Looking Glass: no active camera"; return false
    output.overlap_capture=overlap_capture
    output.async_gpu_copy=async_gpu_copy
    output.max_capture_hz=max_capture_hz
    output.bridge_library=OS.get_environment("BRIDGE_LIBRARY")
    var devices: Array[Dictionary]=output.discover_displays()
    if devices.is_empty(): status.text="Looking Glass: set BRIDGE_LIBRARY and check device connection"; return false
    rig=Rig.new()
    var profile: Dictionary=PROFILES[profile_name]
    real_views=profile.views
    rig.real_views=real_views
    rig.focus_distance=focus_distance
    rig.view_cone_degrees=cone_degrees
    rig.near_clip=source_camera.near
    rig.far_clip=source_camera.far
    rig.vertical_fov=source_camera.fov
    if source_camera.keep_aspect==Camera3D.KEEP_WIDTH:
        var dimensions:=get_viewport().get_visible_rect().size
        rig.vertical_fov=rad_to_deg(2*atan(tan(deg_to_rad(source_camera.fov)*0.5)*dimensions.y/dimensions.x))
    if not output.configure_rig_for_display(rig,devices[0]):
        rig.free(); rig=null
        status.text="Looking Glass: unsupported device preset"
        return false
    rig.source_view_size=profile.size
    rig.reprojection_iterations=profile.iterations
    rig.auto_update_on_transform=profile.auto_requests
    rig.transform=source_camera.global_transform
    rig.process_priority=200
    add_child(rig)
    for view in rig.views:
        view.positional_shadow_atlas_size=profile.atlas
    var view_environment: Environment=source_camera.environment
    if view_environment==null: view_environment=source_camera.get_world_3d().environment
    if view_environment!=null and not profile.effects:
        view_environment=view_environment.duplicate()
        view_environment.ssao_enabled=false
        view_environment.ssil_enabled=false
        view_environment.ssr_enabled=false
        view_environment.volumetric_fog_enabled=false
        view_environment.glow_enabled=false
        view_environment.sdfgi_enabled=false
    for camera in rig.cameras:
        camera.cull_mask=source_camera.cull_mask
        camera.attributes=source_camera.attributes
        camera.environment=view_environment
    error_seen=false
    last_cleanup=false
    status.text="Looking Glass starting…"
    if not output.start_output(rig):
        rig.queue_free(); rig=null
        return false
    if not render_desktop_3d:
        _saved_desktop_disable_3d=get_viewport().disable_3d
        _desktop_overridden=true
        get_viewport().disable_3d=true
    # Benchmark-only legacy mode intentionally bypasses scheduler ownership.
    if profile_name=="original" and output_mode=="worker": rig.auto_update_on_transform=true
    return true

func stop_output() -> void:
    output.stop_output()

func _stopped(graceful: bool) -> void:
    if _desktop_overridden:
        get_viewport().disable_3d=_saved_desktop_disable_3d
        _desktop_overridden=false
    last_cleanup=graceful and output.sdk_cleanup_passed
    last_submitted=output.submitted_frames
    last_received=output.received_frames
    if is_instance_valid(rig): rig.queue_free()
    rig=null
    source_camera=null
    if graceful: status.text="Looking Glass stopped (%s) — F4 Start / Shift+F4 profile"%profile_name
    if closing: get_tree().quit(0 if graceful else 1)

func _process(_delta: float) -> void:
    if not is_instance_valid(rig) or not output.is_output_active(): return
    if not is_instance_valid(source_camera) or get_viewport().get_camera_3d()!=source_camera:
        status.text="Looking Glass: camera changed, stopping; F4 to restart"
        stop_output()
        return
    rig.global_transform=source_camera.global_transform

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F4:
        if event.shift_pressed:
            var names: Array[String]=["fast","balanced","quality"]
            profile_name=names[(names.find(profile_name)+1)%names.size()]
            if output.is_output_active(): stop_output()
            else: status.text="Looking Glass: %s selected — F4 Start"%profile_name
        elif output.is_output_active(): stop_output()
        else: start_output()
        get_viewport().set_input_as_handled()

func shutdown_and_quit() -> void:
    closing=true
    if output.is_output_active(): stop_output()
    else: get_tree().quit()

func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_CLOSE_REQUEST: shutdown_and_quit()
