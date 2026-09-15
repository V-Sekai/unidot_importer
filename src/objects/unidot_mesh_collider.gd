class_name UnidotMeshCollider extends UnidotCollider

var source_mesh_instance: MeshInstance3D # Used only for component added to instanced prefab.

# Not making these animatable?
var convex: bool:
	get:
		return keys.get("m_Convex", 0) != 0

func get_shape() -> Shape3D:
	var source_mesh: Mesh
	if source_mesh_instance != null:
		source_mesh = source_mesh_instance.mesh
	else:
		source_mesh = meta.get_godot_resource(get_mesh(keys))
	if convex:
		return source_mesh.create_convex_shape()
	else:
		return source_mesh.create_trimesh_shape()

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_collider(node, uprops)
	var new_convex = node.shape is ConvexPolygonShape3D
	if uprops.has("m_Convex"):
		new_convex = uprops.get("m_Convex", 1 if new_convex else 0) != 0
		# We do not allow animating this without also changing m_Mesh.
	if uprops.has("m_Mesh"):
		var mesh_ref: Array = get_ref(uprops, "m_Mesh")
		var new_mesh: Mesh = null
		if mesh_ref[1] == 0 and (is_stripped or gameObject.is_stripped):
			pass
		else:
			if mesh_ref[1] == 0:
				if is_stripped or gameObject.is_stripped:
					log_warn("Oh no i am stripped MeshCollider")
				var mf: RefCounted = gameObject.get_meshFilter()
				if mf != null:
					new_mesh = meta.get_godot_resource(mf.mesh)
			else:
				new_mesh = meta.get_godot_resource(mesh_ref)
			if new_mesh != null:
				if new_convex:
					outdict["shape"] = new_mesh.create_convex_shape()
				else:
					outdict["shape"] = new_mesh.create_trimesh_shape()

	return outdict

func get_mesh(uprops: Dictionary) -> Array:  # UnidotRef
	var ret = get_ref(uprops, "m_Mesh")
	if ret[1] == 0:
		if is_stripped or gameObject.is_stripped:
			log_warn("Oh no i am stripped MeshCollider get_mesh")
		var mf: RefCounted = gameObject.get_meshFilter()
		if mf != null:
			if mf.is_stripped:
				log_warn("Oh no i am stripped MeshFilter get_mesh")
			return mf.mesh
	return ret
