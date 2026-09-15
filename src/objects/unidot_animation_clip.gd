class_name UnidotAnimationClip extends UnidotMotion

const human_trait = preload("../../humanoid/human_trait.gd")
const humanoid_transform_util = preload("../../humanoid/transform_util.gd")

func get_godot_type() -> String:
	return "Animation"

func get_godot_extension() -> String:
	return ".anim.tres"

func create_godot_resource() -> Resource:  #Animation:
	if not meta.godot_resources.is_empty():
		return null  # We will create them when referenced.

	# We will try our best to infer this data, but we get better results
	# if created relative to a particular node.
	return create_animation_clip_at_node(null, null)

func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
	var anim_key = "%s:%d" % [self.meta.guid, self.fileID]
	if out_guid_fid_to_anim_name.has(anim_key):
		return
	var basename: String = self.keys["m_Name"]
	var num = 1
	var name: String = basename
	while uniq_name_dict.has(name):
		name = "%s %d" % [name, num]
		num += 1
	uniq_name_dict[name] = 1
	out_guid_fid_to_anim_name[anim_key] = name

func default_gameobject_component_path(unipath: String, unicomp: Variant) -> NodePath:
	if typeof(unicomp) == TYPE_INT and (unicomp == 1 or unicomp == 4):
		return NodePath(unipath)
	return NodePath(unipath + "/" + adapter.to_classname(unicomp))

func resolve_gameobject_component_path(animator: Object, unipath: String, unicomp: Variant) -> NodePath:  # UnidotAnimator
	if animator == null:
		return default_gameobject_component_path(unipath, unicomp)
	var animator_go: UnidotGameObject = animator.gameObject
	var path_split: PackedStringArray = unipath.split("/")
	var current_fileID: int = 0 if animator_go == null else animator_go.fileID
	var animator_nodepath: NodePath = animator.meta.prefab_fileid_to_nodepath.get(current_fileID, animator.meta.fileid_to_nodepath.get(current_fileID, NodePath()))
	var current_obj: Dictionary = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
	var extra_path: String = ""
	for path_component in path_split:
		log_debug("Look for component %s in %d:%s" % [path_component, current_fileID, str(current_obj)])
		if extra_path.is_empty() and current_obj.has(path_component):
			current_fileID = current_obj[path_component]
			current_obj = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
		else:
			extra_path += "/" + str(path_component)
	log_debug("Path %s became %d comp %s %s current %s" % [str(path_split), current_fileID, str(unicomp), extra_path, str(current_obj)])
	if extra_path.is_empty() and (typeof(unicomp) != TYPE_INT or unicomp != 1):
		current_fileID = current_obj.get(unicomp, current_fileID)
	var nodepath: NodePath = animator.meta.prefab_fileid_to_nodepath.get(current_fileID, animator.meta.fileid_to_nodepath.get(current_fileID, NodePath()))
	log_debug("Resolving %d to %s" % [current_fileID, str(nodepath)])
	if nodepath == NodePath():
		log_debug("Returning default nodepath because some path failed to resolve.")
		if typeof(unicomp) == TYPE_INT:
			if unicomp == 1 or unicomp == 4:
				return NodePath(unipath)
			return NodePath(unipath + "/" + adapter.to_classname(unicomp))
		return NodePath(unipath)
	if nodepath == animator_nodepath:
		nodepath = "."
	elif str(nodepath).begins_with(str(animator_nodepath) + "/"):
		nodepath = NodePath(str(nodepath).substr(len(str(animator_nodepath)) + 1))
	elif str(animator_nodepath) == "." or str(nodepath) == ".":
		pass
	else:
		log_warn("NodePath " + str(nodepath) + " not within the animator path " + str(animator_nodepath), "", [null,current_fileID,"",0])
	if not extra_path.is_empty():
		nodepath = NodePath(str(nodepath) + extra_path)
	var skeleton_bone: String = animator.meta.prefab_fileid_to_skeleton_bone.get(current_fileID, animator.meta.fileid_to_skeleton_bone.get(current_fileID, ""))
	if not skeleton_bone.is_empty() and (typeof(unicomp) == TYPE_INT or unicomp == 4):
		return NodePath(str(nodepath) + ":" + skeleton_bone)
	return nodepath

func adapt_track_nodepaths_for_node(animator: RefCounted, node_parent: Node, clip: Animation) -> Array:
	var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
	var new_track_names: Array = []
	var identical: int = 0
	var scale_tracks: Dictionary
	var rot_tracks: Dictionary
	var transform_nodepath_to_fileid: Dictionary
	var mesh_nodepath_to_fileid: Dictionary
	var reverse_gameobject_to_name: Dictionary
	var reverse_gameobject_to_parent: Dictionary
	for fileid in meta.gameobject_name_to_fileid_and_children:
		var dic: Dictionary = meta.gameobject_name_to_fileid_and_children[fileid]
		for chld in dic:
			if typeof(chld) == TYPE_STRING:
				reverse_gameobject_to_name[dic[chld]] = chld
				reverse_gameobject_to_parent[dic[chld]] = fileid
	for fileid in meta.fileid_to_nodepath:
		var nodepath: NodePath = meta.fileid_to_nodepath[fileid]
		var skel_bone: String = meta.fileid_to_skeleton_bone.get(fileid, "")
		if not skel_bone.is_empty():
			nodepath = NodePath(String(nodepath) + ":" + skel_bone)
		# internal_data.get("godot_sanitized_to_orig_remap", {})
		if meta.fileid_to_utype[fileid] == 4: # Transform
			transform_nodepath_to_fileid[nodepath] = meta.fileid_to_gameobject_fileid.get(fileid, 0)
		elif meta.fileid_to_utype[fileid] == 137: # SkinnedMeshRenderer
			mesh_nodepath_to_fileid[nodepath] = meta.fileid_to_gameobject_fileid.get(fileid, 0)
	for track_idx in range(clip.get_track_count()):
		var typ: int = clip.track_get_type(track_idx)
		var resolved_key: String = str(clip.track_get_path(track_idx)).replace("%GeneralSkeleton/", "")
		match typ:
			Animation.TYPE_ROTATION_3D:
				rot_tracks["T" + resolved_key] = track_idx
			Animation.TYPE_SCALE_3D:
				scale_tracks["T" + resolved_key] = track_idx
	for track_idx in range(clip.get_track_count()):
		var typ: int = clip.track_get_type(track_idx)
		var resolved_key: String = str(clip.track_get_path(track_idx)).replace("%GeneralSkeleton/", "")
		var resolved_subpath: String = NodePath(resolved_key).get_concatenated_subnames()
		var source_fileid: int = 0
		match typ:
			Animation.TYPE_BLEND_SHAPE:
				var mesh_key: NodePath = NodePath(clip.track_get_path(track_idx).get_concatenated_names())
				if mesh_nodepath_to_fileid.has(mesh_key):
					source_fileid = mesh_nodepath_to_fileid[mesh_key]
			Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
				var transform_key: NodePath = clip.track_get_path(track_idx)
				if str(transform_key).begins_with("%GeneralSkeleton:"):
					new_track_names.append([clip.track_get_path(track_idx), "", []])
					identical += 1
					continue
				if transform_nodepath_to_fileid.has(transform_key):
					source_fileid = transform_nodepath_to_fileid[transform_key]

		var orig_info: Array
		if source_fileid != 0:
			var source_path_components: PackedStringArray
			var parent_fileid := source_fileid
			while parent_fileid != 0 and reverse_gameobject_to_name.has(parent_fileid) and len(source_path_components) < 100:
				source_path_components.append(reverse_gameobject_to_name[parent_fileid])
				parent_fileid = reverse_gameobject_to_parent[parent_fileid]
			if source_path_components.is_empty():
				log_warn("Unable to lookup reverse name " + str(parent_fileid))
			source_path_components.reverse()
			var source_path: String = "/".join(source_path_components)
			var source_classID: int
			if typ == Animation.TYPE_BLEND_SHAPE:
				resolved_key = "B" + source_path + ":" + resolved_subpath
				source_classID = 137
			else:
				resolved_key = "T" + source_path
				resolved_subpath = ""
				source_classID = 4
			orig_info = [source_path, resolved_key, source_classID]
			log_debug("Converting imported Godot NodePath to " + str([source_path, resolved_key, source_classID]))
		else:
			match typ:
				Animation.TYPE_BLEND_SHAPE:
					resolved_key = "B" + resolved_key
				Animation.TYPE_VALUE:
					resolved_key = "V" + resolved_key
				Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
					resolved_key = "T" + resolved_key
				_:
					log_warn(str(self) + ": anim Unsupported track type " + str(typ) + " at " + resolved_key)
					new_track_names.append([clip.track_get_path(track_idx), "", []])
					identical += 1
					continue  # unsupported track type.
			if not resolved_to_default_paths.has(resolved_key):
				if not resolved_key.begins_with("T%GeneralSkeleton"): # This is normal
					log_warn(str(self) + ": anim No default " + str(typ) + " track path at " + resolved_key)
				new_track_names.append([clip.track_get_path(track_idx), "", []])
				identical += 1
				continue
			orig_info = resolved_to_default_paths[resolved_key]
		var path: String = orig_info[0]
		var attr: String = orig_info[1]
		var classID: int = orig_info[2]
		#var orig_path: String = NodePath(path).get_concatenated_subnames()
		#var orig_pathname: String = orig_path
		var new_path: NodePath = NodePath()
		var new_resolved_key: String = ""
		match typ:
			Animation.TYPE_BLEND_SHAPE:
				classID = 137
				new_path = resolve_gameobject_component_path(animator, path, classID)
				if new_path != NodePath():
					new_path = NodePath(str(new_path) + ":" + str(resolved_subpath))
				new_resolved_key = "B" + str(new_path)
			Animation.TYPE_VALUE:
				new_path = resolve_gameobject_component_path(animator, path, classID)
				if new_path != NodePath():
					new_path = NodePath(str(new_path) + ":" + str(resolved_subpath))
				log_debug("Adapt TYPE_VALUE track " + str(path) + " to " + str(new_path))
				new_resolved_key = "V" + str(new_path)
			Animation.TYPE_ROTATION_3D:
				classID = 4
				new_path = resolve_gameobject_component_path(animator, path, classID)
				log_debug("Adapt TYPE_ROTATION_3D track " + str(path) + " to " + str(new_path))
				new_resolved_key = "T" + str(new_path)
			Animation.TYPE_SCALE_3D:
				classID = 4
				new_path = resolve_gameobject_component_path(animator, path, classID)
				log_debug("Adapt TYPE_SCALE_3D track " + str(path) + " to " + str(new_path))
				new_resolved_key = "T" + str(new_path)
			Animation.TYPE_POSITION_3D:
				classID = 4
				new_path = resolve_gameobject_component_path(animator, path, classID)
				log_debug("Adapt TYPE_POSITION_3D track " + str(path) + " to " + str(new_path))
				new_resolved_key = "T" + str(new_path)
				var resolved_node: Node3D = node_parent.get_node_or_null(new_path)
				log_debug(str(node_parent.name) + ": " + str(resolved_node))
				if resolved_node != null:
					var animator_go: UnidotGameObject = animator.gameObject
					var path_split: PackedStringArray = path.split("/")
					var current_fileID: int = 0 if animator_go == null else animator_go.fileID
					var current_obj: Dictionary = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
					for path_component in path_split:
						if current_obj.has(path_component):
							current_fileID = current_obj[path_component]
							current_obj = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
					current_fileID = current_obj.get(classID, current_fileID)
					log_debug("Found fileID " + str(current_fileID))
					var virtual_transform_obj: UnidotObject = adapter.instantiate_unidot_object_from_utype(animator.meta, current_fileID, classID)
					var godot_rotation: Quaternion = resolved_node.quaternion
					var godot_scale: Vector3 = resolved_node.get_scale()
					var rot_track: int = rot_tracks.get(resolved_key, -1)
					var scale_track: int = scale_tracks.get(resolved_key, -1)
					for key in range(clip.track_get_key_count(track_idx)):
						var ts: float = clip.track_get_key_time(track_idx, key)
						if rot_track != -1:
							godot_rotation = clip.rotation_track_interpolate(rot_track, ts)
						if scale_track != -1:
							godot_scale = clip.scale_track_interpolate(scale_track, ts)
						var pos: Vector3 = clip.position_track_interpolate(track_idx, ts)
						var upos: Vector3 = Vector3(-pos.x, pos.y, pos.z)
						var uquat: Quaternion = godot_rotation
						uquat.y = -uquat.y
						uquat.z = -uquat.z
						var converted_pos: Vector3 = virtual_transform_obj._convert_properties_pos_scale({"m_LocalPosition": upos}, upos, uquat, godot_scale)["position"]
						# log_debug("Adapt key " + str(key) + " ts " + str(ts) + " rot=" + str(godot_rotation.get_euler()) + " scale=" + str(godot_scale) + " pos " + str(pos) + " -> " + str(converted_pos))
						clip.track_set_key_value(track_idx, key, converted_pos)
		if new_path == NodePath():
			log_warn(str(self) + ": anim Unable to resolve " + str(typ) + " track at " + resolved_key + " orig " + str(orig_info))
			identical += 1
			new_track_names.append([clip.track_get_path(track_idx), resolved_key, orig_info])
			continue
		new_track_names.append([new_path, new_resolved_key, orig_info])
		if new_resolved_key == resolved_key:
			identical += 1
	if identical == len(new_track_names):
		return []
	return new_track_names

func adapt_animation_clip_at_node(animator: RefCounted, node_parent: Node, clip: Animation):
	var generated_track_nodepaths: Array = adapt_track_nodepaths_for_node(animator, node_parent, clip)
	if generated_track_nodepaths.is_empty():  # Already adapted.
		return clip
	if meta.importer_type != "NativeFormatImporter" and meta.importer_type != "DefaultImporter":
		if meta.godot_resources.has(-fileID):
			return meta.get_godot_resource([null, -fileID, null, 0])
		var adapted_resource_path: String = clip.resource_path.get_basename().get_basename() + meta.fixup_godot_extension(".adaptedanim.tres")
		clip = clip.duplicate()
		clip.resource_path = adapted_resource_path
		meta.insert_resource_path(-fileID, clip.resource_path)
	# var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
	var new_resolved_to_default: Dictionary = {}.duplicate()
	for track_idx in range(clip.get_track_count()):
		var new_path: NodePath = generated_track_nodepaths[track_idx][0]
		var new_resolved_key: String = generated_track_nodepaths[track_idx][1]
		var orig_info: Array = generated_track_nodepaths[track_idx][2]
		if not orig_info.is_empty():
			new_resolved_to_default[new_resolved_key] = orig_info
		clip.track_set_path(track_idx, new_path)
	clip.set_meta("resolved_to_default_paths", new_resolved_to_default)
	if clip.resource_path != StringName():
		adapter.unidot_utils.save_resource(clip, clip.resource_path)
	return clip

# NOTE: This function is dead code (unused).
# The idea is if there are multiple "solutions" to adapting animation clips, this could allow storing both
# variants of the animation clip by hash, allowing multiple scenes to share their versions of adapted clips.
func get_adapted_clip_path_hash(animator: RefCounted, node_parent: Node, clip: Animation) -> int:
	var generated_track_nodepaths: Array = adapt_track_nodepaths_for_node(animator, node_parent, clip)
	if generated_track_nodepaths.is_empty():  # Already adapted.
		return 0
	# var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
	var new_hash_data: PackedByteArray = PackedByteArray().duplicate()
	var hashctx = HashingContext.new()
	hashctx.start(HashingContext.HASH_MD5)
	for track_idx in range(clip.get_track_count()):
		var new_path: NodePath = generated_track_nodepaths[track_idx][0]
		var new_resolved_key: String = generated_track_nodepaths[track_idx][1]
		var orig_info: Array = generated_track_nodepaths[track_idx][2]
		if not orig_info.is_empty():
			hashctx.update(new_resolved_key.to_utf8_buffer())
			hashctx.update(str(orig_info).to_utf8_buffer())
	# This is arbitrary--just so we can cache existing versions of animation clips
	return hashctx.finish().decode_s64(0)

func create_animation_clip_at_node(animator: RefCounted, node_parent: Node) -> Animation:  # UnidotAnimator
	var anim: Animation = Animation.new()

	var bone_name_to_index := human_trait.bone_name_to_index() # String -> int
	var muscle_name_to_index := human_trait.muscle_name_to_index() # String -> int
	var muscle_index_to_bone_and_axis := human_trait.muscle_index_to_bone_and_axis() # int -> Vector2i
	var special_humanoid_transforms : Dictionary
	for pfx in human_trait.IKPrefixNames:
		for sfx in human_trait.IKSuffixNames:
			special_humanoid_transforms[pfx + sfx] = human_trait.IKSuffixNames[sfx]
	for pfx in human_trait.BoneName:
		special_humanoid_transforms[pfx + "TDOF.x"] = ""
		special_humanoid_transforms[pfx + "TDOF.y"] = ""
		special_humanoid_transforms[pfx + "TDOF.z"] = ""

	var settings: Dictionary = keys.get("m_AnimationClipSettings", {})
	var is_mirror: bool = settings.get("m_Mirror", 0) == 1
	var bake_orientation_into_pose: bool = settings.get("m_LoopBlendOrientation", 0) == 1
	var bake_position_y_into_pose: bool = settings.get("m_LoopBlendPositionY", 0) == 1
	var bake_position_xz_into_pose: bool = settings.get("m_LoopBlendPositionXZ", 0) == 1
	var keep_original_orientation: bool = settings.get("m_KeepOriginalOrientation", 0) == 1
	var keep_original_position_y: bool = settings.get("m_KeepOriginalPositionY", 0) == 1
	var keep_original_position_xz: bool = settings.get("m_KeepOriginalPositionXZ", 0) == 1
	var orientation_offset: float = settings.get("m_OrientationOffsetY", 0.0) * PI / 180.0
	var root_y_level: float = settings.get("m_Level", 0.0)

	# m_AnimationClipSettings[m_StartTime,m_StopTime,m_LoopTime,
	# m_KeepOriginPositionY/XZ/Orientation,m_HeightFromFeet,m_CycleOffset],
	# m_Bounds[m_Center,m_Extent],
	# m_ClipBindingConstant[genericBindings:Array[attribute:hash,customType:20,isPPtrCurve:0,path:hash,script:MonoScript],pptrCurveMapping[??]]
	# m_Compressed:[0,1], m_CompressedRotationCurves, m_Legacy, m_SampleRate (60)
	# m_EditorCurves, m_EulerEditorCurves
	# m_EulerCurves, m_FloatCurves, m_PositionCruves, m_PPtrCurves, m_RotationCurves, m_ScaleCurves
	var resolved_to_default: Dictionary = {}
	var max_ts: float = 0.0
	var humanoid_track_sets: Array[Array]
	var has_humanoid: bool = false
	for i in range(human_trait.BoneCount + 1):
		if i == 0:
			humanoid_track_sets.append([null, null, null, null])
		else:
			humanoid_track_sets.append([null, null, null])
	# humanoid bone idx -> array of Curve object indexed by muscle axis
	# [ [{attr:RootT.x},{attr:RootT.y},{attr:RootT.z}], [{attr:RootQ.x},y,z,w], [Shoulder In-Out,...] ...]

	for track in keys["m_FloatCurves"]:
		var attr: String = track["attribute"]
		var path: String = track.get("path", "")  # Some omit path if for the current GameObject...?
		var classID: int = track["classID"]  # Todo: convet classID to class guid+id
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_warn("Float curve is array")
			track_curve = {"m_Curve": track_curve}
		track_curve = track_curve.duplicate()
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty float curve detected " + path + ":" + attr)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
		if classID == 95 and special_humanoid_transforms.has(attr):
			var flip_sign: bool = false
			if is_mirror:
				if attr.find("Left-Right") != -1:
					track_curve["unidot-mirror"] = true
				elif attr.find("Left") != -1:
					attr = attr.replace("Left", "Right")
				elif attr.find("Right") != -1:
					attr = attr.replace("Right", "Left")
			# Humanoid Root / IK target parameters
			if attr.begins_with("RootT."):
				# hips position (scaled by human scale?)
				humanoid_track_sets[human_trait.BoneCount][special_humanoid_transforms[attr]] = track_curve
			elif attr.begins_with("RootQ."):
				# hips rotation
				humanoid_track_sets[0][special_humanoid_transforms[attr]] = track_curve
			has_humanoid = true
		elif classID == 95 and muscle_name_to_index.has(attr) or human_trait.TraitMapping.has(attr):
			# Humanoid muscle parameters
			var bone_idx_axis: Vector2i = muscle_index_to_bone_and_axis[muscle_name_to_index[human_trait.TraitMapping.get(attr, attr)]]
			humanoid_track_sets[bone_idx_axis.x][bone_idx_axis.y] = track_curve
			has_humanoid = true
		elif classID == 137 and attr.begins_with("blendShape."):
			var bstrack = anim.add_track(Animation.TYPE_BLEND_SHAPE)
			var str_nodepath: String = str(nodepath)
			if str_nodepath.ends_with("/SkinnedMeshRenderer"):
				str_nodepath = "%GeneralSkeleton/" + str_nodepath.split("/")[-2]
			nodepath = NodePath(str_nodepath + ":" + attr.substr(11))
			resolved_to_default["B" + str_nodepath] = [path, attr, classID]
			anim.track_set_path(bstrack, nodepath)
			anim.track_set_interpolation_type(bstrack, Animation.INTERPOLATION_LINEAR)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var val_variant: Variant = key_iter.next()
				if typeof(val_variant) == TYPE_STRING:
					val_variant = val_variant.to_float()
				var value: float = val_variant
				var ts: float = key_iter.timestamp
				anim.blend_shape_track_insert_key(bstrack, ts, value / 100.0)
		else:
			if classID == 95: # animated Animator parameters / aaps. Humanoid should be done separately.
				nodepath = NodePath(".:metadata/" + attr)
			else:
				var target_node: Node = null
				if node_parent != null:
					target_node = node_parent.get_node(nodepath)
					log_debug("nodepath %s from %s %s became %s" % [str(nodepath), str(node_parent), str(node_parent.name), str(target_node)])
					if target_node == null:
						var gdscriptweird: Node = null
						target_node = gdscriptweird
				# yuk yuk. This needs to be improved but should be a good start for some properties:
				var adapted_obj: UnidotObject = adapter.instantiate_unidot_object_from_utype(meta, 0, classID)  # no fileID??
				var converted_property_keys = adapted_obj.convert_properties(target_node, {attr: 0.0}).keys()
				if converted_property_keys.is_empty():
					log_warn("Unknown property " + str(attr) + " for " + str(path) + " type " + str(adapted_obj.type), attr, adapted_obj)
					continue
				var converted_property: String = converted_property_keys[0]
				nodepath = NodePath(str(nodepath) + ":" + converted_property)
			log_debug("Generated TYPE_VALUE node path " + str(nodepath))
			var valtrack = anim.add_track(Animation.TYPE_VALUE)
			resolved_to_default["V" + str(nodepath)] = [path, attr, classID]
			anim.track_set_path(valtrack, nodepath)
			anim.track_set_interpolation_type(valtrack, Animation.INTERPOLATION_LINEAR)
#			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var val_variant: Variant = key_iter.next()
				if typeof(val_variant) == TYPE_STRING:
					val_variant = val_variant.to_float()
				var value: float = val_variant
				var ts: float = key_iter.timestamp
				# FIXME: How does the last optional transition argument work?
				# It says it's used for easing, but I don't see it on blendshape or position tracks?!
				anim.track_insert_key(valtrack, ts, value)
	if has_humanoid:
		var key_iters: Array[LockstepKeyframeiterator]
		key_iters.resize(human_trait.BoneCount + 1)
		var used_ts: Dictionary
		var keyframe_timestamps: Array[float] # will sort
		var keyframe_affects_rootQ: Dictionary
		var per_bone_keyframe_used_ts: Array[Dictionary]
		var per_bone_timestamps: Array[PackedFloat64Array]
		per_bone_keyframe_used_ts.resize(human_trait.BoneCount + 1)
		per_bone_timestamps.resize(human_trait.BoneCount + 1)
		#var donated_limb_keyframe_times_and_twists: Array[PackedVector2Array]
		#var transforms: Array[Transform3D]
		#transforms.resize(human_trait.BoneCount)
		for bone_idx in range(0, human_trait.BoneCount + 1):
			var humanoid_track_set: Array = humanoid_track_sets[bone_idx]
			var keyframe_iters: Array[KeyframeIterator]
			keyframe_iters.resize(len(humanoid_track_set))
			for i in range(len(humanoid_track_set)):
				# may contain null if no animation curve exists.
				if typeof(humanoid_track_set[i]) == TYPE_DICTIONARY:
					# This is the outer object (["curve"]["m_Curve"])
					keyframe_iters[i] = KeyframeIterator.new(humanoid_track_set[i])
			var is_position_track: bool = bone_idx == human_trait.BoneCount
			var key_iter := LockstepKeyframeiterator.new(keyframe_iters, is_position_track)
			key_iters[bone_idx] = key_iter
			var last_ts: float = 0.0
			var same_ts: bool = false
			var itercnt: int = 0
			var affecting_bone_idx: int = human_trait.extraAffectingBones.get(bone_idx, -1)
			while not key_iter.is_eof and itercnt < 100000:
				itercnt += 1
				key_iter.next()
				var ts: float = key_iter.timestamp
				if human_trait.rootQAffectingBones.has(bone_idx) and not keyframe_affects_rootQ.has(ts):
					keyframe_affects_rootQ[ts] = true
				if not used_ts.has(ts):
					keyframe_timestamps.append(ts)
					used_ts[ts] = true
				if not per_bone_keyframe_used_ts[bone_idx].has(ts):
					per_bone_keyframe_used_ts[bone_idx][ts] = true
					per_bone_timestamps[bone_idx].append(ts)
				if affecting_bone_idx != -1 and not per_bone_keyframe_used_ts[affecting_bone_idx].has(ts):
					per_bone_keyframe_used_ts[affecting_bone_idx][ts] = true
					per_bone_timestamps[affecting_bone_idx].append(ts)
			key_iter.reset()
		keyframe_timestamps.sort()
		per_bone_keyframe_used_ts.clear()
		used_ts.clear()
		var timestamp_count := len(keyframe_timestamps)
		var body_bone_count := len(human_trait.boneIndexToParent)

		for bone_idx in range(1, human_trait.BoneCount):
			var godot_human_name: String = human_trait.GodotHumanNames[bone_idx]
			var gd_track: int = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(gd_track, "%GeneralSkeleton:" + godot_human_name)
			anim.track_set_interpolation_type(gd_track, Animation.INTERPOLATION_LINEAR)
			var bone_name: String = godot_human_name

			var key_iter := key_iters[bone_idx]
			var bone_timestamps: PackedFloat64Array = per_bone_timestamps[bone_idx]
			bone_timestamps.sort()
			var affected_by_bone_idx: int = human_trait.extraAffectedByBones.get(bone_idx, -1)
			var affected_by_key_iter: LockstepKeyframeiterator = null
			if affected_by_bone_idx != -1:
				affected_by_key_iter = key_iters[affected_by_bone_idx]
			var last_ts: float = 0
			for ts_idx in range(len(bone_timestamps)):
				var ts: float = bone_timestamps[ts_idx]
				var val_variant: Variant = key_iter.next(ts - last_ts)
				var this_swing_twist: Vector3 = val_variant as Vector3
				var weight = 1.0
				var pre_value := Quaternion.IDENTITY
				if affected_by_bone_idx != -1:
					weight = 0.5
					this_swing_twist.x *= weight
					var affected_by_variant: Variant = affected_by_key_iter.next(ts - last_ts)
					var affected_by_twist: Vector3 = affected_by_variant as Vector3
					affected_by_twist = Vector3(affected_by_twist.x * (1.0 - weight), 0, 0)
					pre_value = humanoid_transform_util.calculate_humanoid_rotation(affected_by_bone_idx, affected_by_twist, true)
				# swing-twist muscle track
				var value: Quaternion = humanoid_transform_util.calculate_humanoid_rotation(bone_idx, this_swing_twist)
				anim.rotation_track_insert_key(gd_track, ts, pre_value * value)
				last_ts = ts
			key_iter.reset()
			if affected_by_bone_idx != -1:
				affected_by_key_iter.reset()

		if not keyframe_timestamps.is_empty():
			# Root position track
			var gd_track_root_pos: int = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(gd_track_root_pos, "%GeneralSkeleton:Root")
			anim.track_set_interpolation_type(gd_track_root_pos, Animation.INTERPOLATION_LINEAR)
			var base_root_pos_offset := Vector3.ZERO
			if bake_position_xz_into_pose and bake_position_y_into_pose:
				if not bake_position_y_into_pose:
					if keep_original_position_y:
						base_root_pos_offset.y = root_y_level # Hips offset is always precisely 1
					else:
						# Ignoring m_HeightFromFeet boolean. it's a small effect and not sure how it's calculated.
						base_root_pos_offset.y = 1.0 + root_y_level

				anim.position_track_insert_key(gd_track_root_pos, 0.0, Vector3())
			# Hips position track
			var gd_track_pos: int = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(gd_track_pos, "%GeneralSkeleton:Hips")
			anim.track_set_interpolation_type(gd_track_pos, Animation.INTERPOLATION_LINEAR)
			var key_iter_pos := key_iters[human_trait.BoneCount] # LockstepKeyframeiterator.new(keyframe_iters)

			# Root rotation track
			var gd_track_root_rot: int = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(gd_track_root_rot, "%GeneralSkeleton:Root")
			anim.track_set_interpolation_type(gd_track_root_rot, Animation.INTERPOLATION_LINEAR)
			var base_y_rotation := Quaternion.IDENTITY
			if bake_position_xz_into_pose and bake_position_y_into_pose:
				var euler_y: float = - orientation_offset
				base_y_rotation = Quaternion.from_euler(Vector3(0, euler_y, 0))
				anim.rotation_track_insert_key(gd_track_root_rot, 0.0, base_y_rotation) # Root rest rotation is identity

			# Hips rotation track
			var gd_track_rot: int = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(gd_track_rot, "%GeneralSkeleton:Hips")
			anim.track_set_interpolation_type(gd_track_rot, Animation.INTERPOLATION_LINEAR)
			var key_iter_rot := key_iters[0] # LockstepKeyframeiterator.new(keyframe_iters)

			var last_ts: float = 0
			var body_positions: Array[Vector3]
			var body_rotations: Array[Quaternion]
			body_positions.resize(body_bone_count)
			body_rotations.resize(body_bone_count)
			# We need to evaluate the position tracks at each timestep and calculate
			# the human pose so we can apply the center of mass corerction
			for ts_idx in range(len(keyframe_timestamps)):
				var ts: float = keyframe_timestamps[ts_idx]
				body_positions[0] = human_trait.xbot_positions[0] # Hips position is hardcoded
				body_rotations[0] = Quaternion.IDENTITY # rest Hips rotation in Godot is always identity
				for body_bone_idx in range(1, body_bone_count):
					var bone_idx: int = human_trait.boneIndexToMono[body_bone_idx]
					var parent_body_bone_idx: int = human_trait.boneIndexToParent[body_bone_idx]
					var local_bone_pos: Vector3 = human_trait.xbot_positions[body_bone_idx]
					var key_iter := key_iters[bone_idx]
					var pre_dbg: String = key_iter.debug()
					var val_variant: Variant = key_iter.next(ts - last_ts)
					var swing_twist: Vector3 = val_variant as Vector3
					# swing-twist muscle track
					var local_rot: Quaternion = humanoid_transform_util.calculate_humanoid_rotation(bone_idx, swing_twist)
					if not local_rot.is_normalized():
						push_error("local_rot " + str(body_bone_idx) + " is not normalized!")
						return
					if (key_iter.timestamp != ts) and not key_iter.is_eof:
						push_warning("State was: " + pre_dbg)
						push_error("bone " + str(human_trait.GodotHumanNames[bone_idx]) + " timestamp " + str(key_iter.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter.debug())
					var par_position := body_positions[parent_body_bone_idx]
					var par_rotation := body_rotations[parent_body_bone_idx]
					if not par_rotation.is_normalized():
						push_error("par_rotation " + str(parent_body_bone_idx) + " is not normalized!")
						return
					body_positions[body_bone_idx] = par_position + par_rotation * local_bone_pos
					body_rotations[body_bone_idx] = par_rotation * local_rot
					if not body_rotations[body_bone_idx].is_normalized():
						push_error("body_rotation " + str(body_bone_idx) + " is not normalized!")
						return

				# Calulcate center of mass
				var pre_dbg_rot: String = key_iter_rot.debug()
				var val_rotation_variant: Variant = key_iter_rot.next(ts - last_ts)
				var root_q: Quaternion = val_rotation_variant as Quaternion
				if is_mirror:
					root_q.y = -root_q.y
					root_q.z = -root_q.z
				if not root_q.is_normalized():
					push_error("root q is not normalized!")
					return
				if (key_iter_rot.timestamp != ts) and not key_iter_rot.is_eof:
					push_warning("RootQ State was: " + pre_dbg_rot)
					push_error("RootQ timestamp " + str(key_iter_rot.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter_rot.debug())
				var delta_q: Quaternion = humanoid_transform_util.get_hips_rotation_delta(body_positions, root_q)
				if not delta_q.is_normalized():
					push_error("delta_q is not normalized!")
					return
				if keyframe_affects_rootQ.has(ts):
					var y_rotation: Quaternion = base_y_rotation
					if not bake_orientation_into_pose:
						var euler_y: float = root_q.get_euler(EULER_ORDER_YZX).y - orientation_offset
						y_rotation = Quaternion.from_euler(Vector3(0, euler_y, 0))
						anim.rotation_track_insert_key(gd_track_root_rot, ts, y_rotation) # Root rest rotation is identity
					anim.rotation_track_insert_key(gd_track_rot, ts, y_rotation.inverse() * delta_q) # Hips rest rotation is identity

				var pre_dbg_pos: String = key_iter_pos.debug()
				var val_position_variant: Variant = key_iter_pos.next(ts - last_ts)
				var root_t: Vector3 = val_position_variant as Vector3
				if is_mirror:
					root_t.x = -root_t.x
				if (key_iter_pos.timestamp != ts) and not key_iter_pos.is_eof:
					push_warning("RootT State was: " + pre_dbg_pos)
					push_error("RootT timestamp " + str(key_iter_pos.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter_pos.debug())
				var hips_pos: Vector3 = humanoid_transform_util.get_hips_position(body_positions, body_rotations, delta_q, root_t)
				var root_pos_offset := base_root_pos_offset
				if not bake_position_xz_into_pose:
					if keep_original_position_xz:
						root_pos_offset = Vector3(hips_pos.x, 0, hips_pos.z)
					else:
						root_pos_offset = Vector3(root_t.x, 0, root_t.z)
				if not bake_position_y_into_pose:
					if keep_original_position_y:
						root_pos_offset.y = hips_pos.y - 1.0 + root_y_level # Hips offset is always precisely 1
					else:
						# Ignoring m_HeightFromFeet boolean. it's a small effect and not sure how it's calculated.
						root_pos_offset.y = root_t.y + root_y_level
				if not bake_position_xz_into_pose or not bake_position_y_into_pose:
					anim.position_track_insert_key(gd_track_root_pos, ts, root_pos_offset)
				anim.position_track_insert_key(gd_track_pos, ts, hips_pos - root_pos_offset)
				last_ts = ts
	for track in keys.get("m_PositionCurves", []):
		var path: String = track.get("path", "")
		var classID: int = 4
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_warn("position curve is array")
			track_curve = {"m_Curve": track_curve}
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty position curve detected " + path)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
		var postrack = anim.add_track(Animation.TYPE_POSITION_3D)
		resolved_to_default["T" + str(nodepath)] = [path, "", classID]
		anim.track_set_path(postrack, nodepath)
		anim.track_set_interpolation_type(postrack, Animation.INTERPOLATION_LINEAR)
		var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
		while not key_iter.is_eof:
			var value: Vector3 = key_iter.next()
			var ts: float = key_iter.timestamp
			if path.ends_with("Spine"):
				log_debug("Spine " + str(ts) + " value " + str(value) + " -> " + str(Vector3(-1, 1, 1) * value))
			anim.position_track_insert_key(postrack, ts, Vector3(-1, 1, 1) * value)

	for track in keys.get("m_EulerCurves", []):
		var path: String = track.get("path", "")
		var classID: int = 4
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_warn("euler curve is array")
			track_curve = {"m_Curve": track_curve}
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty euler curve detected " + path)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
		var rottrack = anim.add_track(Animation.TYPE_ROTATION_3D)
		resolved_to_default["T" + str(nodepath)] = [path, "", classID]
		anim.track_set_path(rottrack, nodepath)
		anim.track_set_interpolation_type(rottrack, Animation.INTERPOLATION_LINEAR)
		var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
		while not key_iter.is_eof:
			var value: Vector3 = key_iter.next()
			var ts: float = key_iter.timestamp
			# NOTE: value is assumed to be YXZ in Godot terms, but it has 6 different modes in Unidot.
			var godot_euler_mode: int = EULER_ORDER_YXZ
			match track["curve"].get("m_RotationOrder", 2):
				0:  # XYZ
					godot_euler_mode = EULER_ORDER_ZYX
				1:  # XZY
					godot_euler_mode = EULER_ORDER_YZX
				2:  # YZX
					godot_euler_mode = EULER_ORDER_XZY
				3:  # YXZ
					godot_euler_mode = EULER_ORDER_ZXY
				4:  # ZXY
					godot_euler_mode = EULER_ORDER_YXZ
				5:  # ZYX
					godot_euler_mode = EULER_ORDER_XYZ
			# This is more complicated than this...
			# The keys need to be baked out and sampled using this mode.
			anim.rotation_track_insert_key(rottrack, ts, Basis.FLIP_X.inverse() * Basis.from_euler(value * PI / 180.0, godot_euler_mode) * Basis.FLIP_X)

	for track in keys.get("m_RotationCurves", []):
		var path: String = track.get("path", "")
		var classID: int = 4
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_warn("rotation curve is array")
			track_curve = {"m_Curve": track_curve}
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty rotation curve detected " + path)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
		var rottrack = anim.add_track(Animation.TYPE_ROTATION_3D)
		resolved_to_default["T" + str(nodepath)] = [path, "", classID]
		anim.track_set_path(rottrack, nodepath)
		anim.track_set_interpolation_type(rottrack, Animation.INTERPOLATION_LINEAR)
		var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
		while not key_iter.is_eof:
			var value: Quaternion = key_iter.next()
			var ts: float = key_iter.timestamp
			anim.rotation_track_insert_key(rottrack, ts, Basis.FLIP_X.inverse() * Basis(value) * Basis.FLIP_X)

	for track in keys.get("m_ScaleCurves", []):
		var path: String = track.get("path", "")
		var classID: int = 4
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_warn("scale curve is array")
			track_curve = {"m_Curve": track_curve}
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty scale curve detected " + path)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
		var scaletrack = anim.add_track(Animation.TYPE_SCALE_3D)
		resolved_to_default["T" + str(nodepath)] = [path, "", classID]
		anim.track_set_path(scaletrack, nodepath)
		anim.track_set_interpolation_type(scaletrack, Animation.INTERPOLATION_LINEAR)
		var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
		while not key_iter.is_eof:
			var value: Vector3 = key_iter.next()
			var ts: float = key_iter.timestamp
			anim.scale_track_insert_key(scaletrack, ts, value)

	for track in keys.get("m_PPtrCurves", []):
		var path: String = track.get("path", "")
		var classID: int = 4
		var track_curve = track["curve"]
		if typeof(track_curve) == TYPE_ARRAY:
			log_debug("pptr curve is array: " + str(track_curve))
			track_curve = {"m_Curve": track_curve}
		if len(track_curve.get("m_Curve", [])) == 0:
			log_warn("Empty pptr curve detected " + path)
			continue
		for keyframe in track_curve["m_Curve"]:
			max_ts = maxf(max_ts, keyframe["time"])
		log_warn("PPtr curves (material swaps) are not yet implemented")
		# TYPE_VALUE track should mostly work for this.
		# This is mostly only used for material overrides.
		# Which will map to MeshInstance3D:surface_material_override/0 and so on.
		pass

	if max_ts <= 0.0:
		max_ts = 1.0 # Animations are 1 second long by default, but can be shorter based on keyframe
	if settings.get("m_StopTime", 0.0) > 0.0:
		max_ts = settings.get("m_StopTime", 0.0)
	anim.length = max_ts
	if settings.get("m_LoopTime", 0) != 0:
		anim.loop_mode = Animation.LOOP_LINEAR
	anim.set_meta("resolved_to_default_paths", resolved_to_default)
	if anim.resource_path == StringName():
		var res_path = StringName()
		if self.fileID == meta.main_object_id:
			#if not meta.path.ends_with(".tres"):
			#	meta.rename(meta.path + ".tres")
			res_path = meta.path
		else:
			res_path = meta.path.get_basename() + meta.fixup_godot_extension(".%d.tres" % [self.fileID])
		res_path = "res://" + res_path
		adapter.unidot_utils.save_resource(anim, res_path)
		meta.insert_resource(self.fileID, anim)
	else:
		adapter.unidot_utils.save_resource(anim, anim.resource_path)
	return anim
