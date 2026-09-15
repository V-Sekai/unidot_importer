class_name UnidotNativeFormatImporter extends UnidotAssetImporter

func get_main_object_id() -> int:
	var ret: int = keys.get("mainObjectFileID", 0)
	if ret == -1:
		return 0
	return ret
