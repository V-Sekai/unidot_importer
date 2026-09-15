class_name UnidotSphereCollider extends UnidotCollider

func get_shape() -> Shape3D:
	var bs: SphereShape3D = SphereShape3D.new()
	return bs

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_collider(node, uprops)
	if uprops.has("m_Radius"):
		outdict["shape:radius"] = uprops.get("m_Radius")
	log_debug("**** SPHERE COLLIDER RADIUS " + str(outdict))
	return outdict

