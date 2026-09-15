class_name UnidotAnimatorController extends UnidotRuntimeAnimatorController

var parameters: Dictionary = {}

# An AnimationController references two things:\
# 1. an animation library which depends on the node.
# 2.
func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnidotAnimator
	var this_res: AnimationRootNode = meta.get_godot_resource([null, self.fileID, null, 0])
	var animation_guid_fileid_to_name: Dictionary = this_res.get_meta(&"guid_fileid_to_animation_name", {})
	assert(not animation_guid_fileid_to_name.is_empty())
	return self.create_animation_library_clips_at_node(animator, node_parent, animation_guid_fileid_to_name, {}.duplicate())

func get_animation_guid_fileid_to_name():
	var animation_guid_fileid_to_name: Dictionary = {}.duplicate()
	var animation_used_names: Dictionary = {}.duplicate()
	var sm_path: Array = [].duplicate()
	var lay_idx: int = -1
	for lay in keys["m_AnimatorLayers"]:
		lay_idx += 1
		var sm: UnidotAnimatorStateMachine = meta.lookup(lay["m_StateMachine"])
		sm_path.append(lay.get("m_Name", "layer"))
		sm.get_all_animations(sm_path, animation_used_names, animation_guid_fileid_to_name)
		sm_path.clear()
	return animation_guid_fileid_to_name

func get_extra_resources() -> Dictionary:
	return {-self.fileID: ".library.tres"}

func get_extra_resource(fileID: int) -> Resource:  #AnimationLibrary:
	var sk: AnimationLibrary = AnimationLibrary.new()
	var fileid_to_name: Dictionary = get_animation_guid_fileid_to_name()
	var anim_library = self.create_animation_library_clips_at_node(null, null, fileid_to_name, {}.duplicate())
	return anim_library

func create_godot_resource() -> Resource:
	return create_animation_node()

func create_animation_node() -> AnimationRootNode:
	# Add all layers to a blend tree.
	var blended_layers = AnimationNodeBlendTree.new()
	var tmp_used_params: Dictionary = {}.duplicate()
	self.parameters = {}.duplicate()
	for param in keys["m_AnimatorParameters"]:
		var type: String = "unknown"
		var defval: Variant = 0
		match str(param["m_Type"]):
			"1":
				type = "float"
				defval = float(param["m_DefaultFloat"])
			"3":
				type = "int"
				defval = int(param["m_DefaultInt"])
			"4":
				type = "bool"
				if param["m_DefaultBool"]:
					defval = true
				else:
					defval = false
			"9":
				type = "trigger"
				if param["m_DefaultBool"]:
					defval = true
				else:
					defval = false
		var param_name: StringName = get_unique_identifier(param["m_Name"], tmp_used_params)
		parameters[param["m_Name"]] = {"uniq_name": param_name, "type": type, "default": defval}
		blended_layers.set_meta(param_name, defval)  # toplevel meta is used.
	var lay_x: float = 0.0
	var last_output: StringName = &""
	var used_names: Dictionary = {}.duplicate()
	var animation_guid_fileid_to_name: Dictionary = {}.duplicate()
	var animation_used_names: Dictionary = {}.duplicate()
	var sm_path: Array = [].duplicate()
	var lay_idx: int = -1
	for lay in keys["m_AnimatorLayers"]:
		lay_idx += 1
		var sm: UnidotAnimatorStateMachine = meta.lookup(lay["m_StateMachine"])
		sm_path.append(lay.get("m_Name", "layer"))
		sm.get_all_animations(sm_path, animation_used_names, animation_guid_fileid_to_name)
		sm_path.clear()

	# Godot: "An AnimationNodeOutput node named output is created by default."
	used_names[&"output"] = 0
	lay_idx = -1
	for lay in keys["m_AnimatorLayers"]:
		lay_idx += 1
		'''
m_Name: Base Layer
m_StateMachine: {fileID: 8941230547955804434}
m_Mask: {fileID: 0}
m_Motions: []
m_Behaviours: []
m_BlendingMode: 0
m_SyncedLayerIndex: -1
m_DefaultWeight: 0
m_IKPass: 0
m_SyncedLayerAffectsTiming: 0
m_Controller: {fileID: 9100000}
		'''
		var renamed_layer = get_unique_name(lay["m_Name"], used_names)
		lay["m_Controller"] = [null, self.fileID, null, 0]
		var node_to_add: AnimationRootNode = create_flat_state_machine(lay_idx, animation_guid_fileid_to_name)
		log_debug("aaa")
		blended_layers.add_node(renamed_layer, node_to_add, Vector2(100 + lay_x, 200))
		log_debug("bbb " + str(renamed_layer))
		if last_output != &"":
			# TODO: We may wish to generate the correct mask based on animation clip outputs...
			# but this will depend on the animation clips in question, and I wanted to keep this agnostic.

			# Add2 will be a reasonable output in most cases, except when clips override each others' outputs.
			# So I will use this for now.
			var mixing_node = AnimationNodeAdd2.new()
			# parameter is &"blend" for Blend2 and &"add_amount" for Add2. Make sure to switch if we change types.
			mixing_node.set_meta(&"add_amount", lay["m_DefaultWeight"])
			var mixing_name = get_unique_name(&"Blend", used_names)
			lay_x += 400.0
			blended_layers.add_node(mixing_name, mixing_node, Vector2(100 + lay_x, 0))
			blended_layers.connect_node(mixing_name, 0, last_output)
			blended_layers.connect_node(mixing_name, 1, renamed_layer)
			last_output = mixing_name
		else:
			lay_x += 400.0
			last_output = renamed_layer
	blended_layers.connect_node(&"output", 0, last_output)
	blended_layers.set_node_position(&"output", Vector2(200 + lay_x, 350))
	# Create a StateMachine for m_StateMachine and all child state machines too.
	# State Machine blending does not currently seem to work.
	# Then, add to blended_layers
	blended_layers.set_meta(&"guid_fileid_to_animation_name", animation_guid_fileid_to_name)
	return blended_layers

#	func allows_dupe_transitions() -> bool:
#		var sm = AnimationNodeStateMachine.new()
#		var n1 = AnimationNodeAnimation.new()
#		var n2 = AnimationNodeAnimation.new()
#		var t1 = AnimationNodeStateMachineTransition.new()
#		var t2 = AnimationNodeStateMachineTransition.new()
#		sm.add_node(&"test1", n1)
#		sm.add_node(&"test2", n2)
#		sm.add_transition(&"test1", &"test2", t1)
#		sm.add_transition(&"test1", &"test2", t2)
#		var has_dupe_transitions: bool = sm.get_transition(0) == t1 && sm.get_transition(1) == t2
#		sm.remove_transition_by_index(1)
#		sm.remove_transition_by_index(0)
#		sm.remove_node(&"test1")
#		sm.remove_node(&"test2")
#		return has_dupe_transitions

func get_parameter_uniq_name(param_name: String) -> StringName:
	if not self.parameters.has(param_name):
		log_warn("Parameter " + param_name + " is missing from " + str(self.parameters.keys()), param_name)
		return &""
	return self.parameters[param_name]["uniq_name"]

const STATE_MACHINE_SCALE: float = 1.0
const STATE_MACHINE_OFFSET: Vector3 = Vector3(300, 100, 0)

func create_flat_state_machine(layer_index: int, animation_guid_fileid_to_name: Dictionary) -> AnimationRootNode:
	var lay: Dictionary = keys["m_AnimatorLayers"][layer_index]
	var root_state_machine_ref: Array = lay["m_StateMachine"]
	var root_sm: UnidotAnimatorStateMachine = meta.lookup(root_state_machine_ref)
	var state_uniq_names = {}.duplicate()
	var state_duplicates = {}.duplicate()  # such as any state self transitions; other self transitions; multi transitions.
	var state_data = {}.duplicate()
	state_uniq_names[&"Start"] = 0
	state_uniq_names[&"End"] = 0
	state_uniq_names[&"playback"] = 0
	state_uniq_names[&"conditions"] = 0
	root_sm.get_state_data("", state_data, state_uniq_names, STATE_MACHINE_OFFSET, STATE_MACHINE_SCALE)

	# var exit_state_name: StringName = &""
	var any_transition_list = [].duplicate()
	root_sm.get_any_state_transitions(any_transition_list)
	any_transition_list.reverse()
	var exit_parent = {}.duplicate()
	exit_parent[root_sm.uniq_key] = root_sm  # null # make a sort of temporary exit node which holds it for one frame.
	root_sm.get_exit_parent(exit_parent)
	var sm = AnimationNodeStateMachine.new()
	sm.resource_name = keys.get("m_Name", "")
	var tmppos: Vector3 = STATE_MACHINE_OFFSET + keys.get("m_EntryPosition", Vector3()) * STATE_MACHINE_SCALE
	sm.set_node_position(&"Start", Vector2(tmppos.x, tmppos.y))
	tmppos = STATE_MACHINE_OFFSET + keys.get("m_ExitPosition", Vector3()) * STATE_MACHINE_SCALE
	sm.set_node_position(&"End", Vector2(tmppos.x, tmppos.y))
	var allow_dupe_transitions: bool = false  # allows_dupe_transitions()

	var transition_count = {}.duplicate()
	var state_count = {}.duplicate()
	for state_key in state_data:
		transition_count[state_key + state_key] = 1  # state to itself is not allowed anyway.
		state_count[state_key] = 1

	for transition_obj in any_transition_list:  # Godot favors last transition.
		var can_trans_to_self: bool = transition_obj.keys.get("m_CanTransitionToSelf", 0) != 0
		var transition_list = transition_obj.resolve_state_transitions(exit_parent, null)
		for src_state_key in state_data:
			for condition_list in transition_list:
				var dst_state: UnidotAnimatorState = condition_list[-1]
				if dst_state == null:
					continue
				if not can_trans_to_self and dst_state.uniq_key == src_state_key:
					continue
				var trans_key: String = src_state_key + dst_state.uniq_key
				if allow_dupe_transitions:
					if dst_state.uniq_key != src_state_key:
						continue
					transition_count[trans_key] = 2
				else:
					if not transition_count.has(trans_key):
						transition_count[trans_key] = 0
					transition_count[trans_key] += 1
				if state_count.has(dst_state.uniq_key):
					state_count[dst_state.uniq_key] = max(state_count[dst_state.uniq_key], transition_count[trans_key])
				else:
					log_warn("state_count " + dst_state.uniq_key + " is missing for Any transition " + trans_key)
					state_count[dst_state.uniq_key] = transition_count[trans_key]

	for state_key in state_data:
		var this_state: Dictionary = state_data[state_key]
		for trans in this_state["state"].keys["m_Transitions"]:
			var transition_obj = this_state["state"].meta.lookup(trans)
			var transition_list = transition_obj.resolve_state_transitions(exit_parent, this_state["sm"])
			for condition_list in transition_list:
				var dst_state: UnidotAnimatorState = condition_list[-1]
				if dst_state == null:
					continue
				var trans_key: String = state_key + dst_state.uniq_key
				if allow_dupe_transitions:
					if dst_state.uniq_key != state_key:
						continue
					transition_count[trans_key] = 2
				else:
					if not transition_count.has(trans_key):
						transition_count[trans_key] = 0
					transition_count[trans_key] += 1
				if state_count.has(dst_state.uniq_key):
					state_count[dst_state.uniq_key] = max(state_count[dst_state.uniq_key], transition_count[trans_key])
				else:
					log_warn("state_count " + dst_state.uniq_key + " is missing for normal transition " + trans_key)
					state_count[dst_state.uniq_key] = transition_count[trans_key]
	for state_key in state_data:
		var this_state: Dictionary = state_data[state_key]
		var anim_node = this_state["state"].create_animation_node(self, layer_index, animation_guid_fileid_to_name)
		sm.add_node(this_state["name"], anim_node, this_state["pos"])
		var dup_prefix = StringName(str(this_state["name"]) + "~Dup")
		get_unique_name(dup_prefix, state_uniq_names)
		var dupes = [].duplicate()
		dupes.append(this_state["name"])
		for i in range(1, state_count[state_key]):
			var dup_name = get_unique_name(dup_prefix, state_uniq_names)
			anim_node = this_state["state"].create_animation_node(self, layer_index, animation_guid_fileid_to_name)
			sm.add_node(dup_name, anim_node, this_state["pos"] + i * Vector2(25, 25))
			dupes.append(dup_name)
		state_duplicates[this_state["name"]] = dupes

	transition_count = {}.duplicate()
	for x_transition_obj in any_transition_list:  # Godot favors last transition.
		var transition_obj: UnidotAnimatorStateTransition = x_transition_obj
		var can_trans_to_self: bool = transition_obj.keys.get("m_CanTransitionToSelf", 0) != 0
		var transition_list: Array = transition_obj.resolve_state_transitions(exit_parent, null)
		for src_state_key in state_data:
			for condition_list in transition_list:
				var dst_state: UnidotAnimatorState = condition_list[-1]
				if dst_state == null:
					continue
				if not can_trans_to_self and dst_state.uniq_key == src_state_key:
					continue
				var trans_key: String = src_state_key + dst_state.uniq_key
				if not state_data.has(dst_state.uniq_key) or not state_data.has(src_state_key):
					log_fail("Missing state_data for dupe any state transition from " + src_state_key + " to " + dst_state.uniq_key)
					continue
				create_dupe_transitions(sm, transition_obj, state_data[src_state_key]["name"], state_data[dst_state.uniq_key]["name"], state_duplicates, transition_count.get(trans_key, 0), condition_list)
				if not allow_dupe_transitions:
					if not transition_count.has(trans_key):
						transition_count[trans_key] = 0
					transition_count[trans_key] += 1

	for state_key in state_data:
		var this_state: Dictionary = state_data[state_key]
		var trans_list: Array = this_state["state"].keys["m_Transitions"].duplicate()
		trans_list.reverse()
		for trans in trans_list:
			var transition_obj = this_state["state"].meta.lookup(trans)
			var transition_list = transition_obj.resolve_state_transitions(exit_parent, this_state["sm"])
			for condition_list in transition_list:
				var dst_state: UnidotAnimatorState = condition_list[-1]
				if dst_state == null:
					continue
				var trans_key: String = state_key + dst_state.uniq_key
				if not state_data.has(dst_state.uniq_key):
					log_fail("Missing state_data for dupe normal transition from " + state_key + " to " + dst_state.uniq_key)
					continue
				create_dupe_transitions(sm, transition_obj, this_state["name"], state_data[dst_state.uniq_key]["name"], state_duplicates, transition_count.get(trans_key, 0), condition_list)
				if not allow_dupe_transitions:
					if not transition_count.has(trans_key):
						transition_count[trans_key] = 0
					transition_count[trans_key] += 1

	var def_state = meta.lookup(root_sm.keys["m_DefaultState"])
	if def_state != null and state_data.has(def_state.uniq_key):
		if sm.get_node(&"Start") != null:
			var trans = AnimationNodeStateMachineTransition.new()
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			sm.add_transition(&"Start", state_data[def_state.uniq_key]["name"], trans)
		else:
			sm.set_start_node(state_data[def_state.uniq_key]["name"])
	return sm

func create_dupe_transitions(sm: AnimationNodeStateMachine, transition_obj: UnidotAnimatorStateTransition, src_state_name: StringName, dst_state_name: StringName, state_duplicates: Dictionary, dst_idx: int, condition_list: Array):
	var conditions: String = ""
	var is_muted: bool = transition_obj.keys.get("m_Mute", false)
	for trans in condition_list:
		if trans == null or not trans.type.ends_with("Transition"):
			continue
		is_muted = is_muted or trans.keys.get("m_Mute", false)
		for cond in trans.keys["m_Conditions"]:
			var parameter: String = get_parameter_uniq_name(str(cond["m_ConditionEvent"]))
			var thresh: float = float(cond["m_EventTreshold"])
			var event: int = cond["m_ConditionMode"]
			var cond_to_add = ""
			match event:
				1:
					cond_to_add = "%s" % [parameter]  # bool true
				2:
					cond_to_add = "not %s" % [parameter]
				3:
					cond_to_add = "%s > %f" % [parameter, thresh]
				4:
					cond_to_add = "%s < %f" % [parameter, thresh]
				6:
					cond_to_add = "%s == %f" % [parameter, thresh]
				7:
					cond_to_add = "%s != %f" % [parameter, thresh]
			if not cond_to_add.is_empty():
				if not conditions.is_empty():
					conditions += " and "
				conditions += cond_to_add

	var trans = AnimationNodeStateMachineTransition.new()
	# During 4.0 beta, xfade_time > 0 sometimes causes hung machines
	# TODO: We need to check if this is still true?
	trans.xfade_time = float(transition_obj.keys.get("m_TransitionDuration", 0))
	# Godot does not currently support exit time. transition_obj.keys["m_ExitTime"]
	if transition_obj.keys["m_HasExitTime"] and transition_obj.keys["m_ExitTime"] > 0.0001:
		trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	else:
		trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	if conditions == "":
		trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	else:
		trans.advance_expression = conditions
		trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO # All conditions use Auto now.
	if is_muted:
		trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	# TODO: Solo is not implemented yet. It requires knowledge of all sibling transitions at each stage of state machine.
	# Not too hard to do if someone uses the Solo feature for something.

	var src_dupe_idx = 0
	for src_dupe in state_duplicates[src_state_name]:
		var actual_dst_idx = dst_idx
		if src_state_name == dst_state_name:
			actual_dst_idx = 1 if src_dupe_idx == 0 else 0
		var dst_dupe: StringName = state_duplicates[dst_state_name][actual_dst_idx]
		sm.add_transition(src_dupe, dst_dupe, trans)
		src_dupe_idx += 1
