class_name UnidotTerrainCollider extends UnidotMeshCollider

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var coll: Node3D = super.create_godot_node(state, new_parent)
	return coll

func get_shape() -> Shape3D:
	return get_collision_shape(self.keys)

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_collider(node, uprops)
	outdict["shape"] = get_collision_shape(uprops)
	return outdict

func get_collision_shape(uprops: Dictionary) -> Shape3D:  # UnidotRef
	var coll_ref: Array = uprops.get("m_TerrainData")
	coll_ref = [null, 0xc0111de4 ^ coll_ref[1], coll_ref[2], coll_ref[3]]
	var concave: ConcavePolygonShape3D = self.meta.get_godot_resource(coll_ref)
	return concave
