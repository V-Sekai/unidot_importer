class_name UnidotCharacterController extends UnidotBehaviour

func get_godot_type() -> String:
	return "CharacterBody3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null

func create_physics_body(state: RefCounted, new_parent: Node3D, name: String) -> Node:
	var character: CharacterBody3D = CharacterBody3D.new()
	character.name = name  # Not type: This replaces the usual transform node.
	state.add_child(character, new_parent, self)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CapsuleShape3D"
	var capsule := CapsuleShape3D.new()
	collision_shape.shape = capsule
	character.add_child(collision_shape)
	collision_shape.owner = character.owner
	return character

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_Height"):
		outdict["_height"] = uprops.get("m_Height", 2.0)
	if uprops.has("m_Radius"):
		outdict["_radius"] = uprops.get("m_Radius", 0.5)
	if uprops.has("m_Center"):
		outdict["_center"] = uprops.get("m_Center", Vector3.ZERO) * Vector3(-1,1,1)
	if uprops.has("m_SlopeLimit"):
		outdict["floor_max_angle"] = uprops.get("m_SlopeLimit", 45) * PI / 180.0
	if uprops.has("m_SkinWidth"):
		outdict["floor_snap_length"] = uprops.get("m_SkinWidth", 0.1)
	# What to do with m_StepOffset... Godot doesn't have this?
	if uprops.has("m_Material"):
		outdict["_material"] = meta.get_godot_resource(uprops.get("m_Material"))
	if uprops.has("m_Layer"):
		outdict["collision_layer"] = uprops.get("m_Layer")
	return outdict

func apply_node_props(node: Node, props: Dictionary):
	var coll_shape: CollisionShape3D = node.get_node("CapsuleShape3D") as CollisionShape3D
	if coll_shape != null:
		var capsule_shape: CapsuleShape3D = coll_shape.shape as CapsuleShape3D
		if capsule_shape != null:
			if props.has("_height"):
				capsule_shape.height = props["_height"]
				props.erase("_height")
			if props.has("_radius"):
				capsule_shape.radius = props["_radius"]
				props.erase("_radius")
			if props.has("_center"):
				coll_shape.position = props["_center"]
				props.erase("_center")
			# TODO: Godot does not yet support per-collision-shape materials
			#if props.has("_material"):
			#	capsule_shape.physics_material_override = props["_material"]
			#	props.erase("_material")
	super.apply_node_props(node, props)
