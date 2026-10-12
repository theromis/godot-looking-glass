extends SceneTree
const Client = preload("res://addons/looking_glass/bridge_client.gd")
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var client = Client.new()
    root.add_child(client)
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--url="):
            client.base_url = arg.trim_prefix("--url=")
    var devices: Array[Dictionary] = await client.detect()
    print(JSON.stringify({"devices": devices, "error": client.last_error}))
    if client.base_url.ends_with(":33335"):
        if not check(devices.size() == 1):
            return
        var rig = preload("res://addons/looking_glass/rig.gd").new()
        if not check(client.apply_geometry(rig, devices[0])):
            return
        if not check(rig.tile_size.x == 192 and rig.view_cone_degrees == 40.0):
            return
        rig.free()
        print("PASS Bridge fixture: session, wrappers, device list, geometry, session close")
    await client.close_session()
    quit()

func check(condition: bool, message: String = "Test condition failed") -> bool:
    if not condition:
        push_error("FAIL " + message)
        quit(1)
    return condition
