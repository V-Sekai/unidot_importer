class_name UnidotReflectionProbe extends UnidotBehaviour

func get_godot_type() -> String:
	return "ReflectionProbe"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "ReflectionProbe"
	# UPDATE_ALWAYS can crash Godot if multiple probes "see" each other
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	assign_object_meta(probe)
	state.add_child(probe, new_parent, self)
	return probe

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_BoxProjection"):
		outdict["interior"] = true if uprops.get("m_BoxProjection") else false
		outdict["box_projection"] = true if uprops.get("m_BoxProjection") else false
	if uprops.has("m_BoxOffset"):
		outdict["position"] = uprops.get("m_BoxOffset")
		outdict["origin_offset"] = -uprops.get("m_BoxOffset")
	if uprops.has("m_BoxSize"):
		outdict["size"] = uprops.get("m_BoxSize")
	if uprops.has("m_CullingMask"):
		# Bits 24-31 seem to be reserved in Godot. Merge layers 24-31 into 16-23.
		# Otherwise, reflection probes and lightmaps will see gizmos.
		# If this is causing problems for you, submit an issue so we can figure out a good setting
		var layer: int = uprops.get("m_CullingMask").get("m_Bits")
		outdict["cull_mask"] = (layer & ~(255 << 24)) | ((layer >> 8) & (255 << 16))
	elif uprops.has("m_CullingMask.m_Bits"):
		var layer: int = uprops.get("m_CullingMask.m_Bits")
		outdict["cull_mask"] = (layer & ~(255 << 24)) | ((layer >> 8) & (255 << 16))
	if uprops.has("m_FarClip"):
		outdict["max_distance"] = uprops.get("m_FarClip")
	if uprops.get("m_Mode", 0) == 0:
		log_warn("Reflection Probe = Baked is not supported. Treating as Realtime / Once")
	if uprops.get("m_Mode", 0) == 2:
		log_warn("Reflection Probe = Custom is not supported. Treating as Realtime / Once")
	'''
	if uprops.get("m_Mode", 0) == 1 and uprops.get("m_RefreshMode", 0) == 1:
		outdict["update_mode"] = 1
	if uprops.has("m_Mode"):
		if uprops.get("m_Mode") == 1:
			if uprops.get("m_RefreshMode", 1) != 1:
				outdict["update_mode"] = 0
		else:
			outdict["update_mode"] = 0
	elif uprops.get("m_RefreshMode", 1) != 1:
		outdict["update_mode"] = 0
	'''
	return outdict
