class_name UnidotAnimation extends UnidotBehaviour

func get_godot_type() -> String:
	return "AnimationPlayer"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var animplayer: AnimationPlayer = AnimationPlayer.new()
	state.add_child(animplayer, new_parent, self)
	animplayer.name = "Animation"
	# TODO: Add AnimationTree as well.
	return animplayer

func setup_post_children(node: Node, _avatar: Object):
	var animplayer: AnimationPlayer = node
	var which_playing: StringName = &""
	var default_ref = keys["m_Animation"]
	var anim_library = AnimationLibrary.new()
	for anim_ref in keys["m_Animations"]:
		var anim_clip_obj: UnidotAnimationClip = meta.lookup(anim_ref, true)
		var anim_res: Animation = meta.get_godot_resource(anim_ref, true)
		var anim_name = StringName()
		if anim_res == null and anim_clip_obj == null:
			meta.lookup(anim_ref)
			continue
		elif anim_res == null and anim_clip_obj != null:
			anim_res = anim_clip_obj.create_animation_clip_at_node(self, node.get_parent())
			anim_name = StringName(anim_clip_obj.keys["m_Name"])
		elif anim_res != null and anim_clip_obj != null:
			anim_res = anim_clip_obj.adapt_animation_clip_at_node(self, node.get_parent(), anim_res)
			anim_name = StringName(anim_clip_obj.keys["m_Name"])
		else:
			anim_name = StringName(anim_res.resource_name)
		anim_library.add_animation(anim_name, anim_res)
		if default_ref == anim_ref:
			which_playing = anim_name
	animplayer.add_animation_library(&"", anim_library)
	animplayer.autoplay = which_playing

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	log_debug("convert_properties Animator" + str(outdict))
	return outdict
