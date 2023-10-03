@tool
extends EditorPlugin

const tarfile = preload("./tarfile.gd")

const package_import_dialog_class: GDScript = preload("./package_import_dialog.gd")

var package_import_dialog: RefCounted = null


func recursive_print(node: Node, indent: String = ""):
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


func show_reimport():
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_reimport()


func show_importer():
	package_import_dialog = package_import_dialog_class.new()
	package_import_dialog.show_importer()

func show_importer_logs():
	if package_import_dialog != null:
		package_import_dialog.show_importer_logs()

func recursive_print_scene():
	recursive_print(get_tree().edited_scene_root)


func _enter_tree():
	print("run enter tree")
	add_tool_menu_item("Import Unity Package...", self.show_importer)
	add_tool_menu_item("Reimport large unity package...", self.show_reimport)
	add_tool_menu_item("Show last import logs", self.show_importer_logs)
	#add_tool_menu_item("Queue Test...", self.queue_test)
	#add_tool_menu_item("Print scene nodes with owner...", self.recursive_print_scene)


func _exit_tree():
	print("run exit tree")
	remove_tool_menu_item("Print scene nodes with owner...")
	remove_tool_menu_item("Import Unity Package...")
	remove_tool_menu_item("Show last import logs")
	#remove_tool_menu_item("Reimport large unity package...")
	#remove_tool_menu_item("Queue Test...")
