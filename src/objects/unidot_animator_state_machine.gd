class_name UnidotAnimatorStateMachine extends UnidotAnimatorRelated

func get_godot_type() -> String:
	return "AnimationNodeStateMachine"

func get_state_data(sm_prefix: String, state_data: Dictionary, unique_names: Dictionary, sm_pos: Vector3, pos_scale: float):
	for state in keys["m_ChildStates"]:
		var child: UnidotAnimatorState = meta.lookup(state["m_State"])
		var child_name: StringName = get_unique_name(StringName(sm_prefix + child.keys["m_Name"]), unique_names)
		var child_pos: Vector3 = sm_pos + state["m_Position"] * pos_scale
		state_data[child.uniq_key] = {"name": child_name, "state": child, "pos": Vector2(child_pos.x, child_pos.y), "sm": self}

	for state_machine in keys["m_ChildStateMachines"]:
		var child: UnidotAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
		var child_pos: Vector3 = sm_pos + state_machine["m_Position"] * pos_scale
		child.get_state_data(sm_prefix + child.keys["m_Name"] + "/", state_data, unique_names, child_pos, pos_scale * 0.5)

func get_exit_parent(sm_to_parent: Dictionary):
	for state_machine in keys["m_ChildStateMachines"]:
		var child: UnidotAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
		sm_to_parent[child.uniq_key] = self
		child.get_exit_parent(sm_to_parent)

func get_any_state_transitions(transition_list: Array):
	for transition in keys["m_AnyStateTransitions"]:
		transition_list.append(meta.lookup(transition))

	for state_machine in keys["m_ChildStateMachines"]:
		var child: UnidotAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
		child.get_any_state_transitions(transition_list)

func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
	for state in keys["m_ChildStates"]:
		var child: UnidotAnimatorState = meta.lookup(state["m_State"])
		var basename: String = child.keys["m_Name"]
		var motion_ref: Array = child.keys["m_Motion"]
		if out_guid_fid_to_anim_name.has(child.ref_to_anim_key(motion_ref)):
			continue
		var motion: UnidotMotion = child.meta.lookup(motion_ref, true) # motion_ref[1] != 7400000)
		if motion != null:
			sm_path.append(basename)
			motion.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
			sm_path.remove_at(len(sm_path) - 1)
		else:
			var name: String = basename
			for i in range(len(uniq_name_dict) + 1):
				if not uniq_name_dict.has(name):
					break
				for sm_name in sm_path:
					if not uniq_name_dict.has(name):
						break
					if i > 0:
						name = "%s %s %d" % [sm_name, basename, i]
					else:
						name = "%s %s" % [sm_name, basename]
					log_debug("Trying %s name %s from %s %s" % [str(sm_name), str(name), str(basename), str(uniq_name_dict)])
			uniq_name_dict[name] = 1
			out_guid_fid_to_anim_name[child.ref_to_anim_key(motion_ref)] = name

	for state_machine in keys["m_ChildStateMachines"]:
		var child: UnidotAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
		sm_path.append(child.keys["m_Name"])
		child.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
		sm_path.remove_at(len(sm_path) - 1)

func resolve_entry_state_transitions(exit_src: Object, exit_parent: Dictionary, transition_list: Array, transition_dict: Dictionary, inp_condition_list: Array):
	var trans_list: Array = keys["m_EntryTransitions"]
	if exit_src != null and exit_src.uniq_key != self.uniq_key:  # if root, we use entry transitions anyway.
		trans_list = []
		#m_StateMachineTransitions:
		#- first: {fileID: 7243501764948564761}
		#  second:
		#  - {fileID: -5738504938746420287}
		#  - {fileID: -1730057159985691264}
		for elem in keys["m_StateMachineTransitions"]:
			var src_sm = meta.lookup(elem["first"])
			if src_sm != null and src_sm.uniq_key == exit_src.uniq_key:
				trans_list = elem["second"]
	for etrans in trans_list:
		var trans_obj: UnidotAnimatorTransition = meta.lookup(etrans)
		var condition_list = inp_condition_list.duplicate()
		condition_list.append(trans_obj)
		if transition_dict.has(trans_obj.uniq_key):
			log_warn("Cycle detected... " + str(transition_dict) + " " + trans_obj.uniq_key)
			continue
		transition_dict[trans_obj.uniq_key] = 1
		var dst_state = meta.lookup(trans_obj.keys["m_DstState"])
		var dst_sm = meta.lookup(trans_obj.keys["m_DstStateMachine"])
		if dst_state != null and not trans_obj.keys["m_IsExit"]:
			condition_list.append(dst_state)
			transition_list.append(condition_list)
		else:  # if dst_sm != null or trans_obj.keys["m_IsExit"]:
			var new_exit_src: Object = null
			if trans_obj.keys["m_IsExit"]:
				new_exit_src = self
				dst_sm = exit_parent.get(self.uniq_key)
			if dst_sm == null:
				dst_sm = exit_parent.get(self.uniq_key)
			if dst_sm == null:
				log_warn("Unable to find exit state parent " + str(self.uniq_key))
				# condition_list.append(null)
				# transition_list.append(condition_list) # transition to broken link or top-level exit: go to special exit state.
			else:
				dst_sm.resolve_entry_state_transitions(new_exit_src, exit_parent, transition_list, transition_dict, condition_list)
		transition_dict.erase(trans_obj.uniq_key)
	var def_state = meta.lookup(keys["m_DefaultState"])
	if def_state != null:
		inp_condition_list.append(def_state)
		transition_list.append(inp_condition_list)
