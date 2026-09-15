class_name UnidotComponent extends UnidotObject

func get_godot_type() -> String:
	return "Node"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	if not meta.get_database().add_unsupported_components:
		return null
	var new_node: Node = Node.new()
	new_node.name = type
	state.add_child(new_node, new_parent, self)
	assign_object_meta(new_node)
	if meta.get_database().enable_unidot_keys:
		new_node.editor_description = str(self)
	return new_node

#func get_gameObject() -> UnidotGameObject:
func get_gameObject():
	if is_stripped:
		log_fail("Attempted to access the gameObject of a stripped " + type + " " + str(self), "gameObject")
		# FIXME: Stripped objects do not know their name.
		return null  # ????
	return meta.lookup(keys.get("m_GameObject", [null, 0, "", 0]))

func get_name() -> String:
	if is_stripped:
		log_fail("Attempted to access the name of a stripped " + type, "name")
		# FIXME: Stripped objects do not know their name.
		# FIXME: Make the calling function crash, since we don't have stacktraces wwww
		return "[stripped]"  # ????
	return str(gameObject.name)

func get_debug_name() -> String:
	if is_stripped or gameObject == null:
		var bone: String = meta.fileid_to_skeleton_bone.get(fileID, meta.prefab_fileid_to_skeleton_bone.get(fileID, ""))
		if not bone.is_empty():
			return bone
		var np: NodePath = meta.fileid_to_nodepath.get(fileID, meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
		if not np.is_empty():
			return np.get_name(np.get_name_count() - 1)
		if is_stripped:
			return "[stripped]"
		return "[null gameObject]"
	return str(gameObject.name)

func is_toplevel() -> bool:
	return false
