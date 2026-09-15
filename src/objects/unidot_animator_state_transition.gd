class_name UnidotAnimatorStateTransition extends UnidotAnimatorTransitionBase

func resolve_state_transitions(exit_parent: Dictionary, this_sm: Object):
	var dst_sm: UnidotAnimatorStateMachine = meta.lookup(keys.get("m_DstStateMachine"))
	var dst_state: UnidotAnimatorState = meta.lookup(keys.get("m_DstState"))

	var transition_list = [].duplicate()
	var condition_list = [].duplicate()
	condition_list.append(self)
	var exit_src = null
	if keys["m_IsExit"]:
		dst_state = null
		dst_sm = exit_parent[this_sm.uniq_key]
		exit_src = this_sm
	if dst_state != null:
		condition_list.append(dst_state)
		transition_list.append(condition_list)
	elif dst_sm != null:
		var transition_dict = {}.duplicate()  # avoid cycles
		dst_sm.resolve_entry_state_transitions(exit_src, exit_parent, transition_list, transition_dict, condition_list)
	return transition_list
