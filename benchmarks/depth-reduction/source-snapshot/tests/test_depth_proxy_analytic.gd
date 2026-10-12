extends SceneTree
const Rig = preload("res://addons/looking_glass/rig.gd")
const Synth = preload("res://addons/looking_glass/synthesizer.gd")
const Probe = preload("res://tests/depth_probe.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var rd := RenderingServer.create_local_rendering_device()
    if rd == null:
        print("FAIL local RD required")
        quit(1)
        return
    var values := PackedFloat32Array()
    values.resize(64*64)
    values.fill((0.1*40.0/3.0-0.1)/(40.0-0.1))
    var format := RDTextureFormat.new()
    format.width=64
    format.height=64
    format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
    format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    var depth: RID=rd.texture_create(format,RDTextureView.new(),[values.to_byte_array()])
    var rig := Rig.new()
    rig.total_views=4
    rig.anchor_indices=[0]
    rig.synthesizer=Synth.new()
    rig.captures=[{"depth":depth}]
    for i in range(4):
        rig.synthesizer.source_a.append(0)
        rig.synthesizer.source_b.append(0)
        var a: float=-0.25 if i in [2,3] else 0.0
        var b: float=0.25 if i==2 else (-0.5 if i==3 else 0.0)
        rig.synthesizer.push_constants.append(PackedFloat32Array([0,a,b,6,32,32,0,0,1,1 if i==0 else 0,0,0,0.1,40,0,0]).to_byte_array())
    var probe := Probe.new()
    if not probe.measure(rig,rd,7).has("error"):
        print("FAIL invalid sample grid accepted")
        quit(1)
        return
    var result: Dictionary=probe.measure(rig,rd)
    # Uniform z=3: exact UV shifts ±1/24 and +1/12. On 64 samples,
    # ±1/24 excludes three edge columns; +1/12 excludes five columns.
    var expected: Array=[[0,0,0,0],[0,0,0,0],[0,384,0,0],[192,128,0,0]]
    for i in range(4):
        if result.rows[i].counts != expected[i]:
            print("FAIL analytical probe row ",i," expected ",expected[i]," got ",result.rows[i].counts)
            quit(1)
            return
    # Same persistent resources, then changed texture RID and changed grid.
    if not probe.configure(rig,rd,64).is_empty():
        print("FAIL persistent configure")
        quit(1)
        return
    for repeat in range(2):
        probe.dispatch()
        rd.submit()
        rd.sync()
        var reused: Dictionary=probe.read_counts()
        for i in range(4):
            if reused.rows[i].counts!=expected[i]:
                print("FAIL persistent counters")
                quit(1)
                return
    values.fill((0.1*40.0/6.0-0.1)/(40.0-0.1))
    var replacement: RID=rd.texture_create(format,RDTextureView.new(),[values.to_byte_array()])
    rig.captures[0].depth=replacement
    probe.dispatch()
    rd.submit()
    rd.sync()
    var focus_plane: Dictionary=probe.read_counts()
    for row in focus_plane.rows:
        if row.counts!=[0,0,0,0]:
            print("FAIL depth RID rebinding")
            quit(1)
            return
    rig.captures[0].depth=depth
    if not probe.configure(rig,rd,128).is_empty():
        print("FAIL grid reconfigure")
        quit(1)
        return
    probe.dispatch()
    rd.submit()
    rd.sync()
    var resized: Dictionary=probe.read_counts()
    var expected128: Array=[[0,0,0,0],[0,0,0,0],[0,1280,0,0],[640,768,0,0]]
    for i in range(4):
        if resized.rows[i].counts!=expected128[i]:
            print("FAIL grid128 analytical counters ",resized.rows[i].counts)
            quit(1)
            return
    for grid in [64,128,256]:
        var error: Dictionary = probe.configure(rig,rd,grid,true)
        if not error.is_empty():
            print("FAIL GPU reduction configure ",error)
            quit(1)
            return
        for repeat in range(2):
            probe.dispatch()
            rd.submit()
            rd.sync()
            var compact: Dictionary = probe.read_counts()
            var blocks: Dictionary = probe.read_block_counts()
            if compact.rows != blocks.rows or compact.readback_bytes != 64:
                print("FAIL GPU reduction grid ",grid)
                quit(1)
                return
    probe.release()
    probe.release()
    rig.free()
    rd.free_rid(depth)
    rd.free_rid(replacement)
    rd.free()
    print("PASS depth proxy analytic: real/zero/opposite/same-direction plane shifts; exact counters, persistent reuse, depth RID rebinding, grid resize, idempotent release; exact GPU reduction at 64/128/256")
    quit()
