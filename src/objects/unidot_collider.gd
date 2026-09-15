class_name UnidotCollider extends UnidotBehaviour

func get_godot_type() -> String:
	return "StaticBody3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var new_node: CollisionShape3D = CollisionShape3D.new()
	log_debug("Creating collider at " + self.name + " type " + self.type + " parent name " + str(new_parent.name if new_parent != null else "NULL") + " path " + str(state.owner.get_path_to(new_parent) if new_parent != null else NodePath()) + " body name " + str(state.body.name if state.body != null else "NULL") + " path " + str(state.owner.get_path_to(state.body) if state.body != null else NodePath()))
	new_node.shape = self.shape
	if state.body == null or keys.get("m_IsTrigger", 0) != 0:
		var new_body: Node3D
		if keys.get("m_IsTrigger", 0) != 0:
			new_body = Area3D.new()
		else:
			new_body = StaticBody3D.new()
		new_body.name = self.type
		new_parent.add_child(new_body, true)
		new_body.owner = state.owner
		new_node.name = "CollisionShape3D"
		state.add_child(new_node, new_body, self)
	else:
		new_node.name = self.type
		state.add_child(new_node, state.body, self)
		var path_to_body = new_parent.get_path_to(state.body)
		var cur_node: Node3D = new_parent
		var xform = Transform3D()
		for i in range(path_to_body.get_name_count()):
			if path_to_body.get_name(i) == ".":
				continue
			elif path_to_body.get_name(i) == "..":
				xform = cur_node.transform * xform
				cur_node = cur_node.get_parent()
				if cur_node == null:
					break
			else:
				cur_node = cur_node.get_node(str(path_to_body.get_name(i)))
				if cur_node == null:
					break
				log_debug("Found node " + str(cur_node) + " class " + str(cur_node.get_class()))
				log_debug("Found node " + str(cur_node) + " transform " + str(cur_node.transform))
				xform = cur_node.transform.affine_inverse() * xform
		#while cur_node != state.body and cur_node != null:
		#	xform = cur_node.transform * xform
		#	cur_node = cur_node.get_parent()
		#if cur_node == null:
		#	xform = Transform3D(self.basis, self.center)
		if not xform.is_equal_approx(Transform3D()):
			new_node.set_meta("__xform_storage", xform)
	return new_node

# TODO: Colliders are complicated because of the transform hierarchy issue above.
func convert_properties_collider(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	var complex_xform: Transform3D = Transform3D.IDENTITY
	if node != null and node.has_meta("__xform_storage"):
		complex_xform = node.get_meta("__xform_storage")
	var center: Vector3 = Vector3()
	var basis: Basis = Basis.IDENTITY

	var center_prop: Variant = get_vector(uprops, "m_Center")
	if typeof(center_prop) == TYPE_VECTOR3:
		center = Vector3(-1.0, 1.0, 1.0) * center_prop
		if not complex_xform.is_equal_approx(Transform3D.IDENTITY):
			outdict["transform"] = complex_xform * Transform3D(basis, center)
		else:
			outdict["position"] = center
	if uprops.has("m_Direction"):
		basis = get_basis_from_direction(uprops.get("m_Direction"))
		if not complex_xform.is_equal_approx(Transform3D.IDENTITY):
			outdict["transform"] = complex_xform * Transform3D(basis, center)
		else:
			outdict["rotation_degrees"] = basis.get_euler() * 180 / PI
	if uprops.has("m_Material"):
		outdict["_material"] = meta.get_godot_resource(uprops.get("m_Material"))
	return outdict

func apply_node_props(node: Node, props: Dictionary):
	if props.get("_material") != null:
		var parent_rigid: RigidBody3D = node.get_parent() as RigidBody3D
		if parent_rigid != null:
			parent_rigid.physics_material_override = props.get("_material")
		var parent_static: StaticBody3D = node.get_parent() as StaticBody3D
		if parent_static != null:
			parent_static.physics_material_override = props.get("_material")
		props.erase("_material")
	super.apply_node_props(node, props)

func get_basis_from_direction(direction: int):
	return Basis()

var shape: Shape3D:
	get:
		return get_shape()

func get_shape() -> Shape3D:
	return null

func is_collider() -> bool:
	return true
