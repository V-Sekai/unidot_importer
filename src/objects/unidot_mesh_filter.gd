class_name UnidotMeshFilter extends UnidotComponent

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	var flags_val: int = keys.get("m_StaticEditorFlags", 0) # We copy this from the GameObject to the MeshRenderer.
	var lightmap_static: bool = (flags_val & 1) != 0
	outdict["_lightmap_static"] = lightmap_static
	if uprops.has("m_Mesh"):
		var mesh_ref: Array = get_ref(uprops, "m_Mesh")
		var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
		log_debug("MeshFilter " + str(self) + " ref " + str(mesh_ref) + " new mesh " + str(new_mesh) + " old mesh " + str(node.mesh))
		outdict["_mesh"] = new_mesh  # property track?
		outdict["_mesh_ref"] = mesh_ref  # property track?
	return outdict

func get_filter_mesh() -> Array:  # UnidotRef
	return keys.get("m_Mesh", [null, 0, "", null])
