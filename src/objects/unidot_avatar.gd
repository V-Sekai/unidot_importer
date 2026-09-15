class_name UnidotAvatar extends UnidotObject

const aligned_byte_buffer := preload("../../aligned_byte_buffer.gd")
const human_trait = preload("../../humanoid/human_trait.gd")

static func read_transform(xform: Dictionary) -> Transform3D:
	var translation: Vector3 = xform["t"] * Vector3(-1, 1, 1)
	var quaternion: Quaternion = xform["q"]
	quaternion.y = -quaternion.y
	quaternion.z = -quaternion.z
	var scale: Vector3 = xform["s"]
	return Transform3D(Basis(Quaternion(quaternion)).scaled(scale), translation)

func get_godot_type() -> String:
	return "BoneMap"

func create_godot_resource() -> Resource:
	var fileid_to_human_bone_index: Dictionary
	var fileid_to_skeleton_bone: Dictionary
	var transform_fileid_to_rotation_delta: Dictionary
	var transform_fileid_to_parent_fileid: Dictionary
	var hip_position: Vector3

	var avatar_keys = keys["m_Avatar"]
	var skeleton_size := len(avatar_keys["m_AvatarSkeleton"]["m_Node"])
	var human_size := len(avatar_keys["m_Human"]["m_Skeleton"]["m_Node"])
	var crc32_skeleton_bones_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_SkeletonNameIDArray"])
	var crc32_skeleton_bones: PackedInt32Array = crc32_skeleton_bones_buf.uint32_subarray(0, skeleton_size)

	var human_to_skeleton_bone_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_HumanSkeletonIndexArray"])
	var human_to_skeleton_bone_indices: PackedInt32Array = human_to_skeleton_bone_indices_buf.uint32_subarray(0, human_size)

	# These arrays are fixed, totaling len(human_trait.HumanBodyBones)
	var human_bone_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_HumanBoneIndex"])
	var human_bone_indices: PackedInt32Array = human_bone_indices_buf.uint32_subarray(0, 25) # 25 human bones excluding hands
	while len(human_bone_indices) < 25:
		human_bone_indices.append(-1)

	var human_left_hand_indices: PackedInt32Array
	if avatar_keys["m_Human"].get("m_HasLeftHand", 1) == 1:
		var human_left_hand_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_LeftHand"]["m_HandBoneIndex"])
		human_left_hand_indices = human_left_hand_indices_buf.uint32_subarray(0, 15) # 3 * 5 fingers
	while len(human_left_hand_indices) < 15:
		human_left_hand_indices.append(-1)
	human_bone_indices.append_array(human_left_hand_indices)

	var human_right_hand_indices: PackedInt32Array
	if avatar_keys["m_Human"].get("m_HasRightHand", 1) == 1:
		var human_right_hand_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_RightHand"]["m_HandBoneIndex"])
		human_right_hand_indices = human_right_hand_indices_buf.uint32_subarray(0, 15) # 3 * 5 fingers
	while len(human_right_hand_indices) < 15:
		human_right_hand_indices.append(-1)
	human_bone_indices.append_array(human_right_hand_indices)

	var crc32_human_skeleton_bones: PackedInt32Array
	for orig_human_skel_index in range(human_size):
		var orig_skeleton_index: int = human_to_skeleton_bone_indices[orig_human_skel_index]
		var crc32_orig_name: int = crc32_skeleton_bones[orig_skeleton_index]
		crc32_human_skeleton_bones.append(crc32_orig_name)

	for human_mono_bone_idx in range(human_trait.BoneCount):
		var human_bone_idx: int = human_trait.boneIndexToMono[human_mono_bone_idx]
		var godot_bone_name: String = human_trait.GodotHumanNames[human_bone_idx]
		var orig_human_skel_index: int = human_bone_indices[human_mono_bone_idx]
		if orig_human_skel_index == -1:
			log_debug("Avatar: Godot bone " + godot_bone_name + " is not assigned")
			continue
		var crc32_orig_name: int = crc32_human_skeleton_bones[orig_human_skel_index]
		log_debug("Avatar: Godot bone " + godot_bone_name + " has crc " + ("%08x" % (0xffffffff&crc32_orig_name)))
		meta.humanoid_bone_map_crc32_dict[crc32_orig_name] = godot_bone_name
		# We're pretending CRC32 are fileids. These are just used temporarily to indirect into transform_fileid_to_rotation_delta
		fileid_to_skeleton_bone[crc32_orig_name] = godot_bone_name
		fileid_to_human_bone_index[crc32_orig_name] = human_bone_idx

	var human_skel_nodes: Array = avatar_keys["m_Human"]["m_Skeleton"]["m_Node"]
	var human_skel_axes: Array = avatar_keys["m_Human"]["m_Skeleton"]["m_AxesArray"]
	var root_xform: Transform3D = read_transform(avatar_keys["m_Human"]["m_RootX"])
	var hips_y: float = root_xform.origin.y
	var root_xform_delta: Transform3D = Transform3D(root_xform.basis.inverse(), Vector3(-root_xform.origin.x, 0, -root_xform.origin.z))
	for orig_human_skel_index in range(human_size):
		var crc32_orig_name: int = crc32_human_skeleton_bones[orig_human_skel_index]
		var parent_id: int = human_skel_nodes[orig_human_skel_index]["m_ParentId"]
		if parent_id > 0x7fffffff or parent_id < 0:
			parent_id = -1
		var axes_id: int = human_skel_nodes[orig_human_skel_index]["m_AxesId"]
		if axes_id > 0x7fffffff or axes_id < 0:
			axes_id = -1
		var crc32_parent_name: int = crc32_human_skeleton_bones[parent_id]
		if parent_id == -1 and axes_id == -1:
			transform_fileid_to_rotation_delta[crc32_orig_name] = root_xform_delta
		else:
			transform_fileid_to_parent_fileid[crc32_orig_name] = crc32_parent_name
			if axes_id != -1:
				if not fileid_to_human_bone_index.has(crc32_orig_name):
					log_warn("Bone hash %08x has parent %08x and axes_id=%d but missing from skeleton map" % [crc32_orig_name, crc32_parent_name, axes_id])
					continue
				var bone_index: int = fileid_to_human_bone_index[crc32_orig_name]
				var gd_postqinv: Quaternion = human_trait.postQ_inverse_exported[bone_index]
				var uni_postq: Quaternion = human_skel_axes[axes_id]["m_PostQ"]
				uni_postq.y = -uni_postq.y
				uni_postq.z = -uni_postq.z
				if bone_index != 0:
					transform_fileid_to_rotation_delta[crc32_orig_name] = root_xform_delta * Transform3D(Basis(gd_postqinv.inverse() * uni_postq.inverse()))
				if bone_index == 0: # Hips
					hips_y = (transform_fileid_to_rotation_delta[crc32_parent_name] * read_transform(avatar_keys["m_Human"]["m_SkeletonPose"]["m_X"][orig_human_skel_index])).origin.y

	var humanDescriptionHuman: Array = keys["m_HumanDescription"]["m_Human"]
	meta.humanoid_bone_map_dict = UnidotModelImporter.generate_bone_map_dict_no_root(self, humanDescriptionHuman)

	meta.humanoid_skeleton_hip_position = Vector3(0, hips_y, 0)
	meta.transform_fileid_to_parent_fileid = transform_fileid_to_parent_fileid
	meta.transform_fileid_to_rotation_delta = transform_fileid_to_rotation_delta
	meta.fileid_to_skeleton_bone = fileid_to_skeleton_bone
	return meta # Indicates no resource will be written to disk
