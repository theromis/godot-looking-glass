extends Node
## Bridge HTTP control plane. Does not transfer live GPU textures.
signal status_changed(message: String)
var base_url: String = "http://127.0.0.1:33334"
var token: String = ""
var devices: Array[Dictionary] = []
var last_error: String = ""

static func unwrap(value: Variant) -> Variant:
    if value is Dictionary:
        if value.has("value"):
            return unwrap(value["value"])
        var result: Dictionary = {}
        for key in value:
            result[key] = unwrap(value[key])
        return result
    if value is Array:
        var result: Array = []
        for entry in value:
            result.append(unwrap(entry))
        return result
    return value

func _request(endpoint: String, body: Dictionary) -> Dictionary:
    var http := HTTPRequest.new()
    http.timeout = 3.0
    add_child(http)
    var error: int = http.request(base_url + "/" + endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_PUT, JSON.stringify(body))
    if error != OK:
        http.queue_free()
        last_error = "HTTP request failed: %d" % error
        return {}
    var response: Array = await http.request_completed
    http.queue_free()
    if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] < 200 or response[1] >= 300:
        last_error = "Bridge unavailable: result=%d HTTP=%d" % [response[0], response[1]]
        return {}
    var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
    if not parsed is Dictionary:
        last_error = "Bridge returned invalid JSON"
        return {}
    return parsed

func detect() -> Array[Dictionary]:
    devices.clear()
    last_error = ""
    var session: Dictionary = await _request("enter_orchestration", {"name": "godot-looking-glass-lab"})
    var payload: Variant = unwrap(session.get("payload", ""))
    if not payload is String or payload.is_empty():
        status_changed.emit(last_error if last_error != "" else "Bridge session missing")
        return devices
    token = payload
    var response: Dictionary = await _request("available_output_devices", {"orchestration": token})
    var outputs: Variant = unwrap(response.get("payload", {}))
    if outputs is Dictionary:
        for key in outputs:
            var device: Variant = outputs[key]
            if not device is Dictionary:
                continue
            var calibration: Variant = device.get("calibration", {})
            if calibration is String:
                if calibration.is_empty():
                    continue
                var parser := JSON.new()
                if parser.parse(calibration) != OK:
                    continue
                # Calibration JSON can itself contain Bridge value wrappers.
                calibration = unwrap(parser.data)
            if not calibration is Dictionary or float(calibration.get("screenW", 0)) <= 0 or float(calibration.get("screenH", 0)) <= 0:
                continue
            device["calibration"] = calibration
            device["index"] = int(key)
            devices.append(device)
    status_changed.emit("Bridge: %d calibrated outputs" % devices.size())
    return devices

func close_session() -> void:
    if token != "":
        await _request("exit_orchestration", {"orchestration": token})
        token = ""

func apply_geometry(rig: Node3D, device: Dictionary) -> bool:
    # Apply before adding the rig to the scene. Lens calibration is retained,
    # but optical interlacing is the native Bridge adapter's responsibility.
    var calibration: Dictionary = device.get("calibration", {})
    var width: float = float(calibration.get("screenW", 0))
    var height: float = float(calibration.get("screenH", 0))
    var cone: float = float(calibration.get("viewCone", 0))
    if width <= 0 or height <= 0 or cone <= 0 or cone >= 80:
        return false
    rig.view_cone_degrees = cone
    rig.tile_size.x = maxi(1, roundi(rig.tile_size.y * width / height))
    return true
