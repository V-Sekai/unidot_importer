class_name UnidotMeshRenderer extends UnidotRenderer

func get_godot_type() -> String:
	return "MeshInstance3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return create_godot_node_orig(state, new_parent, type)

func create_godot_node_orig(state: RefCounted, new_parent: Node3D, component_name: String) -> Node:
	var new_node: MeshInstance3D = MeshInstance3D.new()
	new_node.name = component_name
	state.add_child(new_node, new_parent, self)
	assign_object_meta(new_node)
	if meta.get_database().enable_unidot_keys:
		new_node.editor_description = str(self)
	var mesh_ref: Array = self.get_mesh()
	var mesh_meta: Resource = meta.lookup_meta(mesh_ref)
	if mesh_meta != null:
		new_node.mesh = meta.get_godot_resource(mesh_ref)
		meta.fileid_to_material_order_rev[fileID] = mesh_meta.fileid_to_material_order_rev.get(mesh_ref[1], PackedInt32Array())

	if is_stripped or gameObject.is_stripped:
		log_fail("Oh no i am stripped MeshRenderer create_godot_node_orig")
	var mf: RefCounted = gameObject.get_meshFilter()
	if mf != null:
		state.add_fileID(new_node, mf)
	var idx: int = 0
	var mat_slots: PackedInt32Array = meta.fileid_to_material_order_rev.get(fileID, meta.prefab_fileid_to_material_order_rev.get(fileID, PackedInt32Array()))
	for m in keys.get("m_Materials", []):
		new_node.set_surface_override_material(mat_slots[idx] if idx < len(mat_slots) else idx, meta.get_godot_resource(m))
		idx += 1
	return new_node

# TODO: convert_properties
# both material properties as well as material references??
# anything else to animate?

func get_mesh() -> Array:  # UnidotRef
	if is_stripped or gameObject.is_stripped:
		log_fail("Oh no i am stripped MeshRenderer get_mesh")
	var mf: RefCounted = gameObject.get_meshFilter()
	if mf != null:
		return mf.get_filter_mesh()
	return [null, 0, "", null]

