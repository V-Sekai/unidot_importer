class_name UnidotAudioSource extends UnidotBehaviour

func get_godot_type() -> String:
	return "AudioStreamPlayer3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var audio: Node = null
	var panlevel_curve: Dictionary = keys.get("panLevelCustomCurve", {})
	var curves: Array = panlevel_curve.get("m_Curve", [])
	#if len(curves) == 1:
	#	log_debug("Curve is " + str(curves) + " value is " + str(curves[0].get("value", 1.0)))
	if len(curves) == 1 and str(curves[0].get("value", 1.0)).to_float() < 0.001:
		# Completely 2D: use non-spatialized player.
		audio = AudioStreamPlayer.new()
	else:
		audio = AudioStreamPlayer3D.new()
	audio.name = "AudioSource"
	assign_object_meta(audio)
	state.add_child(audio, new_parent, self)
	return audio

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_CullingMask"):
		outdict["light_cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
	elif uprops.has("m_CullingMask.m_Bits"):
		outdict["light_cull_mask"] = uprops.get("m_CullingMask.m_Bits")
	if uprops.has("m_Pitch"):
		outdict["pitch_scale"] = uprops.get("m_Pitch")
	if uprops.has("m_Volume"):
		var volume_linear: float = 1.0 * uprops.get("m_Volume")
		var volume_db: float = -80.0
		if volume_linear > 0.0001:
			volume_db = 20.0 * log(volume_linear) / log(10.0)
		outdict["volume_db"] = volume_db
		outdict["unit_db"] = volume_db
		outdict["max_db"] = volume_db
	if uprops.has("m_PlayOnAwake"):
		outdict["autoplay"] = uprops.get("m_PlayOnAwake") == 1
	if uprops.has("Mute"):
		outdict["stream_paused"] = uprops.get("Mute") == 1
	# "Loop" not supported?
	if uprops.has("m_audioClip"):
		outdict["stream"] = meta.get_godot_resource(get_ref(uprops, "m_audioClip"))
	if uprops.has("MaxDistance"):
		outdict["max_distance"] = uprops.get("MaxDistance")
	# TODO: how does MinDistance work with falloff curves? Are max_db and unit_db affected?
	if uprops.get("rolloffMode", -1) == 0:
		outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	if uprops.get("rolloffMode", -1) == 1:
		outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if uprops.get("rolloffMode", -1) == 2:
		# Guess which slope curve it is closest to.
		var slope_estimate: float = 0.0
		var curve_points: Array = uprops.get("rolloffCustomCurve", {}).get("m_Curve", [{}])
		for curvept in curve_points:
			slope_estimate += curvept.get("outSlope", 0.0)
		slope_estimate /= len(curve_points)
		if slope_estimate < -5.0:
			outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		elif slope_estimate < -0.1:
			outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		else:
			outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_DISABLED
		# TODO: How does unit_size work?
	return outdict
