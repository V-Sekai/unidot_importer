# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
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

func do_reimport_previous_files():
	if package_import_dialog != null:
		package_import_dialog.do_reimport_previous_files()

func recursive_print_scene():
	recursive_print(get_tree().edited_scene_root)


func anim_import():
	const uoa = preload("./unity_object_adapter.gd")
	for anim_tres in get_editor_interface().get_selected_paths():
		var nod = get_editor_interface().get_selection().get_selected_nodes()[0] # as AnimationMixer
		var anim_raw = ResourceLoader.load(anim_tres)
		anim_raw.meta.initialize(preload("./asset_database.gd").new().get_singleton())
		for obj in anim_raw.objects:
			if obj.ends_with(":AnimationClip"):
				if nod != null:
					nod.get_animation_library("").remove_animation(anim_raw.objects[obj]["m_Name"])
				var ac = uoa.new().instantiate_unity_object_from_utype(anim_raw.meta, obj.split(":")[0].to_int(), 74)
				ac.keys = anim_raw.objects[obj]
				var animator = uoa.new().instantiate_unity_object_from_utype(anim_raw.meta, 1234, 95)
				#var animgo = uoa.new().instantiate_unity_object_from_utype(anim_raw.meta, 1234, 1)
				#var animtr = uoa.new().instantiate_unity_object_from_utype(anim_raw.meta, 1234, 4)
				var anim = ac.create_animation_clip_at_node(animator, null)
				anim.take_over_path(anim_raw.meta.path)
				ResourceSaver.save(anim, anim_raw.meta.path)
				if nod != null:
					nod.get_animation_library("").add_animation(anim_raw.objects[obj]["m_Name"], anim)

func _enter_tree():
	print("run enter tree")
	add_tool_menu_item("Import Unity Package...", self.show_importer)
	add_tool_menu_item("Reimport previous files", self.do_reimport_previous_files)
	add_tool_menu_item("Reimport large unity package...", self.show_reimport)
	add_tool_menu_item("Show last import logs", self.show_importer_logs)
	add_tool_menu_item("Debug Anim", self.anim_import)
	#add_tool_menu_item("Queue Test...", self.queue_test)
	#add_tool_menu_item("Print scene nodes with owner...", self.anim_import) # self.recursive_print_scene)


func _exit_tree():
	print("run exit tree")
	remove_tool_menu_item("Print scene nodes with owner...")
	remove_tool_menu_item("Reimport previous files")
	remove_tool_menu_item("Import Unity Package...")
	remove_tool_menu_item("Show last import logs")
	remove_tool_menu_item("Reimport large unity package...")
	remove_tool_menu_item("Debug Anim")
	#remove_tool_menu_item("Queue Test...")
