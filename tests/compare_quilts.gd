extends SceneTree
func _initialize() -> void:
    var real := Image.load_from_file("res://benchmarks/real48.png")
    var synth := Image.load_from_file("res://benchmarks/synth48.png")
    assert(real != null and synth != null and real.get_size() == synth.get_size())
    var anchors: Array[int] = []
    for i in range(12):
        anchors.append(roundi(float(i) * 47.0 / 11.0))
    var mse: float = 0
    var mae: float = 0
    var n: int = 0
    for y in range(real.get_height()):
        for x in range(real.get_width()):
            var view: int = (11 - y / 128) * 4 + x / 128
            if view in anchors:
                continue
            var a: Color = real.get_pixel(x, y)
            var b: Color = synth.get_pixel(x, y)
            for error in [a.r-b.r, a.g-b.g, a.b-b.b]:
                mse += error * error
                mae += abs(error)
                n += 1
    mse /= n
    mae /= n
    var report := {"compared_rgb_samples":n, "synthetic_tiles":36, "mae_0_1":mae, "psnr_db":-10.0*log(mse)/log(10), "caveat":"static opaque scene; differences include gamma vs Godot output; not optical quality"}
    var file := FileAccess.open("res://benchmarks/quality48.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "  "))
    print(JSON.stringify(report))
    quit()
