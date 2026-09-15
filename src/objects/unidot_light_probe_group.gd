class_name UnidotLightProbeGroup extends UnidotComponent

func get_godot_type() -> String:
	return "LightmapProbe"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var i = 0
	var probe_positions: PackedVector3Array
	for pos in keys.get("m_SourcePositions", []):
		pos.x = -pos.x
		i += 1
		var probe: LightmapProbe = LightmapProbe.new()
		probe.name = "Probe" + str(i)
		new_parent.add_child(probe)
		probe.owner = state.owner
		probe.position = pos
		probe_positions.append(pos)
	# The LightmapProbe objects will be deleted later if there are too many...
	# We store the full original list here so users can reconstruct the probe positions
	# if Godot fixes the performance bugs in the lightmapper.
	new_parent.set_meta("lightmap_probe_positions", probe_positions)
	return null
