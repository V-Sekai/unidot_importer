class_name UnidotRenderer extends UnidotBehaviour

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_Layer"):
		var layer: int = uprops["m_Layer"]
		# We exclude layers 24-31 from visibility masks because these layers are used by gizmos.
		outdict["layers"] = (1 << layer) if layer < 24 else (1 << (layer - 8)) | (1 << layer)
	if uprops.has("m_StaticEditorFlags"):
		var flags_val: int = uprops.get("m_StaticEditorFlags", 0) # We copy this from the GameObject to the MeshRenderer.
		var lightmap_static: bool = (flags_val & 1) != 0
		outdict["_lightmap_static"] = lightmap_static
	if uprops.has("m_ScaleInLightmap"):
		var lightmap_scale: float = uprops.get("m_ScaleInLightmap", 1)
		if lightmap_scale <= 1.55:
			outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_1X
		elif lightmap_scale <= 3.05:
			outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_2X
		elif lightmap_scale <= 6.05:
			outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_4X
		else:
			outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_8X

	# if flags_val & 16: # Occludee static
	# if flags_val & 2: # Occluder static
	if uprops.has("m_DynamicOccludee"):
		outdict["ignore_occlusion_culling"] = uprops.get("m_DynamicOccludee", 1) != 1

	if uprops.has("m_CastShadows"):
		match uprops.get("m_CastShadows", 1):
			0:
				outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			2:
				outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			3:
				outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_:
				outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	if uprops.has("m_Materials"):
		outdict["_materials_size"] = len(uprops.get("m_Materials"))
		var idx: int = 0
		for m in uprops.get("m_Materials", []):
			outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
			idx += 1
		log_debug("Converted mesh prop " + str(outdict))
	else:
		if uprops.has("m_Materials.Array.size"):
			outdict["_materials_size"] = uprops.get("m_Materials.Array.size")
		const MAT_ARRAY_PREFIX: String = "m_Materials.Array.data["
		for prop in uprops:
			if str(prop).begins_with(MAT_ARRAY_PREFIX) and str(prop).ends_with("]"):
				var idx: int = str(prop).substr(len(MAT_ARRAY_PREFIX), len(str(prop)) - 1 - len(MAT_ARRAY_PREFIX)).to_int()
				var m: Array = get_ref(uprops, prop)
				outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
		log_debug("Converted mesh prop " + str(outdict) + "  for uprop " + str(uprops))
	return outdict
