class_name UnidotAssetImporter extends UnidotObject

func get_main_object_id() -> int:
	return 0  # Unknown

var main_object_id: int:
	get:
		return get_main_object_id()  # Unknown

func get_external_objects() -> Dictionary:
	var eo: Dictionary = {}.duplicate()
	var extos: Variant = keys.get("externalObjects")
	if typeof(extos) != TYPE_ARRAY:
		return eo
	for srcAssetIdent in extos:
		var type_str: String = srcAssetIdent.get("first", {}).get("type", "")
		var type_key: String = type_str.split(":")[-1]
		var key: Variant = srcAssetIdent.get("first", {}).get("name", "")  # FIXME: Returns null sometimes????
		var val: Array = srcAssetIdent.get("second", [null, 0, "", null])  # UnidotRef
		if typeof(key) != TYPE_NIL and not key.is_empty():
			if not eo.has(type_key):
				eo[type_key] = {}.duplicate()
			eo[type_key][key] = val
	return eo

var addCollider: bool:
	get:
		return keys.get("meshes", {}).get("addCollider") == 1

func get_animation_clips() -> Array[Dictionary]:
	var src_clips = keys.get("animations", {}).get("clipAnimations", [])
	var out_clips: Array[Dictionary] = []
	for src_clip in src_clips:
		var clip = {}.duplicate()
		clip["name"] = src_clip.get("name", "")
		clip["start_frame"] = src_clip.get("firstFrame", 0.0)
		clip["end_frame"] = src_clip.get("lastFrame", 0.0)
		# "loop" also exists but appears to be unused at least
		clip["loop_mode"] = 0 if src_clip.get("loopTime", 0) == 0 else 1
		clip["take_name"] = src_clip.get("takeName", "default")
		out_clips.append(clip)
		# TODO: Root motion?
		#cycleOffset: -0
		#loop: 0
		#hasAdditiveReferencePose: 0
		#loopTime: 1
		#loopBlend: 1
		#loopBlendOrientation: 0
		#loopBlendPositionY: 1
		#loopBlendPositionXZ: 0
		#keepOriginalOrientation: 0
		#keepOriginalPositionY: 0
		#keepOriginalPositionXZ: 0
		# TODO: Humanoid retargeting?
		# humanDescription:
		#   serializedVersion: 2
		#   human:
		#   - boneName: RightUpLeg
		#     humanName: RightUpperLeg
	return out_clips

var meshes_light_baking: int:
	get:
		# Godot uses: Disabled,Static,StaticLightmaps,Dynamic
		# 1 = Static (defauylt setting)
		# 2 = StaticLightmaps
		return keys.get("meshes", {}).get("generateSecondaryUV", 0) + 1

# The following parameters have special meaning when importing FBX files and do not map one-to-one with godot importer.
var useFileScale: bool:
	get:
		return keys.get("meshes", {}).get("useFileScale", 0) == 1

var extractLegacyMaterials: bool:
	get:
		return keys.get("materials", {}).get("materialLocation", 0) == 0

var globalScale: float:
	get:
		return keys.get("meshes", {}).get("globalScale", 1)

var ensure_tangents: bool:
	get:
		var importTangents: int = keys.get("tangentSpace", {}).get("tangentImportMode", 3)
		return importTangents != 4 and importTangents != 0

var animation_import: bool:
	# legacyGenerateAnimations = 4 ??
	# animationType = 3 ??
	get:
		return keys.get("importAnimation") and keys.get("animationType") != 0

var fileIDToRecycleName: Dictionary:
	get:
		return keys.get("fileIDToRecycleName", {})

var internalIDToNameTable: Array:
	get:
		return keys.get("internalIDToNameTable", [])

var preserveHierarchy: bool:
	get:
		return keys.get("meshes").get("preserveHierarchy", 0) != 0

# 0: No compression; 1: keyframe reduction; 2: keyframe reduction and compress
# 3: all of the above and choose best curve for runtime memory.
func animation_optimizer_settings() -> Dictionary:
	var rotError: float = keys.get("animations").get("animationRotationError", 0.5)  # Degrees
	var rotErrorHalfRevs: float = rotError / 180  # p_alowed_angular_err is defined this way (divides by PI)
	return {
		"enabled": keys.get("animations").get("animationCompression") != 0,
		"max_linear_error": keys.get("animations").get("animationPositionError", 0.5),
		"max_angular_error": rotErrorHalfRevs,  # Godot defaults this value to
	}
