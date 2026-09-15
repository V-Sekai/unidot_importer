class_name UnidotRigidbody extends UnidotComponent

func get_godot_type() -> String:
	return "RigidBody3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null

func create_physics_body(state: RefCounted, new_parent: Node3D, name: String) -> Node:
	var new_node: Node3D
	var rigid: RigidBody3D = RigidBody3D.new()
	rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	new_node = rigid

	new_node.name = name  # Not type: This replaces the usual transform node.
	state.add_child(new_node, new_parent, self)
	return new_node

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_IsKinematic"):
		outdict["freeze"] = uprops["m_IsKinematic"] != 0
	if uprops.has("m_Mass"):
		outdict["mass"] = uprops["m_Mass"]
	if uprops.has("m_Drag"):
		outdict["linear_damp"] = uprops["m_Drag"]
	if uprops.has("m_UseGravity"):
		outdict["gravity_scale"] = 1.0 * uprops["m_UseGravity"] # 0 or 1
	if uprops.has("m_AngularDrag"):
		outdict["angular_damp"] = uprops["m_AngularDrag"]
	if uprops.has("m_CollisionDetection"):
		outdict["continuous_cd"] = uprops["m_CollisionDetection"] != 0
	if uprops.has("m_Constraints"):
		outdict["lock_rotation"] = (uprops["m_Constraints"] & 112) == 112 # 16, 32, 64 lock axes.
		outdict["axis_lock_angular_x"] = (uprops["m_Constraints"] & 16) != 0
		outdict["axis_lock_angular_y"] = (uprops["m_Constraints"] & 32) != 0
		outdict["axis_lock_angular_z"] = (uprops["m_Constraints"] & 64) != 0
		outdict["axis_lock_linear_x"] = (uprops["m_Constraints"] & 2) != 0
		outdict["axis_lock_linear_y"] = (uprops["m_Constraints"] & 4) != 0
		outdict["axis_lock_linear_z"] = (uprops["m_Constraints"] & 8) != 0
	if uprops.has("m_Layer"):
		outdict["collision_layer"] = uprops.get("m_Layer")
	return outdict

func create_physical_bone(state: RefCounted, godot_skeleton: Skeleton3D, name: String):
	var new_node: PhysicalBone3D = PhysicalBone3D.new()
	new_node.bone_name = name
	new_node.name = name
	state.add_child(new_node, godot_skeleton, self)
	return new_node