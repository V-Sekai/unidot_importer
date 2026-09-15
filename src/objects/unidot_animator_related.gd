# Helper functions
class_name UnidotAnimatorRelated extends UnidotObject

func get_unique_identifier(p_name: String, used_names: Dictionary) -> StringName:
	var out_str: String = ""
	for ch in p_name:
		if not out_str.is_empty() and ("a" + ch).is_valid_identifier():
			out_str += ch
		elif ch.is_valid_identifier():
			out_str += ch
		else:
			out_str += "_"
	return get_unique_name(StringName(out_str), used_names)

func get_unique_name(p_name: StringName, used_names: Dictionary) -> StringName:
	var name: StringName = StringName(str(p_name).replace("/", "-").replace(":", ";"))
	var renamed_layer: StringName = name
	while used_names.has(renamed_layer):
		used_names[name] = used_names.get(name, 0) + 1
		renamed_layer = StringName(str(name) + str(used_names[name]))
	used_names[renamed_layer] = 0
	log_debug("get_unique_name: " + str(p_name) + " => " + str(renamed_layer))
	return renamed_layer

func ref_to_anim_key(motion_ref: Array) -> String:
	return "%s:%d" % [meta.guid if typeof(motion_ref[2]) == TYPE_NIL else motion_ref[2], motion_ref[1]]

func recurse_to_motion(controller: RefCounted, layer_index: int, motion_ref: Array, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool):
	var motion_node: AnimationRootNode = null
	var anim_key: String = ref_to_anim_key(motion_ref)
	if animation_guid_fileid_to_name.has(anim_key):
		motion_node = AnimationNodeAnimation.new()
		motion_node.animation = animation_guid_fileid_to_name[anim_key]
		if reverse_animations:
			motion_node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	else:
		var blend_tree = meta.lookup(motion_ref)
		log_debug("Found blend tree " + str(blend_tree))
		if blend_tree.type != "BlendTree":
			log_fail("Animation not in animation_guid_fileid_to_name: " + str(anim_key))
			motion_node = AnimationNodeAnimation.new()
		else:
			motion_node = blend_tree.create_animation_node(controller, layer_index, animation_guid_fileid_to_name, reverse_animations)
	return motion_node
