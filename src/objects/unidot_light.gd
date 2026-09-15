class_name UnidotLight extends UnidotBehaviour

func get_godot_type() -> String:
	return "Light3D"

func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
	var light: Light3D
	# TODO: Change Light to use set() and convert_properties system
	var src_light_type = lightType
	if src_light_type == 0:
		# Assuming default cookie
		# Assuming Legacy pipeline:
		# Scriptable Rendering Pipeline: shape and innerSpotAngle not supported.
		# Assuming RenderSettings.m_SpotCookie: == {fileID: 10001, guid: 0000000000000000e000000000000000, type: 0}
		var spot_light: SpotLight3D = SpotLight3D.new()
		spot_light.set_param(Light3D.PARAM_SPOT_ANGLE, spotAngle * 0.5)
		spot_light.set_param(Light3D.PARAM_SPOT_ATTENUATION, 0.5)  # Eyeball guess for their default spotlight texture
		spot_light.set_param(Light3D.PARAM_ATTENUATION, 0.333)  # Was 1.0
		spot_light.set_param(Light3D.PARAM_RANGE, lightRange)
		light = spot_light
	elif src_light_type == 1:
		# depth_range? max_disatance? blend_splits? bias_split_scale?
		#keys.get("m_ShadowNearPlane")
		var dir_light: DirectionalLight3D = DirectionalLight3D.new()
		dir_light.set_param(Light3D.PARAM_SHADOW_NORMAL_BIAS, shadowNormalBias)
		light = dir_light
	elif src_light_type == 2:
		var omni_light: OmniLight3D = OmniLight3D.new()
		light = omni_light
		omni_light.set_param(Light3D.PARAM_ATTENUATION, 1.0)
		omni_light.set_param(Light3D.PARAM_RANGE, lightRange)
	elif src_light_type == 3:
		log_warn("Rectangle Area Light not supported!", "lightType")
		# areaSize?
		return super.create_godot_node(state, new_parent)
	elif src_light_type == 4:
		log_warn("Disc Area Light not supported!", "lightType")
		return super.create_godot_node(state, new_parent)

	# TODO: Layers
	if keys.get("useColorTemperature"):
		log_warn("Color Temperature not implemented.", "useColorTemperature")
	light.name = type
	state.add_child(light, new_parent, self)
	light.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)))
	light.light_color = color
	light.set_param(Light3D.PARAM_ENERGY, intensity)
	light.set_param(Light3D.PARAM_INDIRECT_ENERGY, bounceIntensity)
	light.shadow_enabled = shadowType != 0
	light.set_param(Light3D.PARAM_SHADOW_BIAS, shadowBias)
	if lightmapBakeType == 1:
		light.light_bake_mode = Light3D.BAKE_DYNAMIC  # INDIRECT??
	elif lightmapBakeType == 2:
		light.light_bake_mode = Light3D.BAKE_STATIC  # BAKE_ALL???
		# light.editor_only = true
	else:
		light.light_bake_mode = Light3D.BAKE_DISABLED
	return light

# TODO: convert to properties!

var color: Color:
	get:
		return keys.get("m_Color")

var lightType: float:
	get:
		return keys.get("m_Type", 1)

var lightRange: float:
	get:
		return keys.get("m_Range")

var intensity: float:
	get:
		return keys.get("m_Intensity")

var bounceIntensity: float:
	get:
		return keys.get("m_BounceIntensity", 1.0)

var spotAngle: float:
	get:
		return keys.get("m_SpotAngle")

var lightmapBakeType: int:
	get:
		return keys.get("m_Lightmapping")

var shadowType: int:
	get:
		return keys.get("m_Shadows").get("m_Type")

var shadowBias: float:
	get:
		return keys.get("m_Shadows").get("m_Bias")

var shadowNormalBias: float:
	get:
		return keys.get("m_Shadows").get("m_NormalBias", 0.01)

func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
	var outdict = self.convert_properties_component(node, uprops)
	if uprops.has("m_CullingMask"):
		outdict["light_cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
	elif uprops.has("m_CullingMask.m_Bits"):
		outdict["light_cull_mask"] = uprops.get("m_CullingMask.m_Bits")
	#if uprops.has("m_TagString"):
	#	outdict["editor_only"] = uprops["m_TagString"] == "EditorOnly"
	return outdict
