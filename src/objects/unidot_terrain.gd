class_name UnidotTerrain extends UnidotBehaviour

func get_godot_type() -> String:
	return "MultiMeshInstance3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	#var terrain: MeshInstance3D = MeshInstance3D.new()
	#terrain.name = "Terrain"
	#assign_object_meta(terrain)
	#state.add_child(terrain, new_parent, self)
	# Traditional instanced scene case: It only requires calling instantiate() and setting the filename.
	var packed_scene: PackedScene = meta.get_godot_resource(keys.get("m_TerrainData", [null, 0, null, null]))
	if packed_scene == null:
		return null
	var instanced_terrain: Node3D = packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	#instanced_scene.scene_file_path = packed_scene.resource_path
	state.add_child(instanced_terrain, new_parent, self)
	state.owner.set_editable_instance(instanced_terrain, true)
	#instanced_terrain.top_level = true
	#instanced_terrain.position = new_parent.global_transform.origin
	instanced_terrain.name = "Terrain"
	return instanced_terrain

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	return outdict
