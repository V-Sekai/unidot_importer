# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

const object_adapter_class := preload("./object_adapter.gd")
const human_trait_class := preload("./humanoid/human_trait.gd")
var object_adapter_class_inst = object_adapter_class.new()

# NOTE: All new member variables must be copied/added to `func duplicate()`

var owner: Node = null
var scene_contents: Node = null
var body: CollisionObject3D = null
var database: Resource = null  # asset_database instance
var meta: Resource = null  # asset_database.AssetMeta instance
var env: Environment = null

# Dictionary from parent_transform fileID -> convert_scene.Skelley
var skelley_parents: Dictionary
# Dictionary from any transform fileID -> convert_scene.Skelley
var fileID_to_skelley: Dictionary
var skelleys: Dictionary
var skel_ids: Dictionary
var num_skels: int = 0

var active_avatars: Array[AvatarState]
var prefab_state: PrefabState = null

# State shared across recursive instances of scene_node_state.
class PrefabState:
	extends RefCounted
	# Prefab_instance_id -> array[UnidotTransform objects]
	var child_transforms_by_stripped_id: Dictionary = {}.duplicate()
	var transforms_by_parented_prefab: Dictionary = {}.duplicate()
	#var transforms_by_parented_prefab_source_obj: Dictionary = {}.duplicate()
	var components_by_stripped_id: Dictionary = {}.duplicate()
	var gameobjects_by_parented_prefab: Dictionary = {}.duplicate()
	#var gameobjects_by_parented_prefab_source_obj: Dictionary = {}.duplicate()
	var skelleys_by_parented_prefab: Dictionary = {}.duplicate()
	var fileID_to_forced_humanoid_orig_name: Dictionary
	var fileID_to_forced_humanoid_godot_name: Dictionary

	var non_stripped_prefab_references: Dictionary = {}.duplicate()  # some legacy 5.6 thing I think
	var gameobject_name_map: Dictionary = {}.duplicate()
	var prefab_gameobject_name_map: Dictionary = {}.duplicate()

	var main_cameras: Array = [].duplicate()
	var animator_node_to_object: Dictionary = {}.duplicate()

	var lod_groups: Array = [].duplicate()

#var root_nodepath: Nodepath = Nodepath("/")


class AvatarState:
	extends RefCounted

	var crc32 := CRC32.new()
	var humanoid_bone_map_dict: Dictionary # node name -> human name
	var human_bone_to_rotation_delta: Dictionary # human name -> global rotation correction
	var excess_rotation_delta: Transform3D
	var humanoid_skeleton_hip_position: Vector3 = Vector3(0.0, 1.0, 0.0)
	var hips_fileid: int
	var reserved_bone_names: Dictionary



func set_main_name_map(name_map: Dictionary, prefab_name_map: Dictionary = {}):
	meta.gameobject_name_to_fileid_and_children = name_map
	meta.prefab_gameobject_name_to_fileid_and_children = prefab_name_map


func add_prefab_to_parent_transform(gameobject_fileid: int, prefab_id):
	if not meta.transform_fileid_to_prefab_ids.has(gameobject_fileid):
		meta.transform_fileid_to_prefab_ids[gameobject_fileid] = PackedInt64Array().duplicate()
	meta.transform_fileid_to_prefab_ids[gameobject_fileid].append(prefab_id)


func add_name_map_to_prefabbed_transform(gameobject_fileid: int, name_map: Dictionary):
	assert(not meta.transform_fileid_to_children.has(gameobject_fileid))
	meta.transform_fileid_to_children[gameobject_fileid] = name_map


func add_component_map_to_prefabbed_gameobject(gameobject_fileid: int, component_map: Dictionary):
	assert(not meta.gameobject_fileid_to_components.has(gameobject_fileid))
	meta.gameobject_fileid_to_components[gameobject_fileid] = component_map


func add_prefab_rename(gameobject_fileid: int, new_name: String):
	if meta.gameobject_fileid_to_rename.has(gameobject_fileid):
		meta.log_debug(gameobject_fileid, "Duplicate rename for fileid " + str(gameobject_fileid) + " : was " + str(meta.gameobject_fileid_to_rename[gameobject_fileid]) + " is now " + new_name)
	meta.gameobject_fileid_to_rename[gameobject_fileid] = new_name


func get_godot_node(uo: RefCounted) -> Node:
	var np = meta.fileid_to_nodepath.get(uo.fileID, NodePath())
	if np == NodePath():
		np = meta.prefab_fileid_to_nodepath.get(uo.fileID, NodePath())
		if np == NodePath():
			return null
	return scene_contents.get_node(np)


func get_object(fileid: int) -> RefCounted:
	var parsed_asset: RefCounted = meta.parsed.assets.get(fileid)
	if parsed_asset != null and not parsed_asset.is_stripped:
		return parsed_asset
	var utype = meta.fileid_to_utype.get(fileid, -1)
	if utype == -1:
		utype = meta.prefab_fileid_to_utype.get(fileid, -1)
		if utype == -1:
			return null  # Not anywhere in the meta.
	var ret: RefCounted = object_adapter_class_inst.instantiate_unidot_object_from_utype(meta, fileid, utype)
	var np = meta.fileid_to_nodepath.get(fileid, NodePath())
	if np == NodePath():
		np = meta.prefab_fileid_to_nodepath.get(fileid, NodePath())
		if np == NodePath():
			return ret
	var node: Node = scene_contents.get_node(np)
	if node == null:
		return ret
	meta.log_warn(fileid, "Attempting to access unidot_keys of node " + str(node.name))
	if node.has_meta("unidot_keys"):
		var keys: Variant = node.get_meta("unidot_keys")
		if typeof(keys) == TYPE_DICTIONARY:
			ret.keys = keys
	return ret


func get_gameobject(uo: RefCounted) -> RefCounted:
	var gofd: int = meta.get_gameobject_fileid(uo.fileID)
	if gofd == 0:
		return null
	return get_object(gofd)


func get_component(uo: RefCounted, type: String) -> RefCounted:
	var compid: int = meta.get_component_fileid(uo.fileID, type)
	if compid == 0:
		return null
	return get_object(compid)


func get_components(uo: RefCounted, type: String = "") -> Array:
	var fileids: PackedInt64Array = meta.get_components_fileids(uo.fileID, type)
	var ret: Array = [].duplicate()
	for f in fileids:
		ret.push_back(get_object(f))
	return ret


func find_objects_of_type(type: String) -> Array:
	var fileids: PackedInt64Array = meta.find_fileids_of_type(type)
	var ret: Array = [].duplicate()
	for f in fileids:
		ret.push_back(get_object(f))
	return ret


class Skelley:
	extends RefCounted
	var id: int = 0
	var bones: Array[RefCounted]

	var root_bones: Array[RefCounted]
	var fileID_to_orig_name: Dictionary
	var godot_bone_idx_to_orig_name: Dictionary

	var bones_set: Dictionary
	var fileID_to_bone: Dictionary
	var godot_skeleton: Skeleton3D = Skeleton3D.new()
	var skinned_mesh_renderers: Array[RefCounted] # UnidotSkinnedMehsRenderer objects.
	var is_prefabbed_skeleton: bool

	# Temporary private storage:
	var intermediate_bones: Array[RefCounted]
	var intermediates: Dictionary
	var bone0_parent_list: Array[RefCounted]
	var bone0_parents: Dictionary
	var found_prefab_instance: RefCounted = null  # UnidotPrefabInstance

	var skeleton_profile_humanoid := SkeletonProfileHumanoid.new()
	var skeleton_profile_humanoid_bones: Dictionary
	var humanoid_avatar_meta: Resource = null

	func _init():
		for bone_idx in range(skeleton_profile_humanoid.bone_size):
			skeleton_profile_humanoid_bones[skeleton_profile_humanoid.get_bone_name(bone_idx)] = bone_idx


	func initialize(bone0: RefCounted):  # UnidotTransform
		var current_parent: RefCounted = bone0  # UnidotTransform or UnidotPrefabInstance
		var tmp: Array
		intermediates[current_parent.fileID] = current_parent
		intermediate_bones.push_back(current_parent)
		while current_parent != null:
			tmp.push_back(current_parent)
			bone0_parents[current_parent.fileID] = current_parent
			current_parent = current_parent.parent_no_stripped
		# reverse list
		for i in range(len(tmp)):
			bone0_parent_list.push_back(tmp[-1 - i])
		# bone0.log_debug("Initialized " + str(self)+ " ints " + str(intermediates) + " intbones " + str(intermediate_bones) + " b0ps " + str(bone0_parents) + " b0pl " + str(bone0_parent_list))


	func add_bone(bone: RefCounted) -> Array:  # UnidotTransform
		if bone == null:
			push_warning("Got null bone in add_bone")
			return []
		if bones_set.has(bone.fileID):
			#bone.log_warn("Already added bone " + str(bone) + " to " + str(self))
			return []
		#bone.log_debug("added bone " + str(bone) + " to " + str(self))
		bones.push_back(bone)
		bones_set[bone.fileID] = true
		# bone.log_debug("Adding a bone: " + str(bones))
		var added_bones: Array = [].duplicate()
		var current_parent: RefCounted = bone  #### UnidotTransform or UnidotPrefabInstance
		intermediates[current_parent.fileID] = current_parent
		intermediate_bones.push_back(current_parent)
		added_bones.push_back(current_parent)
		current_parent = current_parent.parent_no_stripped
		while current_parent != null and not bone0_parents.has(current_parent.fileID):
			if intermediates.has(current_parent.fileID):
				# bone.log_debug("Already intermediate to add " + str(bone) + "/" + str(current_parent) + " " + str(self)+ " ints " + str(intermediates) + " intbones " + str(intermediate_bones) + " b0ps " + str(bone0_parents) + " b0pl " + str(bone0_parent_list))
				return added_bones
			intermediates[current_parent.fileID] = current_parent
			intermediate_bones.push_back(current_parent)
			added_bones.push_back(current_parent)
			current_parent = current_parent.parent_no_stripped
		if current_parent == null:
			bone.log_warn("Warning: No common ancestor for skeleton " + str(bone) + ": assume parented at root")
			bone0_parents.clear()
			bone0_parent_list.clear()
			return added_bones
		#if current_parent.parent_no_stripped == null:
		#	bone0_parents.clear()
		#	bone0_parent_list.clear()
		#	bone.log_warn("Warning: Skeleton parented at root " + str(bone) + " at " + str(current_parent))
		#	return added_bones
		if bone0_parent_list.is_empty():
			# bone.log_debug("b0pl is empty to add " + str(bone) + "/" + str(current_parent) + " " + str(self)+ " ints " + str(intermediates) + " intbones " + str(intermediate_bones) + " b0ps " + str(bone0_parents) + " b0pl " + str(bone0_parent_list) +": " + str(added_bones))
			return added_bones
		while bone0_parent_list[-1] != current_parent:
			bone0_parents.erase(bone0_parent_list[-1].fileID)
			bone0_parent_list.pop_back()
			if bone0_parent_list.is_empty():
				bone.log_fail("Assertion failure " + str(bones[0]) + "/" + str(current_parent), "parent", current_parent)
				return []
			if not intermediates.has(bone0_parent_list[-1].fileID):
				intermediates[bone0_parent_list[-1].fileID] = bone0_parent_list[-1]
				intermediate_bones.push_back(bone0_parent_list[-1])
				added_bones.push_back(bone0_parent_list[-1])
		#if current_parent.is_stripped and found_prefab_instance == null:
		# If this is child a prefab instance, we want to make sure the prefab instance itself
		# is used for skeleton merging, so that we avoid having duplicate skeletons.
		# WRONG!!! They might be different skelleys in the source prefab.
		#	found_prefab_instance = current_parent.parent_no_stripped
		#	if found_prefab_instance != null:
		#		added_bones.push_back(found_prefab_instance)
		# bone.log_debug("success added " + str(bone) + "/" + str(current_parent) + " " + str(self)+ " ints " + str(intermediates) + " intbones " + str(intermediate_bones) + " b0ps " + str(bone0_parents) + " b0pl " + str(bone0_parent_list) +": " + str(added_bones))
		return added_bones

	# if null, this is not mixed with a prefab's nodes
	var parent_prefab: RefCounted:  # UnidotPrefabInstance
		get:
			if bone0_parent_list.is_empty():
				return null
			var arrlen: int = len(bone0_parent_list) - 1
			var pref: RefCounted = bone0_parent_list[arrlen]  # UnidotTransform or UnidotPrefabInstance
			if pref.type == "PrefabInstance":
				return pref
			return null

	# if null, this is a root node.
	var parent_transform: RefCounted:  # UnidotTransform
		get:
			if bone0_parent_list.is_empty():
				return null
			var arrlen: int = len(bone0_parent_list) - 1
			var pref: RefCounted = bone0_parent_list[arrlen]  # UnidotTransform or UnidotPrefabInstance
			if pref.type == "Transform":
				return pref
			return null

	func add_nodes_recursively(skel_parents: Dictionary, child_transforms_by_stripped_id: Dictionary, bone_transform: RefCounted):
		if bone_transform.is_stripped:
			#bone_transform.log_warn("Not able to add skeleton nodes from a stripped transform!")
			for child in child_transforms_by_stripped_id.get(bone_transform.fileID, []):
				if not intermediates.has(child.fileID):
					child.log_debug("Adding child bone " + str(child) + " into intermediates during recursive search from " + str(bone_transform))
					intermediates[child.fileID] = child
					intermediate_bones.push_back(child)
					# TODO: We might also want to exclude prefab instances here.
					# If something is a prefab, we should not include it in the skeleton!
					if not skel_parents.has(child.fileID):
						# We will not recurse: everything underneath this is part of a separate skeleton.
						add_nodes_recursively(skel_parents, child_transforms_by_stripped_id, child)
			return
		for child_ref in bone_transform.children_refs:
			var child: RefCounted = bone_transform.meta.lookup(child_ref)  # UnidotTransform
			# child.log_debug("Try child " + str(child_ref))
			# not skel_parents.has(child.fileID):
			if not intermediates.has(child.fileID):
				child.log_debug("Adding child bone " + str(child) + " into intermediates during recursive search from " + str(bone_transform))
				intermediates[child.fileID] = child
				intermediate_bones.push_back(child)
				# TODO: We might also want to exclude prefab instances here.
				# If something is a prefab, we should not include it in the skeleton!
				if not skel_parents.has(child.fileID):
					# We will not recurse: everything underneath this is part of a separate skeleton.
					add_nodes_recursively(skel_parents, child_transforms_by_stripped_id, child)

	func construct_final_bone_list(skel_parents: Dictionary, child_transforms_by_stripped_id: Dictionary):
		var par_transform: RefCounted = bone0_parent_list[-1]  # UnidotTransform or UnidotPrefabInstance
		if par_transform == null:
			push_error("Final bone list transform is null!")
			return
		var par_key: int = par_transform.fileID
		var contains_stripped_bones: bool = false
		for bone in bone0_parent_list:
			bone.log_debug("Removing parent bone " + str(bone) + " from intermediates")
			intermediates.erase(bone.fileID)
		for bone in intermediate_bones:
			if bone.is_stripped_or_prefab_instance():
				root_bones.push_back(bone)
				continue
			if bone.parent_no_stripped == null or bone.parent_no_stripped.fileID == par_key:
				root_bones.push_back(bone)
		# par_transform.log_debug("Construct final bone list bones: " + str(bones))
		for bone in bones.duplicate():
			bone.log_debug("Skelley " + str(par_transform) + " has root bone " + str(bone))
			self.add_nodes_recursively(skel_parents, child_transforms_by_stripped_id, bone)
		# Keep original bone list in order; migrate intermediates in.
		for bone in bones:
			intermediates.erase(bone.fileID)
		bones[0].log_debug("intermediates: " + str(intermediates))
		for bone in intermediate_bones:
			if bone.is_stripped_or_prefab_instance():
				# We do not explicitly add stripped bones if they are not already present.
				# FIXME: Do cases exist in which we are required to add intermediate stripped bones?
				bone.log_warn("Unable to add stripped intermediate " + str(bone))
				continue
			if intermediates.has(bone.fileID):
				if bones_set.has(bone.fileID):
					bone.log_warn("Already added intermediate bone " + str(bone))
				else:
					bones_set[bone.fileID] = true
					bone.log_debug("Adding intermediate bone " + str(bone))
					bones.push_back(bone)
		var idx: int = 0
		for bone in bones:
			if bone.is_stripped_or_prefab_instance():
				# We do not know yet the full extent of the skeleton
				fileID_to_bone[bone.fileID] = -1
				bone.log_debug("bone " + str(bone) + " is stripped " + str(bone.is_stripped) + " or prefab instance. CLEARING SKELETON")
				is_prefabbed_skeleton = true
				contains_stripped_bones = true
				if godot_skeleton != null:
					godot_skeleton.queue_free()
					godot_skeleton = null
				continue
			if bone.parent_no_stripped.is_stripped_or_prefab_instance():
				is_prefabbed_skeleton = true
				contains_stripped_bones = true
				if godot_skeleton != null:
					godot_skeleton.queue_free()
					godot_skeleton = null
			fileID_to_bone[bone.fileID] = idx
			bone.skeleton_bone_index = idx
			var go: Object = bone.get_gameObject()
			if go != null:
				var animator: Object = go.GetComponent("Animator")
				if animator != null:
					var ava_meta = animator.get_avatar_meta()
					if ava_meta != null:
						humanoid_avatar_meta = ava_meta
			idx += 1

		if humanoid_avatar_meta != null and godot_skeleton != null:
			godot_skeleton.name = "GeneralSkeleton"
		if not contains_stripped_bones:
			var dedupe_dict = {}.duplicate()
			for bone_i in range(godot_skeleton.get_bone_count()):
				dedupe_dict[godot_skeleton.get_bone_name(bone_i)] = null
			for bone in bones:
				if not dedupe_dict.has(bone.name):
					dedupe_dict[bone.name] = bone
			idx = 0
			for bone in bones:
				var ctr: int = 0
				var orig_bone_name: String = bone.name
				var bone_name: String = orig_bone_name
				while dedupe_dict.get(bone_name) != bone:
					ctr += 1
					bone_name = orig_bone_name + " " + str(ctr)
					if not dedupe_dict.has(bone_name):
						dedupe_dict[bone_name] = bone
				godot_skeleton.add_bone(bone_name)
				godot_bone_idx_to_orig_name[idx] = fileID_to_orig_name.get(bone.fileID, orig_bone_name)
				bone.log_debug("Godot Skeleton adding bone " + str(bone) + " " + bone_name + " orig name " + str(godot_bone_idx_to_orig_name[idx]) + " idx " + str(idx) + " new size " + str(godot_skeleton.get_bone_count()))
				idx += 1
			idx = 0
			for bone in bones:
				if bone.parent_no_stripped == null:
					godot_skeleton.set_bone_parent(idx, -1)
				else:
					godot_skeleton.set_bone_parent(idx, fileID_to_bone.get(bone.parent_no_stripped.fileID, -1))
				# godot_skeleton.set_bone_rest(idx, bone.godot_transform)
				idx += 1
	# Skelley rules:
	# Root bone will be added as parent to common ancestor of all bones
	# Found parent transforms of each skeleton.
	# Found a list of bones in each skeleton.

	func merge_independent_sibling_skelley(other: Skelley, state: RefCounted):
		other.bones[0].log_debug("Merging independent skelley " + str(self) + "@" + str(self.id) + " with " + str(other) + "@" + str(other.id))
		for bone in other.root_bones:
			if not bones_set.has(bone.fileID):
				root_bones.append(bone)
		for bone in other.intermediate_bones:
			if not bones_set.has(bone.fileID):
				intermediate_bones.append(bone)
		for bone in other.bones:
			if not bones_set.has(bone.fileID):
				bones.append(bone)
		for fileID in other.bones_set:
			if not bones_set.has(fileID):
				bones_set[fileID] = other.bones_set[fileID]
		for other_fileID in other.fileID_to_orig_name:
			fileID_to_orig_name[other_fileID] = other.fileID_to_orig_name[other_fileID]
			state.fileID_to_skelley[other_fileID] = self
			state.skel_ids[other_fileID] = id
		for fileID in other.fileID_to_bone:
			state.fileID_to_skelley[fileID] = self
		var my_bone_count: int = godot_skeleton.get_bone_count()
		var existing_bone_idx: Dictionary
		var new_bone_to_fileid: Dictionary
		if other.godot_skeleton != null:
			for fileID in other.fileID_to_bone:
				if fileID_to_bone.has(fileID):
					existing_bone_idx[other.fileID_to_bone[fileID]] = fileID_to_bone[fileID]
					other.bones[0].log_debug("Fileid to bone " + str(fileID) + " " + str(fileID_to_bone[fileID]) + " => " + str(other.fileID_to_bone[fileID]))
				else:
					new_bone_to_fileid[other.fileID_to_bone[fileID]] = fileID
					other.bones[0].log_debug("new_bone_to_fileid[" + str(other.fileID_to_bone[fileID]) + "] = " + str(fileID))
			var num_added_bones: int = 0
			for other_bone_idx in range(other.godot_skeleton.get_bone_count()):
				if not existing_bone_idx.has(other_bone_idx):
					godot_skeleton.add_bone(other.godot_skeleton.get_bone_name(other_bone_idx))
					other.bones[0].log_debug("bone " + str(other.godot_skeleton.get_bone_name(other_bone_idx)) + " new_bone_to_fileid[" + str(other_bone_idx) + "] = " + str(new_bone_to_fileid.get(other_bone_idx, "NONE")) + " => " + str(num_added_bones + my_bone_count))
					continue
					fileID_to_bone[new_bone_to_fileid[other_bone_idx]] = num_added_bones + my_bone_count
					var other_parent: int = other.godot_skeleton.get_bone_parent(other_bone_idx)
					if other_parent != -1:
						if existing_bone_idx.has(other_parent):
							godot_skeleton.set_bone_parent(my_bone_count + num_added_bones, existing_bone_idx[other_parent])
						else:
							godot_skeleton.set_bone_parent(my_bone_count + num_added_bones, my_bone_count + other_parent)
					if other.godot_bone_idx_to_orig_name.has(other_bone_idx):
						godot_bone_idx_to_orig_name[my_bone_count + num_added_bones] = other.godot_bone_idx_to_orig_name[other_bone_idx]
					num_added_bones += 1
		skinned_mesh_renderers.append_array(other.skinned_mesh_renderers)
		for bone in other.intermediates:
			intermediates[bone] = other.intermediates[bone]
		if other.humanoid_avatar_meta and not humanoid_avatar_meta:
			humanoid_avatar_meta = other.humanoid_avatar_meta
		if other.godot_skeleton != null:
			other.godot_skeleton.queue_free()
		state.skelleys.erase(other.id)
		is_prefabbed_skeleton = is_prefabbed_skeleton or other.is_prefabbed_skeleton
		if other.parent_prefab != null:
			var uk: int = other.parent_prefab.fileID
			if state.prefab_state.skelleys_by_parented_prefab.has(uk):
				state.prefab_state.skelleys_by_parented_prefab[uk].erase(other)
		if other.parent_transform != null:
			var fileID = other.parent_transform.fileID
			if state.skelley_parents[fileID] == other:
				state.skelley_parents[fileID] = self
		assert(found_prefab_instance == other.found_prefab_instance)


func _init(database: Resource, meta: Resource, root_node: Node3D):
	init_node_state(database, meta, root_node)


func duplicate() -> RefCounted:
	var state = get_script().new(database, meta, owner)
	state.env = env
	state.body = body
	state.skelley_parents = skelley_parents
	state.fileID_to_skelley = fileID_to_skelley
	state.prefab_state = prefab_state
	state.active_avatars = active_avatars
	state.scene_contents = scene_contents

	return state


func add_child(child: Node, new_parent: Node3D, obj: RefCounted):
	# meta. # FIXME???
	if owner != null:
		if new_parent == null:
			meta.log_warn(0, "Trying to add child " + str(child) + " named " + str(child.name) + " to null parent " + str(obj), "parent")
		assert(new_parent != null)
		new_parent.add_child(child, true)
		child.owner = owner
	if new_parent == null:
		assert(owner == null)
		# We are the root (of a Prefab). Become the owner.
		owner = child
		if scene_contents == null:
			scene_contents = child
	else:
		assert(owner != null)
	if obj != null and obj.fileID != 0:
		add_fileID(child, obj)


func add_fileID_to_skeleton_bone(bone_name: String, fileID: int):
	meta.fileid_to_skeleton_bone[fileID] = bone_name


func remove_fileID_to_skeleton_bone(fileID: int):
	meta.fileid_to_skeleton_bone[fileID] = ""


func add_fileID(child: Node, obj: RefCounted):
	if owner != null:
		obj.log_debug("Add fileID " + str(obj.fileID) + " '" + str(obj.get_debug_name()) + "' type " + str(obj.utype) + " " + str(owner.name) + " to " + str(child.name))
		meta.fileid_to_nodepath[obj.fileID] = scene_contents.get_path_to(child)
	# FIXME??
	#else:
	#	meta.fileid_to_nodepath[fileID] = root_nodepath


func init_node_state(database: Resource, meta: Resource, root_node: Node3D) -> RefCounted:
	self.database = database
	self.meta = meta
	self.owner = root_node
	self.scene_contents = root_node
	self.prefab_state = PrefabState.new()
	return self


func state_with_body(new_body: CollisionObject3D) -> RefCounted:
	var state = duplicate()
	state.body = new_body
	return state


func state_with_avatar_meta(avatar_meta: Object) -> RefCounted:
	if not avatar_meta.is_humanoid():
		return self
	var state = duplicate()
	var avatar_state := AvatarState.new()
	for bone in human_trait_class.GodotHumanNames:
		avatar_state.reserved_bone_names[bone] = true
	avatar_state.reserved_bone_names["Root"] = true
	#avatar_state.current_avatar_object = new_avatar
	avatar_state.humanoid_bone_map_dict = avatar_meta.humanoid_bone_map_crc32_dict.duplicate()
	var has_root: bool = false
	if avatar_meta.humanoid_bone_map_crc32_dict.is_empty():
		for orig_bone_name in avatar_meta.autodetected_bone_map_dict:
			if not avatar_meta.autodetected_bone_map_dict[orig_bone_name] == "Root" or avatar_meta.internal_data.get("humanoid_root_bone", "").is_empty():
				avatar_state.humanoid_bone_map_dict[avatar_state.crc32.crc32(orig_bone_name)] = avatar_meta.autodetected_bone_map_dict[orig_bone_name]
		#	if avatar_meta.internal_data.get("humanoid_root_bone", "") == orig_bone_name:
		#		avatar_state.humanoid_bone_map_dict[avatar_state.crc32.crc32(orig_bone_name)] = "Root"
		for orig_bone_name in avatar_meta.humanoid_bone_map_dict:
			avatar_state.humanoid_bone_map_dict[avatar_state.crc32.crc32(orig_bone_name)] = avatar_meta.humanoid_bone_map_dict[orig_bone_name]
	#for crc in avatar_state.humanoid_bone_map_dict:
	#	if avatar_state.humanoid_bone_map_dict[crc] == "Root":
	#		has_root = true
	if not has_root:
		avatar_state.humanoid_bone_map_dict["Root"] = "Root"

	avatar_state.humanoid_skeleton_hip_position = avatar_meta.humanoid_skeleton_hip_position

	var transform_fileid_to_rotation_delta: Dictionary = avatar_meta.transform_fileid_to_rotation_delta
	var fileid_to_skeleton_bone: Dictionary = avatar_meta.fileid_to_skeleton_bone
	var human_bone_to_rotation_delta: Dictionary

	var parent_fileid: int = 0

	for i in transform_fileid_to_rotation_delta:
		if fileid_to_skeleton_bone.has(i):
			if fileid_to_skeleton_bone[i] == "Hips":
				parent_fileid = i
			human_bone_to_rotation_delta[fileid_to_skeleton_bone[i]] = transform_fileid_to_rotation_delta[i]

	avatar_state.human_bone_to_rotation_delta = human_bone_to_rotation_delta
	state.active_avatars.push_back(avatar_state)

	return state

func apply_excess_rotation_delta(node: Node3D, fileID: int):
	for avatar_state in active_avatars:
		if not avatar_state.excess_rotation_delta.is_equal_approx(Transform3D.IDENTITY):
			if meta.transform_fileid_to_parent_fileid.has(fileID) or meta.prefab_transform_fileid_to_parent_fileid.has(fileID):
				var parent_fileid: int = meta.transform_fileid_to_parent_fileid.get(fileID, meta.prefab_transform_fileid_to_parent_fileid.get(fileID))
				var rotation_delta: Transform3D
				if meta.transform_fileid_to_rotation_delta.has(parent_fileid) or meta.prefab_transform_fileid_to_rotation_delta.has(parent_fileid):
					rotation_delta = meta.transform_fileid_to_rotation_delta.get(parent_fileid, meta.prefab_transform_fileid_to_rotation_delta.get(parent_fileid))
				rotation_delta *= avatar_state.excess_rotation_delta
			meta.log_debug(0, "Applying excess rotation delta to node " + str(node.name) + ": " + str(avatar_state.excess_rotation_delta))

var last_humanoid_skeleton_hip_position: Vector3 = Vector3(0.0, 1.0, 0.0)

func _find_next_avatar_bone_recursive(skelley: Skelley, skel: Skeleton3D, bone_idx: int) -> String:
	for avatar in active_avatars:
		var orig_bone_name: String = skelley.godot_bone_idx_to_orig_name.get(bone_idx, skel.get_bone_name(bone_idx))
		var crc32_name := avatar.crc32.crc32(orig_bone_name)
		meta.log_debug(0, "searching bone " + str(bone_idx) + " bone_name=" + str(skel.get_bone_name(bone_idx)) + " orig name=" + str(orig_bone_name) + " crc " + str(crc32_name) + " humanoid " + str(avatar.humanoid_bone_map_dict.get(crc32_name)))
		if avatar.humanoid_bone_map_dict.has(crc32_name):
			return avatar.humanoid_bone_map_dict[crc32_name]
	for child_idx in skel.get_bone_children(bone_idx):
		var ret: String = _find_next_avatar_bone_recursive(skelley, skel, child_idx)
		if ret != "":
			meta.log_debug(0, "Found a bone " + ret)
			return ret
	return ""

func consume_avatar_bone(orig_bone_name: String, godot_bone_name: String, fileid: int, skelley: Skelley, bone_idx: int) -> String:
	var skel: Skeleton3D = skelley.godot_skeleton
	apply_excess_rotation_delta(skel, fileid)
	var name_to_return: String = ""
	var forced_orig_name: String = prefab_state.fileID_to_forced_humanoid_orig_name.get(fileid, "")
	var bone_name_forced: bool = false
	if (not forced_orig_name.is_empty() and forced_orig_name != orig_bone_name) or prefab_state.fileID_to_forced_humanoid_godot_name.get(fileid, orig_bone_name) != orig_bone_name:
		godot_bone_name = prefab_state.fileID_to_forced_humanoid_godot_name.get(fileid, orig_bone_name)
		meta.log_debug(fileid, "Avatar bone " + str(orig_bone_name) + " mapped to original name " + forced_orig_name + " godot name " + str(godot_bone_name))
		if not forced_orig_name.is_empty():
			orig_bone_name = forced_orig_name
		else:
			orig_bone_name = godot_bone_name
		bone_name_forced = true
	meta.log_debug(fileid, "consume avatar bone " + str(orig_bone_name) + " " + str(godot_bone_name) + " for skel " + str(skel) + ":" + str(skel.get_bone_name(bone_idx)))
	for avatar in active_avatars:
		var crc32_name := avatar.crc32.crc32(orig_bone_name)
		if godot_bone_name == "Hips":
			meta.log_debug(fileid, "Hips position " + str(avatar.humanoid_skeleton_hip_position) + " crc32=" + str(crc32_name) + " | " + str(avatar.humanoid_bone_map_dict.get(crc32_name)))
		if avatar.humanoid_bone_map_dict.has(crc32_name):
			if name_to_return.is_empty():
				name_to_return = avatar.humanoid_bone_map_dict[crc32_name]
				godot_bone_name = name_to_return
				if godot_bone_name == "Hips":
					avatar.hips_fileid = fileid
					last_humanoid_skeleton_hip_position = avatar.humanoid_skeleton_hip_position
			avatar.humanoid_bone_map_dict.erase(crc32_name)
		var par_fileid: int = fileid
		while par_fileid != 0 and par_fileid != avatar.hips_fileid:
			par_fileid = meta.transform_fileid_to_parent_fileid.get(par_fileid, 0)
		if avatar.human_bone_to_rotation_delta.has(godot_bone_name):
			meta.log_debug(fileid, "AVA PREFAB Using avatar " + str(orig_bone_name) + "/" + str(godot_bone_name) + " for rotation delta! " + str(avatar.human_bone_to_rotation_delta[godot_bone_name]))
			meta.transform_fileid_to_rotation_delta[fileid] = avatar.human_bone_to_rotation_delta[godot_bone_name]
		elif par_fileid == 0: # Not a decendent of the Hips bone
			if avatar.human_bone_to_rotation_delta.has("Root"):
				meta.log_debug(fileid, "AVA PREFAB Using Root for rotation delta of " + str(orig_bone_name) + "/" + str(godot_bone_name) + "!")
				meta.transform_fileid_to_rotation_delta[fileid] = avatar.human_bone_to_rotation_delta["Root"]
			elif avatar.human_bone_to_rotation_delta.has("Hips"):
				meta.log_debug(fileid, "AVA PREFAB Using Hips for rotation delta of " + str(orig_bone_name) + "/" + str(godot_bone_name) + "!")
				meta.transform_fileid_to_rotation_delta[fileid] = avatar.human_bone_to_rotation_delta["Hips"]
	if name_to_return == "":
		if bone_name_forced:
			name_to_return = godot_bone_name
		var has_root: bool = false
		for avatar in active_avatars:
			if avatar.humanoid_bone_map_dict.has("Root"):
				has_root = true
		if has_root:
			var next_bone: String = _find_next_avatar_bone_recursive(skelley, skel, bone_idx)
			meta.log_debug(fileid, "Found next bone " + next_bone)
			if next_bone == "Hips":
				for avatar in active_avatars:
					if avatar.humanoid_bone_map_dict.has("Root"):
						name_to_return = "Root"
						avatar.humanoid_bone_map_dict.erase("Root")
	if skelley.is_prefabbed_skeleton:
		# It is expected that all avatar bones are in the parent scene.
		# Avatar state is not preserved across scenes leading us to re-consume a bone and rename an inherited bone to "Hips 1" for example.
		name_to_return = ""
	return name_to_return

func consume_root(fileid: int) -> bool:
	var ret: bool = false
	for avatar in active_avatars:
		if avatar.humanoid_bone_map_dict.has("Root"):
			meta.log_debug(fileid, "Consumed Root at " + str(fileid))
			avatar.humanoid_bone_map_dict.erase("Root")
			ret = true
			if avatar.human_bone_to_rotation_delta.has("Root"):
				meta.log_debug(fileid, "Root at " + str(fileid) + " has rotation delta " + str(avatar.human_bone_to_rotation_delta["Root"]))
				meta.transform_fileid_to_rotation_delta[fileid] = avatar.human_bone_to_rotation_delta.get("Hips", Transform3D.IDENTITY)
			elif meta.transform_fileid_to_parent_fileid.has(fileid):
				var parent_fileid: int = meta.transform_fileid_to_parent_fileid[fileid]
				if meta.transform_fileid_to_rotation_delta.has(parent_fileid):
					meta.transform_fileid_to_rotation_delta[fileid] = meta.transform_fileid_to_rotation_delta[parent_fileid]
	return ret

func is_bone_name_reserved(bone_name: String) -> bool:
	for avatar_state in active_avatars:
		return avatar_state.reserved_bone_names.has(bone_name)
	return false

func state_with_meta(new_meta: Resource) -> RefCounted:
	var state = duplicate()
	state.meta = new_meta
	return state


func state_with_owner(new_owner: Node3D) -> RefCounted:
	var state = duplicate()
	state.owner = new_owner
	if state.scene_contents == null:
		state.scene_contents = new_owner
	return state


#func state_with_nodepath(additional_nodepath) -> RefCounted:
#	var state = duplicate()
#	state.root_nodepath = NodePath(str(root_nodepath) + str(asdditional_nodepath) + "/")
#	return state


func add_bone_to_skelley(this_skelley: Skelley, bone_obj: RefCounted) -> Skelley:
	var added_bones = this_skelley.add_bone(bone_obj)
	var this_id: int = this_skelley.id

	# asset.log_debug("Told skelley " + str(this_id) + " to add bone " + str(bone_obj) + ": " + str(added_bones))
	for added_bone in added_bones:
		var fileID: int = added_bone.fileID
		if skel_ids.get(fileID, this_id) != this_id:
			# We found a match! Let's merge the Skelley objects.
			var new_id: int = skel_ids[fileID]
			# asset.log_debug("migrating from " + str(skelleys[this_id].bones))
			for inst in skelleys[this_id].bones:
				# asset.log_debug("Loop " + str(inst.fileID) + " skelley " + str(this_id) + " -> " + str(skel_ids.get(inst.fileID, -1)))
				if skel_ids.get(inst.fileID, -1) == this_id:  # FIXME: This seems to be missing??
					# asset.log_debug("Telling skelley " + str(new_id) + " to merge bone " + str(inst))
					if not skelleys.has(new_id):
						bone_obj.log_fail("Skelleys missing " + str(new_id) + " from " + str(inst) + " thisid " + str(this_id))
					skelleys[new_id].add_bone(inst)
			if skelleys[new_id].humanoid_avatar_meta == null:
				skelleys[new_id].humanoid_avatar_meta = skelleys[this_id].humanoid_avatar_meta
			for i in skel_ids:
				if skel_ids.get(i) == this_id:
					skel_ids[i] = new_id
			skelleys.erase(this_id)  # We merged two skeletons.
			this_id = new_id
			this_skelley = skelleys[this_id]
		skel_ids[fileID] = this_id
		# asset.log_debug("Skel ids now " + str(skel_ids))
	return this_skelley


func create_skelley(bone0_obj: RefCounted) -> Skelley:
	var this_id: int = num_skels
	var this_skelley := Skelley.new()
	this_skelley.initialize(bone0_obj)
	bone0_obj.log_debug("Initialized Skelley at bone " + str(bone0_obj))
	this_skelley.id = this_id
	skelleys[this_id] = this_skelley
	num_skels += 1
	return this_skelley

func initialize_skelleys(assets: Array, is_prefab: bool) -> Array:

	var child_transforms_by_stripped_id: Dictionary = prefab_state.child_transforms_by_stripped_id

	# Start out with one Skeleton per SkinnedMeshRenderer, but merge overlapping skeletons.
	# This includes skeletons where the members are interleaved (S1 -> S2 -> S1 -> S2)
	# which can actually happen in practice, for example clothing with its own bones.
	for asset in assets:
		if asset.type == "SkinnedMeshRenderer":
			if asset.is_stripped:
				# FIXME: We may need to later pull out the "m_Bones" from the modified components??
				continue
			var orig_bones: Array = asset.bones
			var bones: Array = []
			asset.log_debug("Importing mesh " + str(asset) + ": " + str(orig_bones))
			for b in orig_bones:
				if asset.meta.lookup(b) == null:
					continue
				bones.append(b)
			if bones.is_empty():
				# Common if MeshRenderer is upgraded to SkinnedMeshRenderer, e.g. by the user.
				# For example, this happens when adding a Cloth component.
				# Also common for meshes which have blend shapes but no skeleton.
				# Skinned mesh renderers without bones act as normal meshes.
				if not orig_bones.is_empty():
					asset.log_fail("Failed to lookup bone references for " + str(asset))
				continue
			var bone0_obj: RefCounted = asset.meta.lookup(bones[0])  # UnidotTransform
			# TODO: what about meshes with bones but without skin? Can this even happen?
			if bone0_obj == null:
				asset.log_warn("ERROR: Importing model " + asset.meta.guid + " at " + asset.meta.path + ": " + str(bones[0]) + " is null")
			var this_id: int = num_skels
			var this_skelley: Skelley = null
			if skel_ids.has(bone0_obj.fileID):
				# asset.log_debug("Found an existing skelley for " + str(bone0_obj) + ": " + str(skel_ids[bone0_obj.fileID]))
				if not skelleys.has(skel_ids[bone0_obj.fileID]):
					asset.log_fail("Skelleys missing " + str(bone0_obj) + " " + str(skel_ids[bone0_obj.fileID]) + ": " + str(skelleys))
			if skel_ids.has(bone0_obj.fileID) and skelleys.has(skel_ids[bone0_obj.fileID]):
				this_id = skel_ids[bone0_obj.fileID]
				this_skelley = skelleys[this_id]
			else:
				this_skelley = create_skelley(bone0_obj)

			var mesh_ref = asset.get_mesh()
			var mesh_meta = asset.meta.lookup_meta(mesh_ref)
			var forced_avatar_meta = null
			if mesh_meta != null:
				if mesh_meta.is_humanoid():
					if asset.meta.is_force_humanoid():
						var bone_map_dict: Dictionary = {}
						if mesh_meta.importer.type == "ModelImporter":
							var bone_map: BoneMap = mesh_meta.importer.generate_bone_map_from_human()
							for prop in bone_map.get_property_list():
								if prop["name"].begins_with("bone_map/"):
									var prof_name: String = prop["name"].trim_prefix("bone_map/")
									bone_map_dict[prof_name] = bone_map.get_skeleton_bone_name(prof_name)
						else:
							asset.log_warn("Mesh using ModelImporter")
						var orig_skin: Skin = asset.meta.get_godot_resource([null, -mesh_ref[1], mesh_ref[2], 0])
						if orig_skin == null:
							asset.log_warn("Failed to lookup original skin for " + str(asset) + " ref " + str(mesh_ref))
						else:
							var meta_godot_to_orig_bone_names: Dictionary = mesh_meta.internal_data.get("godot_sanitized_to_orig_remap", {}).get("bone_name", {})
							for idx in range(len(orig_bones)):
								var bind_name: String = orig_skin.get_bind_name(idx)
								asset.log_debug("Skin bind " + str(idx) + " Humanoid original name for " + str(orig_bones[idx][1]) + " (" + str(asset.meta.lookup(orig_bones[idx])) + ") is " + bind_name)
								prefab_state.fileID_to_forced_humanoid_godot_name[orig_bones[idx][1]] = bind_name
								var orig_bind_name: String = bone_map_dict.get(bind_name, bind_name)
								if meta_godot_to_orig_bone_names.has(orig_bind_name) or orig_bind_name != bind_name:
									var orig_name: String = meta_godot_to_orig_bone_names.get(orig_bind_name, orig_bind_name)
									prefab_state.fileID_to_forced_humanoid_orig_name[orig_bones[idx][1]] = orig_name
									this_skelley.fileID_to_orig_name[orig_bones[idx][1]] = orig_name
									asset.log_debug("Skin bind " + str(idx) + " bind " + str(bind_name) + " orig human " + str(orig_bind_name) + " mapped to orig name " + str(orig_name))
								else:
									asset.log_debug("Skin bind " + str(idx) + " bind " + str(bind_name) + " orig human " + str(orig_bind_name) + " not found in orig names")
						if this_skelley.humanoid_avatar_meta == null:
							this_skelley.humanoid_avatar_meta = mesh_meta
						forced_avatar_meta = mesh_meta

			var find_animator_obj: RefCounted = bone0_obj
			while find_animator_obj != null and find_animator_obj.gameObject != null:
				var animator: RefCounted = find_animator_obj.gameObject.GetComponent("Animator")
				var add_children: bool = false
				if animator != null:
					if animator.forced_humanoid_avatar_meta == null:
						animator.forced_humanoid_avatar_meta = forced_avatar_meta
					var avatar_meta = animator.get_avatar_meta()
					if avatar_meta != null:
						add_children = true
				elif find_animator_obj.parent == null and is_prefab:
					add_children = true
				if add_children:
					for child_ref in find_animator_obj.children_refs:
						var child_obj = asset.meta.lookup(child_ref)
						if child_obj != null and child_obj.gameObject != null and child_obj.gameObject.GetComponent("SkinnedMeshRenderer") != null:
							continue
						bones.append(child_ref)
				find_animator_obj = find_animator_obj.parent
			for bone in bones:
				var bone_obj: RefCounted = asset.meta.lookup(bone)  # UnidotTransform
				this_skelley = add_bone_to_skelley(this_skelley, bone_obj)

	var skelleys_with_no_parent = [].duplicate()

	# If skelley_parents contains your node, add Skelley.skeleton as a child to it for each item in the list.
	for skel_id in PackedInt32Array(skelleys.keys()):
		var skelley: Skelley = skelleys[skel_id]
		var par_transform: RefCounted = skelley.parent_transform  # UnidotTransform or UnidotPrefabInstance
		var i = 0
		for bone in skelley.bones:
			i = i + 1
			if bone == par_transform:
				par_transform = par_transform.parent_no_stripped
				skelley.bone0_parent_list.pop_back()
		if skelley.parent_transform == null:
			if skelley.parent_prefab == null:
				skelleys_with_no_parent.push_back(skelley)
			else:
				var uk: int = skelley.parent_prefab.fileID
				if not prefab_state.skelleys_by_parented_prefab.has(uk):
					prefab_state.skelleys_by_parented_prefab[uk] = [].duplicate()
				prefab_state.skelleys_by_parented_prefab[uk].push_back(skelley)
		else:
			var fileID = skelley.parent_transform.fileID
			if skelley_parents.has(fileID):
				skelley_parents[fileID].merge_independent_sibling_skelley(skelley, self)
			else:
				skelley_parents[fileID] = skelley

	for skel_id in skelleys:
		var skelley: Skelley = skelleys[skel_id]
		meta.log_debug(0, "Construct final bone list " + str(skelleys[skel_id]) + " " + str(child_transforms_by_stripped_id))
		skelley.construct_final_bone_list(skelley_parents, child_transforms_by_stripped_id)
		for fileID in skelley.fileID_to_bone:
			fileID_to_skelley[fileID] = skelley
			# meta.log_debug(0, "ADDING fileid " + str(fileID) + " bone " + str(skelley.fileID_to_bone[fileID]) + " skelley " + str(skelley))

	return skelleys_with_no_parent


func lookup_or_virtual_transform(fileID: int, target_prefab_meta: Resource, target_fileID: int):
	var calculated_fileid: int = meta.xor_or_stripped(target_fileID, fileID)
	var ret: RefCounted = meta.lookup([null, calculated_fileid, "", 0], true)
	if ret != null:
		return ret
	ret = object_adapter_class_inst.instantiate_unidot_object(meta, calculated_fileid, 4, "Transform")
	ret.is_stripped = true
	ret.keys["m_PrefabInstance"] = [null, fileID, "", 0]
	ret.keys["m_CorrespondingSourceObject"] = [null, target_fileID, target_prefab_meta.guid, 0]
	return ret


func add_bones_to_prefabbed_skeletons(fileID: int, target_prefab_meta: Resource, instanced_scene: Node3D):
	meta.log_debug(fileID, "Add bones to prefabbed skeletons")
	var fileid_to_added_bone: Dictionary = {}.duplicate()
	var fileid_to_skeleton_nodepath: Dictionary = {}.duplicate()
	var fileid_to_bone_name: Dictionary = {}.duplicate()

	var existing_skeletons: Dictionary
	var added_skeletons: Dictionary
	for skelley in prefab_state.skelleys_by_parented_prefab.get(fileID, []):
		if skelley.godot_skeleton != null:
			existing_skeletons[skelley.godot_skeleton] = true
	for bone_fileid in target_prefab_meta.prefab_fileid_to_skeleton_bone:
		var skel_bone: String = target_prefab_meta.prefab_fileid_to_skeleton_bone[bone_fileid]
		if skel_bone.is_empty():
			continue
		if target_prefab_meta.prefab_fileid_to_utype[bone_fileid] != 4:
			continue
		var skel_nodepath: NodePath = target_prefab_meta.prefab_fileid_to_nodepath[bone_fileid]
		var godot_skel: Skeleton3D = instanced_scene.get_node_or_null(skel_nodepath) as Skeleton3D
		if added_skeletons.has(skel_nodepath):
			continue
		var skelley: Skelley
		var virtual_obj = lookup_or_virtual_transform(fileID, target_prefab_meta, bone_fileid)
		if existing_skeletons.has(godot_skel):
			skelley = existing_skeletons[godot_skel]
		else:
			skelley = create_skelley(virtual_obj)
			if skelley.godot_skeleton != null:
				skelley.godot_skeleton.queue_free()
			skelley.godot_skeleton = godot_skel
			existing_skeletons[godot_skel] = skelley
		added_skeletons[skel_nodepath] = skelley
		skelley.is_prefabbed_skeleton = true
		if not prefab_state.skelleys_by_parented_prefab.has(fileID):
			prefab_state.skelleys_by_parented_prefab[fileID] = []
		prefab_state.skelleys_by_parented_prefab[fileID].append(skelley)
		meta.log_debug(fileID, "Adding skelley " + str(skelley) + " from bone " + str(skel_bone))

	for bone_fileid in target_prefab_meta.fileid_to_skeleton_bone:
		var skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone[bone_fileid]
		if skel_bone.is_empty():
			continue
		if target_prefab_meta.fileid_to_utype[bone_fileid] != 4:
			continue
		var skel_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath[bone_fileid]
		var godot_skel: Skeleton3D = instanced_scene.get_node_or_null(skel_nodepath) as Skeleton3D
		if added_skeletons.has(skel_nodepath):
			continue
		var skelley: Skelley
		var virtual_obj = lookup_or_virtual_transform(fileID, target_prefab_meta, bone_fileid)
		if existing_skeletons.has(godot_skel):
			skelley = existing_skeletons[godot_skel]
		else:
			skelley = create_skelley(virtual_obj)
			if skelley.godot_skeleton != null:
				skelley.godot_skeleton.queue_free()
			skelley.godot_skeleton = godot_skel
			existing_skeletons[godot_skel] = skelley
		added_skeletons[skel_nodepath] = skelley
		if not prefab_state.skelleys_by_parented_prefab.has(fileID):
			prefab_state.skelleys_by_parented_prefab[fileID] = []
		prefab_state.skelleys_by_parented_prefab[fileID].append(skelley)
		meta.log_debug(fileID, "Adding skelley " + str(skelley))
	# TODO: for each Skeleton3D node in the instanced, scene, create a Skelley object for each so it can be properly merged.

	var skelley_list: Array = prefab_state.skelleys_by_parented_prefab.get(fileID, []).duplicate()
	meta.log_debug(fileID, "merging prefabbed skeletons from " + str(skelley_list))
	if len(skelley_list) > 1:
		var orig_skel: Skelley = null
		var exclude_skel: Dictionary
		for skelley in skelley_list:
			meta.log_debug(fileID, str(skelley))
			if skelley.godot_skeleton != null and skelley.godot_skeleton.get_parent() != null:
				meta.log_debug(fileID, "Found a parentless skel")
				if orig_skel == null:
					orig_skel = skelley
				exclude_skel[skelley] = true
		if orig_skel == null:
			orig_skel = skelley_list[0]
		for skelley in prefab_state.skelleys_by_parented_prefab.get(fileID, []):
			meta.log_debug(fileID, "Try " + str(skelley))
			if not exclude_skel.has(skelley):
				meta.log_debug(fileID, "not excluded")
				orig_skel.merge_independent_sibling_skelley(skelley, self)
	meta.log_debug(fileID, "Done merging prefab skeletons")

	for skelley in prefab_state.skelleys_by_parented_prefab.get(fileID, []):
		meta.log_debug(fileID, "Fixing skelley from parent prefab " + str(skelley))
		var godot_skeleton_nodepath = NodePath()
		for bone in skelley.bones:  # skelley.root_bones:
			if not bone.is_prefab_reference:
				# We are iterating through bones array because root_bones was not reliable.
				# So we will hit both types of bones. Let's just ignore non-prefab bones for now.
				# FIXME: Should we try to fix the root_bone logic so we can detect bad Skeletons?
				# bone.log_warn("Skeleton parented to prefab contains root bone not rooted within prefab.")
				continue
			var source_obj_ref = bone.prefab_source_object
			var target_skelley: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
			# bone.log_debug("Parented prefab root bone : " + str(bone) + " for " + str(target_skelley) + ":" + str(target_skel_bone))
			if godot_skeleton_nodepath == NodePath() and target_skelley != NodePath():
				godot_skeleton_nodepath = target_skelley
				skelley.godot_skeleton = instanced_scene.get_node(godot_skeleton_nodepath)
			if target_skelley != godot_skeleton_nodepath:
				bone.log_fail("Skeleton child of prefab spans multiple Skeleton objects in source prefab.", "bones", source_obj_ref)
			fileid_to_skeleton_nodepath[bone.fileID] = target_skelley
			fileid_to_bone_name[bone.fileID] = target_skel_bone
			if skelley.godot_skeleton != null:
				bone.skeleton_bone_index = skelley.godot_skeleton.find_bone(target_skel_bone)
			# if fileid_to_skeleton_nodepath.has(source_obj_ref[1]):
			# 	if fileid_to_skeleton_nodepath.get(source_obj_ref[1]) != target_skelley:
			# 		bone.log_warn("Skeleton spans multiple ")
			# WE ARE NOT REQUIRED TO create a new skelley object for each Skeleton3D instance in the inflated scene.
			# NO! THIS IS STUPID Then, the skelley objects with parent=scene should be dissolved and replaced with extended versions of the prefab's skelley
			# For every skelley in this prefab, go find the corresponding Skeleton3D object and add the missing nodes. that's it.
			# Then, we should make sure we create the bone attachments for all grand/great children too.
			# FINALLY! We did all this. now let's add the skins and proper bone index arrays into the skins!
		# Add all the bones
		if skelley.godot_skeleton == null:
			meta.log_fail(0, "Skelley " + str(skelley) + " in prefab " + str(fileID) + " could not find source godot skeleton!", "prefab", [null, -1, target_prefab_meta.guid, -1])
			continue
		var dedupe_dict = {}.duplicate()
		for idx in range(skelley.godot_skeleton.get_bone_count()):
			dedupe_dict[skelley.godot_skeleton.get_bone_name(idx)] = null
		for bone in skelley.bones:
			if bone.is_prefab_reference:
				continue
			if fileid_to_bone_name.has(bone.fileID):
				continue
			if not dedupe_dict.has(bone.name):
				dedupe_dict[bone.name] = bone
		for bone in skelley.bones:
			if bone.is_prefab_reference:
				continue
			if fileid_to_bone_name.has(bone.fileID):
				continue
			var new_idx: int = skelley.godot_skeleton.get_bone_count()
			var ctr: int = 0
			var orig_bone_name: String = bone.name
			var bone_name: String = orig_bone_name
			while dedupe_dict.get(bone_name) != bone:
				ctr += 1
				bone_name = orig_bone_name + " " + str(ctr)
				if not dedupe_dict.has(bone_name):
					dedupe_dict[bone_name] = bone
			skelley.godot_skeleton.add_bone(bone_name)
			bone.log_debug("Prefab adding bone " + bone.name + " idx " + str(new_idx) + " new size " + str(skelley.godot_skeleton.get_bone_count()))
			fileid_to_bone_name[bone.fileID] = skelley.godot_skeleton.get_bone_name(new_idx)
			bone.skeleton_bone_index = new_idx
		# Now set up the indices and parents.
		for bone in skelley.bones:
			if bone.is_prefab_reference:
				continue
			if fileid_to_skeleton_nodepath.has(bone.fileID):
				continue
			var idx: int = skelley.godot_skeleton.find_bone(fileid_to_bone_name.get(bone.fileID, ""))
			var parent_bone_index: int = -1
			if bone.parent.is_prefab_reference:
				var source_obj_ref = bone.parent.prefab_source_object
				var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
				parent_bone_index = skelley.godot_skeleton.find_bone(target_skel_bone)
			else:
				parent_bone_index = skelley.godot_skeleton.find_bone(fileid_to_bone_name.get(bone.parent.fileID, ""))
			bone.log_debug("Parent bone index: " + str(bone.name) + " / " + str(bone) + " / " + str(parent_bone_index))
			skelley.godot_skeleton.set_bone_parent(idx, parent_bone_index)
			# skelley.godot_skeleton.set_bone_rest(idx, bone.godot_transform) # Set later on.
			fileid_to_skeleton_nodepath[bone.fileID] = godot_skeleton_nodepath


class CRC32:
	extends RefCounted

	var table: PackedInt32Array

	func _init():
		var poly: int = 0xedb88320
		for byte in range(256):
			var crc: int = 0
			for bit in range(8):
				if (byte ^ crc) & 1:
					crc = (crc >> 1) ^ poly
				else:
					crc >>= 1
				byte >>= 1
			table.append(crc)

	func crc32(str: String) -> int:
		var buf := str.to_utf8_buffer()
		var value: int = 0xffffffff
		for byt in buf:
			value = (table[(byt ^ value) & 0xff] ^ (value >> 8)) & 0xffffffff
		var ret: int = 0xffffffff ^ value
		if ret > 0x7fffffff:
			return ret - 0x100000000
		return ret
