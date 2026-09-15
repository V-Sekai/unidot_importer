class_name UnidotGameObject extends UnidotObject

func get_godot_type() -> String:
	return "Node3D"

func recurse_to_child_transform(state: RefCounted, child_transform: UnidotObject, new_parent: Node3D) -> Array:  # prefab_fileID,prefab_name,go_fileID,node
	if child_transform.type == "PrefabInstance":
		# PrefabInstance child of stripped Transform part of another PrefabInstance
		var prefab_instance: UnidotPrefabInstance = child_transform
		return prefab_instance.instantiate_prefab_node(state, new_parent)
	elif child_transform.is_prefab_reference:
		# PrefabInstance child of ordinary Transform
		if not child_transform.is_stripped:
			log_debug("Expected a stripped transform for prefab root as child of transform")
		var prefab_instance: UnidotPrefabInstance = meta.lookup(child_transform.prefab_instance)
		return prefab_instance.instantiate_prefab_node(state, new_parent)
	else:
		if child_transform.is_stripped:
			log_fail("*!*!*! CHILD IS STRIPPED " + str(child_transform) + "; " + str(child_transform.is_prefab_reference) + ";" + str(child_transform.prefab_source_object) + ";" + str(child_transform.prefab_instance), "child", child_transform)
		var child_game_object: UnidotGameObject = child_transform.gameObject
		if child_game_object.is_prefab_reference:
			log_warn("child gameObject is a prefab reference!", "chi;d", child_game_object)
		var new_skelley: RefCounted = state.fileID_to_skelley.get(child_transform.fileID, null)  # Skelley
		if new_skelley == null and new_parent == null:
			log_warn("We did not create a node for this child, but it is not a skeleton bone! " + str(self) + " child " + str(child_transform) + " gameObject " + str(child_game_object), "child", child_game_object)
		elif new_skelley != null:
			# log_debug("Go from " + str(transform_asset) + " to " + str(child_game_object) + " transform " + str(child_transform) + " found skelley " + str(new_skelley))
			child_game_object.create_skeleton_bone(state, new_skelley)
		else:
			child_game_object.create_godot_node(state, new_parent)
		return [null]

func create_skeleton_bone(xstate: RefCounted, skelley: RefCounted):  # SceneNodeState, Skelley
	var state: Object = xstate
	var godot_skeleton: Skeleton3D = skelley.godot_skeleton
	# Instead of a transform, this sets the skeleton transform position maybe?, etc. etc. etc.
	var transform: UnidotTransform = self.transform
	var skeleton_bone_index: int = transform.skeleton_bone_index
	var skeleton_bone_name: String = godot_skeleton.get_bone_name(skeleton_bone_index)
	log_debug("create_skeleton_bone skelley " + str(skelley) + "/" + str(skeleton_bone_index) + "/" + str(skeleton_bone_name) + " owner " + str(godot_skeleton.owner.scene_file_path))
	var ret: Node3D = null
	var animator = GetComponent("Animator")
	var sub_avatar_meta: RefCounted
	if animator != null:
		sub_avatar_meta = animator.get_avatar_meta()
		if sub_avatar_meta != null:
			state = state.state_with_avatar_meta(sub_avatar_meta)
			if godot_skeleton.name != "GeneralSkeleton":
				log_fail("Skelley object should have ensured godot_skeleton with avatar is named GeneralSkeleton")
			log_warn("Humanoid Animator component on skeleton bone " + str(skeleton_bone_name) + " does not fully support unique_name_in_owner")
			# TODO: Implement scene saving for partial skeleton humanoid avatar
	var avatar_bone_name = state.consume_avatar_bone(self.name, skeleton_bone_name, transform.fileID, skelley, skeleton_bone_index)
	#var configure_root_bone: bool = false
	if not avatar_bone_name.is_empty():
		var conflicting_bone := godot_skeleton.find_bone(avatar_bone_name)
		var dedupe := 1
		if conflicting_bone != -1:
			while godot_skeleton.find_bone(avatar_bone_name + " " + str(dedupe)) != -1:
				dedupe += 1
			log_debug("BONE RENAMING AVATAR CASE FOR " + str(skeleton_bone_index) + " RENAMING " + str(conflicting_bone) + " TO " + str(avatar_bone_name + " " + str(dedupe)))
			godot_skeleton.set_bone_name(conflicting_bone, avatar_bone_name + " " + str(dedupe))
		log_debug("BONE RENAMING STEALING AVATAR CASE " + str(skeleton_bone_index) + " TO " + str(avatar_bone_name))
		godot_skeleton.set_bone_name(skeleton_bone_index, avatar_bone_name)
		skeleton_bone_name = avatar_bone_name
		if avatar_bone_name == "Hips":
			if state.consume_root(transform.fileID):
				dedupe = 1
				conflicting_bone = godot_skeleton.find_bone("Root")
				if conflicting_bone != -1:
					while godot_skeleton.find_bone("Root " + str(dedupe)) != -1:
						dedupe += 1
					log_debug("BONE RENAMING ROOT CASE FOR " + str(skeleton_bone_index) + " RENAMING " + str(conflicting_bone) + " TO " + str("Root " + str(dedupe)))
					godot_skeleton.set_bone_name(conflicting_bone, "Root " + str(dedupe))
				var root_idx = godot_skeleton.get_bone_count()
				godot_skeleton.add_bone("Root") # identity transform 0,0,0 is ok
				#configure_root_bone = true
				godot_skeleton.set_bone_parent(root_idx, godot_skeleton.get_bone_parent(skeleton_bone_index)) # parent *should be* -1
				godot_skeleton.set_bone_parent(skeleton_bone_index, root_idx)
	elif state.is_bone_name_reserved(skeleton_bone_name):
		var dedupe := 1
		while godot_skeleton.find_bone(skeleton_bone_name + " " + str(dedupe)) != -1:
			dedupe += 1
		log_debug("BONE RENAMING RESERVED CASE " + str(skeleton_bone_index) + " TO " + str(skeleton_bone_name + " " + str(dedupe)))
		godot_skeleton.set_bone_name(skeleton_bone_index, skeleton_bone_name + " " + str(dedupe))
		skeleton_bone_name = skeleton_bone_name + " " + str(dedupe)
	var rigidbody = GetComponent("Rigidbody")
	var name_map = {}
	name_map[1] = self.fileID
	name_map[4] = transform.fileID
	name_map[transform.utype] = transform.fileID  # RectTransform may also point to this.
	if rigidbody != null:
		ret = rigidbody.create_physical_bone(state, godot_skeleton, skeleton_bone_name)
		rigidbody.configure_node(ret)
		state.add_fileID(ret, self)
		state.add_fileID(ret, transform)
	else:
		state.add_fileID(godot_skeleton, self)
		state.add_fileID(godot_skeleton, transform)
		state.add_fileID_to_skeleton_bone(skeleton_bone_name, fileID)
		state.add_fileID_to_skeleton_bone(skeleton_bone_name, transform.fileID)
		if len(components) > 1 or state.skelley_parents.has(transform.fileID):
			ret = BoneAttachment3D.new()
			ret.name = self.name
			ret.bone_name = skeleton_bone_name
			state.add_child(ret, godot_skeleton, null)
			# state.add_fileID(ret, transform)
	# TODO: do we need to configure GameObject here? IsActive, Name on a skeleton bone?
	transform.configure_skeleton_bone(godot_skeleton, skeleton_bone_name)
	var rest_bone_pose := godot_skeleton.get_bone_pose(skeleton_bone_index)
	if avatar_bone_name == "Root":
		rest_bone_pose = Transform3D()
	if not avatar_bone_name.is_empty() and skelley.skeleton_profile_humanoid_bones.has(avatar_bone_name):
		var sph : SkeletonProfileHumanoid = skelley.skeleton_profile_humanoid
		rest_bone_pose.basis = Basis(sph.get_reference_pose(sph.find_bone(avatar_bone_name)).basis.get_rotation_quaternion()).scaled(rest_bone_pose.basis.get_scale())
		if avatar_bone_name == "Hips":
			rest_bone_pose.origin = state.last_humanoid_skeleton_hip_position
			godot_skeleton.motion_scale = state.last_humanoid_skeleton_hip_position.y
	godot_skeleton.set_bone_rest(skeleton_bone_index, rest_bone_pose)
#	var smrs: Array[UnidotSkinnedMeshRenderer]
	var smrs: Array
	if ret != null:
		var new_skelley: RefCounted = state.skelley_parents.get(transform.fileID, null)
		if new_skelley != null:
			ret.add_child(godot_skeleton, true)
			godot_skeleton.owner = state.owner
			for smr in new_skelley.skinned_mesh_renderers:
				smrs.append(smr)

	var skip_first: bool = true

	var transform_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(transform.fileID, meta.prefab_transform_fileid_to_rotation_delta.get(transform.fileID, Transform3D()))
	var animator_node_to_object: Dictionary
	for component_ref in components:
		if skip_first:
			#Is it a fair assumption that Transform is always the first component???
			skip_first = false
		else:
			var component = meta.lookup(component_ref.values()[0])
			if keys.has("m_StaticEditorFlags"):
				component.keys["m_StaticEditorFlags"] = keys["m_StaticEditorFlags"]
			if keys.has("m_Layer"):
				component.keys["m_Layer"] = keys["m_Layer"]
			if keys.has("m_TagString"):
				component.keys["m_TagString"] = keys["m_TagString"]
			if ret == null:
				log_fail("Unable to create godot node " + component.type + " on null skeleton", "bone", self)
			var tmp = component.create_godot_node(state, ret)
			if tmp is AnimationPlayer or tmp is AnimationTree:
				animator_node_to_object[tmp] = component
			if tmp != null:
				component.configure_node(tmp)
				while tmp.get_parent() != null and tmp.get_parent() != ret:
					tmp = tmp.get_parent()
				if tmp is Node3D:
					tmp.transform = transform_delta * tmp.transform
			var component_key = component.get_component_key()
			if not name_map.has(component_key):
				name_map[component_key] = component.fileID

	var prefab_name_map = name_map.duplicate()
	for child_ref in transform.children_refs:
		var child_transform: UnidotTransform = meta.lookup(child_ref)
		if ret == null and child_transform.is_prefab_reference or child_transform.type == "PrefabInstance":
			#log_warn("Unable to recurse to child_transform " + str(child_transform) + " on null skeleton bone ret", "children", self)
			ret = BoneAttachment3D.new()
			ret.name = self.name
			ret.bone_name = skeleton_bone_name
			state.add_child(ret, godot_skeleton, null)
		var prefab_data: Array = recurse_to_child_transform(state, child_transform, ret)
		if len(prefab_data) == 4:
			name_map[prefab_data[1]] = prefab_data[2]
			prefab_name_map[prefab_data[1]] = prefab_data[2]
			state.add_prefab_to_parent_transform(transform.fileID, prefab_data[0])
		elif len(prefab_data) == 1:
			name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
			prefab_name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID

	for smr in smrs:
		var smrnode: Node = smr.create_skinned_mesh(state)
		if smrnode != null:
			smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr) + " into node Skeleton " + str(state.owner.get_path_to(smrnode)))

	if ret is BoneAttachment3D and ret.get_child_count() == 0:
		godot_skeleton.remove_child(ret)
		ret.queue_free()
	state.prefab_state.gameobject_name_map[self.fileID] = name_map
	state.prefab_state.prefab_gameobject_name_map[self.fileID] = prefab_name_map
	for plugin in meta.get_enabled_plugins():
		plugin.setup_post_children(self, state, ret, null)
	for animtree in animator_node_to_object:
		var obj: RefCounted = animator_node_to_object[animtree]
		# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
		# If not found, we can't recreate the animationLibrary
		obj.setup_post_children(animtree, sub_avatar_meta)

func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node:  # -> Node3D:
	var state: Object = xstate
	var ret: Node3D = null
	var components: Array = self.components
	var has_collider: bool = false
	var extra_fileID: Array = [self]
	var transform: UnidotTransform = self.transform
	var sub_avatar_meta = null
	var name_map = {}
	name_map[1] = self.fileID
	name_map[4] = transform.fileID
	name_map[transform.utype] = transform.fileID  # RectTransform may also point to this.

	for component_ref in components:
		var component = meta.lookup(component_ref.values()[0])
		if component.type == "CharacterController":
			ret = component.create_physics_body(state, new_parent, name)
			transform.configure_node(ret)
			component.configure_node(ret)
			extra_fileID.push_back(transform)
			state = state.state_with_body(ret)
	for component_ref in components:
		var component = meta.lookup(component_ref.values()[0])
		# Some components take priority and must be created here.
		if ret == null and component.type == "Rigidbody":
			ret = component.create_physics_body(state, new_parent, name)
			transform.configure_node(ret)
			component.configure_node(ret)
			extra_fileID.push_back(transform)
			state = state.state_with_body(ret)
		if component.is_collider():
			extra_fileID.push_back(component)
			log_debug("Has a collider " + self.name)
			has_collider = true
		if component.type == "Animator":
			sub_avatar_meta = component.get_avatar_meta()
			if sub_avatar_meta != null:
				state = state.state_with_avatar_meta(sub_avatar_meta)
	var new_skelley: RefCounted = state.skelley_parents.get(transform.fileID, null)
	if new_skelley != null:
		if new_skelley.humanoid_avatar_meta != null and new_skelley.humanoid_avatar_meta != sub_avatar_meta:
			sub_avatar_meta = new_skelley.humanoid_avatar_meta
			state = state.state_with_avatar_meta(sub_avatar_meta)
	var this_avatar_meta = sub_avatar_meta
	if state.owner == null or ret == state.owner:
		sub_avatar_meta = null
	if ret == null:
		ret = Node3D.new()
		transform.configure_node(ret)
		ret.name = name
		state.add_child(ret, new_parent, transform)
	for ext in extra_fileID:
		state.add_fileID(ret, ext)
	var skip_first: bool = true
	var orig_meta_owner: Node = state.owner
	if sub_avatar_meta != null:
		# Due to the scene unique name requirement,
		# make sure all GeneralSkeleton trees are in their own scn file.
		state = state.state_with_owner(ret)

	var transform_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(transform.fileID, meta.prefab_transform_fileid_to_rotation_delta.get(transform.fileID, Transform3D()))
	var animator_node_to_object: Dictionary
	for component_ref in components:
		if skip_first:
			#Is it a fair assumption that Transform is always the first component???
			skip_first = false
		else:
			var component = meta.lookup(component_ref.values()[0])
			if keys.has("m_StaticEditorFlags"):
				component.keys["m_StaticEditorFlags"] = keys["m_StaticEditorFlags"]
			if keys.has("m_Layer"):
				component.keys["m_Layer"] = keys["m_Layer"]
			if keys.has("m_TagString"):
				component.keys["m_TagString"] = keys["m_TagString"]
			var tmp = component.create_godot_node(state, ret)
			if tmp is AnimationPlayer or tmp is AnimationTree:
				animator_node_to_object[tmp] = component
			if tmp != null:
				component.configure_node(tmp)
				while tmp.get_parent() != null and tmp.get_parent() != ret:
					tmp = tmp.get_parent()
				if tmp is Node3D:
					tmp.transform = transform_delta * tmp.transform
			var component_key = component.get_component_key()
			if not name_map.has(component_key):
				name_map[component_key] = component.fileID

#	var smrs: Array[UnidotSkinnedMeshRenderer]
	var smrs: Array
	if new_skelley != null:
		if not new_skelley.godot_skeleton:
			log_fail("Skelley " + str(new_skelley) + " is missing a godot_skeleton")
		else:
			ret.add_child(new_skelley.godot_skeleton, true)
			if not state.active_avatars.is_empty():
				new_skelley.godot_skeleton.name = "GeneralSkeleton"
			new_skelley.godot_skeleton.owner = state.owner
			if not state.active_avatars.is_empty():
				new_skelley.godot_skeleton.unique_name_in_owner = true
			for smr in new_skelley.skinned_mesh_renderers:
				smrs.append(smr)

	var prefab_name_map = name_map.duplicate()
	for child_ref in transform.children_refs:
		var child_transform: UnidotTransform = meta.lookup(child_ref)
		var prefab_data: Array = recurse_to_child_transform(state, child_transform, ret)
		if len(prefab_data) == 4:
			name_map[prefab_data[1]] = prefab_data[2]
			prefab_name_map[prefab_data[1]] = prefab_data[2]
			state.add_prefab_to_parent_transform(transform.fileID, prefab_data[0])
		elif len(prefab_data) == 1:
			name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
			prefab_name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID

	for smr in smrs:
		var smrnode: Node = smr.create_skinned_mesh(state)
		if smrnode != null:
			smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr) + " into nested Skeleton " + str(state.owner.get_path_to(smrnode)))

	state.prefab_state.gameobject_name_map[self.fileID] = name_map
	state.prefab_state.prefab_gameobject_name_map[self.fileID] = prefab_name_map
	for plugin in meta.get_enabled_plugins():
		plugin.setup_post_children(self, state, ret, this_avatar_meta)

	for animtree in animator_node_to_object:
		var obj: RefCounted = animator_node_to_object[animtree]
		# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
		# If not found, we can't recreate the animationLibrary
		obj.setup_post_children(animtree, this_avatar_meta)
	if sub_avatar_meta != null:
		var sub_scene_filename: String = meta.fixup_godot_extension(meta.path.get_basename() + "." + str(self.name) + ".tscn")
		var ps: PackedScene = PackedScene.new()
		ps.pack(ret)
		adapter.unidot_utils.save_resource(ps, sub_scene_filename)
		ret.scene_file_path = sub_scene_filename
		orig_meta_owner.set_editable_instance(ret, true)
		#ps = ResourceLoader.load(sub_scene_filename)
		#ret = ps.instantiate()

	return ret

var components: Variant:  # Array:
	get:
		if is_stripped:
			log_fail("Attempted to access the component array of a stripped " + type + " " + str(self), "components")
			# FIXME: Stripped objects do not know their name.
			return 12345.678  # ????
		return keys.get("m_Component")

func get_transform() -> Object:  # UnidotTransform:
	if is_stripped:
		log_fail("Attempted to access the transform of a stripped " + type + " " + str(self), "transform")
		# FIXME: Stripped objects do not know their name.
		return null  # ????
	if typeof(components) != TYPE_ARRAY:
		log_fail(str(self) + " has component array: " + str(components), "transform")
	elif len(components) < 1 or typeof(components[0]) != TYPE_DICTIONARY:
		log_fail(str(self) + " has invalid first component: " + str(components), "transform")
	elif len(components[0].values()[0]) < 3:
		log_fail(str(self) + " has invalid component: " + str(components), "transform")
	else:
		var component = meta.lookup(components[0].values()[0])
		if component.type != "Transform" and component.type != "RectTransform":
			log_fail(str(self) + " does not have Transform as first component! " + str(component.type) + ": components " + str(components), "transform")
		return component
	return null

func GetComponent(typ: String) -> RefCounted:
	for component_ref in components:
		var component = meta.lookup(component_ref.values()[0])
		if component.type == typ:
			return component
	return null

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = convert_properties_component(node, uprops)
	if uprops.has("m_IsActive"):
		outdict["visible"] = uprops.get("m_IsActive")
	if uprops.has("m_Name"):
		outdict["name"] = uprops.get("m_Name")
	return outdict

#var meshFilter: UnidotMeshFilter = null
var meshFilter = null

#func get_meshFilter() -> UnidotMeshFilter:
func get_meshFilter():
	if meshFilter != null:
		return meshFilter
	return GetComponent("MeshFilter")

var enabled: bool:
	get:
		return keys.get("m_IsActive", 0) != 0

func is_toplevel() -> bool:
	if is_stripped:
		# Stripped objects are part of a Prefab, so by definition will never be toplevel
		# (The PrefabInstance itself will be the toplevel object)
		return false
	if typeof(transform) == TYPE_NIL:
		log_warn(str(self) + " has no transform in toplevel: " + str(transform))
		return false
	if typeof(transform.parent_ref) != TYPE_ARRAY:
		log_warn(str(self) + " has invalid or missing parent_ref: " + str(transform.parent_ref))
		return false
	return transform.parent_ref[1] == 0

#	func get_gameObject() -> UnidotGameObject:  # UnidotGameObject:
func get_gameObject():  # UnidotGameObject:
	return self

func get_debug_name() -> String:
	if is_stripped or self.name.is_empty():
		var bone: String = meta.fileid_to_skeleton_bone.get(fileID, meta.prefab_fileid_to_skeleton_bone.get(fileID, ""))
		if not bone.is_empty():
			return bone
		var np: NodePath = meta.fileid_to_nodepath.get(fileID, meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
		if not np.is_empty():
			return np.get_name(np.get_name_count() - 1)
		if is_stripped:
			return "[stripped]"
		return "[empty]"
	return str(self.name)
