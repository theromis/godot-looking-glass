extends Node3D
## Hardware-free controls. Recreate the rig to apply projection/view changes.
const Rig = preload("res://addons/looking_glass/rig.gd")
var rig: Node3D
var subjects: Array[MeshInstance3D] = []
var controls: Dictionary = {}
var sun: DirectionalLight3D
var environment: Environment
var center_camera: Camera3D
var center_view: SubViewport
var focus_marker: MeshInstance3D
var quilt_preview: TextureRect
var status: Label
var apply_button: Button
var lighting: CheckBox
var shadows: CheckBox
var marker_toggle: CheckBox
var busy: bool = false
var floor_node: MeshInstance3D

func _ready() -> void:
    environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.2, 0.4, 0.7)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.45, 0.55, 0.7)
    environment.ambient_light_energy = 0.3
    var world := WorldEnvironment.new()
    world.environment = environment
    add_child(world)
    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-45, -35, 0)
    sun.light_color = Color(1, 0.9, 0.8)
    sun.light_energy = 1.2
    sun.light_angular_distance = 2
    sun.shadow_blur = 1
    add_child(sun)
    var box := _mesh(BoxMesh.new(), Color(0.8, 0.3, 0.1))
    subjects.append(box)
    for i in range(3):
        var sphere := _mesh(SphereMesh.new(), [Color.RED, Color.GREEN, Color.BLUE][i])
        sphere.position = Vector3((i-1)*0.4, 0.55, 0)
        subjects.append(sphere)
    var floor_shape := PlaneMesh.new()
    floor_shape.size = Vector2(5, 5)
    floor_node = _mesh(floor_shape, Color(0.5, 0.52, 0.55))
    floor_node.position.y = -0.6
    focus_marker = MeshInstance3D.new()
    var lines := ImmediateMesh.new()
    lines.surface_begin(Mesh.PRIMITIVE_LINES)
    var corners := [Vector3(-0.8, -0.4, 0), Vector3(0.8, -0.4, 0), Vector3(0.8, 1.1, 0), Vector3(-0.8, 1.1, 0)]
    for i in range(4):
        lines.surface_add_vertex(corners[i])
        lines.surface_add_vertex(corners[(i+1)%4])
    lines.surface_end()
    focus_marker.mesh = lines
    var marker_material := StandardMaterial3D.new()
    marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    marker_material.albedo_color = Color.WHITE
    focus_marker.material_override = marker_material
    focus_marker.layers = 2
    focus_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(focus_marker)
    _build_ui()
    await _apply()
    if "--tuning-smoke" in OS.get_cmdline_user_args():
        await _smoke()

func _mesh(shape: Mesh, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = shape
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.6
    node.material_override = material
    add_child(node)
    return node

func _number(parent: VBoxContainer, title: String, key: String, minimum: float, maximum: float, step: float, value: float) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var text := Label.new()
    text.text = title
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(text)
    var input := SpinBox.new()
    input.min_value = minimum
    input.max_value = maximum
    input.step = step
    input.value = value
    input.custom_minimum_size.x = 100
    row.add_child(input)
    controls[key] = input

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(12, 12)
    panel.size = Vector2(290, 690)
    layer.add_child(panel)
    var stack := VBoxContainer.new()
    panel.add_child(stack)
    var heading := Label.new()
    heading.text = "Looking Glass scene tuning"
    stack.add_child(heading)
    _number(stack, "Focus distance", "focus", 1, 12, 0.1, 5.6)
    _number(stack, "Reference cone (degrees)", "cone", 1, 80, 1, 54)
    _number(stack, "Subject depth factor", "depth", 0.1, 1, 0.05, 0.35)
    _number(stack, "Real views / 48", "real", 2, 48, 1, 48)
    _number(stack, "Source height (pixels)", "height", 128, 672, 16, 336)
    _number(stack, "Right sphere focus offset", "offset", -1, 1, 0.05, -0.1)
    lighting = CheckBox.new()
    lighting.text = "Per-pixel shading: ON"
    lighting.button_pressed = true
    lighting.toggled.connect(func(value: bool): lighting.text = "Per-pixel shading: ON" if value else "Per-pixel shading: OFF")
    stack.add_child(lighting)
    shadows = CheckBox.new()
    shadows.text = "Shadow maps: ON"
    shadows.button_pressed = true
    shadows.toggled.connect(func(value: bool): shadows.text = "Shadow maps: ON" if value else "Shadow maps: OFF")
    stack.add_child(shadows)
    marker_toggle = CheckBox.new()
    marker_toggle.text = "Focus plane outline: ON"
    marker_toggle.button_pressed = true
    marker_toggle.toggled.connect(func(value: bool):
        focus_marker.visible = value
        marker_toggle.text = "Focus plane outline: ON" if value else "Focus plane outline: OFF"
    )
    stack.add_child(marker_toggle)
    apply_button = Button.new()
    apply_button.text = "Apply settings"
    apply_button.pressed.connect(_apply)
    stack.add_child(apply_button)
    var note := Label.new()
    note.text = "Hardware-free preview.\nDepth factor changes demo geometry.\nEye span reference stays at distance 6.\nPlane outline is excluded from the quilt.\nFull-resolution physical checks are separate."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(note)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(status)
    center_view = SubViewport.new()
    center_view.size = Vector2i(378, 672)
    center_view.world_3d = get_world_3d()
    center_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(center_view)
    center_camera = Camera3D.new()
    center_camera.position = Vector3(0, 0, 6)
    center_camera.cull_mask = 3
    center_camera.current = true
    center_camera.fov = 35
    center_view.add_child(center_camera)
    var center_preview := TextureRect.new()
    var center_title := Label.new()
    center_title.text = "Center view / focus plane outline"
    center_title.position = Vector2(314, 12)
    layer.add_child(center_title)
    center_preview.position = Vector2(314, 40)
    center_preview.size = Vector2(300, 650)
    center_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    center_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    center_preview.texture = center_view.get_texture()
    layer.add_child(center_preview)
    quilt_preview = TextureRect.new()
    var quilt_title := Label.new()
    quilt_title.text = "GPU quilt preview"
    quilt_title.position = Vector2(630, 12)
    layer.add_child(quilt_title)
    quilt_preview.position = Vector2(630, 40)
    quilt_preview.size = Vector2(505, 650)
    quilt_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    quilt_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    layer.add_child(quilt_preview)

func _apply() -> void:
    if busy:
        return
    busy = true
    apply_button.disabled = true
    quilt_preview.texture = null
    if is_instance_valid(rig):
        rig.queue_free()
        # Let the old rig disconnect and release queued render resources.
        await get_tree().process_frame
        await get_tree().process_frame
    var focus: float = controls.focus.value
    var plane_z: float = 6.0-focus
    var depth: float = controls.depth.value
    subjects[0].position.z = plane_z+(0.0-plane_z)*depth
    subjects[0].scale = Vector3(0.55, 0.55, depth)
    for i in range(3):
        subjects[i+1].position.z = plane_z+((1-i)*0.8-plane_z)*depth
        subjects[i+1].scale = Vector3(0.4, 0.4, depth)
    subjects[3].position.z = plane_z+controls.offset.value
    for node in subjects:
        node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lighting.button_pressed else BaseMaterial3D.SHADING_MODE_UNSHADED
    floor_node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lighting.button_pressed else BaseMaterial3D.SHADING_MODE_UNSHADED
    sun.shadow_enabled = shadows.button_pressed and lighting.button_pressed
    focus_marker.position.z = plane_z
    focus_marker.visible = marker_toggle.button_pressed
    rig = Rig.new()
    rig.position.z = 6
    rig.total_views = 48
    rig.real_views = int(controls.real.value)
    rig.columns = 8
    var height: int = int(controls.height.value)
    rig.tile_size = Vector2i(roundi(height*0.5625), height)
    rig.focus_distance = focus
    rig.camera_span_reference_distance = 6
    rig.view_cone_degrees = controls.cone.value
    rig.angular_view_sampling = true
    rig.synthesis = rig.real_views < rig.total_views
    add_child(rig)
    for camera in rig.cameras:
        camera.cull_mask = 1
    quilt_preview.texture = rig.quilt_texture
    status.text = "%d real / 48 output views\nQuilt %s\nFocus plane world Z: %.2f\nApply to refresh changed values." % [rig.real_views, str(rig.tile_size*Vector2i(8, 6)), plane_z]
    apply_button.disabled = false
    busy = false

func _smoke() -> void:
    for i in range(12):
        await get_tree().process_frame
    controls.real.value = 12
    controls.focus.value = 5.2
    await _apply()
    for i in range(30):
        await get_tree().process_frame
    if rig.real_views != 12 or rig.cameras.size() != 12 or not is_equal_approx(focus_marker.position.z, 0.8) or rig.cameras[0].cull_mask != 1 or center_camera.cull_mask != 3 or quilt_preview.texture == null:
        printerr("FAIL tuning smoke: rebuilt controls or preview state")
        get_tree().quit(1)
        return
    if rig.synthesis and rig.synthesizer.dispatch_count < 1:
        printerr("FAIL tuning smoke: no compute quilt dispatch")
        get_tree().quit(1)
        return
    print("PASS tuning smoke: rig rebuild, focus marker isolation, preview and compute dispatch")
    if "--tuning-capture" in OS.get_cmdline_user_args():
        await RenderingServer.frame_post_draw
        var image: Image = get_viewport().get_texture().get_image()
        if image.save_png("res://benchmarks/tuning-preview.png") != OK:
            get_tree().quit(1)
            return
    get_tree().quit()
