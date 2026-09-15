class_name UnidotAnimator extends UnidotBehaviour

const anim_tree_runtime := preload("../../runtime/anim_tree.gd")

var forced_humanoid_avatar_meta: Resource

func get_godot_type() -> String:
	return "AnimationTree"

func _find_mesh_reference_recursive(xform: UnidotTransform) -> Object:
	children_refs = xform.children_refs
	for ref in children_refs:
		var child = meta.lookup(ref, true)
		if child != null:
			var child_go: UnidotGameObject = child.gameObject
			if child_go != null:
				var smr := child_go.GetComponent("SkinnedMeshRenderer")
				if smr != null:
					var mesh_ref = smr.keys.get("m_Mesh")
					if mesh_ref != null and len(mesh_ref) > 3:
						var ret = meta.lookup_meta(mesh_ref)
						if ret.internal_data.has("humanoid_root_bone"):
							return ret
	for ref in children_refs:
		var child = meta.lookup(ref, true)
		if child != null:
			var ret = _find_mesh_reference_recursive(child)
			if ret != null:
				return ret
	return null

func get_avatar_meta() -> Object:
	var ret = meta.lookup_meta(keys.get("m_Avatar", [null, 0, "", null]))
	if ret != null:
		return ret
	if forced_humanoid_avatar_meta != null:
		return forced_humanoid_avatar_meta
	return null

func assign_controller(anim_player: AnimationPlayer, anim_tree: AnimationTree, controller_ref: Array):
	var main_library: AnimationLibrary = null
	var base_library: AnimationLibrary = null
	var root_node: AnimationRootNode = null
	var referenced_resource: Resource = meta.get_godot_resource(controller_ref)
	if referenced_resource is AnimationLibrary:
		main_library = referenced_resource
		root_node = main_library.get_meta("base_node")
		base_library = main_library.get_meta("base_library")
	else:
		root_node = referenced_resource
		var lib_ref: Array = [null, -controller_ref[1], controller_ref[2], controller_ref[3]]
		main_library = meta.get_godot_resource(lib_ref)
	for libname in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(StringName(libname))
	if anim_player.has_animation_library(&""):
		# Imported models such as prefabs may come with a library, but we need to use our own.
		anim_player.remove_animation_library(&"")
	anim_player.add_animation_library(&"", main_library)
	if base_library != null:
		anim_player.add_animation_library(&"base", base_library)
	anim_tree.tree_root = root_node

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var animplayer: AnimationPlayer = AnimationPlayer.new()
	animplayer.name = "AnimationPlayer"
	state.add_child(animplayer, new_parent, self)
	animplayer.root_node = NodePath("..")
	if keys.get("m_ApplyRootMotion", 0) == 0:
		if not state.active_avatars.is_empty():
			# Godot 4.1 and earlier only support this on AnimationTree
			animplayer.set("root_motion_track", NodePath("%GeneralSkeleton:Root"))

	var animtree: AnimationTree = AnimationTree.new()
	animtree.name = "AnimationTree"
	animtree.set("deterministic", false) # New feature in 4.2, acts like Untiy write defaults off
	if keys.get("m_ApplyRootMotion", 0) == 0:
		if not state.active_avatars.is_empty():
			animtree.root_motion_track = NodePath("%GeneralSkeleton:Root")
	state.add_child(animtree, new_parent, self)
	animtree.anim_player = animtree.get_path_to(animplayer)
	animtree.active = meta.setting_animtree_active() and keys.get("m_Enabled", true)
	animtree.set_script(anim_tree_runtime)
	# TODO: Add AnimationTree as well.
	assign_controller(animplayer, animtree, keys["m_Controller"])
	return animtree

func setup_post_children(node: Node, avatar_meta: RefCounted):
	var animtree: AnimationTree = node
	var anim_player: AnimationPlayer = animtree.get_node(animtree.anim_player)
	var anim_controller_meta: Resource = meta.lookup_meta(keys["m_Controller"])
	var virtual_unidot_object: UnidotRuntimeAnimatorController = meta.lookup_or_instantiate(keys["m_Controller"], "RuntimeAnimatorController")
	if virtual_unidot_object != null:
		# couldn't find meta. this means it probably won't work.
		virtual_unidot_object.adapt_animation_player_at_node(self, anim_player)

	var sph := SkeletonProfileHumanoid.new()
	var root_node := anim_player.get_node(anim_player.root_node)
	var reset_animation: Animation = anim_player.get_animation(&"RESET") if anim_player.has_animation(&"RESET") else Animation.new()
	var reset_used_dict: Dictionary
	for idx in reset_animation.get_track_count():
		reset_used_dict[str(reset_animation.track_get_type(idx)) + str(reset_animation.track_get_path(idx))] = true
	if avatar_meta != null:
		var tpose_animation: Animation = anim_player.get_animation(&"_T-Pose_") if anim_player.has_animation(&"_T-Pose_") else Animation.new()
		if anim_player.has_animation(&"_T-Pose_"):
			tpose_animation = anim_player.get_animation(&"_T-Pose_")
		else:
			tpose_animation = Animation.new()
		var skel: Skeleton3D
		if root_node != null:
			skel = root_node.get_node_or_null(^"%GeneralSkeleton") as Skeleton3D
		var t_used_dict: Dictionary
		for idx in tpose_animation.get_track_count():
			t_used_dict[str(tpose_animation.track_get_type(idx)) + str(tpose_animation.track_get_path(idx))] = true
		if skel != null:
			var motion_scale: float = skel.motion_scale
			if motion_scale <= 0:
				motion_scale = 1.0
			for bone_idx in range(skel.get_bone_count()):
				var bone_name: String = skel.get_bone_name(bone_idx)
				if sph.find_bone(bone_name) == -1:
					continue
				var bone_rest := skel.get_bone_rest(bone_idx)
				if not t_used_dict.has(str(Animation.TYPE_ROTATION_3D) + "%GeneralSkeleton:" + str(bone_name)):
					var idx := tpose_animation.add_track(Animation.TYPE_ROTATION_3D)
					tpose_animation.track_set_path(idx, "%GeneralSkeleton:" + str(bone_name))
					tpose_animation.rotation_track_insert_key(idx, 0.0, bone_rest.basis.get_rotation_quaternion())
				if not reset_used_dict.has(str(Animation.TYPE_ROTATION_3D) + "%GeneralSkeleton:" + str(bone_name)):
					var idx := reset_animation.add_track(Animation.TYPE_ROTATION_3D)
					reset_animation.track_set_path(idx, "%GeneralSkeleton:" + str(bone_name))
					reset_animation.rotation_track_insert_key(idx, 0.0, skel.get_bone_pose_rotation(bone_idx))
				if bone_name == "Hips" or bone_name == "Root":
					if not t_used_dict.has(str(Animation.TYPE_POSITION_3D) + "%GeneralSkeleton:" + str(bone_name)):
						var idx := tpose_animation.add_track(Animation.TYPE_POSITION_3D)
						tpose_animation.track_set_path(idx, "%GeneralSkeleton:" + str(bone_name))
						tpose_animation.position_track_insert_key(idx, 0.0, bone_rest.origin / motion_scale)
					if not reset_used_dict.has(str(Animation.TYPE_POSITION_3D) + "%GeneralSkeleton:" + str(bone_name)):
						var idx := reset_animation.add_track(Animation.TYPE_POSITION_3D)
						reset_animation.track_set_path(idx, "%GeneralSkeleton:" + str(bone_name))
						reset_animation.position_track_insert_key(idx, 0.0, skel.get_bone_pose_position(bone_idx) / motion_scale)
		if not anim_player.has_animation(&"_T-Pose_"):
			if not anim_player.has_animation_library(&""):
				anim_player.add_animation_library(&"", AnimationLibrary.new())
			anim_player.get_animation_library(&"").add_animation(&"_T-Pose_", tpose_animation)
	for library_name in anim_player.get_animation_library_list():
		var library: AnimationLibrary = anim_player.get_animation_library(library_name)
		for clip_name in library.get_animation_list():
			if clip_name == &"_T-Pose_" or clip_name == &"RESET":
				continue
			var src_clip: Animation = library.get_animation(clip_name)
			for idx in range(src_clip.get_track_count()):
				var path := src_clip.track_get_path(idx)
				var path_str := str(path)
				var type := src_clip.track_get_type(idx)
				if (type == Animation.TYPE_POSITION_3D or type == Animation.TYPE_POSITION_3D) and path_str.trim_prefix("%").begins_with("%GeneralSkeleton:"):
					if sph.find_bone(path.get_concatenated_subnames()) != -1:
						continue # We process humanoid tracks separately (above)
				if reset_used_dict.has(str(type) + path_str):
					continue
				var reset_idx := reset_animation.add_track(type)
				reset_animation.track_set_path(reset_idx, path)
				var child_node := root_node.get_node_or_null(NodePath(path.get_concatenated_names()))
				match type:
					Animation.TYPE_VALUE:
						if child_node != null and path.get_subname_count() > 0:
							var value: Variant = child_node
							var fail: bool = false
							for subidx in range(path.get_subname_count()):
								value = value.get(path.get_subname(subidx))
								if typeof(value) != TYPE_OBJECT or value == null:
									fail = true
									break
							if not fail:
								reset_animation.track_insert_key(reset_idx, 0.0, value)
					Animation.TYPE_BLEND_SHAPE:
						var blendshape_name: StringName = path.get_concatenated_subnames()
						var mi := child_node as MeshInstance3D
						if mi != null:
							var bsidx := mi.find_blend_shape_by_name(blendshape_name)
							if bsidx != -1:
								var blendshape_value: float = mi.get_blend_shape_value(bsidx)
								reset_animation.blend_shape_track_insert_key(reset_idx, 0.0, blendshape_value)
					Animation.TYPE_POSITION_3D:
						var bone_name: StringName = path.get_concatenated_subnames()
						var node_3d := child_node as Node3D
						if child_node != null and bone_name != &"":
							var skel := child_node as Skeleton3D
							if skel != null:
								var motion_scale: float = skel.motion_scale
								if motion_scale <= 0:
									motion_scale = 1.0
								var bone_idx := skel.find_bone(bone_name)
								if bone_idx != -1:
									reset_animation.position_track_insert_key(reset_idx, 0.0, skel.get_bone_pose_position(bone_idx) / motion_scale)
						elif node_3d != null:
							reset_animation.position_track_insert_key(reset_idx, 0.0, node_3d.position)
					Animation.TYPE_ROTATION_3D:
						var bone_name: StringName = path.get_concatenated_subnames()
						var node_3d := child_node as Node3D
						if child_node != null and bone_name != &"":
							var skel := child_node as Skeleton3D
							if skel != null:
								var bone_idx := skel.find_bone(bone_name)
								if bone_idx != -1:
									reset_animation.rotation_track_insert_key(reset_idx, 0.0, skel.get_bone_pose_rotation(bone_idx))
						elif node_3d != null:
							reset_animation.rotation_track_insert_key(reset_idx, 0.0, node_3d.quaternion)
					Animation.TYPE_SCALE_3D:
						var bone_name: StringName = path.get_concatenated_subnames()
						var node_3d := child_node as Node3D
						if child_node != null and bone_name != &"":
							var skel := child_node as Skeleton3D
							if skel != null:
								var bone_idx := skel.find_bone(bone_name)
								if bone_idx != -1:
									reset_animation.scale_track_insert_key(reset_idx, 0.0, skel.get_bone_pose_scale(bone_idx))
						elif node_3d != null:
							reset_animation.scale_track_insert_key(reset_idx, 0.0, node_3d.scale)
				reset_used_dict[str(type) + path_str] = true
	if not anim_player.has_animation(&"RESET") and (not reset_used_dict.is_empty() or avatar_meta != null):
		if not anim_player.has_animation_library(&""):
			anim_player.add_animation_library(&"", AnimationLibrary.new())
		anim_player.get_animation_library(&"").add_animation(&"RESET", reset_animation)
	#if anim_controller != null:
	#	animplayer.add_animation_library(&"", anim_controller.create_animation_library_at_node(self, node.get_parent()))

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	log_debug("Animator convert_properties " + str(outdict))
	if uprops.has("m_Controller"):
		if node is AnimationTree:
			assign_controller(node.get_node(node.anim_player), node, uprops["m_Controller"])
	if uprops.has("m_ApplyRootMotion"):
		if uprops.get("m_ApplyRootMotion", 0) == 0:
			outdict["root_motion_track"] = NodePath("%GeneralSkeleton:Root")
		else:
			outdict["root_motion_track"] = NodePath()
	return outdict
