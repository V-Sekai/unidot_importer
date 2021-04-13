@tool
extends EditorPlugin

var tarfile = preload("./tarfile.gd")

const static_storage: GDScript = preload("./static_storage.gd")
const package_import_dialog_class: GDScript = preload("./package_import_dialog.gd")

var package_import_dialog: Reference = null

func recursive_print(node:Node, indent:String=""):
	var fnstr = "" if str(node.filename) == "" else (" (" + str(node.filename) + ")")
	print(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#print(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_print(c, new_indent)

func queue_test():
	var queue_lib: GDScript = load("./queue_lib.gd")
	var q = queue_lib.new()
	q.run_test()

func show_importer():
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_importer()

func recursive_print_scene():
	recursive_print(get_tree().edited_scene_root)

func _enter_tree():
	static_storage.new().set_editor_interface(get_editor_interface())
	print("EditorInterface: " + str(static_storage.new().get_editor_interface()))

	add_tool_menu_item("Import Unity Package...",self.show_importer)
	add_tool_menu_item("Queue Test...",self.queue_test)
	add_tool_menu_item("Print scene nodes with owner...",self.recursive_print_scene)

func _exit_tree():
	remove_tool_menu_item("Print scene nodes with owner...")
	remove_tool_menu_item("Import Unity Package...")
	remove_tool_menu_item("Queue Test...")

