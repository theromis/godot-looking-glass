extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
var rigs: Array = []
func _initialize() -> void:
    run.call_deferred()
func draw_frames(count: int) -> void:
    for i in range(count):
        await process_frame
        RenderingServer.force_draw(false,1.0/60.0)
        RenderingServer.force_sync()
func check(condition: bool, message: String) -> bool:
    if not condition:
        print("FAIL on-demand: ",message)
        quit(1)
    return condition
func compare() -> bool:
    for mode in range(3):
        var a: Image = rigs[mode*2].quilt_texture.get_image()
        var b: Image = rigs[mode*2+1].quilt_texture.get_image()
        if "--save-native-diff" in OS.get_cmdline_user_args() and a != null and b != null and a.get_data()!=b.get_data():
            for item in [["continuous",a],["cached",b]]:
                var file := FileAccess.open("res://benchmarks/native-bridge/on-demand-"+item[0]+".bin",FileAccess.WRITE)
                file.store_buffer(item[1].get_data())
            print("Diagnostic size ",a.get_size()," format ",a.get_format())
        if not check(a != null and b != null and a.get_data()==b.get_data(),"continuous/on-demand pixels mode "+str(mode)):
            return false
    return true
func run() -> void:
    RenderingServer.set_render_loop_enabled(false)
    var scene := Node3D.new()
    root.add_child(scene)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0.07,0.15,0.3)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.2
    scene.add_child(environment)
    var light := OmniLight3D.new()
    light.position = Vector3(0,2,3)
    light.omni_range = 12
    light.shadow_enabled = true
    scene.add_child(light)
    var box := MeshInstance3D.new()
    box.mesh = BoxMesh.new()
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.9,0.3,0.1)
    box.material_override = material
    scene.add_child(box)
    for mode in range(3):
        for demand in [false,true]:
            var rig := Rig.new()
            rig.total_views = 5
            rig.real_views = 2
            rig.tile_size = Vector2i(65,67)
            rig.synthesis = true
            rig.borrow_source_color = mode>0
            rig.borrow_source_depth = mode==2
            rig.update_on_demand = demand
            rig.position.z = 6
            scene.add_child(rig)
            rigs.append(rig)
    await draw_frames(12)
    var settled: bool = "--settled-startup" in OS.get_cmdline_user_args()
    if settled:
        for mode in range(3): rigs[mode*2+1].request_update()
        await draw_frames(12)
    if not compare(): return
    var initial: Array = rigs.map(func(r): return r.synthesizer.dispatch_count)
    var captures: Array = rigs.map(func(r): return r.captures[0].capture_count)
    for mode in range(3):
        if not check(initial[mode*2+1]==(2 if settled else 1),"initial quilt must dispatch once"): return
    await draw_frames(12)
    for mode in range(3):
        var continuous = rigs[mode*2]
        var demand = rigs[mode*2+1]
        if not check(continuous.synthesizer.dispatch_count>initial[mode*2],"continuous path stalled"): return
        if not check(demand.synthesizer.dispatch_count==initial[mode*2+1] and demand.captures[0].capture_count==captures[mode*2+1],"idle still renders or assembles"): return
    var old: PackedByteArray = rigs[1].quilt_texture.get_image().get_data()
    box.position.x = 0.8
    material.albedo_color = Color(0.1,0.8,0.3)
    for mode in range(3):
        # Consecutive requests should coalesce, with fresh depth/color for every source.
        rigs[mode*2+1].request_update()
        rigs[mode*2+1].request_update()
    await draw_frames(12)
    if not compare(): return
    if not check(old!=rigs[1].quilt_texture.get_image().get_data(),"scene update not visible"): return
    for mode in range(3):
        var demand = rigs[mode*2+1]
        if not check(demand.synthesizer.dispatch_count==initial[mode*2+1]+1 and demand.completed_revision==demand.requested_revision,"requests not coalesced"): return
    var before_light: PackedByteArray = rigs[1].quilt_texture.get_image().get_data()
    light.light_color = Color(0.3,0.6,1.0)
    for mode in range(3): rigs[mode*2+1].request_update()
    await draw_frames(12)
    if not compare(): return
    if not check(before_light!=rigs[1].quilt_texture.get_image().get_data(),"light change not visible"): return
    for mode in range(3):
        if not check(rigs[mode*2+1].synthesizer.dispatch_count==initial[mode*2+1]+2,"light refresh missing"): return
    for rig in rigs:
        rig.position.x = -0.3
        rig._process(0)
    await draw_frames(12)
    if not compare(): return
    for mode in range(3):
        if not check(rigs[mode*2+1].synthesizer.dispatch_count==initial[mode*2+1]+3,"camera motion did not refresh"): return
    for rig in rigs:
        for view in rig.views: view.size = Vector2i(81,79)
        rig.request_update()
    await draw_frames(12)
    if not compare(): return
    for mode in range(3):
        var demand = rigs[mode*2+1]
        if not check(demand.synthesizer.dispatch_count==initial[mode*2+1]+4 and demand.captures.all(func(c): return c.dimensions==Vector2i(81,79)),"resized buffers not refreshed"): return
    # Re-enable continuous behavior through a fresh rig, rather than changing mode mid-frame.
    for rig in rigs: rig.queue_free()
    await draw_frames(4)
    print("Startup policy: ","explicit refresh after 12 draws" if settled else "first capture")
    print("PASS on-demand: exact continuous/copy/borrowed quilts; idle zero captures/dispatches; scene/material invalidation; coalesced requests; light change; camera motion; source resize; release")
    quit()
