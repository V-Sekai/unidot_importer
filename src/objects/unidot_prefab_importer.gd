class_name UnidotPrefabImporter extends UnidotAssetImporter

func get_main_object_id() -> int:
	# PrefabInstance is 1001. Multiply by 100000 to create default ID.
	return 100100000  # Always should be this ID.
