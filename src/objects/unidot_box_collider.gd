class_name UnidotBoxCollider extends UnidotCollider

func get_shape() -> Shape3D:
	var bs: BoxShape3D = BoxShape3D.new()
	return bs

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_collider(node, uprops)
	var size = get_vector(uprops, "m_Size")
	if typeof(size) != TYPE_NIL:
		outdict["shape:size"] = size
	log_debug("convert_properties: " + str(outdict))
	return outdict
