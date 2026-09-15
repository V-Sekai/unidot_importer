class_name UnidotTransform extends UnidotComponent

func get_godot_type() -> String:
	return "Node3D"

var skeleton_bone_index: int = -1

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	return null

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	# FIXME: Do we need convert_properties_component?
	# var outdict = convert_properties_component(node, uprops)
	var n3d: Node3D = node as Node3D
	if n3d == null:
		log_warn("Unable to convert Transform properties using original values.")
		return _convert_properties_pos_scale(uprops, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE)
	elif n3d is Skeleton3D and skeleton_bone_index != -1:
		return _convert_properties_pos_scale(uprops,
			n3d.get_bone_pose_position(skeleton_bone_index),
			n3d.get_bone_pose_rotation(skeleton_bone_index),
			n3d.get_bone_pose_scale(skeleton_bone_index))
	else:
		return _convert_properties_pos_scale(uprops, n3d.position, n3d.quaternion, n3d.scale)

func _convert_properties_pos_scale(uprops: Dictionary, orig_pos_godot: Vector3, orig_rot_godot: Quaternion, orig_scale_godot: Vector3) -> Dictionary:
	# We only insert them here if it's not 1,1,1 or -1,-1,-1 which are the only two godot supported scale signs.
	var cur_signs: Vector3 = (orig_scale_godot.sign() + Vector3(0.5,0.5,0.5)).sign()
	# We need to be careful not to double-apply the sign logic, since Godot will cache the correct signs in memory sometimes.
	# log_debug("signs are " + str(meta.transform_fileid_to_scale_signs) + " | prefab signs are " + str(meta.prefab_transform_fileid_to_scale_signs) + "  fileID is " + str(fileID) + " " + str(cur_signs))
	if cur_signs.is_equal_approx(Vector3.ONE) or cur_signs.is_equal_approx(-Vector3.ONE):
		if meta.transform_fileid_to_scale_signs.has(fileID) or meta.prefab_transform_fileid_to_scale_signs.has(fileID):
			var signs: Vector3 = meta.transform_fileid_to_scale_signs.get(fileID, meta.prefab_transform_fileid_to_scale_signs.get(fileID))
			cur_signs = signs
			var cnt: int = int(signs.x < 0) + int(signs.y < 0) + int(signs.z < 0)
			orig_scale_godot = abs(orig_scale_godot) * signs
			if cnt != 1:
				signs *= -1 # Make sure exactly one is negative
			if signs.x < 0: # Rotate about X axis 180 degrees
				#log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about x, now cur_signs is " + str(cur_signs))
				orig_rot_godot = Quaternion(1, 0, 0, 0) * orig_rot_godot
			elif signs.y < 0: # Rotate about Y axis 180 degrees
				#log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about y, now cur_signs is " + str(cur_signs))
				orig_rot_godot = Quaternion(0, 1, 0, 0) * orig_rot_godot
			else: # Rotate about Z axis 180 degrees
				#log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about z, now cur_signs is " + str(cur_signs))
				orig_rot_godot = Quaternion(0, 0, 1, 0) * orig_rot_godot

	var outdict: Dictionary
	var rotation_delta: Transform3D
	#var pos_rotation_delta: Transform3D
	var rotation_delta_post := Transform3D.IDENTITY
	var has_post: bool = false
	if meta.transform_fileid_to_rotation_delta.has(fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(fileID):
		rotation_delta_post = meta.transform_fileid_to_rotation_delta.get(fileID, meta.prefab_transform_fileid_to_rotation_delta.get(fileID, Transform3D.IDENTITY))
		rotation_delta_post = rotation_delta_post.affine_inverse()
		#log_debug("convert_properties: This fileID is a humanoid bone position offset=" + str(rotation_delta_post.origin) + " rotation offset=" + str(rotation_delta_post.basis.get_rotation_quaternion()) + " scale offset=" + str(rotation_delta_post.basis.get_scale()))
		has_post = true
	if meta.transform_fileid_to_parent_fileid.has(fileID) or meta.prefab_transform_fileid_to_parent_fileid.has(fileID):
		var parent_fileid: int = meta.transform_fileid_to_parent_fileid.get(fileID, meta.prefab_transform_fileid_to_parent_fileid.get(fileID))
		if meta.transform_fileid_to_rotation_delta.has(parent_fileid) or meta.prefab_transform_fileid_to_rotation_delta.has(parent_fileid):
			rotation_delta = meta.transform_fileid_to_rotation_delta.get(parent_fileid, meta.prefab_transform_fileid_to_rotation_delta.get(parent_fileid))
			#log_debug("convert_properties: parent fileID " + str(parent_fileid) + " is a humanoid bone with child position offset=" + str(rotation_delta.origin) + " rotation offset=" + str(rotation_delta.basis.get_rotation_quaternion()) + " scale offset=" + str(rotation_delta.basis.get_scale()))
	#else:
	#	log_debug("convert_properties: Node has no parent.")

	var rot_quat: Quaternion = Quaternion.IDENTITY
	#log_debug("inv post " + str(rotation_delta_post.basis.get_rotation_quaternion().inverse()) + " orig rot " + str(orig_rot_godot) + " inv delta " + str(rotation_delta.basis.get_rotation_quaternion().inverse()))
	var orig_rot_quat: Quaternion = rotation_delta_post.basis.get_rotation_quaternion().inverse() * orig_rot_godot * rotation_delta.basis.get_rotation_quaternion().inverse()
	orig_rot_quat.y = -orig_rot_quat.y
	orig_rot_quat.z = -orig_rot_quat.z
	var rot_vec: Variant = get_quat(uprops, "m_LocalRotation", orig_rot_quat) # left-handed
	#log_debug("Original rotation: " + str(orig_rot_quat) + " -> " + str(rot_vec))
	if typeof(rot_vec) == TYPE_QUATERNION:
		rot_quat = rot_vec as Quaternion
		# Assuming t-pose, in a humanoid a lot of these expressions will cancel out nicely to godot's bone rest (T-pose)
		# This is
		# Previously:
		# (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() *  this_orig_rest.affine_inverse() * node.get_bone_rest(p_skel_bone) = node.get_bone_rest(p_skel_bone)
		# Quaternion.IDENTITY == (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() * this_orig_rest.affine_inverse()
		# node.get_bone_rest(p_skel_bone)

		# Now:
		# this_orig_global_rest = parent_orig_global_rest * ... * this_orig_rest
		# par_global_rest.affine_inverse() * parent_orig_global_rest * (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() * this_orig_rest.affine_inverse() * parent_orig_global_rest.affine_inverse() * par_global_rest * this_bone_rest
		# par_global_rest.affine_inverse() * parent_orig_global_rest * parent_orig_global_rest.affine_inverse() * par_global_rest * this_bone_rest
		# par_global_rest.atffine_inverse() * par_global_rest * this_bone_rest
		# this_bone_rest
		# WANT: this_bone_rest
		# Same as (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion()
		rot_quat.y = -rot_quat.y
		rot_quat.z = -rot_quat.z
		rot_quat = rotation_delta.basis.get_rotation_quaternion() * rot_quat * rotation_delta_post.basis.get_rotation_quaternion()
		outdict["quaternion"] = rot_quat
		#log_debug("Rotation would be " + str(outdict["quaternion"]) + " (" + str(rot_quat.get_euler() * 180.0 / PI) + " deg)")
	else:
		rot_quat = orig_rot_godot
	rot_quat = rotation_delta.basis.get_rotation_quaternion().inverse() * rot_quat * rotation_delta_post.basis.get_rotation_quaternion().inverse()
	#rot_quat.y = -rot_quat.y
	#rot_quat.z = -rot_quat.z

	var orig_scale: Vector3 = cur_signs * (rotation_delta.basis.inverse() * Basis.from_scale(orig_scale_godot.abs()) * rotation_delta_post.basis.inverse()).get_scale()
	#log_debug("Original scale: " + str(orig_scale_godot) + " -> " + str(orig_scale))
	var input_scale_vec: Vector3
	var scale: Variant = get_vector(uprops, "m_LocalScale", orig_scale)
	if typeof(scale) == TYPE_VECTOR3:
		input_scale_vec = scale as Vector3
		var scale_vec: Vector3 = scale as Vector3
		#log_debug("Scale originally is " + str(scale_vec))
		# FIXME: Godot handles scale 0 much worse than Unidot. Try to avoid it.
		if scale_vec.x > -1e-7 && scale_vec.x < 1e-7:
			scale_vec.x = 1e-7
		if scale_vec.y > -1e-7 && scale_vec.y < 1e-7:
			scale_vec.y = 1e-7
		if scale_vec.z > -1e-7 && scale_vec.z < 1e-7:
			scale_vec.z = 1e-7
		var new_signs: Vector3 = (scale_vec.sign() + Vector3(0.5,0.5,0.5)).sign()
		scale_vec = new_signs * (rotation_delta.basis * Basis.from_scale(scale_vec.abs()) * rotation_delta_post.basis).get_scale()
		outdict["scale"] = scale_vec
		#log_debug("Scale would be " + str(outdict["scale"]))
	else:
		input_scale_vec = orig_scale

	var orig_pos: Vector3 = (rotation_delta.basis.inverse() * orig_pos_godot) * Vector3(-1, 1, 1)
	#log_debug("Original position: " + str(orig_pos_godot) + " -> " + str(orig_pos))
	var pos_tmp: Variant = get_vector(uprops, "m_LocalPosition", orig_pos)
	if typeof(pos_tmp) == TYPE_VECTOR3:
		var pos_vec: Vector3 = pos_tmp as Vector3
		#log_debug("Position originally is " + str(pos_vec * Vector3(-1, 1, 1)) + " adding " + str(rot_quat * (input_scale_vec * rotation_delta_post.origin)))
		pos_vec = rotation_delta * (pos_vec * Vector3(-1, 1, 1) + rot_quat * (input_scale_vec * rotation_delta_post.origin)) # * rotation_delta_post.basis #.get_rotation_quaternion()
		outdict["position"] = pos_vec
		#log_debug("Position would be " + str(outdict["position"]))

	return outdict

func convert_skeleton_properties(skel: Skeleton3D, bone_name: String, uprops: Dictionary):
	var bone_idx: int = skel.find_bone(bone_name)
	return _convert_properties_pos_scale(uprops, skel.get_bone_pose_position(bone_idx), skel.get_bone_pose_rotation(bone_idx), skel.get_bone_pose_scale(bone_idx))

var rootOrder: int:
	get:
		return keys.get("m_RootOrder", 0)

var parent_ref: Variant:  # Array: # UnidotRef
	get:
		if is_stripped:
			log_fail("Attempted to access the parent of a stripped " + type + " " + str(self), "parent")
			return 12345.678  # FIXME: Returning bogus value to crash whoever does this
		return keys.get("m_Father", [null, 0, "", 0])

var parent_no_stripped: UnidotObject:  # UnidotTransform
	get:
		if is_stripped or is_non_stripped_prefab_reference:
			return meta.lookup(self.prefab_instance)  # Not a UnidotTransform, but sufficient for determining a common "ancestor" for skeleton bones.
		return meta.lookup(parent_ref)

var parent: Variant:  # UnidotTransform:
	get:
		if is_stripped:
			log_fail("Attempted to access the parent of a stripped " + type + " " + str(self), "parent")
			return 12345.678  # FIXME: Returning bogus value to crash whoever does this
		return meta.lookup(parent_ref)
