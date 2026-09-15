class_name UnidotAnimatorState extends UnidotAnimatorRelated

func get_godot_type() -> String:
	return "AnimationRootNode"

func create_animation_node(controller: RefCounted, layer_index: int, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool=false) -> AnimationRootNode:
	var speed: float = keys.get("m_Speed", 1)
	if speed < 0:
		speed *= -1
		reverse_animations = not reverse_animations
	var motion_ref: Array = keys["m_Motion"]
	var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, motion_ref, animation_guid_fileid_to_name, reverse_animations)
	# TODO: Convert states with motion time, speed or other parameters into AnimationBlendTree graphs.
	var cycle_off: float = keys.get("m_CycleOffset", 0)
	var speed_param_active: int = keys.get("m_SpeedParameterActive", 0) and not keys.get("m_SpeedParameter", "").is_empty()
	var time_param_active: int = keys.get("m_TimeParameterActive", 0) and not keys.get("m_TimeParameter", "").is_empty()
	var cycle_param_active: int = keys.get("m_CycleParameterActive", 0) and not keys.get("m_CycleParameter", "").is_empty()
	var ret = motion_node
	# not sure we support cycle offset?
	if speed != 1 or speed_param_active == 1 or time_param_active == 1:
		var bt = AnimationNodeBlendTree.new()
		ret = bt
		bt.add_node(&"Animation", motion_node, Vector2(200, 200))
		var last_node = &"Animation"
		var xval = 500
		if speed != 1:
			var tsnode = AnimationNodeTimeScale.new()
			tsnode.set_meta("scale", speed)
			bt.add_node(&"TimeScale", tsnode, Vector2(xval, 0))
			xval += 200
			bt.connect_node(&"TimeScale", 0, last_node)
			last_node = &"TimeScale"
		if time_param_active:
			var seeknode = AnimationNodeTimeSeek.new()
			seeknode.set_meta("seek_request", controller.get_parameter_uniq_name(keys["m_TimeParameter"]))
			var node_name = StringName("TimeSeek")
			bt.add_node(node_name, seeknode, Vector2(xval, 0))
			xval += 200
			bt.connect_node(node_name, 0, last_node)
			last_node = node_name
		if speed_param_active:
			var tsnode = AnimationNodeTimeScale.new()
			tsnode.set_meta("scale", controller.get_parameter_uniq_name(keys["m_SpeedParameter"]))
			var node_name = StringName("TimeScaleParam")
			bt.add_node(node_name, tsnode, Vector2(xval, 0))
			xval += 200
			bt.connect_node(node_name, 0, last_node)
			last_node = node_name
		bt.connect_node(&"output", 0, last_node)
		bt.set_node_position(&"output", Vector2(xval, 0))
	return ret
