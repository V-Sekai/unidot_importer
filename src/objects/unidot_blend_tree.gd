class_name UnidotBlendTree extends UnidotMotion

func get_godot_type() -> String:
	return "AnimationNodeBlendSpace2D"

func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
	for child in keys["m_Childs"]:
		var basename: String = sm_path[-1]
		if keys["m_BlendType"] == 0:
			basename = "%s_%s" % [basename, child.get("m_Threshold", 0)]
		elif keys["m_BlendType"] == 4:
			basename = "%s_%s" % [basename, child.get("m_DirectBlendParameter", "")]
		else:
			var pos: Vector2 = child.get("m_Position", Vector2())
			basename = "%s_%.02f_%.02f" % [basename, pos.x, pos.y]
		var motion_ref: Array = child["m_Motion"]
		if out_guid_fid_to_anim_name.has(ref_to_anim_key(motion_ref)):
			continue
		var motion: Object = meta.lookup(motion_ref, true)  # TODO: Need to get the godot resource's name for imported glb
		if motion != null:
			sm_path.append(basename)
			motion.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
			sm_path.remove_at(len(sm_path) - 1)
		else:
			var name: String = basename
			for i in range(len(uniq_name_dict) + 1):
				if not uniq_name_dict.has(name):
					break
				for j in range(len(sm_path) - 1, -1, -1):
					var sm_name = sm_path[j]
					if not uniq_name_dict.has(name):
						break
					if i > 0:
						name = "%s %s %d" % [sm_name, basename, i]
					else:
						name = "%s %s" % [sm_name, basename]
					log_debug("Trying %s name %s from %s %s" % [str(sm_name), str(name), str(basename), str(uniq_name_dict)])
			uniq_name_dict[name] = 1
			out_guid_fid_to_anim_name[ref_to_anim_key(motion_ref)] = name

func create_animation_node(controller: RefCounted, layer_index: int, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool=false) -> AnimationRootNode:
	var minmax: Rect2 = Rect2(-1.1, -1.1, 2.2, 2.2)
	var ret: AnimationRootNode = null
	match keys["m_BlendType"]:
		0:  # Simple1D
			var bs = AnimationNodeBlendSpace1D.new()
			for child in keys["m_Childs"]:
				var speed: float = child.get("m_TimeScale", 1)
				if speed < 0:
					speed *= -1
					reverse_animations = not reverse_animations
				# TODO: m_TimeScale and m_CycleOffset
				var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
				if speed != 1:
					var bt = AnimationNodeBlendTree.new()
					var tsnode = AnimationNodeTimeScale.new()
					tsnode.set_meta("scale", speed)
					bt.add_node(&"Motion", motion_node, Vector2(200, 200))
					bt.add_node(&"TimeScale", tsnode, Vector2(500, 200))
					bt.connect_node(&"TimeScale", 0, &"Motion")
					bt.connect_node(&"output", 0, &"TimeScale")
					bt.set_node_position(&"output", Vector2(700, 200))
					motion_node = bt
				bs.add_blend_point(motion_node, child["m_Threshold"])
				minmax = minmax.expand(Vector2(child["m_Threshold"] * 1.1, 0.0))
			bs.min_space = minmax.position.x
			bs.max_space = minmax.end.x
			bs.set_meta("blend_position", controller.get_parameter_uniq_name(keys.get("m_BlendParameter", "Blend")))
			ret = bs
		1, 2, 3:  # SimpleDirectional2D, FreeformDirectional2D, FreeformCartesian2D
			# TODO: Does Godot support the different types of 2D blending?
			var bs = AnimationNodeBlendSpace2D.new()
			for child in keys["m_Childs"]:
				var speed: float = child.get("m_TimeScale", 1)
				if speed < 0:
					speed *= -1
					reverse_animations = not reverse_animations
				# TODO: m_TimeScale and m_CycleOffset
				var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
				if speed != 1:
					var bt = AnimationNodeBlendTree.new()
					var tsnode = AnimationNodeTimeScale.new()
					tsnode.set_meta("scale", speed)
					bt.add_node(&"Motion", motion_node, Vector2(200, 200))
					bt.add_node(&"TimeScale", tsnode, Vector2(500, 200))
					bt.connect_node(&"TimeScale", 0, &"Motion")
					bt.connect_node(&"output", 0, &"TimeScale")
					bt.set_node_position(&"output", Vector2(700, 200))
					motion_node = bt
				bs.add_blend_point(motion_node, child["m_Position"])
				minmax = minmax.expand(child["m_Position"] * 1.1)
			bs.min_space = minmax.position
			bs.max_space = minmax.end
			bs.set_meta("blend_position_x", controller.get_parameter_uniq_name(keys.get("m_BlendParameter", "Blend")))
			bs.set_meta("blend_position_y", controller.get_parameter_uniq_name(keys.get("m_BlendParameterY", "Blend")))
			ret = bs
		4:  # Direct
			# Add a bunch of AnimationNodeAdd2? Do these get chained somehow?
			var bt = AnimationNodeBlendTree.new()
			var uniq_dict: Dictionary = {}.duplicate()
			uniq_dict[&"output"] = 1
			uniq_dict[&"Child"] = 1
			uniq_dict[&"TimeScale"] = 1
			uniq_dict[&"Transition"] = 1
			bt.add_node(&"Transition", AnimationNodeTransition.new(), Vector2(200, 200))
			var last_name = &"Transition"

			var i = 0
			for child in keys["m_Childs"]:
				var speed: float = child.get("m_TimeScale", 1)
				if speed < 0:
					speed *= -1
					reverse_animations = not reverse_animations
				var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
				var motion_name = get_unique_name("Child", uniq_dict)
				bt.add_node(motion_name, motion_node, Vector2(500, i * 200))
				if speed != 1:
					var tsnode = AnimationNodeTimeScale.new()
					var tsname = get_unique_name("TimeScale", uniq_dict)
					tsnode.set_meta("scale", speed)
					bt.add_node(tsname, tsnode, Vector2(700, i * 200 - 50))
					bt.connect_node(tsname, 0, motion_name)
					motion_name = tsname
				var add_node = AnimationNodeAdd2.new()
				add_node.set_meta("add_amount", controller.get_parameter_uniq_name(child.get("m_DirectBlendParameter", "Blend")))
				var add_name = get_unique_name(child.get("m_DirectBlendParameter", "Blend"), uniq_dict)
				bt.add_node(add_name, add_node, Vector2(900, i * 200 - 100))
				bt.connect_node(add_name, 0, last_name)
				bt.connect_node(add_name, 1, motion_name)
				last_name = add_name
				i += 1
			bt.connect_node(&"output", 0, last_name)
			ret = bt
	return ret
