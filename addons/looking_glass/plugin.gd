@tool
extends EditorPlugin

func _enter_tree() -> void:
    add_custom_type("LookingGlassRig", "Node3D", preload("rig.gd"), null)
    add_custom_type("LookingGlassMetalOutput", "Node", preload("metal_output.gd"), null)

func _exit_tree() -> void:
    remove_custom_type("LookingGlassMetalOutput")
    remove_custom_type("LookingGlassRig")
