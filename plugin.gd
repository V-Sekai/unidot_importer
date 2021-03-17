@tool
extends EditorPlugin

var tarfile = preload("./tarfile.gd")

const static_storage: GDScript = preload("./static_storage.gd")
const package_import_dialog_class: GDScript = preload("./package_import_dialog.gd")

var package_import_dialog: Reference = null

func queue_test():
	var queue_lib: GDScript = load("./queue_lib.gd")
	var q = queue_lib.new()
	q.run_test()

func show_importer():
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_importer()

func _enter_tree():
	static_storage.new().set_editor_interface(get_editor_interface())
	print("EditorInterface: " + str(static_storage.new().get_editor_interface()))

	add_tool_menu_item("Import Unity Package...",self.show_importer)
	add_tool_menu_item("Queue Test...",self.queue_test)

func _exit_tree():
	remove_tool_menu_item("Import Unity Package...")
	remove_tool_menu_item("Queue Test...")

