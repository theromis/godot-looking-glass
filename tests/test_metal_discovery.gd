extends SceneTree
const Output=preload("res://addons/looking_glass/metal_output.gd")
const Rig=preload("res://addons/looking_glass/rig.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var output:=Output.new()
    var devices:=output.discover_displays()
    var passed: bool=not devices.is_empty()
    if passed:
        var rig:=Rig.new()
        passed=output.configure_rig_for_display(rig,devices[0])
        passed=passed and rig.total_views==66 and rig.source_view_size==Vector2i(384,682) and output.display_index==devices[0].index
        rig.free()
    output.free()
    print("DISCOVERY devices=",devices.size())
    print("PASS display discovery and rig configuration" if passed else "FAIL display discovery")
    quit(0 if passed else 1)
