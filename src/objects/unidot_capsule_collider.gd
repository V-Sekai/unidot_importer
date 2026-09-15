class_name UnidotCapsuleCollider extends UnidotCollider

func get_shape() -> Shape3D:
	var bs: CapsuleShape3D = CapsuleShape3D.new()
	return bs

func get_basis_from_direction(direction: int):
	if direction == 0:  # Along the X-Axis
		return Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0))
	if direction == 1:  # Along the Y-Axis (Godot default)
		return Basis.from_euler(Vector3(0.0, 0.0, 0.0))
	if direction == 2:  # Along the Z-Axis
		return Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_collider(node, uprops)
	var radius: float = 0.0  # FIXME: height including radius???? Did godot change this???
	if node != null:
		radius = node.shape.radius
		log_debug("Convert capsules " + str(node.shape.radius) + " " + str(node.name) + " and " + str(outdict))
	if typeof(uprops.get("m_Radius")) != TYPE_NIL:
		radius = uprops.get("m_Radius")
		outdict["shape:radius"] = radius
	if typeof(uprops.get("m_Height")) != TYPE_NIL:
		var adj_height: float = uprops.get("m_Height") - 2 * radius
		if adj_height < 0.0:
			adj_height = 0.0
		outdict["shape:height"] = adj_height
	return outdict


