@tool
extends Skeleton3D

const DEBUG_SKEL_ERRORS: bool = false

var target_skel: Skeleton3D
var my_path_from_skel: String
var bone_attachments: Array[BoneAttachment3D]
var mesh_instances: Array[MeshInstance3D]
var unique_skins: Array[Skin]

# Prevent duplicate NOTIFICATION_UPDATE_SKELETON (can infinite loop)
var last_pose_positions: PackedVector3Array
var last_pose_rotations: Array[Quaternion]
var last_pose_scales: PackedVector3Array

signal updated_skeleton_pose


func find_ancestor_skeleton() -> Skeleton3D:
	var node: Node3D = get_parent_node_3d()
	while node != null:
		if node is Skeleton3D:
			return node as Skeleton3D
		node = node.get_parent_node_3d()
	return null


func find_bone_attachments(target_skel: Skeleton3D) -> Array[BoneAttachment3D]:
	var res: Array[BoneAttachment3D]
	for attachment_node in find_children("*", "BoneAttachment3D", true):
		var attachment := attachment_node as BoneAttachment3D
		if attachment.get_use_external_skeleton():
			var extern_skel: Skeleton3D = attachment.get_node_or_null(attachment.get_external_skeleton()) as Skeleton3D
			if extern_skel == self or extern_skel == target_skel:
				res.append(attachment)
		elif attachment.get_parent() == self:
			res.append(attachment)
	return res


func find_mesh_instances(target_skel: Skeleton3D) -> Array[MeshInstance3D]:
	var res: Array[MeshInstance3D]
	for mesh_node in find_children("*", "MeshInstance3D", true):
		var mesh_inst: MeshInstance3D = mesh_node as MeshInstance3D
		if mesh_inst.skin != null:
			var extern_skel: Skeleton3D = mesh_inst.get_node_or_null(mesh_inst.get_skeleton_path()) as Skeleton3D
			if extern_skel == self or extern_skel == target_skel:
				res.append(mesh_inst)
	return res


func convert_to_named_bind(skeleton: Skeleton3D, skin: Skin):
	for bind_idx in range(skin.get_bind_count()):
		var bind_name: String = skin.get_bind_name(bind_idx)
		if bind_name.is_empty():
			var bind_bone: int = skin.get_bind_bone(bind_idx)
			if bind_bone > len(skeleton.get_bone_count()):
				push_warning("Failed to find non-named bone bind " + str(bind_bone) + " at index " + str(bind_idx))
				bind_bone = 0
			var bone_name: String = skeleton.get_bone_name(bind_bone)
			skin.set_bind_name(bind_idx, bone_name)


func uniqify_skins(mesh_instances: Array[MeshInstance3D]) -> Array[Skin]:
	var orig_skin_to_skin: Dictionary
	var unique_skins: Array[Skin]
	for mesh_inst in mesh_instances:
		var skel: Skeleton3D = mesh_inst.get_node(mesh_inst.get_skeleton_path()) as Skeleton3D
		if mesh_inst.skin.resource_local_to_scene and mesh_inst.skin.has_meta(&"orig_skin"):
			# We can assume this is not referencing a different scene file, so it is mutable
			if not orig_skin_to_skin.has(mesh_inst.skin):
				convert_to_named_bind(skel, mesh_inst.skin)
				unique_skins.append(mesh_inst.skin)
			orig_skin_to_skin[mesh_inst.skin] = mesh_inst.skin
		else:
			if orig_skin_to_skin.has(mesh_inst.skin):
				mesh_inst.skin = orig_skin_to_skin[mesh_inst.skin] as Skin
			else:
				var new_skin: Skin = mesh_inst.skin.duplicate() as Skin
				convert_to_named_bind(skel, new_skin)
				new_skin.resource_local_to_scene = true
				new_skin.set_meta(&"orig_skin", mesh_inst.skin)
				orig_skin_to_skin[mesh_inst.skin] = new_skin
				mesh_inst.skin = new_skin
				unique_skins.append(new_skin)
	return unique_skins


func attach_skeleton(skel_arg: Skeleton3D):
	target_skel = skel_arg
	if target_skel == null:
		return
	# Godot will logspam errors and corrupt NodePath to ^"" before we even get to _exit_tree, so we store strings instead.
	my_path_from_skel = str(target_skel.get_path_to(self))
	#print(my_path_from_skel)
	var old_rest = target_skel.show_rest_only
	target_skel.show_rest_only = true

	# Godot bone attachments are incredibly buggy and not unsetting a skeleton could crash godot with
	# "ERROR: Cannot update external skeleton cache: Skeleton3D Nodepath does not point to a Skeleton3D node!"
	# So I will disable them for now...
	bone_attachments = find_bone_attachments(target_skel)
	mesh_instances = find_mesh_instances(target_skel)
	unique_skins = uniqify_skins(mesh_instances)

	#target_skel.reset_bone_poses()

	var required_bones: Dictionary
	for attachment in bone_attachments:
		# Some models such as PhantomVenus create a bone which is only referenced by a BoneAttachment3D
		required_bones[attachment.bone_name] = []
	for skin in unique_skins:
		var orig_skin = skin.get_meta(&"orig_skin")
		for bind_idx in range(skin.get_bind_count()):
			var bind_name: String = skin.get_bind_name(bind_idx)
			if not required_bones.has(bind_name):
				required_bones[bind_name] = []
			required_bones[bind_name].append(skin)
			var target_bone_idx := target_skel.find_bone(bind_name)
			var my_bone_idx := find_bone(bind_name)
			#if target_bone_idx != -1 and my_bone_idx != -1:
				#set_bone_pose_position(my_bone_idx, target_skel.get_bone_pose_position(target_bone_idx))
				#set_bone_pose_rotation(my_bone_idx, target_skel.get_bone_pose_rotation(target_bone_idx))
				#set_bone_pose_scale(my_bone_idx, target_skel.get_bone_pose_scale(target_bone_idx)) # should always be 1,1,1

	if not target_skel.has_meta(&"merged_skeleton_bone_owners"):
		target_skel.set_meta(&"merged_skeleton_bone_owners", {})
	var bone_owners: Dictionary = target_skel.get_meta(&"merged_skeleton_bone_owners")
	var added_to_owners: Dictionary
	# var prof := SkeletonProfileHumanoid.new()

	for bone_key in required_bones:
		var bone := bone_key as String
		if DEBUG_SKEL_ERRORS: push_warning("find_bone " + str(bone))
		var bone_idx: int = find_bone(bone)
		if bone_idx == -1:
			push_warning("Failed to lookup bone " + str(bone) + " from skin bind.")
			continue
		var bone_chain_to_add: Array[int]
		while true:
			if DEBUG_SKEL_ERRORS: push_warning("get_bone_name " + str(bone_idx))
			var bone_name: String = get_bone_name(bone_idx)
			if DEBUG_SKEL_ERRORS: push_warning("find_bone " + str(bone_name))
			if target_skel.find_bone(bone_name) != -1:
				if not bone_owners.has(bone_name) or added_to_owners.has(bone_idx):
					break
				added_to_owners[bone_idx] = true
				if not bone_owners[bone_name].has(my_path_from_skel):
					bone_owners[bone_name][my_path_from_skel] = true
				continue
			bone_chain_to_add.append(bone_idx)
			# Store string here to avoid godot logspam / corruption
			bone_owners[bone_name] = {}
			bone_owners[bone_name][my_path_from_skel] = true
			bone_idx = get_bone_parent(bone_idx)
			if bone_idx == -1:
				break

		bone_chain_to_add.reverse()
		if DEBUG_SKEL_ERRORS: push_warning("get_bone_name " + str(bone_idx))
		if DEBUG_SKEL_ERRORS: push_warning("ts find_bone " + str(get_bone_name(bone_idx)))
		var target_parent_bone_idx: int = target_skel.find_bone(get_bone_name(bone_idx)) 
		for chain_bone_idx in bone_chain_to_add:
			var target_bone_idx: int = target_skel.get_bone_count()
			if DEBUG_SKEL_ERRORS: push_warning("get_bone_name " + str(chain_bone_idx))
			target_skel.add_bone(get_bone_name(chain_bone_idx))
			if target_parent_bone_idx != -1:
				if DEBUG_SKEL_ERRORS: push_warning("ts set_bone_parent " + str(target_bone_idx) + " " + str(target_parent_bone_idx))
				target_skel.set_bone_parent(target_bone_idx, target_parent_bone_idx)
			if DEBUG_SKEL_ERRORS: push_warning("ts set_bone_pose " + str(target_bone_idx))
			target_skel.set_bone_pose_position(target_bone_idx, get_bone_pose_position(chain_bone_idx))
			target_skel.set_bone_pose_rotation(target_bone_idx, get_bone_pose_rotation(chain_bone_idx))
			target_skel.set_bone_pose_scale(target_bone_idx, get_bone_pose_scale(chain_bone_idx))
			target_skel.set_bone_rest(target_bone_idx, get_bone_rest(chain_bone_idx))
			target_parent_bone_idx = target_bone_idx

	target_skel.show_rest_only = old_rest

	update_skin_poses()
	for attachment in bone_attachments:
		if attachment.get_use_external_skeleton():
			var extern_skel: Skeleton3D = attachment.get_node_or_null(attachment.get_external_skeleton()) as Skeleton3D
			if extern_skel == self:
				attachment.set_external_skeleton(attachment.get_path_to(target_skel))
				attachment.bone_idx = target_skel.find_bone(attachment.bone_name)
		elif attachment.get_parent() == self:
			attachment.set_external_skeleton(attachment.get_path_to(target_skel))
			attachment.set_use_external_skeleton(true)
			attachment.bone_idx = target_skel.find_bone(attachment.bone_name)
	print("Merging Bone Attachments: " + str(bone_attachments))

	for mesh_inst in mesh_instances:
		if mesh_inst.get_node_or_null(mesh_inst.get_skeleton_path()) != target_skel:
			mesh_inst.set_skeleton_path(mesh_inst.get_path_to(target_skel))
	print(str(name) + " Merging Mesh Instances: " + str(mesh_instances))


func detach_skeleton():
	#var target_skel := find_ancestor_skeleton()
	#var my_path_from_skel := target_skel.get_path_to(self)
	#var bone_attachments := find_bone_attachments(target_skel)
	#var mesh_instances := find_mesh_instances(target_skel)
	if target_skel == null:
		print(str(name) + " Exiting tree without detaching skeleton")
		return
	scale = Vector3.ONE
	#for bone in get_parentless_bones():
		#set_bone_pose_scale(bone, Vector3.ONE)
	print(str(name) + "Detaching Bone Attachments: " + str(bone_attachments))
	print(str(name) + "Detaching Mesh Instances: " + str(mesh_instances))
	#push_warning("Before bone attachments")
	for attachment in bone_attachments:
		if attachment.get_parent() == self:
			attachment.set_use_external_skeleton(false)
			attachment.set_external_skeleton(NodePath())
			attachment.bone_idx = find_bone(attachment.bone_name)
		else:
			var np: String = ".."
			var par: Node = attachment.get_parent()
			while par != self and par != null:
				np += "/.."
				par = par.get_parent()
			attachment.set_external_skeleton(NodePath(np))
			attachment.bone_idx = find_bone(attachment.bone_name)
	bone_attachments.clear()
	#push_warning("Before mesh instances")

	for mesh_inst in mesh_instances:
		if mesh_inst.get_parent() == self:
			#print(str(mesh_inst.name) + " set to ..")
			mesh_inst.set_skeleton_path(NodePath(".."))
		else:
			var np: String = ".."
			var par: Node = mesh_inst.get_parent()
			while par != self and par != null:
				np += "/.."
				par = par.get_parent()
			#print(str(mesh_inst.name) + " set to " + np)
			mesh_inst.set_skeleton_path(NodePath(np))
	mesh_instances.clear()
	#push_warning("Before get meta")

	for skin in unique_skins:
		var orig_skin = skin.get_meta(&"orig_skin")
		for bind_idx in range(skin.get_bind_count()):
			var bind_name: String = skin.get_bind_name(bind_idx)
			skin.set_bind_pose(bind_idx, orig_skin.get_bind_pose(bind_idx))

	if not target_skel.has_meta(&"merged_skeleton_bone_owners"):
		target_skel.set_meta(&"merged_skeleton_bone_owners", {})
	var bone_owners: Dictionary = target_skel.get_meta(&"merged_skeleton_bone_owners")
	var bones_to_erase: Dictionary
	print("My path is " + str(my_path_from_skel))
	#print(bone_owners)
	for bone_name in bone_owners:
		#print(bone_owners[bone_name])
		if len(bone_owners[bone_name]) == 1 and bone_owners[bone_name].has(my_path_from_skel):
			bones_to_erase[bone_name] = true
		else:
			bone_owners[bone_name].erase(my_path_from_skel)
	print("Removing bones from parent skeleton: " + str(bones_to_erase))
	if not bones_to_erase.is_empty():
		for bone_name in bones_to_erase:
			bone_owners.erase(bone_name)
		#push_warning("Cleared bone owners")
		var bone_positions: PackedVector3Array
		var bone_rotations: Array[Quaternion]
		var bone_scales: PackedVector3Array
		var bone_rests: Array[Transform3D]
		var bone_names: PackedStringArray
		var old_to_new_bone_idx: PackedInt32Array
		var bone_parents: PackedInt32Array
		var new_bone_idx: int = 0
		for bone_idx in range(target_skel.get_bone_count()):
			if not bones_to_erase.has(target_skel.get_bone_name(bone_idx)):
				old_to_new_bone_idx.append(new_bone_idx)
				bone_positions.append(target_skel.get_bone_pose_position(bone_idx))
				bone_rotations.append(target_skel.get_bone_pose_rotation(bone_idx))
				bone_scales.append(target_skel.get_bone_pose_scale(bone_idx))
				bone_rests.append(target_skel.get_bone_rest(bone_idx))
				bone_names.append(target_skel.get_bone_name(bone_idx))
				bone_parents.append(target_skel.get_bone_parent(bone_idx))
				new_bone_idx += 1
			else:
				old_to_new_bone_idx.append(-1)
		#push_warning("Before clear bones")
		target_skel.clear_bones()
		#push_warning("After clear bones")
		for bone_idx in range(len(bone_positions)):
			target_skel.add_bone(bone_names[bone_idx])
			target_skel.set_bone_pose_position(bone_idx, bone_positions[bone_idx])
			target_skel.set_bone_pose_rotation(bone_idx, bone_rotations[bone_idx])
			target_skel.set_bone_pose_scale(bone_idx, bone_scales[bone_idx])
			target_skel.set_bone_rest(bone_idx, bone_rests[bone_idx])
		#print(old_to_new_bone_idx)
		#print(bone_parents)
		for bone_idx in range(len(bone_positions)):
			if bone_parents[bone_idx] != -1:
				if bone_idx > len(bone_parents) or bone_parents[bone_idx] > len(old_to_new_bone_idx) or old_to_new_bone_idx[bone_parents[bone_idx]] == -1:
					push_error("Cannot map old to new parent for " + str(bone_idx) + " " + str(bone_parents[bone_idx]) + " " + str(bone_names[bone_idx]))
				assert(old_to_new_bone_idx[bone_parents[bone_idx]] != -1)
				target_skel.set_bone_parent(bone_idx, old_to_new_bone_idx[bone_parents[bone_idx]])
		#push_warning("Before clear meta")
		if bone_owners.is_empty():
			target_skel.remove_meta(&"merged_skeleton_bone_owners")
		target_skel = null
		unique_skins.clear()
		print(str(name) + " detached from parent skeleton")
	last_pose_positions.resize(0)
	last_pose_rotations.resize(0)
	last_pose_scales.resize(0)


func update_skin_poses():
	updated_skeleton_pose.emit()

	if target_skel == null:
		return
	var changed: bool = false
	last_pose_positions.resize(get_bone_count())
	last_pose_rotations.resize(get_bone_count())
	last_pose_scales.resize(get_bone_count())
	for i in range(get_bone_count()):
		if (last_pose_positions[i] != get_bone_pose_position(i) or
				last_pose_rotations[i] != get_bone_pose_rotation(i) or
				last_pose_scales[i] != get_bone_pose_scale(i)):
			changed = true
			last_pose_positions[i] = get_bone_pose_position(i)
			last_pose_rotations[i] = get_bone_pose_rotation(i)
			last_pose_scales[i] = get_bone_pose_scale(i)
	# Godot may infinite loop if two NOTIFICATION_UPDATE_SKELETON somehow get deferred and we then
	# perform anything that hits the dirty flag (such as set_bone_pose_position or skin changes)
	# To prevent this, we have to abort early to prevent queuing another NOTIFICIATION_UPDATE_SKELETON.
	if not changed:
		return
	# Calculate global_bone_pose
	var my_poses: Array[Transform3D]
	my_poses.resize(get_bone_count())
	var poses_filled: Array[bool]
	poses_filled.resize(get_bone_count())
	var target_poses: Array[Transform3D]
	target_poses.resize(target_skel.get_bone_count())
	var target_poses_filled: Array[bool]
	target_poses_filled.resize(target_skel.get_bone_count())

	for skin in unique_skins:
		var orig_skin = skin.get_meta(&"orig_skin")
		for bind_idx in range(skin.get_bind_count()):
			var bind_name: String = skin.get_bind_name(bind_idx)
			var orig_bind_name: String = orig_skin.get_bind_name(bind_idx) if orig_skin != null else bind_name
			if orig_bind_name.is_empty():
				var bind_bone: int = orig_skin.get_bind_bone(bind_idx)
				if bind_bone > len(get_bone_count()):
					bind_bone = 0
				orig_bind_name = get_bone_name(bind_bone)
			var target_bone_idx := target_skel.find_bone(bind_name)
			var my_bone_idx := find_bone(orig_bind_name)
			if target_bone_idx == -1 or my_bone_idx == -1:
				continue
			# Workaround for get_bone_global_pose
			# var relative_transform := target_skel.get_bone_global_pose(target_bone_idx) * get_bone_global_pose(my_bone_idx).affine_inverse()
			# get_bone_global_pose seems to trigger NOTIFICATION_UPDATE_SKELETON
			# which crashes godot even if this is deferred, so we do it ourselves.
			var bone_stack: Array[int]
			bone_stack.append(my_bone_idx)
			while bone_stack[-1] != -1 and not poses_filled[bone_stack[-1]]:
				var parent_idx := get_bone_parent(bone_stack[-1])
				bone_stack.append(parent_idx)
			while not bone_stack.is_empty():
				var parent_idx := bone_stack[-1]
				bone_stack.pop_back()
				if not bone_stack.is_empty():
					poses_filled[bone_stack[-1]] = true
					if parent_idx == -1:
						my_poses[bone_stack[-1]] = get_bone_pose(bone_stack[-1])
					else:
						my_poses[bone_stack[-1]] = my_poses[parent_idx] * get_bone_pose(bone_stack[-1])
			bone_stack.append(target_bone_idx)
			while bone_stack[-1] != -1 and not target_poses_filled[bone_stack[-1]]:
				var parent_idx := target_skel.get_bone_parent(bone_stack[-1])
				bone_stack.append(parent_idx)
			while not bone_stack.is_empty():
				var parent_idx := bone_stack[-1]
				bone_stack.pop_back()
				if not bone_stack.is_empty():
					target_poses_filled[bone_stack[-1]] = true
					if parent_idx == -1:
						target_poses[bone_stack[-1]] = target_skel.get_bone_rest(bone_stack[-1])
					else:
						target_poses[bone_stack[-1]] = target_poses[parent_idx] * target_skel.get_bone_rest(bone_stack[-1])
			# End get_bone_global_pose_workaround
			var relative_transform := target_poses[target_bone_idx].affine_inverse() * my_poses[my_bone_idx]
			skin.set_bind_pose(bind_idx, relative_transform * orig_skin.get_bind_pose(bind_idx))


func _init():
	if Engine.is_editor_hint():
		if is_inside_tree():
			self.attach_skeleton.call_deferred(find_ancestor_skeleton())
		script_changed.connect(self.detach_skeleton)
	else:
		set_script(null)


func _enter_tree():
	if not Engine.is_editor_hint():
		return
	#print("enter tree")

	attach_skeleton.call_deferred(find_ancestor_skeleton())
	#print("done enter tree")


func _exit_tree():
	if not Engine.is_editor_hint():
		return
	#print("exit tree")

	detach_skeleton.call_deferred()
	#print("done exit tree")


func _notification(what):
	#if what != NOTIFICATION_INTERNAL_PHYSICS_PROCESS:
		#print(what)
	if not Engine.is_editor_hint():
		return
	match what:
		NOTIFICATION_UPDATE_SKELETON:
			# update_skin_poses.call_deferred()
			update_skin_poses()
			pass
		NOTIFICATION_PREDELETE:
			detach_skeleton()


static func adjust_bone_scale(skel: Skeleton3D, target_skel: Skeleton3D, bone_name: String, relative_to_bone: String):
	var bone_idx := skel.find_bone(bone_name)
	var idx := skel.find_bone(relative_to_bone)
	if bone_idx == -1 or idx == -1:
		return
	var chest_pose := Transform3D.IDENTITY
	while idx != -1:
		chest_pose = skel.get_bone_pose(idx) * chest_pose
		idx = skel.get_bone_parent(idx)
	idx = bone_idx
	var hips_pose := Transform3D.IDENTITY
	while idx != -1:
		hips_pose = skel.get_bone_pose(idx) * hips_pose
		idx = skel.get_bone_parent(idx)
	var hips_to_chest_distance: float = hips_pose.origin.distance_to(chest_pose.origin)
	# print("bone " + str(bone_idx) + " at " + str(hips_pose.origin) + " rel " + str(relative_to_bone) + " at " + str(chest_pose.origin) + " length " + str(hips_to_chest_distance))

	var target_position := target_skel.get_bone_global_pose(target_skel.find_bone(bone_name)).origin
	# print("Target position ")
	var target_chest_position := target_skel.get_bone_global_pose(target_skel.find_bone(relative_to_bone)).origin
	var target_hips_to_chest_distance: float = target_position.distance_to(target_chest_position)
	# print("target bone " + str(bone_name) + " at " + str(target_position) + " rel " + str(relative_to_bone) + " at " + str(target_chest_position) + " length " + str(target_hips_to_chest_distance))

	var hips_scale_ratio: float = clampf(target_hips_to_chest_distance / hips_to_chest_distance, 0.5, 2.0)
	var final_scale: Vector3 = hips_scale_ratio * skel.get_bone_pose_scale(bone_idx) # * get_bone_pose_scale(bone_idx) / hips_pose.basis.get_scale()
	# print("RATIO: " + str(hips_scale_ratio) + " orig " + str(skel.get_bone_pose_scale(bone_idx)) + " scale " + str(hips_pose.basis.get_scale()) + " final " + str(final_scale))
	skel.set_bone_pose_scale(bone_idx, final_scale)


static func adjust_pose(skel: Skeleton3D, target_skel: Skeleton3D):
	target_skel.reset_bone_poses()
	skel.reset_bone_poses()
	const BONE_TO_PARENT := {
		# "Chest": "Hips",
		"LeftLowerLeg": "LeftUpperLeg",
		"LeftFoot": "LeftLowerLeg",
		"RightLowerLeg": "RightUpperLeg",
		"RightFoot": "RightLowerLeg",
		"LeftLowerArm": "LeftUpperArm",
		"LeftHand": "LeftLowerArm",
		"RightLowerArm": "RightUpperArm",
		"RightHand": "RightLowerArm",
	}
	const PRESERVE_POSITION_BONES := {
		"Hips": "Root",
		"Head": "Hips",
		"LeftShoulder": "Hips",
		"RightShoulder": "Hips",
		"LeftUpperLeg": "Hips",
		"RightUpperLeg": "Hips",
	}
	for bone in PRESERVE_POSITION_BONES:
		var my_idx: int = skel.find_bone(bone)
		var relative_bone_name: String = PRESERVE_POSITION_BONES[bone]
		if my_idx == -1:
			continue
		var target_bone_idx := target_skel.find_bone(bone)
		var target_pose := target_skel.get_bone_global_pose(target_bone_idx)
		#var target_relative_bone_idx := target_skel.find_bone(relative_bone_name)
		#var target_relative_pose := target_skel.get_bone_global_pose(target_relative_bone_idx)
		var my_parent_idx := skel.get_bone_parent(my_idx)
		var parent_to_relative_bone_pose := Transform3D.IDENTITY
		while my_parent_idx != -1: # and get_bone_name(my_parent_idx) != relative_bone_name:
			parent_to_relative_bone_pose = skel.get_bone_pose(my_parent_idx) * parent_to_relative_bone_pose
			my_parent_idx = skel.get_bone_parent(my_parent_idx)
		# var combined_pose := parent_to_relative_bone_pose.affine_inverse() * target_relative_pose.affine_inverse() * target_pose
		var combined_pose := parent_to_relative_bone_pose.affine_inverse() * target_pose
		skel.set_bone_pose_position(my_idx, combined_pose.origin)
		print("Bone " + str(bone) + " set position to " + str(combined_pose.origin))
		if bone == "Hips":
			if skel.find_bone("Head") != -1:
				adjust_bone_scale(skel, target_skel, "Hips", "Head")
			else:
				adjust_bone_scale(skel, target_skel, "Hips", "Chest")

	for bone in BONE_TO_PARENT:
		var parent_bone_name: String = BONE_TO_PARENT[bone]
		adjust_bone_scale(skel, target_skel, parent_bone_name, bone)


static func preserve_pose(skel: Skeleton3D, target_skel: Skeleton3D):
	for bone in target_skel.get_bone_count():
		var my_bone: int = skel.find_bone(target_skel.get_bone_name(bone))
		if my_bone != -1:
			var pose_adj: Quaternion = Quaternion.IDENTITY
			if not target_skel.show_rest_only:
				pose_adj = target_skel.get_bone_rest(bone).basis.get_rotation_quaternion() * target_skel.get_bone_pose_rotation(bone).inverse()
			if skel.show_rest_only:
				pose_adj *= skel.get_bone_rest(my_bone).basis.get_rotation_quaternion()
			else:
				pose_adj *= skel.get_bone_pose_rotation(my_bone)
			skel.set_bone_pose_rotation(my_bone, pose_adj)
			var position_adj: Vector3 = Vector3.ZERO
			if not target_skel.show_rest_only:
				position_adj = target_skel.get_bone_rest(bone).origin - target_skel.get_bone_pose_position(bone)
			if skel.show_rest_only:
				position_adj += skel.get_bone_rest(my_bone).origin
			else:
				position_adj += skel.get_bone_pose_position(my_bone)
			skel.set_bone_pose_position(my_bone, position_adj)
