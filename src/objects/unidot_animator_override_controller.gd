class_name UnidotAnimatorOverrideController extends UnidotRuntimeAnimatorController

# Store original object!
func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnidotAnimator
	var controller_ref: Array = keys["m_Controller"]
	var referenced_sm: AnimationRootNode = self.meta.get_godot_resource(controller_ref)
	var lib_ref: Array = [null, -controller_ref[1], controller_ref[2], controller_ref[3]]
	var referenced_library: AnimationLibrary = self.meta.get_godot_resource(lib_ref)
	if referenced_sm == null or referenced_library == null:
		log_fail("Override controller's base controller is missing. Creating dummy library")
		var anim_library: AnimationLibrary = AnimationLibrary.new()
		for clip in keys["m_Clips"]:
			var orig_clip: Array = clip["m_OriginalClip"]
			var override_clip: Array = clip["m_OverrideClip"]
			var anim: Animation = self.meta.get_godot_resource(override_clip)
			if anim != null:
				anim_library.add_animation(anim.resource_name, anim)
		return anim_library
	var animation_guid_fileid_to_name: Dictionary = referenced_sm.get_meta(&"guid_fileid_to_animation_name", {})
	var override_clips = {}.duplicate()
	for clip in keys["m_Clips"]:
		var orig_clip: Array = clip["m_OriginalClip"]
		var override_clip: Array = clip["m_OverrideClip"]
		override_clips[animation_guid_fileid_to_name[ref_to_anim_key(orig_clip)]] = override_clip
	# m_Clips: m_OriginalClip / m_OverrideClip
	var anim_library = self.create_animation_library_clips_at_node(animator, node_parent, animation_guid_fileid_to_name, override_clips)
	anim_library.set_meta("base_node", referenced_sm)
	anim_library.set_meta("base_library", referenced_library)
	return anim_library

func get_godot_type() -> String:
	return "AnimationLibrary"

func create_godot_resource() -> Resource:
	return create_animation_library_at_node(null, null)
