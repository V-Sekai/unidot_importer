class_name DiscardUnidotComponent extends UnidotComponent

func get_godot_type() -> String:
	return "MissingNode"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null
