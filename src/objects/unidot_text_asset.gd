class_name UnidotTextAsset extends UnidotObject

func get_godot_type() -> String:
	return "TextFile"

func get_godot_extension() -> String:
	return "." + meta.path.get_extension()

func create_godot_resource() -> Resource:
	var fa: FileAccess = FileAccess.open(meta.path, FileAccess.WRITE)
	var script: Variant = keys.get("m_Script", PackedByteArray())
	if typeof(script) == TYPE_STRING:
		script = script.to_utf8_buffer()
	fa.store_buffer(script)
	fa.close()
	return meta # Don't error even though we didn't technically create a Godot resource.
