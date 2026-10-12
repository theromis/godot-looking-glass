extends RefCounted
## Small lit occlusion/transparency fixture shared by the live transport test.
static func add_details(scene: Node3D, environment: Environment, box: MeshInstance3D, material: StandardMaterial3D) -> void:
    environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color=Color(0.55,0.62,0.75)
    environment.ambient_light_energy=0.35
    material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
    material.albedo_color=Color(0.95,0.4,0.08)
    box.scale=Vector3(0.35,0.9,0.35)
    var light:=OmniLight3D.new()
    light.position=Vector3(-1.8,2,2.5)
    light.omni_range=8
    light.light_energy=3
    light.shadow_enabled=true
    scene.add_child(light)
    var colors: Array[Color]=[Color(0.8,0.08,0.05),Color(0.08,0.7,0.12),Color(0.05,0.2,0.85)]
    for i in range(3):
        var sphere:=MeshInstance3D.new()
        var mesh:=SphereMesh.new()
        mesh.radius=0.32
        mesh.height=0.64
        sphere.mesh=mesh
        sphere.position=Vector3((i-1)*0.62,0,(i-1)*0.18)
        var surface:=StandardMaterial3D.new()
        surface.albedo_color=colors[i]
        surface.roughness=0.65
        sphere.material_override=surface
        scene.add_child(sphere)
    var floor_mesh:=MeshInstance3D.new()
    var plane:=PlaneMesh.new()
    plane.size=Vector2(3,2)
    floor_mesh.mesh=plane
    floor_mesh.position.y=-0.5
    var floor_material:=StandardMaterial3D.new()
    floor_material.albedo_color=Color(0.35,0.4,0.48)
    floor_mesh.material_override=floor_material
    scene.add_child(floor_mesh)
    var panel:=MeshInstance3D.new()
    var quad:=QuadMesh.new()
    quad.size=Vector2(0.65,1.1)
    panel.mesh=quad
    panel.position=Vector3(0.65,0,0.4)
    var glass:=StandardMaterial3D.new()
    glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    glass.albedo_color=Color(0.15,0.8,0.95,0.3)
    glass.cull_mode=BaseMaterial3D.CULL_DISABLED
    glass.roughness=0.25
    panel.material_override=glass
    scene.add_child(panel)
