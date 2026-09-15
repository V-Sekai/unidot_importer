# Creates Godot materials from Unity materials.
#
# In Godot, materials and shaders are decoupled:
# - StandardMaterial3D (built-in shading model)
# - ShaderMaterial (custom shader-driven)
#
# In Unity, materials and shaders are tightly coupled:
# shaders define the available properties, and materials store values for them.
#
# Unity has multiple render pipelines (Built-in, URP, HDRP), but we do not need to explicitly handle
# pipeline selection here because the exported material already contains resolved shader + property data.
# The .mat file serializes the shader reference (by GUID) and resolved property values directly.
# Texture references are stored as GUIDs and must be resolved separately via the asset database.
#
# The conversion process is:
# 1. Detect the Unity shader used by the material
# 2. Interpret its property schema (and keywords)
# 3. Map those properties to equivalent Godot material fields
class_name UnidotMaterial extends UnidotObject

func get_godot_extension() -> String:
	return ".mat.tres"

func get_godot_type() -> String:
	return "StandardMaterial3D"

func create_godot_resource() -> Resource:  #Material:
	#log_debug("keys: " + str(keys))
	var kws: Dictionary = _get_keywords()
	var floatProperties: Dictionary = _get_float_properties()
	#log_debug(str(floatProperties))
	var texProperties: Dictionary = _get_tex_properties()
	#log_debug(str(texProperties))
	var colorProperties: Dictionary = _get_color_properties()
	#log_debug(str(colorProperties))
	# depth_draw_mode is apparently wrong, causing issues when typed - will look shortly
#	var ret: StandardMaterial3D = StandardMaterial3D.new()
	var ret = StandardMaterial3D.new()
	ret.resource_name = self.name
	# FIXME: Kinda hacky since transparent stuff doesn't always draw depth in Unidot
	# But it seems to workaround a problem with some materials for now.
	ret.depth_draw_mode = true  ##### BaseMaterial3D.DEPTH_DRAW_ALWAYS
	ret.albedo_color = _get_color(colorProperties, "_Color", Color.WHITE)
	var albedo_textures_to_try: Array[Variant] = ["_MainTex", "_Tex", "_Albedo", "_Diffuse", "_BaseColor", "_BaseColorMap"]
	for name in texProperties:
		if albedo_textures_to_try.has(name):
			continue
		if not name.ends_with("Map"):
			albedo_textures_to_try.append(name)
	# Pick a random non-null texture property as albedo. Prefer texture slots not ending with "Map"
	for name in texProperties:
		if name == "_BumpMap" or name == "_OcclusionMap" or name == "_MetallicGlossMap" or name == "_ParallaxMap":
			continue
		if name.ends_with("ColorMap") or name.ends_with("BaseMap"):
			albedo_textures_to_try.append(name)
	for name in albedo_textures_to_try:
		var env = texProperties.get(name, {})
		var texref: Array = env.get("m_Texture", [null, 0, "", 0])
		if not texref.is_empty():
			ret.albedo_texture = meta.get_godot_resource(texref)
			if ret.albedo_texture != null:
				log_debug("Trying to get albedo from " + str(name) + ": " + str(ret.albedo_texture))
				ret.uv1_scale = _get_texture_scale(texProperties, name)
				ret.uv1_offset = _get_texture_offset(texProperties, name)
				break

	if ret.albedo_texture == null:
		ret.uv1_scale = _get_texture_scale(texProperties, "_MainTex")
		ret.uv1_offset = _get_texture_offset(texProperties, "_MainTex")

	# TODO: ORM not yet implemented.
	if true: # kws.get("_NORMALMAP", false):
		ret.normal_texture = _get_texture(texProperties, "_BumpMap")
		ret.normal_scale = _get_float(floatProperties, "_BumpScale", 1.0)
		if ret.normal_texture != null:
			ret.normal_enabled = true
	if kws.get("_EMISSION", false):
		var emis_vec: Plane = _get_vector_from_color(colorProperties, "_EmissionColor", Color.BLACK)
		var emis_mag = max(emis_vec.x, max(emis_vec.y, emis_vec.z))
		ret.emission = Color.BLACK
		if emis_mag > 0.01:
			ret.emission_enabled = true
			ret.emission = Color(emis_vec.x / emis_mag, emis_vec.y / emis_mag, emis_vec.z / emis_mag).linear_to_srgb()
			ret.emission_energy = emis_mag
			ret.emission_texture = _get_texture(texProperties, "_EmissionMap")
			if ret.emission_texture != null:
				ret.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	if true: # kws.get("_PARALLAXMAP", false):
		ret.heightmap_texture = _get_texture(texProperties, "_ParallaxMap")
		if ret.heightmap_texture != null:
			ret.heightmap_enabled = true
			# Godot generated standard shader code looks something like this:
			# float depth = 1.0 - texture(texture_heightmap, base_uv).r;
			# vec2 ofs = base_uv - view_dir.xy * depth * heightmap_scale * 0.01;
			# ------
			# Note in particular the * 0.01 multiplier.
			# Unfortunately, Godot does not have a heightmap bias setting (such as 0.5)
			# Therefore, it is not possible to represent a heightmap completely accurately
			# And we must pick a direction: positive or negative. In this case I choose negative.
			# Which causes the heightmap to "pop out" of the surface.
			ret.heightmap_scale = -100.0 * _get_float(floatProperties, "_Parallax", 1.0)
	if kws.get("_SPECULARHIGHLIGHTS_OFF", false):
		ret.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if kws.get("_GLOSSYREFLECTIONS_OFF", false):
		pass
	if kws.get("_DOUBLESIDED_ON", false): # HDRP-compatible materials should set this.
		ret.cull_mode = BaseMaterial3D.CULL_DISABLED
	var occlusion: Texture = _get_texture(texProperties, "_OcclusionMap")
	if occlusion != null:
		ret.ao_enabled = true
		ret.ao_texture = occlusion
		ret.ao_light_affect = _get_float(floatProperties, "_OcclusionStrength", 1.0)  # why godot defaults to 0???
		ret.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var metallic_texture: Texture = null
	var use_glossmap := false
	if true: # kws.get("_METALLICGLOSSMAP"):
		var metallic_gloss_texture_ref: Array = _get_texture_ref(texProperties, "_MetallicGlossMap")
		if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
			metallic_gloss_texture_ref = _get_texture_ref(texProperties, "_MetallicSmoothness")
		if not metallic_gloss_texture_ref.is_empty() and metallic_gloss_texture_ref[1] != 0:
			metallic_gloss_texture_ref[1] = -metallic_gloss_texture_ref[1]
			if not is_equal_approx(_get_float(floatProperties, "_GlossMapScale", 1.0), 0.0):
				metallic_texture = meta.get_godot_resource(metallic_gloss_texture_ref, false)
				log_debug("Found metallic roughness texture " + str(metallic_gloss_texture_ref) + " => " + str(metallic_texture))
				use_glossmap = true
			if metallic_texture == null:
				if use_glossmap:
					log_debug("Load roughness " + str(load("res://Assets/ArchVizPRO Interior Vol.6/3D MATERIAL/Tiles_White/Tiles_White_metallic.roughness.png")))
					log_warn("Unable to load metallic roughness texture. Trying metallic gloss.", "_MetallicGlossMap", metallic_gloss_texture_ref)
				metallic_gloss_texture_ref[1] = -metallic_gloss_texture_ref[1]
				metallic_texture = meta.get_godot_resource(metallic_gloss_texture_ref)
				log_debug("Found metallic gloss texture " + str(metallic_gloss_texture_ref) + " => " + str(metallic_texture))
				use_glossmap = false
		ret.metallic_texture = metallic_texture
		ret.metallic = _get_float(floatProperties, "_Metallic", 0.0)
		ret.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if use_glossmap:
			ret.roughness_texture = metallic_texture
			ret.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
			ret.roughness = 1.0 # We scaled down the roughness in code.
	# TODO: Glossiness: invert color channels??
	if metallic_texture == null:
		# UnidotStandardInput.cginc ignores _Glossiness if _METALLICGLOSSMAP.
		ret.roughness = 1.0 - _get_float(floatProperties, "_Glossiness", 0.0)
	if kws.get("_ALPHATEST_ON"):
		ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		var cutoff: float = _get_float(floatProperties, "_Cutoff", 0.0)
		if cutoff > 0.0:
			ret.alpha_scissor_threshold = cutoff
	elif kws.get("_ALPHABLEND_ON") or kws.get("_ALPHAPREMULTIPLY_ON"):
		# FIXME: No premultiply
		ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Godot's detail map is a bit lacking right now...
	#if kws.get("_DETAIL_MULX2"):
	#	ret.detail_enabled = true
	#	ret.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	assign_object_meta(ret)
	return ret

func bake_roughness_texture_if_needed(tmp_path: String, guid_to_pkgasset: Dictionary, stage2_dict_lock: Mutex, stage2_extra_asset_dict: Dictionary) -> String:
	var kws: Dictionary = _get_keywords()
	var floatProperties: Dictionary = _get_float_properties()
	var texProperties: Dictionary = _get_tex_properties()
	# Note that this must be pre-baked into the texture to bring it towards 1.
	# _GlossMapScale ????
	var glossiness_value: float = _get_float(floatProperties, "_GlossMapScale", 1.0)
	if is_equal_approx(glossiness_value, 0.0):
		log_debug("Material has 0 _GlossMapScale")
		return "" # We can ignore the texture
	var metallic_gloss_texture_ref: Array = _get_texture_ref(texProperties, "_MetallicGlossMap")
	if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
		metallic_gloss_texture_ref = _get_texture_ref(texProperties, "_MetallicSmoothness")
	# Not any more: Material has _METALLICGLOSSMAP enabled.
	if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
		log_debug("Material has null _MetallicGlossMap")
		# null gloss: no roughness to bake
		return ""
	log_debug("gloss map ref is " + str(metallic_gloss_texture_ref))
	#var metallic_gloss_texture = get_texture(texProperties, "_MetallicGlossMap")
	var target_meta: Object
	if not metallic_gloss_texture_ref.is_empty() and guid_to_pkgasset.has(metallic_gloss_texture_ref[2]):
		target_meta = guid_to_pkgasset[metallic_gloss_texture_ref[2]].parsed_meta
	else:
		target_meta = meta.lookup_meta(metallic_gloss_texture_ref)
	if target_meta == null:
		log_warn("Failed to lookup gloss texture ref", "_MetallicGlossMap", metallic_gloss_texture_ref)
		return ""
	target_meta.mutex.lock()
	var pathname: String = target_meta.path
	var roughness_filename: String = pathname.get_basename() + ".roughness.png"
	# Sometimes multiple materials reference the same roughness texture. We to avoid generating the same texture multiple times.
	stage2_dict_lock.lock()
	if stage2_extra_asset_dict.has(roughness_filename):
		stage2_dict_lock.unlock()
		target_meta.mutex.unlock()
		return ""
	stage2_extra_asset_dict[roughness_filename] = true
	stage2_dict_lock.unlock()
	var ret: String = _bake_roughness_texture_locked(tmp_path, target_meta, roughness_filename, glossiness_value, guid_to_pkgasset)
	target_meta.mutex.unlock()
	return ret

func _bake_roughness_texture_locked(tmp_path: String, target_meta: Object, roughness_filename: String, glossiness_value: float, guid_to_pkgasset: Dictionary) -> String:
	var pathname: String = target_meta.path
	if FileAccess.file_exists(roughness_filename):
		var fa := FileAccess.open(roughness_filename, FileAccess.READ)
		if fa != null:
			if fa.get_length() > 0:
				if not target_meta.godot_resources.has(-target_meta.main_object_id):
					target_meta.insert_resource_path(-target_meta.main_object_id, "res://" + roughness_filename)
				log_debug("Roughness texture already exists. Modified " + str(target_meta.guid) + "/" + str(target_meta.path) + " godot_resources: " + str(target_meta.godot_resources))
				return "" # Nothing new to import.
	var image: Image
	if FileAccess.file_exists(tmp_path + "/" + pathname):
		image = Image.load_from_file(tmp_path + "/" + pathname)
	elif FileAccess.file_exists(pathname):
		image = Image.load_from_file(pathname)
	if image != null:
		log_debug("Texture " + str(pathname) + " exists. Loaded " + str(image))
		if image != null and image.get_width() > 0 and image.get_height() > 0:
			if not meta.internal_data.has("extra_textures"):
				meta.internal_data["extra_textures"] = {}
			meta.internal_data["extra_textures"][roughness_filename] = {
				"temp_path": tmp_path + "/" + roughness_filename,
				"source_meta_guid": target_meta.guid,
				"roughness/mode": 5,
			}
			if not FileAccess.file_exists(roughness_filename + ".import"):
				var cfile: ConfigFile = ConfigFile.new()
				cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
				# Make an empty "keep" importer file so it will not be imported.
				cfile.set_value("remap", "importer", "keep")
				cfile.save("res://" + roughness_filename + ".import")
				log_debug("Generated dummy roughness " + str(roughness_filename))
			if not FileAccess.file_exists(roughness_filename):
				# Make an empty file so it will be found by a scan!
				var f: FileAccess = FileAccess.open(roughness_filename, FileAccess.WRITE_READ)
				f.close()
				f = null
			else:
				log_debug("Already existing roughness " + str(roughness_filename))
			var col: Color
			for x in range(image.get_width()):
				for y in range(image.get_height()):
					col = image.get_pixel(x, y)
					col.a = 1.0 - glossiness_value * col.a
					image.set_pixel(x, y, col)
			image.save_png(tmp_path + "/" + roughness_filename)
			target_meta.insert_resource_path(-target_meta.main_object_id, "res://" + roughness_filename)
			log_debug("Roughness texture modified " + str(target_meta.guid) + "/" + str(target_meta.path) + " godot_resources: " + str(target_meta.godot_resources))
			log_debug("Generated " + str(tmp_path) + "/" + str(roughness_filename) + " " + str(image.get_size()))
			return roughness_filename
	# TODO: Glossiness: invert color channels??
	log_warn("Failed to generate roughness texture at " + str(pathname) + " from " + str(target_meta.guid), "_MetallicGlossMap", [null, target_meta.main_object_id, target_meta.guid, 0])
	return ""

func _get_float_properties() -> Dictionary:
	var flts = keys.get("m_SavedProperties", {}).get("m_Floats", [])
	var ret: Dictionary = {}.duplicate()
	# log_debug("material floats: " + str(flts))
	for dic in flts:
		if len(dic) == 2 and dic.has("first") and dic.has("second"):
			ret[dic["first"]["name"]] = dic["second"]
		else:
			for key in dic:
				ret[key] = dic.get(key)
	return ret

func _get_color_properties() -> Dictionary:
	var cols = keys.get("m_SavedProperties", {}).get("m_Colors", [])
	var ret: Dictionary = {}.duplicate()
	for dic in cols:
		if len(dic) == 2 and dic.has("first") and dic.has("second"):
			ret[dic["first"]["name"]] = dic["second"]
		else:
			for key in dic:
				ret[key] = dic.get(key)
	return ret

func _get_tex_properties() -> Dictionary:
	var texs = keys.get("m_SavedProperties", {}).get("m_TexEnvs", [])
	var ret: Dictionary = {}.duplicate()
	for dic in texs:
		if len(dic) == 2 and dic.has("first") and dic.has("second"):
			ret[dic["first"]["name"]] = dic["second"]
		else:
			for key in dic:
				ret[key] = dic.get(key)
	return ret

func _get_texture_ref(texProperties: Dictionary, name: String) -> Array:
	var env = texProperties.get(name, {})
	return env.get("m_Texture", [null, 0, "", 0])

func _get_texture(texProperties: Dictionary, name: String) -> Texture:
	var texref: Array = _get_texture_ref(texProperties, name)
	if not texref.is_empty():
		return meta.get_godot_resource(texref)
	return null

func _get_texture_scale(texProperties: Dictionary, name: String) -> Vector3:
	var env = texProperties.get(name, {})
	var scale: Vector2 = env.get("m_Scale", Vector2(1, 1))
	return Vector3(scale.x, scale.y, 0.0)

func _get_texture_offset(texProperties: Dictionary, name: String) -> Vector3:
	var env = texProperties.get(name, {})
	var offset: Vector2 = env.get("m_Offset", Vector2(0, 0))
	return Vector3(offset.x, offset.y, 0.0)

func _get_color(colorProperties: Dictionary, name: String, dfl: Color) -> Color:
	var col: Color = colorProperties.get(name, dfl)
	return col

func _get_float(floatProperties: Dictionary, name: String, dfl: float) -> float:
	var ret: float = floatProperties.get(name, dfl)
	return ret

func _get_vector_from_color(colorProperties: Dictionary, name: String, dfl: Color) -> Plane:
	var col: Color = colorProperties.get(name, dfl)
	return Plane(Vector3(col.r, col.g, col.b), col.a)

func _get_keywords() -> Dictionary:
	var ret: Dictionary = {}.duplicate()
	var kwd = keys.get("m_ShaderKeywords", "")
	if typeof(kwd) == TYPE_STRING:
		for x in kwd.split(" "):
			ret[x] = true
	var validkws: Array = keys.get("m_ValidKeywords", [])
	for x in validkws:
		ret[str(x)] = true
	var invalidkws: Array = keys.get("m_InvalidKeywords", [])
	for x in invalidkws:
		# Keywords from before the material was switched to another shader.
		# Since we don't parse shaders, this will sometimes give the equivalent Standard shader keywords.
		ret[str(x)] = true
	return ret
