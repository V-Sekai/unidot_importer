class_name UnidotLODGroup extends UnidotBehaviour

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	if keys.get("m_Enabled"):
		state.prefab_state.lod_groups.append(self)
	return super.create_godot_node(state, new_parent) # make a default node.
