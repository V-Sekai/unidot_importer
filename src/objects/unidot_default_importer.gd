class_name UnidotDefaultImporter extends UnidotAssetImporter

# Will depend on filetype or file extension?
# Check file extension from `meta.path`???
func get_main_object_id() -> int:
	match meta.path.get_extension().to_lower():
		"tscn", "scene":
			# Scene file.
			# 1: OcclusionCullingSettings (29),
			# 2: RenderSettings (104),
			# 3: LightmapSettings (157),
			# 4: NavMeshSettings (196),
			# We choose 1 to represent the default id, but there is no actual root node.
			return 1
		"txt", "html", "htm", "xml", "bytes", "json", "csv", "yaml", "fnt":
			# Supported file extensions for text (.bytes is special)
			return 4900000  # TextAsset
		_:
			# Folder, or unsupported type.
			return 102900000  # DefaultAsset
