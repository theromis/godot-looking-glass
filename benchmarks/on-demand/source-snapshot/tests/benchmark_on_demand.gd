extends "res://demo/main.gd"
# Warmup-control refresh is outside measured idle samples, not an automatic
# scene-change detector or a production settling guarantee.
func _process(delta: float) -> void:
    super._process(delta)
    if rig.update_on_demand and frames == warmup-4:
        rig.request_update()
