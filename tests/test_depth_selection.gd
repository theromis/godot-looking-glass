extends "res://tests/test_depth_proxy.gd"
## Offline experiment: candidate depth costs never sample source color.
var selections_path: String = ""
func _initialize() -> void:
    run.call_deferred()
func make_rig(scene: Node3D, anchors: Array) -> Node3D:
    var rig := Rig.new()
    rig.total_views=48
    rig.real_views=anchors.size()
    rig.custom_anchor_indices=PackedInt32Array(anchors)
    rig.synthesis=true
    rig.borrow_source_depth=true
    rig.borrow_source_color=true
    rig.tile_size=Vector2i(256,256)
    rig.position.z=6
    scene.add_child(rig)
    return rig
func save_quilt(rig: Node3D, path: String) -> bool:
    var image: Image=rig.quilt_texture.get_image()
    if image==null or image.is_empty() or image.get_pixel(0,0).b<0.01:
        print("FAIL empty selection quilt")
        return false
    image.convert(Image.FORMAT_RGBA8)
    return image.save_png(path)==OK
func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="):
            output=arg.trim_prefix("--output=")
        if arg.begins_with("--selections="):
            selections_path=arg.trim_prefix("--selections=")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    var selections: Dictionary={}
    if selections_path!="":
        var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(selections_path))
        if not parsed is Dictionary:
            print("FAIL selection JSON")
            quit(1)
            return
        selections=parsed.cases
    RenderingServer.set_render_loop_enabled(false)
    var reports: Array[Dictionary]=[]
    for scene_name in ["smooth","bars","layers"]:
        var scene := build_fixture(scene_name)
        for snapshot in range(3):
            var name: String=scene_name+"-"+str(snapshot)
            var layouts: Dictionary={}
            if selections_path=="":
                for gap in [2,3]:
                    for phase in range(gap):
                        var anchors: Array=[0,47]
                        for index in range(phase,48,gap):
                            if not anchors.has(index): anchors.append(index)
                        anchors.sort()
                        layouts["gap%d-phase%d" % [gap,phase]]=anchors
            else:
                for method in ["both_invalid","source_horizontal_depth_edge","oracle"]:
                    layouts[method]=selections[name][method].anchors.map(func(value): return int(value))
            var uniform: Array=[]
            for index in range(24): uniform.append(roundi(float(index)*47/23))
            layouts["uniform"]=uniform
            layouts["reference"]=range(48)
            var rigs: Dictionary={}
            for label in layouts:
                var anchors: Array=layouts[label]
                if anchors[0]!=0 or anchors[-1]!=47:
                    print("FAIL incomplete endpoint selection")
                    quit(1)
                    return
                for i in range(1,anchors.size()):
                    if anchors[i]<=anchors[i-1]:
                        print("FAIL invalid sorted selection")
                        quit(1)
                        return
                if selections_path!="" and label!="reference" and anchors.size()!=24:
                    print("FAIL camera budget")
                    quit(1)
                    return
                rigs[label]=make_rig(scene,anchors)
            var x: float=float(snapshot-1)*0.35
            var yaw: float=float(snapshot-1)*0.035
            for frame in range(18):
                var progress: float=minf(1.0,float(frame+1)/16)
                for rig in rigs.values():
                    rig.position=Vector3(x-0.25*(1-progress),0,6)
                    rig.rotation.y=yaw-0.025*(1-progress)
                    rig._process(0)
                await process_frame
                RenderingServer.force_draw(false,1.0/60.0)
                RenderingServer.force_sync()
            var entries: Array[Dictionary]=[]
            for label in rigs:
                var rig=rigs[label]
                if rig.synthesizer.dispatch_count<8 or rig.anchor_indices!=layouts[label]:
                    print("FAIL actual synthesis/configuration ",label," dispatches ",rig.synthesizer.dispatch_count," actual ",rig.anchor_indices," expected ",layouts[label])
                    quit(1)
                    return
                for capture in rig.captures:
                    if not capture.borrow_depth or not capture.depth.is_valid():
                        print("FAIL missing raw depth")
                        quit(1)
                        return
                if not save_quilt(rig,output+"/"+name+"-"+label+".png"):
                    print("FAIL capture save")
                    quit(1)
                    return
                var entry: Dictionary={"label":label,"anchors":rig.anchor_indices,"dispatches":rig.synthesizer.dispatch_count}
                if selections_path=="" and label.begins_with("gap"):
                    RenderingServer.call_on_render_thread(func():
                        _probe_result.call_deferred(Probe.new().measure(rig,null,256))
                    )
                    var result: Dictionary=await probe_complete
                    if result.has("error") or result.rows.size()!=48 or result.readback_bytes!=786432:
                        print("FAIL incomplete depth cost probe")
                        quit(1)
                        return
                    for row in result.rows:
                        for count in row.counts:
                            if count<0 or count>65536 or (row.real and count!=0):
                                print("FAIL depth cost counters")
                                quit(1)
                                return
                    entry["probe"]=result
                entries.append(entry)
            reports.append({"name":name,"scene":scene_name,"snapshot":snapshot,"camera_x":x,"camera_yaw_radians":yaw,"layouts":entries})
            print("SELECTION ",name)
            for rig in rigs.values(): rig.queue_free()
            for frame in range(4):
                await process_frame
                RenderingServer.force_sync()
        scene.queue_free()
        await process_frame
    var file:=FileAccess.open(output+"/raw.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"godot":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"tile":256,"stage":"costs" if selections_path=="" else "validation","cases":reports,"motion":"16 moving-camera draws, two settling draws at each sampled pose; no temporal/flicker evaluation."},"  "))
    RenderingServer.set_render_loop_enabled(true)
    print("PASS depth selection: nine poses with rendered quilts; ","costs" if selections_path=="" else "validation")
    quit()
