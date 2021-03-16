extends Reference

# Instantiated from static_preload.gd
var static_storage_file: Resource = load("res://static_storage.tres")
const static_storage_class: GDScript = preload("./static_preload.gd")
var static_storage: Resource = static_storage_class.new() if static_storage_file == null else static_storage_file

func set_editor_interface(ei: EditorInterface):
	if ei != null:
		static_storage.set("os_instance_id", OS.get_instance_id())
		static_storage.set("editor_interface_instance_id", ei.get_instance_id())
		static_storage.emit_changed()
		print("SS:" + str(static_storage.get_instance_id()) + " / " + "OS:" + str(static_storage.get("os_instance_id")) + " / " + "Editor:" + str(static_storage.get("editor_interface_instance_id")))
		ResourceSaver.save("res://static_storage.tres", static_storage)

func get_editor_interface() -> EditorInterface:
	if static_storage.get("os_instance_id") == 0:
		print("Singleton ID unset. Will attempt reload.")
		static_storage = load("res://static_storage.tres")
	if static_storage.get("os_instance_id") != OS.get_instance_id():
		print("Singleton ID mismatch. Will attempt reload.")
		static_storage = load("res://static_storage.tres")
	if static_storage.get("os_instance_id") != OS.get_instance_id():
		printerr("Singleton ID mismatch. Will return null " + str(static_storage.get("os_instance_id")) + "," + str(OS.get_instance_id()))
		return null
	var ei: EditorInterface = instance_from_id(static_storage.get("editor_interface_instance_id"))
	if static_storage.get("editor_interface_instance_id") != ei.get_instance_id():
		printerr("EditorInterface ID changed. Will update")
		static_storage.set("editor_interface_instance_id", ei.get_instance_id())
		static_storage.emit_changed()
		ResourceSaver.save("res://static_storage.tres", static_storage)
	return ei

func get_resource_filesystem() -> EditorFileSystem:
	return get_editor_interface().get_resource_filesystem()
