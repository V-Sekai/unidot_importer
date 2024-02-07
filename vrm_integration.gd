extends RefCounted

var vrm_spring_bone_class = load("res://addons/vrm/vrm_spring_bone.gd")
var vrm_collider_class = load("res://addons/vrm/vrm_collider.gd")
var vrm_collider_group_class = load("res://addons/vrm/vrm_collider_group.gd")
var vrm_meta_class = load("res://addons/vrm/vrm_meta.gd")
var vrm_toplevel_class = load("res://addons/vrm/vrm_toplevel.gd")
var vrm_secondary_class = load("res://addons/vrm/vrm_secondary.gd")


func find_key(keys: Dictionary, try_strings: Dictionary, type: int) -> Array:
	for key in keys:
		for needle in try_strings:
			if key.to_lower().contains(needle):
				var is_correct_type: bool = false
				var value: Variant = keys[key]
				if typeof(keys[key]) == type:
					is_correct_type = true
				if type == TYPE_FLOAT and typeof(keys[key]) == TYPE_INT:
					is_correct_type = true
					value = float(value)
				if type == TYPE_INT and typeof(keys[key]) == TYPE_BOOL:
					is_correct_type = true
					value = int(value)
				if type == -1: # UnidotRef
					if typeof(keys[key]) == TYPE_ARRAY and len(keys[key]) == 4 and typeof(keys[key][0]) == TYPE_NIL:
						is_correct_type = true
				if is_correct_type:
					var fn: Variant = try_strings[needle]
					if typeof(fn) == TYPE_CALLABLE and fn.is_valid():
						value = fn.call(value)
					return [value]
	return []


func detect_spring_bone_collider(obj: RefCounted, state: RefCounted):
	var matched: Array
	var colliders: Array
	if typeof(obj.keys.get("Colliders", null)) == TYPE_ARRAY:
		colliders = obj.keys["Colliders"]
	if colliders.is_empty():
		colliders = [obj.keys]

	var root_obj: RefCounted = obj
	matched = find_key(obj.keys, {"transform": 0, "root": 0}, -1)
	if matched:
		var new_root: RefCounted = obj.meta.lookup(matched[0])
		if new_root != null:
			root_obj = new_root
	var vrm_collider_group: Resource = vrm_collider_group_class.new()
	for collider in colliders:
		var vrm_collider: Resource = vrm_collider_class.new()
		vrm_collider_group.colliders.append(vrm_collider)
		matched = find_key(collider, {"radius": 0}, TYPE_FLOAT)
		if matched.is_empty():
			obj.log_debug("vrm collider missing radius")
			return # wrong format
		var radius := float(matched[0])
		vrm_collider.radius = radius
		matched = find_key(collider, {"offset": 0, "center": 0, "position": 0}, TYPE_VECTOR3)
		if matched.is_empty():
			obj.log_debug("vrm collider missing offset")
			return
		var offset: Vector3 = matched[0] * Vector3(-1, 1, 1)
		matched = find_key(collider, {"insidebound": 0, "m_bound": 0}, TYPE_INT)
		if matched and matched[0]:
			obj.log_warn("Ignoring inside collider " + str(root_obj.gameObject) + " radius=" + str(radius) + " offset=" + str(offset))
			return # Inside colliders not currently supported.
		matched = find_key(collider, {"tail":0}, TYPE_VECTOR3)
		var tail: Vector3 = offset
		if matched:
			tail = matched[0] * Vector3(-1, 1, 1)
		else:
			matched = find_key(collider, {"shapetype": 0}, TYPE_INT)
			if matched.is_empty() or matched[0] == 1:
				matched = find_key(collider, {"height": 0}, TYPE_FLOAT)
				if matched:
					var height := float(matched[0])
					var axis := Vector3(0,1,0)
					matched = find_key(collider, {"direction": 0}, TYPE_VECTOR3)
					if matched:
						match matched[0]:
							0:
								axis = Vector3(1,0,0)
							2:
								axis = Vector3(0,0,1)
					matched = find_key(collider, {"rotation": func(q): return Quaternion(q.x, -q.y, -q.z, q.w)}, TYPE_QUATERNION)
					if matched:
						axis = matched[0] * axis
					if height > 2 * radius:
						tail = offset + axis * (0.5 * height - radius)
						offset = offset - axis * (0.5 * height - radius)
		vrm_collider.offset = offset
		vrm_collider.tail = tail
		vrm_collider.is_capsule = not tail.is_equal_approx(offset)
		obj.log_debug("Found collider " + str(root_obj.gameObject) + " radius=" + str(radius) + " offset " + str(offset) + " tail " + str(tail))
	if "vrm_collider_groups" not in state.prefab_state.extra_data:
		state.prefab_state.extra_data["vrm_collider_groups"] = {}
	root_obj.log_debug("Adding collider group " + str(obj.fileID) + " = " + str(vrm_collider_group))
	state.prefab_state.extra_data["vrm_collider_groups"][obj.fileID] = [obj, vrm_collider_group]


# fileID_to_skelley

func detect_spring_bone(obj: RefCounted, state: RefCounted):
	var matched: Array
	var root_obj: RefCounted = obj
	matched = find_key(obj.keys, {"rootbones": 0}, TYPE_ARRAY)
	if matched.is_empty():
		matched = find_key(obj.keys, {"transform": 0, "root": 0}, -1)
		if matched.is_empty():
			return # wrong format
	matched = find_key(obj.keys, {"drag": 0, "damp": 0, "spring": func(x): return 1 - x}, TYPE_FLOAT)
	if matched.is_empty():
		return # wrong format
	matched = find_key(obj.keys, {"stiff": 0, "elastic": func(x): return 4.0 * x, "pull": func(x): return 4.0 * x}, TYPE_FLOAT)
	if matched.is_empty():
		return # wrong format
	if "vrm_spring_bone_components" not in state.prefab_state.extra_data:
		state.prefab_state.extra_data["vrm_spring_bone_components"] = []
	state.prefab_state.extra_data["vrm_spring_bone_components"].append(obj)

func convert_spring_bone(obj: RefCounted, state: RefCounted) -> Array:
	var matched: Array
	var root_bones: Array = []
	var my_fileid: int = 0 # Transform object
	var allow_forking: bool = false
	var end_length: float = 0
	matched = find_key(obj.keys, {"end": 0}, TYPE_FLOAT)
	if matched:
		end_length = matched[0]
	matched = find_key(obj.keys, {"end": 0}, TYPE_VECTOR3)
	var end_offset := Vector3.ZERO
	if matched:
		end_offset = matched[0]
	matched = find_key(obj.keys, {"rootbones": 0}, TYPE_ARRAY)
	if matched:
		root_bones = matched[0]
		# VRM 0 behavior:
		end_length = 0.07
		allow_forking = true 
	else:
		matched = find_key(obj.keys, {"transform": 0, "root": 0}, -1)
		# TODO: VRMSpringBone (old 0x0) is TYPE_ARRAY of transform
		if matched.is_empty():
			obj.log_debug("Failed to match springbone")
			return [] # wrong format
		my_fileid = matched[0][1] # always a Transform object
	if not root_bones.is_empty():
		my_fileid = root_bones[0][1]
	if my_fileid == 0:
		# We need to lookup the Transform instance so we can resolve this to a Skelley
		var go_fileid: int = obj.keys.get("m_GameObject")[1]
		my_fileid = obj.meta.prefab_gameobject_name_to_fileid_and_children.get(go_fileid, obj.meta.gameobject_name_to_fileid_and_children.get(go_fileid, {})).get(4, go_fileid)
		obj.meta.log_debug(my_fileid, "Found root for springbone object at gameObject=" + str(go_fileid))
	if not state.fileID_to_skelley.has(my_fileid):
		obj.log_fail("Skelley does not contain fileid " + str(my_fileid))
		return []
	var skelley: RefCounted = state.fileID_to_skelley[my_fileid]
	var bone_name: String = obj.meta.fileid_to_skeleton_bone.get(my_fileid, obj.meta.prefab_fileid_to_skeleton_bone.get(my_fileid, ""))
	var godot_skel: Skeleton3D = skelley.godot_skeleton
	var skel_parent := godot_skel.get_parent() as Node3D if godot_skel != null else null
	if skel_parent == null or bone_name.is_empty():
		obj.log_debug("Skelley skeleton bone " + str(bone_name) + " has no parent")
		state.prefab_state.extra_data["vrm_spring_bone_components"].append(obj)
		return []

	matched = find_key(obj.keys, {"drag": 0, "damp": 0, "spring": func(x): return 1 - x}, TYPE_FLOAT)
	if matched.is_empty():
		obj.log_fail("springbone component missing drag")
		return [] # wrong format
	var drag: float = matched[0]
	matched = find_key(obj.keys, {"stiff": 0, "elastic": func(x): return 4.0 * x, "pull": func(x): return 4.0 * x}, TYPE_FLOAT)
	if matched.is_empty():
		obj.log_fail("springbone component missing stiff")
		return [] # wrong format

	allow_forking = allow_forking or obj.keys.has("m_Stiffness")
	var type = "VRM-0" if obj.keys.has("m_stiffnessForce") else ("DynamicBone" if obj.keys.has("m_Stiffness") else "Other")

	var stiffness: float = matched[0]
	var gravity_multiplier: float = 1.0
	matched = find_key(obj.keys, {"gravity": 0}, TYPE_FLOAT)
	if matched:
		gravity_multiplier = matched[0]
	var gravity_direction: Vector3 = Vector3(0, -1, 0)
	matched = find_key(obj.keys, {"gravity": 0}, TYPE_VECTOR3)
	if matched:
		gravity_direction = matched[0]
	var radius: float = 1.0
	matched = find_key(obj.keys, {"radius": 0}, TYPE_FLOAT)
	if matched:
		radius = matched[0]
		var transform_delta: Transform3D = obj.meta.transform_fileid_to_rotation_delta.get(my_fileid, obj.meta.prefab_transform_fileid_to_rotation_delta.get(my_fileid, Transform3D.IDENTITY))
		radius = transform_delta.basis.get_scale().length() / sqrt(3) * radius

	var add_end_bone: bool = not is_equal_approx(end_length, 0.0) or not end_offset.is_equal_approx(Vector3.ZERO)
	obj.log_debug("Creating springbone from " + str(type) + " format: drag=" + str(drag) + " stiff=" + str(stiffness) + " radius=" + str(radius) + " gravity=" + str(gravity_multiplier * gravity_direction) + " endbone=" + str(add_end_bone))

	matched = find_key(obj.keys, {"ignore": 0, "exclusions": 0}, TYPE_ARRAY)
	var excluded_bones: Dictionary = {}
	if matched:
		for exclusion in matched[0]:
			var sb = obj.meta.fileid_to_skeleton_bone.get(exclusion[1], obj.meta.prefab_fileid_to_skeleton_bone.get(exclusion[1], ""))
			if not sb.is_empty():
				excluded_bones[sb] = true

	var collider_groups: Array
	var collider_map: Dictionary = state.prefab_state.extra_data.get("vrm_collider_groups", {})
	matched = find_key(obj.keys, {"collider": 0}, TYPE_ARRAY)
	if matched:
		for collider_ref in matched[0]:
			obj.log_debug("Handling colliders " + str(collider_ref))
			if collider_map.has(collider_ref[1]):
				var tmp: Array = collider_map[collider_ref[1]]
				var monobehaviour: RefCounted = tmp[0]
				var transform_fileid: int = 0
				var vrm_collider_group: Resource = tmp[1]
				matched = find_key(monobehaviour.keys, {"transform": 0, "root": 0}, -1)
				var go_fileid: int
				if matched:
					go_fileid = matched[0][1]
				if go_fileid == 0:
					go_fileid = monobehaviour.keys.get("m_GameObject")[1]
				transform_fileid = monobehaviour.meta.prefab_gameobject_name_to_fileid_and_children.get(go_fileid, monobehaviour.meta.gameobject_name_to_fileid_and_children.get(go_fileid, {})).get(4, go_fileid)
				var transform_delta: Transform3D = monobehaviour.meta.transform_fileid_to_rotation_delta.get(transform_fileid, monobehaviour.meta.prefab_transform_fileid_to_rotation_delta.get(transform_fileid, Transform3D.IDENTITY))
				var bone: String = monobehaviour.meta.fileid_to_skeleton_bone.get(transform_fileid, monobehaviour.meta.prefab_fileid_to_skeleton_bone.get(transform_fileid, ''))
				var nodepath: NodePath = monobehaviour.meta.fileid_to_nodepath.get(transform_fileid, monobehaviour.meta.prefab_fileid_to_nodepath.get(transform_fileid, NodePath()))
				obj.meta.log_debug(transform_fileid, "Transform for bone " + str(bone) + " / " + str(nodepath) + " from " + str(go_fileid))
				if bone.is_empty() and skelley.godot_skeleton != null and nodepath != NodePath():
					var node: Node = state.scene_contents.get_node(nodepath)
					nodepath = NodePath("../" + str(skelley.godot_skeleton.get_path_to(node)))
				else:
					nodepath = NodePath()
				var resource_name: String
				for collider in vrm_collider_group.colliders:
					collider.resource_name = nodepath.get_name(nodepath.get_name_count() - 1) if collider.bone.is_empty() else collider.bone
					if collider.bone.is_empty() and collider.node_path == NodePath():
						collider.radius = transform_delta.basis.get_scale().length() / sqrt(3) * collider.radius
						collider.offset = transform_delta.basis * collider.offset
						collider.tail = transform_delta.basis * collider.tail
					collider.bone = bone
					collider.node_path = nodepath
				obj.log_debug("Collider " + str(vrm_collider_group) + " created at " + str(nodepath) + " bone=" + str(bone))
				if not vrm_collider_group.colliders.is_empty():
					vrm_collider_group.resource_name = vrm_collider_group.colliders[0].resource_name
					collider_groups.append(vrm_collider_group)

	# FIXME: There's supposedly a factor of 10 between dynbone and phys, and a factor of 20 between phys and vrm
	var vrm_spring_bones: Array[RefCounted]
	var fork_stack: Array[int]
	if not root_bones.is_empty():
		for ref in root_bones:
			bone_name = obj.meta.fileid_to_skeleton_bone.get(ref[1], obj.meta.prefab_fileid_to_skeleton_bone.get(ref[1], ""))
			if not bone_name.is_empty():
				fork_stack.append(godot_skel.find_bone(bone_name))
	else:
		fork_stack.append(godot_skel.find_bone(bone_name))
	while not fork_stack.is_empty():
		var bone_idx: int = fork_stack.pop_back()
		var vrm_spring_bone: RefCounted = vrm_spring_bone_class.new()
		vrm_spring_bones.append(vrm_spring_bone)
		vrm_spring_bone.joint_nodes.clear()
		while bone_idx != -1:
			vrm_spring_bone.joint_nodes.append(godot_skel.get_bone_name(bone_idx))
			var children = godot_skel.get_bone_children(bone_idx)
			if children.is_empty():
				break
			bone_idx = children[0]
			if excluded_bones.has(godot_skel.get_bone_name(bone_idx)):
				break
			var ignore_first := true
			if allow_forking:
				for other_bone_idx in children:
					if ignore_first or excluded_bones.has(godot_skel.get_bone_name(other_bone_idx)):
						ignore_first = false
						continue
					fork_stack.append(other_bone_idx)

		if add_end_bone:
			# Technically speaking we should allow adjusting the endbone instead of using VRM's default 0.07
			# But, end length seems to be set very arbitrarily.
			# This will accomplish the most important aspect: simulating an extra bone. See vrm_spring_bone.gd
			vrm_spring_bone.joint_nodes.push_back("")
		if not skelley.skeleton_profile_humanoid_bones.has(vrm_spring_bone.joint_nodes[0]) and len(vrm_spring_bone.joint_nodes) > 2:
			# We don't want jiggly head bones and so on.
			vrm_spring_bone.joint_nodes.remove_at(0)
		vrm_spring_bone.resource_name = vrm_spring_bone.joint_nodes[0]
		# FIXME: We do not currently support parsing Curve, so we treat all bone as constant. This might cause issues with radius, for example.
		if typeof(vrm_spring_bone.get(&"gravity_dir_default")) == TYPE_VECTOR3:
			# New system is property + optional array of points.
			# TODO: Parse Curve objects and convert to Godot curve, then put these in the vector, or maybe add support for Curve in godot-vrm
			vrm_spring_bone.stiffness_scale = stiffness
			vrm_spring_bone.drag_force_scale = drag
			vrm_spring_bone.hit_radius_scale = radius
			vrm_spring_bone.gravity_scale = gravity_multiplier
			vrm_spring_bone.gravity_dir_default = gravity_direction
		else:
			for joint_idx in range(len(vrm_spring_bone.joint_nodes)):
				vrm_spring_bone.stiffness_force.append(stiffness)
				vrm_spring_bone.drag_force.append(drag)
				vrm_spring_bone.hit_radius.append(radius)
				vrm_spring_bone.gravity_power.append(gravity_multiplier)
				vrm_spring_bone.gravity_dir.append(gravity_direction)
		obj.log_debug("Created springbone with joints " + str(vrm_spring_bone.joint_nodes))
		for vrm_collider_group in collider_groups:
			vrm_spring_bone.collider_groups.append(vrm_collider_group)

	return [skelley, vrm_spring_bones]


func handle_monobehaviour(obj: RefCounted, state: RefCounted, node: Node, existing_node_or_null: Node):
	return null


func handle_scripted_object(obj: RefCounted):
	#print("Handle scripted object unused")
	pass # not needed for springbones.


func post_process_avatar(obj: RefCounted, state: RefCounted, node: Node, this_avatar_meta: RefCounted):
	obj.log_debug("Post process avatar at node " + str(state.scene_contents.get_path_to(node)))
	var skelley_to_vrm_collider_groups_used: Dictionary
	# var vrm_collider_groups: Array
	var skelley_to_vrm_spring_bones: Dictionary
	if "vrm_spring_bone_components" in state.prefab_state.extra_data:
		var spring_bone_components: Array = state.prefab_state.extra_data["vrm_spring_bone_components"]
		state.prefab_state.extra_data["vrm_spring_bone_components"] = []
		for sb in spring_bone_components:
			sb.log_debug("Post process springbone!")
			var ret: Array = convert_spring_bone(sb, state)
			if ret.is_empty() or ret[1].is_empty():
				continue
			var skelley: RefCounted = ret[0]
			var vrm_spring_bones: Array = ret[1]
			if not skelley_to_vrm_collider_groups_used.has(skelley):
				skelley_to_vrm_collider_groups_used[skelley] = {}
			if not skelley_to_vrm_spring_bones.has(skelley):
				skelley_to_vrm_spring_bones[skelley] = []
			# All the bone chains will have the same collider_groups, so we can do this:
			for coll in vrm_spring_bones[0].collider_groups:
				skelley_to_vrm_collider_groups_used[skelley][coll] = true
			skelley_to_vrm_spring_bones[skelley].append_array(vrm_spring_bones)

	for skelley in skelley_to_vrm_spring_bones:
		obj.log_debug("Post process skelley " + str(skelley))
		var skel_parent: Node3D = skelley.godot_skeleton.get_parent_node_3d()
		if skel_parent.get_script() == null:
			skel_parent.set_script(vrm_toplevel_class)
		if skel_parent.get_script().resource_path != vrm_toplevel_class.resource_path:
			obj.log_fail("Incorrect script at toplevel")
			return []
		if skel_parent.vrm_meta == null:
			skel_parent.vrm_meta = vrm_meta_class.new()
		var secondary_node: Node = skel_parent.get_node_or_null(^"secondary")
		if secondary_node == null:
			secondary_node = Node3D.new()
			secondary_node.name = "secondary"
			skel_parent.add_child(secondary_node)
			secondary_node.owner = state.owner
		if secondary_node.get_script() == null:
			secondary_node.set_script(vrm_secondary_class)
		if secondary_node.get_script().resource_path != vrm_secondary_class.resource_path:
			obj.log_fail("Incorrect script at secondary")
			return []
		secondary_node.skeleton = NodePath("../" + str(skelley.godot_skeleton.name))
		skelley_to_vrm_spring_bones[skelley].sort_custom(func(a, b): return a.resource_name < b.resource_name)
		for res in skelley_to_vrm_spring_bones[skelley]:
			secondary_node.spring_bones.append(res)


func setup_post_children(game_object: RefCounted, state: RefCounted, node: Node, this_avatar_meta: RefCounted):
	if this_avatar_meta:
		post_process_avatar(game_object, state, node, this_avatar_meta)


func setup_post_prefab(prefab_object: RefCounted, state: RefCounted, instanced_scene: Node):
	# FIXME: this code assumes the skeleton is at the root of the prefab (such as an instanced fbx model) but this is not guaranteed.
	post_process_avatar(prefab_object, state, instanced_scene, null)


func setup_post_scene(pkgasset: RefCounted, root_objects: Array, root_skelleys: Array, state: RefCounted, instanced_scene: Node):
	for obj in root_objects:
		post_process_avatar(obj, state, instanced_scene, null)

func initialize_skelleys(state: RefCounted, objs: Array, is_prefab: bool):
	if vrm_collider_group_class == null or vrm_collider_class == null:
		print("Failed to import vrm classes")
		return null

	var some_obj: RefCounted = null
	for obj in objs:
		some_obj = obj
		if obj.type != "MonoBehaviour" or obj.is_stripped:
			continue

		var root_obj: RefCounted = obj
		var matched_rootbones = find_key(obj.keys, {"rootbones": 0}, TYPE_ARRAY)
		var matched_root: Array = find_key(obj.keys, {"transform": 0, "root": 0}, -1)
		var matched2: Array = find_key(obj.keys, {"drag": 0, "damp": 0, "spring": func(x): return 1 - x}, TYPE_FLOAT)
		var matched3: Array = find_key(obj.keys, {"stiff": 0, "elastic": func(x): return 4.0 * x, "pull": func(x): return 4.0 * x}, TYPE_FLOAT)
		if (matched_root or matched_rootbones) and matched2 and matched3:
			obj.log_debug("Found a Springobne component " + str(obj) + " " + str(obj.gameObject))
			var transform_objs: Array[RefCounted] # Transform object
			if matched_rootbones:
				for ref in matched_rootbones[0]:
					transform_objs.append(obj.meta.lookup(ref))
			else:
				if matched_root[0][1] != 0:
					transform_objs.append(obj.meta.lookup(matched_root[0])) # always a Transform object
				else:
					var go = root_obj.gameObject
					# We have to rely on stripped game objects here because prefabs haven't been resolved yet.
					if go != null and not go.is_stripped:
						transform_objs.append(go.transform)
			for transform_obj in transform_objs:
				# For now, pick the first skeleton in the file. This will work for prefabs but break horribly for scenes.
				if len(state.skelleys) == 1:
					for this_skelley in state.skelleys:
						obj.log_debug("Add bone to only skelley " + str(transform_obj) + " " + str(state.skelleys[this_skelley]))
						state.add_bone_to_skelley(state.skelleys[this_skelley], transform_obj)
						break
				else:
					var new_skelley: RefCounted = state.create_skelley(transform_obj)
					# For now, we can't guess which skeleton to add it to.
					obj.log_warn("Add bone to new skelley " + str(transform_obj) + " " + str(new_skelley))
					state.add_bone_to_skelley(new_skelley, transform_obj)
					obj.log_debug(str(new_skelley.parent_transform) + " - " + str(transform_obj))
					var x: RefCounted = new_skelley.parent_transform
					if x != null and x.is_prefab_reference:
						var prefab_id = x.prefab_instance[1]
						if not state.prefab_state.skelleys_by_parented_prefab.has(prefab_id):
							state.prefab_state.skelleys_by_parented_prefab[prefab_id] = [].duplicate()
						obj.log_debug("Adding to prefab " + str(prefab_id))
						state.prefab_state.skelleys_by_parented_prefab[prefab_id].push_back(new_skelley)
		detect_spring_bone_collider(obj, state)
		detect_spring_bone(obj, state)

	if some_obj != null:
		some_obj.log_debug("vrm end init")
