class_name UnidotTextureImporter extends UnidotAssetImporter

var textureShape: int:
	get:
		# 1: Texture2D
		# 2: Cubemap
		# 3: Texture2DArray (version 2020)
		# 4: Texture3D (version 2020)
		return keys.get("textureShape", 0)  # Some old files do not have this

# TODO: implement textureType. Currently unused
var textureType: int:
	get:
		# -1: Unknown
		# 0: Default
		# 1: NormalMap
		# 2: GUI
		# 3: Sprite
		# ...
		# bumpmap.convertToNormalMap?
		return keys.get("textureType", 0)

func get_main_object_id() -> int:
	match textureShape:
		0, 1:
			return 2800000  # "Texture2D",
		2:
			return 8900000  # "Cubemap",
		3:
			return 18700000  # "Texture2DArray",
		4:
			return 11700000  # "Texture3D",
		_:
			return 0
