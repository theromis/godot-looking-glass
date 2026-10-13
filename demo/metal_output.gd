extends Node3D
## Desktop preview remains available independently of Bridge and native builds.
const Rig=preload("res://addons/looking_glass/rig.gd")
const Output=preload("res://addons/looking_glass/metal_output.gd")
var output: Node
var rig: Node3D
var cube: MeshInstance3D
var devices: Array[Dictionary]=[]
var choice: OptionButton
var runtime: LineEdit
var status: Label
var counters: Label
var start_button: Button
var stop_button: Button
var refresh_button: Button
var preview: SubViewport
var quitting: bool=false

func _ready() -> void:
    get_tree().auto_accept_quit=false
    var world:=WorldEnvironment.new()
    world.environment=Environment.new()
    world.environment.background_mode=Environment.BG_COLOR
    world.environment.background_color=Color(0.12,0.2,0.3)
    world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_energy=0.4
    add_child(world)
    var light:=OmniLight3D.new()
    light.position=Vector3(-2,3,3)
    light.omni_range=12
    light.light_energy=3
    add_child(light)
    cube=_mesh(BoxMesh.new(),Color(0.95,0.35,0.05),Vector3.ZERO)
    for i in range(3):
        var sphere:=SphereMesh.new()
        sphere.radius=0.24
        sphere.height=0.48
        _mesh(sphere,[Color.RED,Color.GREEN,Color.BLUE][i],Vector3((i-1)*0.7,0.7,(i-1)*0.1))
    output=Output.new()
    add_child(output)
    output.started.connect(func(): status.text="Streaming to Looking Glass (experimental)")
    output.failed.connect(func(reason: String): status.text=reason)
    output.stopped.connect(_stopped)
    _ui()
    if "--preview-smoke" in OS.get_cmdline_user_args():
        for i in range(8): await get_tree().process_frame
        for argument in OS.get_cmdline_user_args():
            if argument.begins_with("--screenshot="):
                get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--screenshot="))
        assert(preview.get_texture()!=null and not output.is_output_active() and rig==null)
        print("PASS Metal demo hardware-free preview")
        get_tree().quit()
    if "--output-smoke" in OS.get_cmdline_user_args():
        _refresh()
        _start()
        await get_tree().create_timer(6).timeout
        output.stop_output()
        if output.is_output_active(): await output.stopped
        var passed: bool=output.sdk_cleanup_passed and output.submitted_frames>0 and output.submitted_frames==output.received_frames
        print("DEMO submitted=",output.submitted_frames," received=",output.received_frames)
        print("PASS Metal demo output" if passed else "FAIL Metal demo output")
        get_tree().quit(0 if passed else 1)

func _mesh(mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
    var node:=MeshInstance3D.new()
    node.mesh=mesh
    node.position=at
    var material:=StandardMaterial3D.new()
    material.albedo_color=color
    node.material_override=material
    add_child(node)
    return node

func _ui() -> void:
    var layer:=CanvasLayer.new()
    add_child(layer)
    var panel:=VBoxContainer.new()
    panel.position=Vector2(16,16)
    panel.custom_minimum_size=Vector2(1100,0)
    layer.add_child(panel)
    var title:=Label.new()
    title.text="Looking Glass — experimental Metal output / desktop preview"
    panel.add_child(title)
    runtime=LineEdit.new()
    runtime.placeholder_text="External Bridge library path (or set BRIDGE_LIBRARY)"
    runtime.text=OS.get_environment("BRIDGE_LIBRARY")
    panel.add_child(runtime)
    var row:=HBoxContainer.new()
    panel.add_child(row)
    refresh_button=Button.new()
    refresh_button.text="Discover displays"
    refresh_button.pressed.connect(_refresh)
    row.add_child(refresh_button)
    choice=OptionButton.new()
    choice.custom_minimum_size.x=420
    row.add_child(choice)
    start_button=Button.new()
    start_button.text="Start (60 seconds)"
    start_button.disabled=true
    start_button.pressed.connect(_start)
    row.add_child(start_button)
    stop_button=Button.new()
    stop_button.text="Stop"
    stop_button.disabled=true
    stop_button.pressed.connect(func(): status.text="Stopping…"; output.stop_output())
    row.add_child(stop_button)
    status=Label.new()
    status.text="Desktop preview active. Configure Bridge and discover displays to enable output."
    panel.add_child(status)
    counters=Label.new()
    panel.add_child(counters)
    var container:=SubViewportContainer.new()
    container.custom_minimum_size=Vector2(640,480)
    panel.add_child(container)
    preview=SubViewport.new()
    preview.size=Vector2i(640,480)
    preview.world_3d=get_world_3d()
    preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    container.add_child(preview)
    var camera:=Camera3D.new()
    camera.position.z=6
    camera.fov=35
    preview.add_child(camera)
    camera.current=true

func _refresh() -> void:
    if output.is_output_active(): return
    output.bridge_library=runtime.text.strip_edges()
    status.text="Querying Bridge…"
    devices=output.discover_displays()
    choice.clear()
    for device in devices:
        choice.add_item("Display %d — %dx%d / %dx%d"%[device.index,device.width,device.height,device.columns,device.rows])
    start_button.disabled=devices.is_empty()
    status.text="Select a display and start output. Preview remains active." if not devices.is_empty() else "No devices found. Check Bridge, library path and display connection. Preview remains active."

func _start() -> void:
    if output.is_output_active() or choice.selected<0 or devices.is_empty(): return
    rig=Rig.new()
    rig.real_views=24
    rig.position.z=6
    rig.focus_distance=6
    rig.view_cone_degrees=30
    if not output.configure_rig_for_display(rig,devices[choice.selected]):
        rig.free()
        rig=null
        status.text="Unsupported display preset. Preview remains active."
        return
    add_child(rig)
    output.bridge_library=runtime.text.strip_edges()
    status.text="Starting worker…"
    if not output.start_output(rig):
        rig.queue_free()
        rig=null
        return
    start_button.disabled=true
    refresh_button.disabled=true
    choice.disabled=true
    runtime.editable=false
    stop_button.disabled=false

func _stopped(graceful: bool) -> void:
    if is_instance_valid(rig): rig.queue_free()
    rig=null
    start_button.disabled=devices.is_empty()
    refresh_button.disabled=false
    choice.disabled=false
    runtime.editable=true
    stop_button.disabled=true
    if graceful: status.text="Stopped cleanly. Desktop preview remains active."
    if quitting: get_tree().quit()

func _process(delta: float) -> void:
    if is_instance_valid(cube): cube.rotation.y+=delta*0.5
    if is_instance_valid(counters):
        counters.text="Submitted: %d / copied by worker: %d (not panel FPS)"%[output.submitted_frames,output.received_frames]

func _notification(what: int) -> void:
    if what==NOTIFICATION_WM_CLOSE_REQUEST:
        quitting=true
        if output.is_output_active(): output.stop_output()
        else: get_tree().quit()
