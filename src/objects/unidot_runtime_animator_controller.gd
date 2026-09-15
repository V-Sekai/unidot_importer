class_name UnidotRuntimeAnimatorController extends UnidotAnimatorRelated

func get_godot_extension() -> String:
	return ".controller.tres"

func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnidotAnimator
	return null

func create_animation_library_clips_at_node(animator: RefCounted, node_parent: Node, animation_guid_fileid_to_name: Dictionary, requested_clips: Dictionary) -> AnimationLibrary:
	var animation_guid_fileid_to_name_new: Dictionary
	for key in animation_guid_fileid_to_name:
		var guid_fid = key.split(":")
		var anim_guid = guid_fid[0]
		var anim_fileid: int = guid_fid[1].to_int()
		var anim_ref = [null, anim_fileid, anim_guid, 2]
		var clip_name = animation_guid_fileid_to_name[key]
		if not requested_clips.has(clip_name):
			requested_clips[clip_name] = anim_ref
			log_debug("Requesting clip " + str(clip_name) + " at " + str(anim_ref))

	var anim_library = AnimationLibrary.new()
	for clip_name in requested_clips:
#		var anim_clip_obj: UnidotAnimationClip = meta.lookup(requested_clips[clip_name], true)  # TODO: What if this fails? What if animation in glb file?
		var anim_clip_obj = meta.lookup(requested_clips[clip_name], true)  # TODO: What if this fails? What if animation in glb file?
		var anim_res: Animation = meta.get_godot_resource(requested_clips[clip_name], true)
		log_debug("clip " + str(clip_name) + " animation " + str(anim_res) + " obj " + str(anim_clip_obj))
		if anim_res == null and anim_clip_obj == null:
			meta.lookup(requested_clips[clip_name])
			continue
		elif anim_res == null and anim_clip_obj != null:
			anim_res = anim_clip_obj.create_animation_clip_at_node(animator, node_parent)
		elif anim_res != null and anim_clip_obj != null and node_parent != null:
			anim_res = anim_clip_obj.adapt_animation_clip_at_node(animator, node_parent, anim_res)
		var clip_sn := StringName(clip_name)
		if anim_res != null:
			anim_library.add_animation(clip_sn, anim_res)
		var target_guid: String
		if typeof(requested_clips[clip_name][2]) == TYPE_NIL:
			target_guid = meta.guid
		else:
			target_guid = requested_clips[clip_name][2]
		animation_guid_fileid_to_name_new[target_guid + ":" + str(requested_clips[clip_name][1])] = clip_sn
	anim_library.set_meta(&"guid_fileid_to_animation_name", animation_guid_fileid_to_name_new)
	return anim_library

func adapt_animation_player_at_node(animator: RefCounted, anim_player: AnimationPlayer):
	var node_parent: Node = anim_player.get_parent()
#	var virtual_generic_animation_clip: UnidotAnimationClip = adapter.instantiate_unidot_object(meta, 0, 0, "AnimationClip")
	var virtual_generic_animation_clip = adapter.instantiate_unidot_object(meta, 0, 0, "AnimationClip")
	log_debug("Current fileid_to_nodepath: " + str(meta.fileid_to_nodepath.keys()) + " prefab " + str(meta.prefab_fileid_to_nodepath.keys()))
	for library_name in anim_player.get_animation_library_list():
		var library: AnimationLibrary = anim_player.get_animation_library(library_name)
		var animation_guid_fileid_to_name: Dictionary = library.get_meta(&"guid_fileid_to_animation_name", {})
		var done_names: Dictionary
		for key in animation_guid_fileid_to_name:
			var guid_fid = key.split(":")
			var anim_guid = guid_fid[0]
			var anim_fileid: int = guid_fid[1].to_int()
			var anim_ref = [null, anim_fileid, anim_guid, 2]
			var clip_name = animation_guid_fileid_to_name[key]
			done_names[clip_name] = true
			if not library.has_animation(clip_name):
				log_warn("Library is missing animation " + str(clip_name))
				continue
			var clip = library.get_animation(clip_name)
			log_debug("Adapting AnimationClip " + clip_name + " at node " + str(node_parent.name))
#			var virtual_animation_clip: UnidotAnimationClip = adapter.instantiate_unidot_object(meta.lookup_meta(anim_ref), anim_ref[1], 0, "AnimationClip")
			var virtual_animation_clip = adapter.instantiate_unidot_object(meta.lookup_meta(anim_ref), anim_ref[1], 0, "AnimationClip")
			var new_clip: Animation = virtual_animation_clip.adapt_animation_clip_at_node(animator, node_parent, clip)
			if new_clip != null and new_clip != clip:
				library.remove_animation(clip_name)
				library.add_animation(clip_name, new_clip)
		for clip_name in library.get_animation_list():
			if done_names.has(clip_name) or clip_name == &"RESET" or clip_name == &"_T-Pose_":
				continue
			var clip: Animation = library.get_animation(clip_name)
			log_warn("Adapting unrecognized AnimationClip " + clip_name + " at node " + str(node_parent.name))
			var new_clip: Animation = virtual_generic_animation_clip.adapt_animation_clip_at_node(animator, node_parent, clip)
			if new_clip != null and new_clip != clip:
				library.remove_animation(clip_name)
				library.add_animation(clip_name, new_clip)


func get_godot_type() -> String:
	return "AnimationNodeBlendTree"

func create_godot_resource() -> Resource:
	return null
