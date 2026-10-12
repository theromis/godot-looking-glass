extends SceneTree
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if not check(args.size() == 2):
        return
    var a := Image.load_from_file(args[0])
    var b := Image.load_from_file(args[1])
    if not check(a != null and b != null and a.get_size() == b.get_size()):
        return
    a.convert(Image.FORMAT_RGBA8)
    b.convert(Image.FORMAT_RGBA8)
    var av := a.get_data()
    var bv := b.get_data()
    var changed: int = 0
    var absolute_error: float = 0
    var square_error: float = 0
    for i in range(av.size()):
        if i % 4 == 3:
            continue
        var error: float = abs(int(av[i]) - int(bv[i])) / 255.0
        absolute_error += error
        square_error += error * error
        if av[i] != bv[i]:
            changed += 1
    var count: int = a.get_width() * a.get_height() * 3
    var mse: float = square_error / count
    print(JSON.stringify({"size": [a.get_width(), a.get_height()], "changed_rgb_channels": changed, "mae": absolute_error / count, "psnr_db": -10.0 * log(mse) / log(10.0) if mse > 0 else null, "exact": changed == 0}))
    quit()

func check(condition: bool, message: String = "Test condition failed") -> bool:
    if not condition:
        push_error("FAIL " + message)
        quit(1)
    return condition
