# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

const package_file: GDScript = preload("./package_file.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const import_worker_class: GDScript = preload("./import_worker.gd")
const meta_worker_class: GDScript = preload("./meta_worker.gd")
const asset_adapter_class: GDScript = preload("./asset_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
const object_adapter_class: GDScript = preload("./object_adapter.gd")
const asset_meta_class: GDScript = preload("./asset_meta.gd")

# Set THREAD_COUNT to 0 to run single-threaded.
const THREAD_COUNT = 10
const DISABLE_TEXTURES = false

const STATE_DIALOG_SHOWING = 0
const STATE_PREPROCESSING = 1
const STATE_TEXTURES = 2
const STATE_IMPORTING_MATERIALS_AND_ASSETS = 3
const STATE_IMPORTING_MODELS = 4
const STATE_IMPORTING_YAML_POST_MODEL = 5
const STATE_IMPORTING_PREFABS = 6
const STATE_IMPORTING_SCENES = 7
const STATE_DONE_IMPORT = 8

var import_worker = import_worker_class.new()
var import_worker2 = import_worker_class.new()
var meta_worker = meta_worker_class.new()
var asset_adapter = asset_adapter_class.new()
var object_adapter = object_adapter_class.new()

var editor_plugin: EditorPlugin = null
var main_dialog: AcceptDialog = null
var file_dialog: EditorFileDialog = null
var main_dialog_tree: Tree = null
var hide_button: Button
var pause_button: Button
var abort_button: Button

var base_control: Control
var spinner_icon: AnimatedTexture = null
var spinner_icon1: Texture = null
var fail_icon: Texture = null
var log_icon: Texture = null
var error_icon: Texture = null
var warning_icon: Texture = null
var status_error_icon: Texture = null
var status_warning_icon: Texture = null
var status_success_icon: Texture = null
var folder_icon: Texture = null
var file_icon: Texture = null
var class_icons: Dictionary # String -> Texture2D

var checkbox_off_unicode: String = "\u2610"
var checkbox_on_unicode: String = "\u2611"

var tmpdir: String = ""
var asset_database: asset_database_class = null
var current_selected_package: String
var tree_dialog_state: int = 0
var path_to_tree_item: Dictionary
var guid_to_dependency_guids: Dictionary
var dependency_guids_to_guid: Dictionary
var ignore_dependencies: Dictionary

var _currently_preprocessing_assets: int = 0
var _preprocessing_second_pass: Array = []
var retry_tex: bool = false
var _keep_open_on_import: bool = false
var paused: bool = false
var auto_import: bool = false
var _meta_work_count: int = 0

var auto_hide_checkbox: CheckBox
var dont_auto_select_dependencies_checkbox: CheckBox
var save_text_resources: CheckBox
var save_text_scenes: CheckBox
var skip_reimport_models_checkbox: CheckBox = null
var set_animation_trees_active_checkbox: CheckBox
var enable_unidot_keys_checkbox: CheckBox
var add_unsupported_components_checkbox: CheckBox
var debug_disable_silhouette_fix_checkbox: CheckBox
var force_humanoid_checkbox: CheckBox
var enable_verbose_log_checkbox: CheckBox
var enable_vrm_spring_bones_checkbox: CheckBox
var convert_fbx_to_gltf_checkbox: CheckBox

var batch_import_list_widget: ItemList
var batch_import_add_button: Button

var batch_import_file_list: PackedStringArray
var batch_import_types: Dictionary

var progress_bar : ProgressBar
var status_bar : Label
var options_vbox : VBoxContainer
var show_advanced_options: CheckButton
var advanced_options_container: Container
var advanced_options_hbox : HBoxContainer
var advanced_options_vbox : VBoxContainer
var import_finished: bool = false
var written_additional_textures: bool = false
var global_logs_tree_item: TreeItem
var global_logs_last_count: int = 0
var select_by_type_tree_item: TreeItem
var select_by_type_items: Dictionary # String -> TreeItem

var asset_work_written_last_stage: int = 0
var asset_work_waiting_write: Array = [].duplicate()
var asset_work_waiting_scan: Array = [].duplicate()
var asset_work_currently_importing: Array = [].duplicate()
var asset_work_completed: Array = [].duplicate()

var asset_all: Array = [].duplicate()
var asset_textures: Array = [].duplicate()
var asset_materials_and_other: Array = [].duplicate()
var asset_models: Array = [].duplicate()
var asset_yaml_post_model: Array = [].duplicate()
var asset_prefabs: Array = [].duplicate()
var asset_scenes: Array = [].duplicate()

var builtin_ufbx_supported: bool = ClassDB.class_exists(&"FBXDocument") and ClassDB.class_exists(&"FBXState")

var result_log_lineedit: TextEdit 

var new_editor_plugin := EditorPlugin.new()
var pkg: Object = null  # Type package_file, set in _selected_package

func _resource_reimported(resources: PackedStringArray):
	if import_finished or tree_dialog_state == STATE_DIALOG_SHOWING or tree_dialog_state == STATE_DONE_IMPORT:
		return
	asset_database.log_debug([null, 0, "", 0], "RESOURCES REIMPORTED ============")
	for res in resources:
		asset_database.log_debug([null, 0, "", 0], res)
	asset_database.log_debug([null, 0, "", 0], "=================================")


func _resource_reloaded(resources: PackedStringArray):
	if import_finished or tree_dialog_state == STATE_DIALOG_SHOWING or tree_dialog_state == STATE_DONE_IMPORT:
		return
	asset_database.log_debug([null, 0, "", 0], "Got a RESOURCES RELOADED ============")
	for res in resources:
		asset_database.log_debug([null, 0, "", 0], res)
	asset_database.log_debug([null, 0, "", 0], "=====================================")


func _init():
	meta_worker.asset_processing_finished.connect(self._meta_completed, CONNECT_DEFERRED)
	import_worker.asset_processing_finished.connect(self._asset_processing_finished, CONNECT_DEFERRED)
	import_worker.asset_processing_started.connect(self._asset_processing_started, CONNECT_DEFERRED)
	import_worker2.stage2 = true
	import_worker2.asset_processing_finished.connect(self._asset_processing_stage2_finished, CONNECT_DEFERRED)
	tmpdir = asset_adapter.create_temp_dir()
	var editor_filesystem: EditorFileSystem = new_editor_plugin.get_editor_interface().get_resource_filesystem()
	editor_filesystem.resources_reimported.connect(self._resource_reimported)
	editor_filesystem.resources_reload.connect(self._resource_reloaded)



func _set_indeterminate_up_recursively(ti: TreeItem, is_checked: bool):
	if ti == null:
		return
	var is_all_checked: bool = true
	var is_all_unchecked: bool = true
	for sib in ti.get_children():
		if sib.is_checked(0) or sib.is_indeterminate(0):
			is_all_unchecked = false
		if not sib.is_checked(0) or sib.is_indeterminate(0):
			is_all_checked = false
	if is_all_checked:
		if ti.is_indeterminate(0) or not ti.is_checked(0):
			ti.set_indeterminate(0, false)
			ti.set_checked(0, true)
			_set_indeterminate_up_recursively(ti.get_parent(), is_checked)
			if ti == select_by_type_items.get(ti.get_text(0)):
				batch_import_types[ti.get_text(0)] = true
	elif is_all_unchecked:
		if ti.is_indeterminate(0) or ti.is_checked(0):
			ti.set_indeterminate(0, false)
			ti.set_checked(0, false)
			_set_indeterminate_up_recursively(ti.get_parent(), is_checked)
			if ti == select_by_type_items.get(ti.get_text(0)):
				batch_import_types[ti.get_text(0)] = false
	else:
		if not ti.is_indeterminate(0):
			ti.set_checked(0, false)
			ti.set_indeterminate(0, true)
			ti.set_checked(0, false)
			_set_indeterminate_up_recursively(ti.get_parent(), is_checked)
			if ti == select_by_type_items.get(ti.get_text(0)):
				batch_import_types[ti.get_text(0)] = false


func _check_recursively(ti: TreeItem, is_checked: bool, process_dependencies: bool, visited_set: Dictionary={}, is_recursive_file: bool=false) -> void:
	if visited_set.is_empty():
		visited_set = {}
	if visited_set.has(ti):
		return 
	visited_set[ti] = true
	if ti == select_by_type_items.get(ti.get_text(0)):
		batch_import_types[ti.get_text(0)] = is_checked
	var other_item: TreeItem = ti.get_metadata(1) as TreeItem
	if other_item != null:
		_check_recursively(other_item, is_checked, false, visited_set, false)
		#other_item.set_checked(0, is_checked)
		#_set_indeterminate_up_recursively(other_item, is_checked)

	if ti.is_selectable(0):
		ti.set_indeterminate(0, false)
		ti.set_checked(0, is_checked)
	#var old_prefix: String = (checkbox_on_unicode if !is_checked else checkbox_off_unicode)
	#var new_prefix: String  = (checkbox_on_unicode if is_checked else checkbox_off_unicode)
	#ti.set_text(0, new_prefix + ti.get_text(0).substr(len(old_prefix)))
	for chld in ti.get_children():
		_check_recursively(chld, is_checked, process_dependencies, visited_set, true)

	if ti.is_selectable(0):
		ti.set_indeterminate(0, false)
		ti.set_checked(0, is_checked)
	if not is_recursive_file:
		var par := ti.get_parent()
		_set_indeterminate_up_recursively(par, is_checked)
	if process_dependencies and ti.get_child_count() == 0:
		var path: String = ti.get_tooltip_text(0)
		var asset = pkg.path_to_pkgasset.get(path)
		if not asset:
			return
		var dep_guids: Dictionary
		if is_checked:
			dep_guids = guid_to_dependency_guids.get(asset.guid, {})
		elif not ignore_dependencies.has(asset.guid):
			# When unchecking an asset, we must 
			dep_guids = dependency_guids_to_guid.get(asset.guid, {})
		for guid in dep_guids:
			if ignore_dependencies.has(guid):
				continue
			var dep_asset = pkg.guid_to_pkgasset.get(guid)
			if not dep_asset:
				continue
			var child = path_to_tree_item.get(dep_asset.orig_pathname)
			if not child:
				continue
			_check_recursively(child, is_checked, process_dependencies, visited_set)


func update_progress_bar(amt: int):
	progress_bar.value += amt

func update_global_logs():
	if len(asset_database.log_message_holder.all_logs) == global_logs_last_count:
		return
	global_logs_last_count = len(asset_database.log_message_holder.all_logs)
	var filtered_msgs: PackedStringArray
	var col: int = -1
	if global_logs_tree_item.is_checked(2):
		col = 2
		filtered_msgs = asset_database.log_message_holder.all_logs
	elif global_logs_tree_item.is_checked(3):
		col = 3
		filtered_msgs = asset_database.log_message_holder.all_logs
	elif global_logs_tree_item.is_checked(4):
		col = 4
		filtered_msgs = asset_database.log_message_holder.fails
	if col > 0:
		var data: Variant = global_logs_tree_item.get_metadata(col)
		var current_scroll: int = 0
		if typeof(data) == TYPE_PACKED_STRING_ARRAY:
			current_scroll = unmerge_log_lines(data as PackedStringArray, current_scroll)
		current_scroll = merge_log_lines(filtered_msgs, current_scroll)
		global_logs_tree_item.set_metadata(col, filtered_msgs)
		result_log_lineedit.text = '\n'.join(visible_log_lines)
		result_log_lineedit.scroll_vertical = current_scroll


func update_all_logs():
	var root_ti: TreeItem = main_dialog_tree.get_root()
	var current_scroll = result_log_lineedit.scroll_vertical
	var child_list: Array[TreeItem]
	_get_children_recursive(child_list, root_ti)
	visible_log_lines.resize(0)
	var filtered_msgs: PackedStringArray
	for child_ti in child_list:
		for sub_col in range(2, 5):
			child_ti.set_metadata(sub_col, null)
	for child_ti in child_list:
		if child_ti.get_parent() == null:
			continue
		for sub_col in range(2, 5):
			if child_ti.is_checked(sub_col):
				if not child_ti.get_parent().is_checked(sub_col):
					log_column_checked(child_ti, sub_col, true, false)
				break
	result_log_lineedit.text = '\n'.join(visible_log_lines)
	result_log_lineedit.scroll_vertical = current_scroll
	result_log_lineedit.visible = true

class ErrorSyntaxHighlighter extends SyntaxHighlighter:
	var fail_highlight: Dictionary
	var warn_highlight: Dictionary
	var default_highlight: Dictionary
	var inited: bool = false
	var pid: Object

	const ERROR_COLOR_TAG := "FAIL: "
	const WARNING_COLOR_TAG := "warn: "

	func _init(package_import_dialog_val: Object):
		pid = package_import_dialog_val

	func _get_line_syntax_highlighting(line: int):
		if line >= len(pid.visible_log_lines) or line < 0:
			return {}
		var linestr: String = pid.visible_log_lines[line]
		if not inited:
			var error_color : Color = get_text_edit().get_theme_color(&"error_color", &"Editor")
			var warning_color : Color = get_text_edit().get_theme_color(&"warning_color", &"Editor")
			fail_highlight = {0: {"size": 1, "color": Color.DIM_GRAY}, 8: {"color": error_color}}
			warn_highlight = {0: {"size": 1, "color": Color.DIM_GRAY}, 8: {"color": warning_color}}
			default_highlight = {0: {"size": 1, "color": Color.DIM_GRAY}, 8: {}}
			inited = true
		var off1: int = linestr.find(":")
		var beg: String = linestr.substr(0, linestr.find(":", off1 + 1) + 2)
		var ret: Dictionary = default_highlight
		if beg.contains(ERROR_COLOR_TAG):
			ret = fail_highlight
		if beg.contains(WARNING_COLOR_TAG):
			ret = warn_highlight
		ret = ret.duplicate()
		ret[off1] = ret[8]
		ret[8] = {"color": Color.MEDIUM_PURPLE}
		return ret

var visible_log_lines: PackedStringArray = []
var tmp_log_lines: PackedStringArray = []

func merge_log_lines(lines_to_add: PackedStringArray, current_scroll: float) -> float:
	var is_end: bool = result_log_lineedit.get_last_full_visible_line() >= len(visible_log_lines) - 1
	#len(visible_log_lines) - current_scroll < result_log_lineedit.get_last_full_visible_line()
	if lines_to_add.is_empty():
		return current_scroll
	var idx1: int = len(visible_log_lines) - 1
	visible_log_lines.resize(len(visible_log_lines) + len(lines_to_add))
	var idx_out: int = len(visible_log_lines) - 1
	for idx2 in range(len(lines_to_add) - 1, -1, -1):
		while idx1 >= 0 and visible_log_lines[idx1] > lines_to_add[idx2]:
			visible_log_lines[idx_out] = visible_log_lines[idx1]
			if idx1 == current_scroll:
				current_scroll = idx_out
			idx1 -= 1
			idx_out -= 1
		visible_log_lines[idx_out] = lines_to_add[idx2]
		idx2 -= 1
		idx_out -= 1
	while idx1 >= 0:
		visible_log_lines[idx_out] = visible_log_lines[idx1]
		if idx1 == current_scroll:
			current_scroll = idx_out
		idx1 -= 1
		idx_out -= 1
	if is_end:
		return len(visible_log_lines) - result_log_lineedit.get_parent_area_size().y / result_log_lineedit.get_line_height() + 1
	return current_scroll

func unmerge_log_lines(lines_to_remove: PackedStringArray, current_scroll: float) -> float:
	if lines_to_remove.is_empty():
		return current_scroll
	var idx1: int = 0
	var idx_out: int = 0
	for line in lines_to_remove:
		#print("Remove " + str(line))
		while idx1 < len(visible_log_lines) and visible_log_lines[idx1] < line:
			#print("loop " + str(idx1) + " " + str(idx_out) + " " + str(len(visible_log_lines)) + " " + str(visible_log_lines[idx1]))
			visible_log_lines[idx_out] = visible_log_lines[idx1]
			if idx1 == current_scroll:
				current_scroll = idx_out
			idx1 += 1
			idx_out += 1
		if idx1 < len(visible_log_lines) and visible_log_lines[idx1] == line:
			#print("Do " + str(visible_log_lines[idx1]))
			if idx1 == current_scroll:
				current_scroll = idx_out
			idx1 += 1
	#print(str(idx_out)  + "," + str(idx1))
	while idx1 < len(visible_log_lines):
		#print("loop2 " + str(idx1) + " " + str(idx_out) + " " + str(len(visible_log_lines)) + " " + str(visible_log_lines[idx1]))
		visible_log_lines[idx_out] = visible_log_lines[idx1]
		if idx1 == current_scroll:
			current_scroll = idx_out
		idx1 += 1
		idx_out += 1
	#assert(idx_out == len(visible_log_lines) - len(lines_to_remove))
	visible_log_lines.resize(idx_out)
	return current_scroll


func _get_children_recursive(child_list: Array[TreeItem], cur: TreeItem):
	child_list.append(cur)
	for i in range(cur.get_child_count()):
		_get_children_recursive(child_list, cur.get_child(i))

func _cell_selected() -> void:
	var ti: TreeItem = main_dialog_tree.get_selected()
	if not ti:
		return
	var col: int = main_dialog_tree.get_selected_column()
	ti.deselect(col)
	if (col == 0 or col == 1) and ti.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK:
		if ti != null:  # and col == 1:
			var new_checked: bool = !ti.is_indeterminate(0) and !ti.is_checked(0)
			var process_dependencies: bool = false
			if new_checked and not dont_auto_select_dependencies_checkbox.button_pressed:
				process_dependencies = true
			if not new_checked and not dont_auto_select_dependencies_checkbox.button_pressed:
				process_dependencies = true
			if Input.is_key_pressed(KEY_SHIFT):
				process_dependencies = not process_dependencies
			_check_recursively(ti, new_checked, process_dependencies)
	elif col >= 2:
		ti.set_checked(col, not ti.is_checked(col))
		log_column_checked(ti, col, ti.is_checked(col))

func log_column_checked(ti: TreeItem, col: int, is_checked: bool, update_textbox: bool=true):
	if col >= 2:
		var current_scroll = result_log_lineedit.scroll_vertical
		var child_list: Array[TreeItem]
		_get_children_recursive(child_list, ti)
		if ti.is_checked(col):
			var filtered_msgs: PackedStringArray
			var data_to_unmerge: PackedStringArray
			for child_ti in child_list:
				for sub_col in range(2, 5):
					if ti != child_ti or sub_col > col:
						var data: Variant = child_ti.get_metadata(sub_col)
						if typeof(data) == TYPE_PACKED_STRING_ARRAY:
							data_to_unmerge.append_array(data as PackedStringArray)
						child_ti.set_metadata(sub_col, PackedStringArray())
						if sub_col >= col:
							child_ti.set_checked(sub_col, true)
						child_ti.set_selectable(sub_col, false)
			if not data_to_unmerge.is_empty():
				current_scroll = unmerge_log_lines(data_to_unmerge, current_scroll)

			var needs_sort: bool
			for child_ti in child_list:
				var metadat: Object = child_ti.get_metadata(1)
				if metadat is TreeItem:
					continue
				var tw: package_file.PkgAsset = metadat
				var start_idx = len(filtered_msgs)
				if tw != null:
					if not filtered_msgs.is_empty():
						needs_sort = true
					if col == 2:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.all_logs)
					elif col == 3:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.warnings_fails)
					elif col == 4:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.fails)
			if ti == global_logs_tree_item:
				if not filtered_msgs.is_empty():
					needs_sort = true
				if col == 2:
					filtered_msgs.append_array(asset_database.log_message_holder.all_logs)
				elif col == 3:
					filtered_msgs.append_array(asset_database.log_message_holder.all_logs)
				elif col == 4:
					filtered_msgs.append_array(asset_database.log_message_holder.fails)
			if needs_sort:
				filtered_msgs.sort()
			ti.set_metadata(col, filtered_msgs)
			current_scroll = merge_log_lines(filtered_msgs, current_scroll)
		elif not ti.is_checked(col):
			var data: Variant = ti.get_metadata(col)
			ti.set_metadata(col, PackedStringArray())
			if typeof(data) == TYPE_PACKED_STRING_ARRAY:
				current_scroll = unmerge_log_lines(data as PackedStringArray, current_scroll)
			for child_ti in child_list:
				for sub_col in range(2, 5):
					if ti != child_ti or sub_col > col:
						child_ti.set_checked(sub_col, false)
						child_ti.set_selectable(sub_col, true)
		#print("Updating text " + str(ti.is_checked(col)))
		#print(len(visible_log_lines))
		if update_textbox:
			result_log_lineedit.text = '\n'.join(visible_log_lines)
			result_log_lineedit.scroll_vertical = current_scroll
			result_log_lineedit.visible = true # not visible_log_lines.is_empty()

const HUMAN_READABLE_NAMES: Dictionary = {
	5866666021909216657: "Animator",
	-8679921383154817045: "Transform",
	919132149155446097: "GameObject",
	1091099324641564166: "PrefabInstance",
	2357318004158062694: "PrefabInstance",
}

func human_readable_fileid_heuristic(fileID: int) -> String:
	if fileID == 0:
		return ""
	if fileID > 0 and (fileID / 1000) % 100 == 0 and (fileID / 100000) < 1002:
		var classID: int = fileID / 100000
		return object_adapter.utype_to_classname[classID]
	if HUMAN_READABLE_NAMES.has(fileID):
		return HUMAN_READABLE_NAMES[fileID]
	return str(fileID)

func _meta_completed(tw: Object):
	_meta_work_count -= 1
	var pkgasset = tw.asset
	var ti = tw.extra as TreeItem
	var importer_type: String = ""
	if pkgasset.parsed_meta != null:
		importer_type = pkgasset.parsed_meta.importer_type.replace("Importer", "")
		if importer_type == "NativeFormat":
			importer_type = "[" + tw.asset_main_object_type + "]"
			if pkgasset.parsed_meta.main_object_id != 0 and pkgasset.parsed_meta.main_object_id % 100000 == 0:
				var clsid: int = pkgasset.parsed_meta.main_object_id / 100000
				if object_adapter.utype_to_classname.has(clsid):
					importer_type = "[" + object_adapter.utype_to_classname[clsid] + "]"
		var dep_guids: Dictionary = pkgasset.parsed_meta.meta_dependency_guids.duplicate()
		if importer_type == "[LightingDataAsset]":
			if batch_import_types.get(".asset LightingDataAsset", false) == false:
				ignore_dependencies[pkgasset.guid] = true
				_check_recursively(ti, false, false)
		if importer_type == "[MonoScript]" or importer_type == "Mono" or importer_type == "":
			if batch_import_types.get(".cs Script", false) == false:
				ignore_dependencies[pkgasset.guid] = true
				_check_recursively(ti, false, false)
		if importer_type == "[Shader]" or importer_type == "Shader":
			if batch_import_types.get(".shader Shader", false) == false:
				ignore_dependencies[pkgasset.guid] = true
				_check_recursively(ti, false, false)
		for guid in pkgasset.parsed_meta.dependency_guids:
			dep_guids[guid] = pkgasset.parsed_meta.dependency_guids[guid]
		var da := DirAccess.open("res://")
		for guid in dep_guids:
			var guid_meta = asset_database.get_meta_by_guid(guid)
			if guid_meta != null and da.file_exists(guid_meta.path):
				# No need to force selection
				continue
			if guid_meta == null and not pkg.guid_to_pkgasset.has(guid):
				push_error("Asset " + pkgasset.parsed_meta.path + " depends on missing GUID " + guid + " fileID " + human_readable_fileid_heuristic(dep_guids[guid]))
			if not guid_to_dependency_guids.has(pkgasset.guid):
				guid_to_dependency_guids[pkgasset.guid] = {}
			guid_to_dependency_guids[pkgasset.guid][guid] = dep_guids[guid]
			if not dependency_guids_to_guid.has(guid):
				dependency_guids_to_guid[guid] = {}
			dependency_guids_to_guid[guid][pkgasset.guid] = dep_guids[guid]
	ti.set_text(1, "Scene" if pkgasset.orig_pathname.to_lower().ends_with(".scene") else importer_type)
	var cls: String
	if importer_type.begins_with("["):
		cls = importer_type.substr(1, len(importer_type) - 2)
		var tmp_instance = object_adapter.instantiate_unidot_object(pkgasset.parsed_meta, 0, 0, cls)
		cls = tmp_instance.get_godot_type()
	else:
		var tmp_importer = null
		if pkgasset.parsed_meta != null:
			tmp_importer = pkgasset.parsed_meta.importer
		if tmp_importer == null:
			tmp_importer = object_adapter.instantiate_unidot_object(pkgasset.parsed_meta, 0, 0, importer_type + "Importer")
		var main_object_id: int = tmp_importer.get_main_object_id()
		if main_object_id == 1 or main_object_id == 100100000:
			cls = "PackedScene"
		else:
			var utype: int = main_object_id / 100000
			var tmp_instance = object_adapter.instantiate_unidot_object_from_utype(pkgasset.parsed_meta, 0, utype)
			cls = tmp_instance.get_godot_type()
	var tooltip_cls: String = cls
	if cls.begins_with("AnimationNode"):
		cls = "AnimatedTexture"
	if cls == "Texture2D":
		cls = "ImageTexture"
	if cls == "BoneMap":
		cls = "BoneAttachment3D"
	if not class_icons.has(cls):
		class_icons[cls] = base_control.get_theme_icon(cls, "EditorIcons")
	var icon: Texture2D = class_icons[cls]
	if icon == null:
		icon = file_icon
	if ti.get_icon(0) == null or ti.get_icon(0) == file_icon:
		ti.set_icon(0, icon)
	ti.set_icon(1, icon)
	ti.set_tooltip_text(1, tooltip_cls)

	var color = Color(0.3 + 0.4 * fmod(importer_type.unicode_at(0) * 173.0 / 255.0, 1.0), 0.3 + 0.4 * fmod(importer_type.unicode_at(1) * 139.0 / 255.0, 1.0), 0.7 * fmod(importer_type.unicode_at(2) * 157.0 / 255.0, 1.0), 1.0)
	ti.set_custom_color(1, color)

	var obj_type: String = tw.asset_main_object_type
	if pkgasset.orig_pathname.to_lower().ends_with(".scene"):
		obj_type = "Scene"
	elif importer_type == "Model":
		obj_type = "Model"
	elif importer_type == "Prefab":
		obj_type = "Prefab"
	elif pkgasset.parsed_meta.main_object_id != 0 and pkgasset.parsed_meta.main_object_id % 100000 == 0:
		var clsid: int = pkgasset.parsed_meta.main_object_id / 100000
		if object_adapter.utype_to_classname.has(clsid):
			obj_type = object_adapter.utype_to_classname[clsid]
	if pkgasset.orig_pathname.to_lower().ends_with(".cs"):
		obj_type = "Script"
	if pkgasset.orig_pathname.to_lower().ends_with(".shader"):
		obj_type = "Shader"
	var select_by_type_item: TreeItem
	var type_parent: TreeItem
	var obj_type_desc = "." + pkgasset.orig_pathname.get_extension() + " " + obj_type
	if auto_import:
		if batch_import_types.get(obj_type_desc, true) == false:
			ignore_dependencies[pkgasset.guid] = true
			_check_recursively(ti, false, false)
	if pkgasset.orig_pathname.to_lower().ends_with(".dll") or pkgasset.orig_pathname.to_lower().ends_with(".dylib") or pkgasset.orig_pathname.to_lower().ends_with(".so"):
		ignore_dependencies[pkgasset.guid] = true
		_check_recursively(ti, false, false)

	if select_by_type_items.has(obj_type_desc):
		type_parent = select_by_type_items[obj_type_desc]
		if type_parent.is_checked(0) and not ti.is_checked(0):
			type_parent.set_indeterminate(0, true)
			batch_import_types[obj_type_desc] = true
		if not type_parent.is_checked(0) and ti.is_checked(0):
			type_parent.set_indeterminate(0, true)
			batch_import_types[obj_type_desc] = true
	else:
		var insert_idx: int = 0
		for chld in select_by_type_tree_item.get_children():
			if chld.get_text(0).casecmp_to(obj_type_desc) > 0:
				break
			insert_idx += 1
		type_parent = select_by_type_tree_item.create_child(insert_idx)
		type_parent.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		type_parent.set_icon(0, icon)
		# We have the type in column 0, so copy it here.
		type_parent.set_custom_color(0, ti.get_custom_color(1))
		type_parent.set_text(0, obj_type_desc)
		type_parent.set_collapsed_recursive(true)
		type_parent.set_checked(0, ti.is_checked(0))
		select_by_type_items[obj_type_desc] = type_parent
		batch_import_types[obj_type_desc] = ti.is_checked(0)
	select_by_type_item = type_parent.create_child()
	select_by_type_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	select_by_type_item.set_checked(0, ti.is_checked(0))
	select_by_type_item.set_text(0, ti.get_text(0))
	select_by_type_item.set_icon(0, ti.get_icon(0))
	select_by_type_item.set_tooltip_text(0, ti.get_tooltip_text(0))
	select_by_type_item.set_cell_mode(1, TreeItem.CELL_MODE_STRING)
	select_by_type_item.set_text(1, ti.get_text(1))
	select_by_type_item.set_icon(1, ti.get_icon(1))
	select_by_type_item.set_custom_color(1, ti.get_custom_color(1))
	select_by_type_item.set_tooltip_text(1, ti.get_tooltip_text(1))
	select_by_type_item.set_metadata(1, ti)
	ti.set_metadata(1, select_by_type_item)

	if _meta_work_count <= 0:
		if auto_import:
			if preprocess_timer != null:
				preprocess_timer.queue_free()
			preprocess_timer = Timer.new()
			preprocess_timer.wait_time = 0.1
			preprocess_timer.autostart = true
			preprocess_timer.process_callback = Timer.TIMER_PROCESS_IDLE
			new_editor_plugin.get_editor_interface().get_base_control().add_child(preprocess_timer, true)
			preprocess_timer.timeout.connect(self._auto_import_tick)

var auto_clean_tick_count = 10

func _auto_import_tick():
	if new_editor_plugin.get_editor_interface().get_resource_filesystem().is_scanning():
		auto_clean_tick_count = 10
	else:
		# Reduce chance of race condition with editor scanning / import
		auto_clean_tick_count -= 1
		if auto_clean_tick_count < 0:
			preprocess_timer.timeout.disconnect(self._auto_import_tick)
			preprocess_timer.queue_free()
			preprocess_timer = null
			_asset_tree_window_confirmed()


func _prune_unselected_items(p_ti: TreeItem) -> bool:
	# Directories might be unchecked but have children which are checked.
	var children = p_ti.get_children()
	children.reverse() # probably faster to remove from end.
	var was_directory = not children.is_empty() or p_ti.get_text(1) == "Directory"

	for child_ti in children:
		if not _prune_unselected_items(child_ti):
			p_ti.remove_child(child_ti)

	if not p_ti.is_checked(0) and p_ti.get_child_count() == 0:
		var path = p_ti.get_tooltip_text(0)  # HACK! No data field in TreeItem?? Let's use the tooltip?!
		var asset = pkg.path_to_pkgasset.get(path)
		if asset != null:
			# After the user has made their selection, it is important that we treat all unselected files
			# as if they do not exist. Some operations such as roughness texture generation (stage2)
			# use this dictionary to find not-yet-imported smoothness textures
			pkg.path_to_pkgasset.erase(path)
			pkg.guid_to_pkgasset.erase(asset.guid)
		return false
	# Check if column 1 (type) is "Directory". is there a cleaner way to do this?
	if was_directory and p_ti.get_child_count() == 0:
		return false

	var path = p_ti.get_tooltip_text(0)  # HACK! No data field in TreeItem?? Let's use the tooltip?!
	var asset = pkg.path_to_pkgasset.get(path)
	# Has children or it is checked.
	var tooltip = p_ti.get_tooltip_text(0)
	var text = p_ti.get_text(0)
	#p_ti.add_button(1, log_icon, 1, false, "View Log")
	p_ti.set_cell_mode(0, TreeItem.CELL_MODE_STRING)
	p_ti.set_checked(0, false)
	p_ti.set_selectable(0, false)
	if len(text.get_basename()) > 25:
		text = text.get_basename().substr(0, 30) + "..." + text.get_extension()
	p_ti.set_text(0, text)
	p_ti.set_tooltip_text(0, tooltip)
	if asset:
		p_ti.set_icon(0, spinner_icon)
	else:
		p_ti.set_icon(0, folder_icon)
	#p_ti.set_expand_right(0, true)
	if asset_database.enable_verbose_logs:
		p_ti.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)
		p_ti.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		p_ti.set_text(2, "Logs")
		p_ti.set_selectable(2, true)
		p_ti.set_icon(2, log_icon)
	return true


func _selected_package(p_path: String) -> void:
	current_selected_package = p_path
	main_dialog.title = "Select Assets to import from " + current_selected_package.get_file()
	print(editor_plugin)
	if editor_plugin != null and file_dialog != null:
		editor_plugin.last_selected_dir = file_dialog.current_dir
		editor_plugin.file_dialog_mode = file_dialog.display_mode
		print("CURRENT DIR " + file_dialog.current_dir)
	if p_path.to_lower().contains("technologies"):
		OS.alert("Beware that this package may use a non-standard license.\nPlease take the time to double-check that you are\nin compliance with all licenses.")
	_preprocessing_second_pass = [].duplicate()
	asset_work_waiting_write = [].duplicate()
	asset_work_waiting_scan = [].duplicate()
	asset_work_currently_importing = [].duplicate()
	asset_all = [].duplicate()
	asset_textures = [].duplicate()
	asset_materials_and_other = [].duplicate()
	asset_models = [].duplicate()
	asset_yaml_post_model = [].duplicate()
	asset_prefabs = [].duplicate()
	asset_scenes = [].duplicate()
	asset_database = asset_database_class.new().get_singleton()
	print("Got here " + str(p_path))
	if p_path.is_empty():
		pkg = package_file.new().external_tar_with_filename("")
	elif p_path.to_lower().ends_with(".unitypackage"):
		pkg = package_file.new().init_with_filename(p_path)
	elif p_path.to_lower().ends_with("/asset.meta"):
		pkg = package_file.new().external_tar_with_filename("", p_path.get_base_dir().get_base_dir())
	elif p_path.to_lower().ends_with(".meta"):
		pkg = package_file.new().init_with_asset_dir(p_path.get_base_dir())
	elif DirAccess.dir_exists_absolute(p_path):
		print("It's a dir!! " + str(p_path))
		pkg = package_file.new().init_with_asset_dir(p_path)
	#pkg.parse_all_meta(asset_database)
	meta_worker.asset_database = asset_database
	asset_database.clear_logs()
	asset_database.in_package_import = true
	asset_database.log_debug([null, 0, "", 0], "Asset database object returned " + str(asset_database))

	dont_auto_select_dependencies_checkbox = _add_checkbox_option("Hold shift to select dependencies", false if asset_database.auto_select_dependencies else true)
	dont_auto_select_dependencies_checkbox.toggled.connect(self._dont_auto_select_dependencies_checkbox_changed)
	save_text_resources = _add_advanced_checkbox_option("Save resources as text .tres (slow)", true if asset_database.use_text_resources else false)
	save_text_resources.toggled.connect(self._save_text_resources_changed)
	save_text_scenes = _add_advanced_checkbox_option("Save scenes as text .tscn (slow)", true if asset_database.use_text_scenes else false)
	save_text_scenes.toggled.connect(self._save_text_scenes_changed)
	skip_reimport_models_checkbox = _add_advanced_checkbox_option("Skip already-imported fbx files", true if asset_database.skip_reimport_models else false)
	skip_reimport_models_checkbox.toggled.connect(self._skip_reimport_models_checkbox_changed)
	set_animation_trees_active_checkbox = _add_checkbox_option("Import active AnimationTrees (animate in editor)", true if asset_database.set_animation_trees_active else false)
	set_animation_trees_active_checkbox.toggled.connect(self._set_animation_trees_active_changed)
	enable_unidot_keys_checkbox = _add_advanced_checkbox_option("Save yaml data in metadata/unidot_keys", true if asset_database.enable_unidot_keys else false)
	enable_unidot_keys_checkbox.toggled.connect(self._enable_unidot_keys_changed)
	add_unsupported_components_checkbox = _add_advanced_checkbox_option("Add empty MonoBehaviour/unsupported nodes", true if asset_database.add_unsupported_components else false)
	add_unsupported_components_checkbox.toggled.connect(self._add_unsupported_components_changed)
	debug_disable_silhouette_fix_checkbox = _add_advanced_checkbox_option("Disable silhouette fix (DEBUG)", true if asset_database.debug_disable_silhouette_fix else false)
	debug_disable_silhouette_fix_checkbox.toggled.connect(self._debug_disable_silhouette_fix_changed)
	enable_verbose_log_checkbox = _add_advanced_checkbox_option("Enable verbose logs", true if asset_database.enable_verbose_logs else false)
	enable_verbose_log_checkbox.toggled.connect(self._enable_verbose_log_changed)
	enable_vrm_spring_bones_checkbox = _add_checkbox_option("Convert dynamic bones to VRM springbone", true if asset_database.vrm_spring_bones else false)
	enable_vrm_spring_bones_checkbox.toggled.connect(self._enable_vrm_spring_bones_changed)
	force_humanoid_checkbox = _add_checkbox_option("Import ALL scenes as humanoid retargeted skeletons", true if asset_database.force_humanoid else false)
	force_humanoid_checkbox.toggled.connect(self._force_humanoid_changed)
	if builtin_ufbx_supported:
		convert_fbx_to_gltf_checkbox = _add_advanced_checkbox_option("Convert FBX models to glTF", true if asset_database.convert_fbx_to_gltf else false)
		convert_fbx_to_gltf_checkbox.toggled.connect(self._convert_fbx_to_gltf_changed)
	else:
		convert_fbx_to_gltf_checkbox = _add_checkbox_option("Convert FBX models to glTF\n(Update to Godot 4.3 to disable)", true)
		convert_fbx_to_gltf_checkbox.disabled = true

	var vspace := Control.new()
	vspace.custom_minimum_size = Vector2(0, 16)
	vspace.size = Vector2(0, 16)
	options_vbox.add_child(vspace)
	options_vbox.add_child(advanced_options_container)
	options_vbox.add_child(vspace.duplicate())

	batch_import_list_widget = ItemList.new()
	batch_import_list_widget.item_activated.connect(self._batch_import_list_widget_activated)
	options_vbox.add_child(batch_import_list_widget)
	batch_import_add_button = Button.new()
	batch_import_add_button.text = "Add extra packages to batch"
	batch_import_add_button.pressed.connect(self._add_batch_import)
	batch_import_add_button.tooltip_text = """
	Batch import additional .unitypackage archives.
	Double-click a package to remove it from the list.

	The file type checkboxes to the right will determine which files are imported from the batch.
	"""
	options_vbox.add_child(batch_import_add_button)

	meta_worker.start_threads(THREAD_COUNT)  # Don't DISABLE_THREADING
	main_dialog_tree.hide_root = true
	main_dialog_tree.create_item()
	var hidden_root: TreeItem = main_dialog_tree.get_root()

	select_by_type_tree_item = hidden_root.create_child()
	select_by_type_tree_item.set_text(0, "Select by Type")
	select_by_type_tree_item.set_text(1, " ") # We check for " " later to remove the subtree.

	var tree_names = []
	var ti: TreeItem
	#var ti: TreeItem = main_dialog_tree.create_item()
	#ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	#ti.set_text(0, "Assets")
	#ti.set_expand_right(0, true)
	#ti.set_expand_right(1, false)
	#ti.set_checked(0, true)
	#ti.set_icon_max_width(0, 24)
	#ti.set_icon(0, folder_icon)
	#ti.set_text(1, "RootDirectory")
	var tree_items = []
	for path in pkg.paths:
		var pkgasset = pkg.path_to_pkgasset[path]
		var path_names: Array = path.split("/")
		var i: int = len(tree_names) - 1
		while i >= 0 and (i >= len(path_names) or path_names[i] != tree_names[i]):
			#asset_database.log_debug([null,0,"",0], "i=" + str(i) + "/" + str(len(path_names)) + "/" + str(tree_names[i]))
			tree_names.pop_back()
			tree_items.pop_back()
			i -= 1
		#if i < 0:
		#	asset_database.log_fail([null, 0, "", 0], "Path outside of Assets: " + path)
		#	print("Path outside of Assets: " + path)
		#	break
		while i < len(path_names) - 1:
			i += 1
			tree_names.push_back(path_names[i])
			ti = main_dialog_tree.create_item(null if i == 0 or tree_items.is_empty() else tree_items[i - 1])
			tree_items.push_back(ti)
			ti.set_expand_right(0, true)
			ti.set_expand_right(1, false)
			ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			if DISABLE_TEXTURES and (path.to_lower().ends_with("png") or path.to_lower().ends_with("jpg")):
				ti.set_checked(0, false)
				ti.set_selectable(0, false)
			else:
				ti.set_checked(0, true)
				ti.set_selectable(0, true)
			if i == len(path_names) - 1:
				path_to_tree_item[path] = ti
				ti.set_tooltip_text(0, path)
			ti.set_icon_max_width(0, 24)
			#ti.set_custom_color(0, Color.DARK_BLUE)
				# ti.add_button(0, spinner_icon1, -1, true)
			ti.set_text(0, path_names[i])
			var icon: Texture = pkgasset.icon
			if icon != null:
				ti.set_icon(0, icon)
			if i == len(path_names) - 1:
				meta_worker.push_asset(pkgasset, ti)
				_meta_work_count += 1
				ti.set_text(1, "")
			else:
				ti.set_text(1, "Directory")
				ti.set_icon(0, folder_icon)
	main_dialog.popup_centered_ratio()
	check_fbx2gltf()
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null


func _reselect_pruned_items(p_ti: TreeItem):
	for child_ti in p_ti.get_children():
		_reselect_pruned_items(child_ti)
	var text = p_ti.get_text(0)
	p_ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	p_ti.set_checked(0, true)
	p_ti.set_text(0, text)


func do_reimport_previous_files() -> void:
	_currently_preprocessing_assets = 0
	_preprocessing_second_pass.clear()
	retry_tex = false

	asset_work_waiting_write.clear()
	asset_work_waiting_scan.clear()
	asset_work_currently_importing.clear()
	asset_work_completed.clear()

	asset_all.clear()
	asset_textures.clear()
	asset_materials_and_other.clear()
	asset_models.clear()
	asset_yaml_post_model.clear()
	asset_prefabs.clear()
	asset_scenes.clear()

	result_log_lineedit.text = ""
	result_log_lineedit.syntax_highlighter = ErrorSyntaxHighlighter.new(self)

	import_finished = false
	written_additional_textures = false
	tree_dialog_state = STATE_DIALOG_SHOWING
	_reselect_pruned_items(main_dialog_tree.get_root())
	_asset_tree_window_confirmed()
	main_dialog.show()


func show_reimport(ep: EditorPlugin) -> void:
	editor_plugin = ep
	file_dialog = null
	_show_importer_common()
	self._selected_package("")


func show_importer(ep: EditorPlugin) -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.add_filter("*.unitypackage, *.meta", "Asset packages or file")
	file_dialog.show_hidden_files = true
	editor_plugin = ep
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_ANY
	# FILE_MODE_OPEN_FILE = 0  –  The dialog allows selecting one, and only one file.
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.set_title("Import .unitypackage archive, or Select Assets folder...")
	file_dialog.file_selected.connect(self._selected_package)
	file_dialog.dir_selected.connect(self._selected_package)
	ep.get_editor_interface().get_base_control().add_child(file_dialog, true)
	if ep.get("last_selected_dir"):
		file_dialog.current_dir = ep.last_selected_dir
		file_dialog.display_mode = ep.file_dialog_mode
	_show_importer_common()
	check_fbx2gltf()


func check_fbx2gltf():
	if builtin_ufbx_supported:
		return # No need to check for FBX2glTF on engines with native fbx.
	var d = DirAccess.open("res://")
	var addon_path: String = new_editor_plugin.get_editor_interface().get_editor_settings().get_setting("filesystem/import/fbx/fbx2gltf_path")
	if not addon_path.get_file().is_empty():
		print(addon_path)
		if not d.file_exists(addon_path):
			var error_dialog := AcceptDialog.new()
			new_editor_plugin.get_editor_interface().get_base_control().add_child(error_dialog)
			error_dialog.title = "Unidot Importer"
			error_dialog.dialog_text = "FBX2glTF is not configured in Editor settings. This will cause corrupt imports!\nPlease install FBX2glTF in Editor Settings."
			error_dialog.popup_centered()


func show_importer_logs() -> void:
	main_dialog.show()


func _auto_hide_toggled(is_on: bool) -> void:
	_keep_open_on_import = not is_on


func _add_checkbox_option(optname: String, defl: bool, this_options_vbox: VBoxContainer = null) -> CheckBox:
	if this_options_vbox == null:
		this_options_vbox = options_vbox
	var checkbox := CheckBox.new()
	checkbox.text = optname
	checkbox.size_flags_vertical = Control.SIZE_SHRINK_END
	checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkbox.size_flags_stretch_ratio = 0.0
	this_options_vbox.add_child(checkbox)
	checkbox.button_pressed = defl
	return checkbox

func _add_advanced_checkbox_option(optname: String, defl: bool):
	if defl and not show_advanced_options.button_pressed:
		show_advanced_options.button_pressed = true
	return _add_checkbox_option(optname, defl, advanced_options_vbox)


func _save_text_resources_changed(val: bool):
	asset_database.use_text_resources = val


func _save_text_scenes_changed(val: bool):
	asset_database.use_text_scenes = val


func _dont_auto_select_dependencies_checkbox_changed(val: bool):
	asset_database.auto_select_dependencies = not val


func _skip_reimport_models_checkbox_changed(val: bool):
	asset_database.skip_reimport_models = val

func _set_animation_trees_active_changed(val: bool):
	asset_database.set_animation_trees_active = val

func _enable_unidot_keys_changed(val: bool):
	asset_database.enable_unidot_keys = val

func _add_unsupported_components_changed(val: bool):
	asset_database.add_unsupported_components = val

func _debug_disable_silhouette_fix_changed(val: bool):
	asset_database.debug_disable_silhouette_fix = val

func _force_humanoid_changed(val: bool):
	asset_database.force_humanoid = val

func _enable_verbose_log_changed(val: bool):
	asset_database.enable_verbose_logs = val

func _enable_vrm_spring_bones_changed(val: bool):
	asset_database.vrm_spring_bones = val

func _convert_fbx_to_gltf_changed(val: bool):
	asset_database.convert_fbx_to_gltf = val

func _show_advanced_options_toggled(val: bool):
	advanced_options_hbox.visible = val

func _add_batch_import():
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null
	file_dialog = EditorFileDialog.new()
	file_dialog.add_filter("*.unitypackage", "Only asset packages supported")
	file_dialog.show_hidden_files = true
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	# FILE_MODE_OPEN_FILE = 0  –  The dialog allows selecting one, and only one file.
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.set_title("Batch import additional .unitypackage archives...")
	file_dialog.file_selected.connect(self._selected_batch_import_file)
	file_dialog.files_selected.connect(self._selected_batch_import_files)
	new_editor_plugin.get_editor_interface().get_base_control().add_child(file_dialog, true)
	if file_dialog != null:
		if editor_plugin != null:
			file_dialog.current_dir = editor_plugin.last_selected_dir
			file_dialog.display_mode = editor_plugin.file_dialog_mode
		file_dialog.popup_centered_ratio()

func _selected_batch_import_file(path: String):
	_selected_batch_import_files(PackedStringArray([path]))

func _selected_batch_import_files(paths: PackedStringArray):
	if editor_plugin != null and file_dialog != null:
		editor_plugin.last_selected_dir = file_dialog.current_dir
		editor_plugin.file_dialog_mode = file_dialog.display_mode
	var cur_files: Dictionary
	cur_files[current_selected_package] = true
	for path in batch_import_file_list:
		cur_files[path] = true
	for path in paths:
		batch_import_list_widget.custom_minimum_size = Vector2(100, 100)
		if not cur_files.has(path):
			batch_import_list_widget.add_item(path.get_file())
			batch_import_list_widget.set_item_tooltip(batch_import_list_widget.item_count - 1, path)
			batch_import_file_list.append(path)

func _batch_import_list_widget_activated(idx: int):
	batch_import_list_widget.remove_item(idx)
	batch_import_file_list.remove_at(idx)


func _pause_toggled(val: bool):
	paused = val
	if not paused:
		abort_button.visible = false

func _abort_clicked():
	tree_dialog_state = STATE_DONE_IMPORT
	status_bar.text = "Import aborted during [" + status_bar.text + "]"


func _show_importer_common() -> void:
	if editor_plugin != null:
		editor_plugin.package_import_dialog = self
	base_control = new_editor_plugin.get_editor_interface().get_base_control()
	main_dialog = AcceptDialog.new()
	main_dialog.title = "Select Assets to import"
	main_dialog.dialog_hide_on_ok = false
	main_dialog.ok_button_text = "        Start Import        "
	main_dialog.confirmed.connect(self._asset_tree_window_confirmed)
	# "cancelled" ????
	hide_button = main_dialog.add_cancel_button("          Cancel          ")
	auto_hide_checkbox = CheckBox.new()
	auto_hide_checkbox.text = "Hide when complete"
	auto_hide_checkbox.button_pressed = true
	auto_hide_checkbox.toggled.connect(self._auto_hide_toggled)
	main_dialog.get_ok_button().visible = true
	hide_button.add_sibling(auto_hide_checkbox)
	main_dialog.custom_action.connect(self._asset_tree_window_confirmed_custom)
	var n: Label = main_dialog.get_label()
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_FILL
	vbox.size_flags_horizontal = Control.SIZE_FILL
	var hbox := HSplitContainer.new()
	hbox.size_flags_vertical = Control.SIZE_FILL
	hbox.size_flags_horizontal = Control.SIZE_FILL
	main_dialog_tree = Tree.new()
	main_dialog_tree.columns = 2
	main_dialog_tree.set_column_titles_visible(true)
	main_dialog_tree.set_column_title(0, "Path")
	main_dialog_tree.set_column_title(1, "Importer             ")
	main_dialog_tree.set_column_expand(0, true)
	main_dialog_tree.set_column_expand(1, false)
	main_dialog_tree.set_column_expand_ratio(0, 1.0)
	main_dialog_tree.set_column_expand_ratio(1, 0.0)
	main_dialog_tree.cell_selected.connect(self._cell_selected)
	main_dialog_tree.item_activated.connect(self._cell_selected)
	main_dialog_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_dialog_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_dialog_tree.custom_minimum_size = Vector2(300.0, 300.0)
	main_dialog_tree.size_flags_stretch_ratio = 1.0
	result_log_lineedit = TextEdit.new()
	result_log_lineedit.syntax_highlighter = ErrorSyntaxHighlighter.new(self)
	result_log_lineedit.visible = false
	result_log_lineedit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_log_lineedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_log_lineedit.custom_minimum_size = Vector2(300.0, 300.0)
	result_log_lineedit.size_flags_stretch_ratio = 1.0
	vbox.add_child(hbox)
	vbox.size_flags_stretch_ratio = 1.0
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_vbox = VBoxContainer.new()
	show_advanced_options = CheckButton.new()
	show_advanced_options.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	show_advanced_options.add_theme_icon_override(&"unchecked", base_control.get_theme_icon(&"arrow_collapsed", &"Tree"))
	show_advanced_options.add_theme_icon_override(&"checked", base_control.get_theme_icon(&"arrow", &"Tree"))
	show_advanced_options.add_theme_icon_override(&"unchecked_mirrored", base_control.get_theme_icon(&"arrow_collapsed_mirrored", &"Tree"))
	show_advanced_options.add_theme_icon_override(&"checked_mirrored", base_control.get_theme_icon(&"arrow", &"Tree"))
	show_advanced_options.text = "Advanced Settings"
	show_advanced_options.toggled.connect(self._show_advanced_options_toggled)
	advanced_options_hbox = HBoxContainer.new()
	advanced_options_hbox.hide()
	advanced_options_hbox.add_spacer(true).custom_minimum_size = Vector2(16, 0)
	advanced_options_vbox = VBoxContainer.new()
	advanced_options_hbox.add_child(advanced_options_vbox)
	advanced_options_container = PanelContainer.new()
	var new_stylebox_normal = advanced_options_container.get_theme_stylebox("panel").duplicate()
	if not (new_stylebox_normal is StyleBoxFlat):
		new_stylebox_normal = StyleBoxFlat.new()
	new_stylebox_normal.set_border_width_all(2)
	new_stylebox_normal.set_corner_radius_all(3)
	new_stylebox_normal.set_expand_margin_all(4)
	new_stylebox_normal.border_color = Color(0.5, 0.5, 0.5)
	advanced_options_container.add_theme_stylebox_override("panel", new_stylebox_normal)
	var adv_panel_inner_vbox := VBoxContainer.new()
	advanced_options_container.add_child(adv_panel_inner_vbox)
	adv_panel_inner_vbox.add_child(show_advanced_options)
	adv_panel_inner_vbox.add_child(advanced_options_hbox)

	hbox.size_flags_stretch_ratio = 1.0
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(options_vbox)
	hbox.add_child(main_dialog_tree)
	hbox.add_child(result_log_lineedit)
	n.add_sibling(vbox)
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	progress_bar.show_percentage = false
	vbox.add_child(progress_bar)
	status_bar = Label.new()
	status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	status_bar.size = Vector2(100, 20)
	vbox.add_child(status_bar)
	base_control.add_child(main_dialog, true)

	tree_dialog_state = STATE_DIALOG_SHOWING

	_keep_open_on_import = false
	written_additional_textures = false
	import_finished = false
	if file_dialog != null:
		file_dialog.popup_centered_ratio()

	log_icon = base_control.get_theme_icon("CodeEdit", "EditorIcons")
	fail_icon = base_control.get_theme_icon("ImportFail", "EditorIcons")
	error_icon = base_control.get_theme_icon("Error", "EditorIcons")
	warning_icon = base_control.get_theme_icon("ErrorWarning", "EditorIcons")
	spinner_icon1 = base_control.get_theme_icon("Progress1", "EditorIcons")
	status_warning_icon = base_control.get_theme_icon("StatusWarning", "EditorIcons")
	status_error_icon = base_control.get_theme_icon("StatusError", "EditorIcons")
	status_success_icon = base_control.get_theme_icon("StatusSuccess", "EditorIcons")
	folder_icon = base_control.get_theme_icon("Folder", "EditorIcons")
	file_icon = base_control.get_theme_icon("File", "EditorIcons")
	spinner_icon = AnimatedTexture.new()
	for i in range(8):
		# was get_icon in 3.2
		var progress_icon = base_control.get_theme_icon("Progress" + str(i + 1), "EditorIcons")
		if progress_icon == null:
			asset_database.log_fail([null, 0, "", 0], "Failed to get icon!")
		else:
			spinner_icon.set_frame_texture(i, progress_icon)
	spinner_icon.frames = 8


func _notification(what):
	match what:
		NOTIFICATION_PREDELETE:
			if file_dialog:
				file_dialog.queue_free()
				file_dialog = null

			if main_dialog:
				main_dialog.queue_free()
				main_dialog = null


func generate_sentinel_png_filename():
	return "_unidotimp_temp" + str(tree_dialog_state) + ("_retry" if retry_tex else "") + ".png"


var _delay_tick: int = 0


func on_import_fully_completed():
	var da := DirAccess.open("res://")
	print("Import is fully completed")
	da.remove("res://_sentinel_file.png")
	da.remove("res://_sentinel_file.png.import")
	var ei = new_editor_plugin.get_editor_interface()
	if ei.has_method("save_all_scenes"):
		ei.save_all_scenes()
	else:
		ei.save_scene()
	var editor_filesystem: EditorFileSystem = ei.get_resource_filesystem()
	hide_button.text = "            Close            "
	auto_hide_checkbox.hide()
	pause_button.visible = false
	abort_button.visible = false
	paused = false
	editor_filesystem.scan()
	import_finished = true
	if not _keep_open_on_import:
		if main_dialog:
			main_dialog.hide()
	if typeof(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb")) != TYPE_NIL:
		ProjectSettings.set_setting("memory/limits/message_queue/max_size_mb", asset_database.orig_max_size_mb)

	if not batch_import_file_list.is_empty():
		var rc = RefCounted.new()
		rc.set_script(get_script())
		rc.editor_plugin = editor_plugin
		rc._show_importer_common()
		rc.batch_import_file_list = batch_import_file_list.slice(1)
		rc.batch_import_types = batch_import_types
		rc.auto_import = true
		rc._keep_open_on_import = _keep_open_on_import
		rc._selected_package(batch_import_file_list[0])
		rc.batch_import_file_list = batch_import_file_list.slice(1)
		rc.batch_import_types = batch_import_types
		print(batch_import_types)
		rc.auto_import = true
		rc._keep_open_on_import = _keep_open_on_import
		if rc.batch_import_list_widget != null:
			for f in rc.batch_import_file_list:
				rc.batch_import_list_widget.add_item(f)
		rc.main_dialog.title = "Batch importing " + batch_import_file_list[0] + "..."


func update_task_color(tw: RefCounted):
	var ti: TreeItem = tw.extra
	if tw.did_fail and tw.asset.parsed_meta == null:
		asset_database.log_fail([null, 0, "", 0], "Pkgasset " + str(tw.asset.pathname) + " guid " + str(tw.asset.guid) + " failed to parse meta. did_fail=" + str(tw.did_fail))
		ti.set_icon(0, status_error_icon)
		ti.set_custom_color(0, Color("#ffbb77"))
	elif tw.asset.parsed_meta == null:
		asset_database.log_debug([null, 0, "", 0], "Pkgasset " + str(tw.asset.pathname) + " guid " + str(tw.asset.guid) + " skipped import and succeeded")
		ti.set_icon(0, status_success_icon)
		ti.set_custom_color(0, Color("#ddffbb"))
	else:
		var holder: asset_meta_class.LogMessageHolder = tw.asset.parsed_meta.log_message_holder
		if tw.did_fail:
			asset_database.log_fail([null, 0, "", 0], "Pkgasset " + str(tw.asset.pathname) + " guid " + str(tw.asset.guid) + " parsed meta but did_fail=" + str(tw.did_fail) + " is_loaded=" + str(tw.is_loaded))
			ti.set_icon(0, status_error_icon)
			ti.set_custom_color(0, Color("#ff7733"))
		elif not tw.is_loaded:
			asset_database.log_fail([null, 0, "", 0], "Pkgasset " + str(tw.asset.pathname) + " guid " + str(tw.asset.guid) + " could not be loaded.")
			ti.set_icon(0, status_error_icon)
			ti.set_custom_color(0, Color("#ff4422"))
		elif holder.has_fails():
			ti.set_icon(0, status_warning_icon)
			ti.set_custom_color(0, Color("#ff8822"))
			ti.set_text(0, tw.asset.parsed_meta.path.get_file())
		elif holder.has_warnings():
			ti.set_icon(0, status_success_icon)
			ti.set_custom_color(0, Color("#ccff22"))
			ti.set_text(0, tw.asset.parsed_meta.path.get_file())
		else:
			ti.set_icon(0, status_success_icon)
			ti.set_custom_color(0, Color("#22ff44"))
			ti.set_text(0, tw.asset.parsed_meta.path.get_file())
		if holder != null:
			var num_fails = len(holder.fails)
			var delta_num_fails = num_fails - ("0" + ti.get_text(4)).to_int()
			var num_warnings = len(holder.warnings_fails) - num_fails
			var delta_num_warnings = num_warnings - ("0" + ti.get_text(3)).to_int()
			while ti != null:
				if num_fails > 0:
					main_dialog_tree.set_column_title(4, "Errors")
					ti.set_cell_mode(4, TreeItem.CELL_MODE_CHECK)
					ti.set_icon(4, fail_icon)
					ti.set_custom_bg_color(4, Color(0.4,0.1,0.12,0.5),true)
					ti.set_text_alignment(4, HORIZONTAL_ALIGNMENT_RIGHT)
					ti.set_text(4, str(delta_num_fails + ("0" + ti.get_text(4)).to_int()))
					ti.set_tooltip_text(4, str(num_fails)+ " Errors")
				if num_warnings > 0 or num_fails > 0:
					main_dialog_tree.set_column_title(3, "Warnings")
					ti.set_cell_mode(3, TreeItem.CELL_MODE_CHECK)
					ti.set_icon(3, warning_icon)
					ti.set_custom_bg_color(3, Color(0.4,0.36,0.1,0.5),true)
					ti.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
					ti.set_text(3, str(delta_num_warnings + ("0" + ti.get_text(3)).to_int()))
					ti.set_tooltip_text(3, str(num_warnings)+ " Warnings")
				ti = ti.get_parent()

func on_file_completed_godot_import(tw: RefCounted, loaded: bool):
	var ti: TreeItem = tw.extra
	if ti.get_button_count(0) > 0:
		ti.erase_button(0, 0)
	update_task_color(tw)
	asset_work_completed.append(tw)


var tmp_material_texture_files: PackedStringArray


func do_import_step():
	if _currently_preprocessing_assets != 0:
		asset_database.log_fail([null, 0, "", 0], "Import step called during preprocess")
		return
	var editor_filesystem: EditorFileSystem = new_editor_plugin.get_editor_interface().get_resource_filesystem()

	for tw in asset_work_completed:
		update_task_color(tw)

	if tree_dialog_state >= STATE_DONE_IMPORT:
		if not paused:
			status_bar.text = "Import complete."
		return
	if paused:
		abort_button.visible = true
		return

	asset_database.log_debug([null, 0, "", 0], "Scanning percentage: " + str(editor_filesystem.get_scanning_progress()))
	while len(asset_work_waiting_scan) == 0 and len(asset_work_waiting_write) == 0:
		asset_database.log_debug([null, 0, "", 0], "Trying to scan more things: state=" + str(tree_dialog_state))
		if asset_work_written_last_stage > 10:
			asset_database.save()
		asset_work_written_last_stage = 0
		if tree_dialog_state == STATE_PREPROCESSING:
			update_progress_bar(10)
			tree_dialog_state = STATE_TEXTURES
			for tw in asset_textures:
				asset_work_waiting_write.append(tw)
			asset_work_written_last_stage = len(asset_work_waiting_write)
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " textures, animations and audio..."
			asset_work_waiting_write.reverse()
			asset_textures = [].duplicate()
			if tree_dialog_state == STATE_TEXTURES and not asset_materials_and_other.is_empty():
				break
		elif tree_dialog_state == STATE_TEXTURES:
			update_progress_bar(10)
			tree_dialog_state = STATE_IMPORTING_MATERIALS_AND_ASSETS
			for tw in asset_materials_and_other:
				asset_work_waiting_write.append(tw)
			asset_work_written_last_stage = len(asset_work_waiting_write)
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " materials..."
			asset_work_waiting_write.reverse()
			asset_materials_and_other = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MATERIALS_AND_ASSETS:
			update_progress_bar(10)
			tree_dialog_state = STATE_IMPORTING_MODELS
			for tw in asset_models:
				asset_work_waiting_write.append(tw)
			asset_work_written_last_stage = len(asset_work_waiting_write)
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " models..."
			asset_work_waiting_write.reverse()
			asset_models = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MODELS:
			# Clear stale dummy texture file placeholders.
			var dres = DirAccess.open("res://")
			for file_path in tmp_material_texture_files:
				var fa := FileAccess.open(file_path, FileAccess.READ)
				if fa == null or fa.get_length() != 0:
					asset_database.log_debug([null, 0, "", 0], "Dummy texture " + str(file_path) + " is not very dummy")
					continue
				fa.close()
				asset_database.log_debug([null, 0, "", 0], "Removing dummy empty texture " + str(file_path))
				dres.remove(file_path)
				dres.remove(file_path + ".import")
			tmp_material_texture_files.clear()

			update_progress_bar(10)
			tree_dialog_state = STATE_IMPORTING_YAML_POST_MODEL
			for tw in asset_yaml_post_model:
				asset_work_waiting_write.append(tw)
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " animation trees..."
			asset_work_waiting_write.reverse()
			asset_yaml_post_model = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_YAML_POST_MODEL:
			update_progress_bar(10)
			tree_dialog_state = STATE_IMPORTING_PREFABS
			var guid_to_meta = {}.duplicate()
			var guid_to_tw = {}.duplicate()
			var a_meta: Object = null
			for tw in asset_prefabs:
				a_meta = tw.asset.parsed_meta
				guid_to_meta[tw.asset.guid] = tw.asset.parsed_meta
				guid_to_tw[tw.asset.guid] = tw
			var toposorted: Array = []
			if a_meta != null:
				toposorted = a_meta.toposort_prefab_recurse_toplevel(asset_database, guid_to_meta)
			var tmpprint: Array = [].duplicate()
			for meta in toposorted:
				tmpprint.push_back(meta.path)
			asset_database.log_debug([null, 0, "", 0], "Toposorted prefab dependencies: " + str(tmpprint))
			for meta in toposorted:
				if guid_to_tw.has(meta.guid):
					asset_work_waiting_write.append(guid_to_tw.get(meta.guid))
			asset_work_written_last_stage = len(asset_work_waiting_write)
			asset_work_waiting_write.reverse()
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " prefabs..."
			asset_prefabs = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_PREFABS:
			update_progress_bar(10)
			tree_dialog_state = STATE_IMPORTING_SCENES
			for tw in asset_scenes:
				asset_work_waiting_write.append(tw)
			asset_work_written_last_stage = len(asset_work_waiting_write)
			status_bar.text = "Importing " + str(len(asset_work_waiting_write)) + " scenes..."
			asset_work_waiting_write.reverse()
			asset_scenes = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_SCENES:
			update_progress_bar(10)
			status_bar.text = "Completing import..."
			tree_dialog_state = STATE_DONE_IMPORT
			break
		elif tree_dialog_state == STATE_DONE_IMPORT:
			break
		else:
			asset_database.log_fail([null, 0, "", 0], "Invalid state: " + str(tree_dialog_state))
			break

	asset_database.log_debug([null, 0, "", 0], "Writing non-imported assets: state=" + str(tree_dialog_state))
	var files_to_reimport: PackedStringArray = PackedStringArray().duplicate()
	var start_ts = Time.get_ticks_msec()
	var wrote_header := false
	while not asset_work_waiting_write.is_empty():
		var tw: Object = asset_work_waiting_write.pop_back()
		update_progress_bar(3)
		asset_database.log_debug([null, 0, "", 0], "Writing " + str(tw.asset.pathname))
		start_godot_import(tw)
		if not asset_adapter.uses_godot_importer(tw.asset):
			if not wrote_header:
				wrote_header = true
				asset_database.log_debug([null, 0, "", 0], "RESOURCES WRITTEN ============")
			asset_database.log_debug([null, 0, "", 0], tw.asset.pathname)
			update_progress_bar(7)
			var ticks_ts = Time.get_ticks_msec()
			if ticks_ts > start_ts + 300:
				break
	if wrote_header:
		asset_database.log_debug([null, 0, "", 0], "=================================")

	var asset_work = asset_work_waiting_scan
	asset_database.log_debug([null, 0, "", 0], "Queueing work: state=" + str(tree_dialog_state))
	#for tw in asset_work:
	#	editor_filesystem.update_file(tw.asset.pathname)
	for tw in asset_work:
		asset_work_currently_importing.push_back(tw)
		if asset_adapter.uses_godot_importer(tw.asset):
			asset_adapter.about_to_import(tw.asset)
			tw.asset.log_debug("asset " + str(tw.asset) + " uses godot import")
			asset_database.log_debug([null, 0, "", 0], "Importing " + str(tw.asset.pathname) + " with the godot importer...")
			files_to_reimport.append("res://" + tw.asset.pathname)
		var ti: TreeItem = tw.extra
		if ti.get_button_count(0) <= 0:
			ti.add_button(0, spinner_icon, -1, true, "Loading...")

	# After all textures have been written, but before materials are done, 
	if asset_work_waiting_write.is_empty() and tree_dialog_state == STATE_TEXTURES and not written_additional_textures:
		written_additional_textures = true
		for tw in asset_materials_and_other:
			for filename in asset_adapter.write_additional_import_dependencies(tw.asset, pkg.guid_to_pkgasset):
				tw.asset.parsed_meta.log_debug(0, "Additional import dependency discovered: " + str(filename))
				if filename.is_empty():
					continue
				if not filename.begins_with("res://"):
					filename = "res://" + filename
				files_to_reimport.append(filename)
		asset_database.log_debug([null, 0, "", 0], "Done checking for additional import dependencies.")

	asset_work_waiting_scan = [].duplicate()
	#retry_tex = false
	#asset_adapter.write_sentinel_png(generate_sentinel_png_filename())
	#files_to_reimport.append("res://" + generate_sentinel_png_filename())
	#asset_database.log_debug([null,0,"",0], "Writing " + str(generate_sentinel_png_filename()))
	if not files_to_reimport.is_empty():
		update_global_logs()
		editor_filesystem.reimport_files(files_to_reimport)
		update_progress_bar(len(files_to_reimport) * 7)

	var completed_scan: Array = asset_work_currently_importing
	asset_work_currently_importing = [].duplicate()

	for tw in completed_scan:
		tw.asset.log_debug("Asset " + tw.asset.pathname + "/" + tw.asset.guid + " completed import.")
		var loaded_asset: Resource = ResourceLoader.load(tw.asset.pathname, "", ResourceLoader.CACHE_MODE_REPLACE)
		tw.is_loaded = (loaded_asset != null)
		#var loaded_asset: Resource = load(tw.asset.pathname)
		if loaded_asset != null:
			tw.asset.parsed_meta.insert_resource_path(tw.asset.parsed_meta.main_object_id, tw.asset.pathname)
		asset_adapter.finished_import(tw.asset, loaded_asset)
		on_file_completed_godot_import(tw, loaded_asset != null)
	if asset_work_waiting_write.is_empty():
		if tree_dialog_state == STATE_PREPROCESSING:
			status_bar.text = "Importing textures, animations and audio..."
		elif tree_dialog_state == STATE_TEXTURES:
			status_bar.text = "Importing materials..."
		elif tree_dialog_state == STATE_IMPORTING_MATERIALS_AND_ASSETS:
			status_bar.text = "Importing models..."
		elif tree_dialog_state == STATE_IMPORTING_MODELS:
			status_bar.text = "Importing animation trees..."
		elif tree_dialog_state == STATE_IMPORTING_YAML_POST_MODEL:
			status_bar.text = "Importing prefabs..."
		elif tree_dialog_state == STATE_IMPORTING_PREFABS:
			status_bar.text = "Importing scenes..."
		asset_database.log_debug([null, 0, "", 0], "============= " + status_bar.text)

	asset_database.log_debug([null, 0, "", 0], "Done Queueing work: state=" + str(tree_dialog_state))


func _done_preprocessing_assets():
	asset_database.log_debug([null, 0, "", 0], "Finished all preprocessing!!")
	self.import_worker.stop_all_threads_and_wait()
	asset_database.log_debug([null, 0, "", 0], "Joined.")
	import_worker2.start_threads(THREAD_COUNT)
	#asset_adapter.write_sentinel_png(generate_sentinel_png_filename())

	# Write temporary dummy texture file placeholders relative to .fbx files so the FBX importer will find them.
	var dres = DirAccess.open("res://")
	asset_database.log_debug([null, 0, "", 0], "Go through assets " + str(pkg.guid_to_pkgasset) + ".")
	for guid in pkg.guid_to_pkgasset:
		var pkgasset = pkg.guid_to_pkgasset.get(guid, null)
		asset_database.log_debug([null, 0, "", 0], str(guid) + " " + str(pkgasset)  + " " + str(pkgasset.pathname))
		var dbgref = [null, 0, "", 0] # [null, pkgasset.parsed_meta.main_object_id, guid, 0]
		if not pkgasset:
			continue
		asset_database.log_debug(dbgref, str(pkgasset.parsed_meta.unique_texture_map))
		for tex_name in pkgasset.parsed_meta.unique_texture_map:
			var tex_pathname: String = pkgasset.pathname.get_base_dir().path_join(tex_name)
			if dres.file_exists(tex_pathname + ".import") or dres.file_exists(tex_pathname):
				asset_database.log_debug(dbgref, "letsgooo already exists " + str(tex_pathname))
				tmp_material_texture_files.append(tex_pathname)
				continue
			var fa := FileAccess.open(tex_pathname + ".import", FileAccess.WRITE_READ)
			if fa == null:
				continue
			asset_database.log_debug(dbgref, "Writing " + str(tex_pathname))
			fa.store_buffer("[remap]\n\nimporter=\"skip\"\n".to_utf8_buffer())
			fa.close()
			fa = FileAccess.open(tex_pathname, FileAccess.WRITE_READ)
			asset_database.log_debug(dbgref, "Writing " + str(tex_pathname))
			fa.close()
			asset_database.log_debug(dbgref, "letsgooo")
			tmp_material_texture_files.append(tex_pathname)

	status_bar.text = "Converting textures to metal roughness..."
	import_worker2.set_stage2(pkg.guid_to_pkgasset)
	var visited = {}.duplicate()
	var second_pass: Array = [].duplicate()
	var num_processing = _preprocess_recursively(main_dialog_tree.get_root(), visited, second_pass, true)


func _done_preprocessing_assets_stage2():
	status_bar.text = "Done preprocessing. Scanning filesystem..."
	asset_database.log_debug([null, 0, "", 0], "Finished all preprocessing stage2!!")
	self.import_worker2.stop_all_threads_and_wait()
	asset_database.log_debug([null, 0, "", 0], "Joined 2.")
	asset_database.save()


func start_godot_import(tw: Object):
	#var meta_data: PackedByteArray = tw.asset.metadata_tar_header.get_data()
	#var metafil = FileAccess.open("res://" + tmpdir + "/" + tw.asset.pathname + ".meta", FileAccess.WRITE_READ)
	#metafil.store_buffer(meta_data)
	#metafil.flush()
	#metafil = null
	var asset_modified: bool = asset_adapter.write_godot_asset(tw.asset, tmpdir + "/" + tw.output_path)
	var import_modified: bool = asset_adapter.write_godot_import(tw.asset)
	tw.asset.log_debug("Wrote file " + tw.output_path + " asset modified:" + str(asset_modified) + " import modified:" + str(import_modified))

	var force_reimport: bool = false
	if asset_adapter.get_asset_type(tw.asset) == asset_adapter.ASSET_TYPE_MODEL and not skip_reimport_models_checkbox.button_pressed:
		force_reimport = true
	if asset_database.get_meta_at_path(tw.asset.parsed_meta.path) == null:
		tw.asset.log_debug("Asset " + str(tw.asset.parsed_meta.guid) + " does not yet exist in asset database. It must be new.")
		force_reimport = true

	if not asset_modified and not import_modified and not force_reimport:
		tw.asset.log_debug("We can skip this file!")
		if asset_adapter.uses_godot_importer(tw.asset):
			update_progress_bar(7)
		var ti: TreeItem = tw.extra
		if ti.get_button_count(0) > 0:
			ti.erase_button(0, 0)
		ti.set_custom_color(0, Color("#22bb66"))
		ti.set_icon(0, status_success_icon)
		if tw.asset.parsed_meta != null:
			tw.asset.parsed_meta.taken_over_import_references.clear()
		return

	if asset_adapter.uses_godot_importer(tw.asset):
		asset_database.insert_meta(tw.asset.parsed_meta)
	asset_work_waiting_scan.push_back(tw)


func _asset_processing_finished(tw: Object):
	_currently_preprocessing_assets -= 1
	update_progress_bar(1)
	tw.asset.log_debug(str(tw.asset) + " preprocess finished!")
	var ti: TreeItem = tw.extra
	ti.set_metadata(1, tw.asset)
	if tw.did_fail:
		update_task_color(tw)
	else:
		ti.set_custom_color(0, Color("#44ffff"))
	if ti.get_button_count(0) > 0:
		ti.erase_button(0, 0)
	tw.asset.log_debug("Asset database object is now " + str(asset_database))
	#
	# func _asset_failed(tw: Object):
	# _currently_preprocessing_assets -= 1
	# tw.asset.log_fail(str(tw.asset) + " preprocess failed!")
	# var ti: TreeItem = tw.extra
	# ti.set_custom_color(0, Color("#222288"))
	# ti.erase_button(0, 0)
	# ti.add_button(0, fail_icon, -1, true, "Import Failed!")
	#
	if tw.asset.parsed_meta == null:
		tw.asset.parsed_meta = asset_database.create_dummy_meta(tw.asset.guid)
		tw.asset.log_fail("Did not successfully parse meta.")
	tw.asset.log_debug("For guid " + str(tw.asset.guid) + ": internal_data=" + str(tw.asset.parsed_meta.internal_data))
	tw.asset.log_debug("Finished processing meta path " + str(tw.asset.parsed_meta.path) + " guid " + str(tw.asset.parsed_meta.guid) + " opath " + str(tw.output_path))
	if not tw.did_fail:
		if not asset_adapter.uses_godot_importer(tw.asset):
			asset_database.insert_meta(tw.asset.parsed_meta)
	if not tw.did_fail and tw.asset.asset_tar_header != null:
		var extn = tw.output_path.get_extension()
		var asset_type = asset_adapter.get_asset_type(tw.asset)
		asset_all.push_back(tw)
		if asset_type == asset_adapter.ASSET_TYPE_TEXTURE or asset_type == asset_adapter.ASSET_TYPE_ANIM:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is texture/anim")
			asset_textures.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_YAML:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is yaml")
			asset_materials_and_other.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_MODEL:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is model")
			asset_models.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_YAML_POST_MODEL:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is yaml")
			asset_yaml_post_model.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_PREFAB:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is prefab")
			asset_prefabs.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_SCENE:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is scene")
			asset_scenes.push_back(tw)
		else:  # asset_type == asset_adapter.ASSET_TYPE_UNKNOWN:
			tw.asset.log_debug("Asset " + str(tw.output_path) + " is other")
			asset_materials_and_other.push_back(tw)
	else:
		update_progress_bar(10) # 1 for stage2, 10 for import.
		# start_godot_import_stub(tw) # We now write it directly in the preprocess function.
	if _currently_preprocessing_assets == 0:
		if not _preprocessing_second_pass.is_empty():
			_preprocess_second_pass()
			status_bar.text = "Preprocessing humanoid or dependent fbx... " + str(_currently_preprocessing_assets) + " remaining."
			_preprocessing_second_pass = [].duplicate()
		else:
			_done_preprocessing_assets()
	status_bar.text = status_bar.text.get_slice("...", 0) + "... " + str(_currently_preprocessing_assets) + " remaining."


func _preprocess_second_pass():
	var second_pass = _preprocessing_second_pass
	_preprocessing_second_pass = [].duplicate()
	var pkgassets: Array = [].duplicate()
	for ti2 in second_pass:
		var path = ti2.get_tooltip_text(0)  # HACK! No data field in TreeItem?? Let's use the tooltip?!
		var asset = pkg.path_to_pkgasset.get(path)
		_currently_preprocessing_assets += 1
		progress_bar.max_value += 1
		asset.meta_dependencies = {}.duplicate()
		for dep in asset.parsed_meta.meta_dependency_guids:
			if pkg.guid_to_pkgasset.has(dep):
				asset.meta_dependencies[dep] = pkg.guid_to_pkgasset[dep].parsed_meta
			else:
				asset.meta_dependencies[dep] = asset_database.get_meta_by_guid(dep)
		pkgassets.append(asset)
	for i in range(len(second_pass)):
		self.import_worker.push_asset(pkgassets[i], tmpdir, second_pass[i])


func _asset_processing_started(tw: Object):
	asset_database.log_debug([null, 0, tw.asset.guid, 0], "Started processing asset is " + str(tw.asset.pathname) + "/" + str(tw.asset.guid))
	var ti: TreeItem = tw.extra
	if tw.asset.parsed_meta != null:
		tw.asset.parsed_meta.clear_logs()
	ti.set_custom_color(0, Color("#228888"))


func _asset_processing_stage2_finished(tw: Object):
	_currently_preprocessing_assets -= 1
	update_progress_bar(1)
	var ti: TreeItem = tw.extra
	if _currently_preprocessing_assets == 0:
		_done_preprocessing_assets_stage2()

func _preprocess_recursively(ti: TreeItem, visited: Dictionary, second_pass: Array, is_second_stage: bool=false) -> int:
	var ret: int = 0
	# I think this now runs after _prune_unselected_items so it should always be true
	if ti.is_checked(0) or ti.get_cell_mode(0) != TreeItem.CELL_MODE_CHECK: # It's now always CELL_MODE_STRING
		var path = ti.get_tooltip_text(0)  # tooltip contains the path so no need to use metadata
		if not path.is_empty():
			var asset = pkg.path_to_pkgasset.get(path)
			if asset == null:
				asset_database.log_fail([null, 0, "", 0], "Path " + str(path) + " has null asset!")
			else:
				ret += 1
				if is_second_stage:
					asset.parsed_meta.log_debug(0, "Queueing for import_worker2")
					_currently_preprocessing_assets += 1
					import_worker2.push_asset(asset, tmpdir, ti)
				elif not asset.parsed_meta.meta_dependency_guids.is_empty():
					asset.parsed_meta.log_debug(0, "Meta has dependencies " + str(asset.parsed_meta.dependency_guids))
					second_pass.append(ti)
				else:
					_currently_preprocessing_assets += 1
					var tw: RefCounted = self.import_worker.push_asset(asset, tmpdir, ti)
				# ti.set_cell_mode(0, TreeItem.CELL_MODE_ICON)
				if ti.get_button_count(0) <= 0:
					ti.add_button(0, spinner_icon, -1, true, "Loading...")
	for chld in ti.get_children():
		ret += _preprocess_recursively(chld, visited, second_pass, is_second_stage)
	return ret


func _asset_tree_window_confirmed_custom(action_name):
	pass #assert(action_name == "pause_import")


var import_step_timer: Timer = null
var import_step_tick_count: int = 0
var import_step_reentrant: bool = false

var preprocess_timer: Timer = null


func _do_import_step_tick():
	if import_step_reentrant:
		asset_database.log_debug([null, 0, "", 0], "Still working...")
		# We can safely ignore reentrant ticks.
		# it is healthy and normal to get ticked while displaying the progress bar for reimport_files.
		# asset_database.log_debug([null,0,"",0], "reentrant TICK ======= " + str(import_step_tick_count))
		return
	import_step_reentrant = true
	import_step_tick_count += 1
	#asset_database.log_debug([null, 0, "", 0], "TICK ======= " + str(import_step_tick_count))
	OS.close_midi_inputs()  # Place to set C++ breakpoint to check for reentrancy
	do_import_step()
	if tree_dialog_state >= STATE_DONE_IMPORT:
		import_step_timer.timeout.disconnect(self._do_import_step_tick)
		import_step_timer.queue_free()
		import_step_timer = null
		asset_database.log_debug([null, 0, "", 0], "All done")
		asset_database.in_package_import = false
		asset_database.save()
		asset_database.log_debug([null, 0, "", 0], "Saved database")
		if not paused:
			status_bar.text = "Import complete."
		update_all_logs()
		call_deferred(&"on_import_fully_completed")
	else:
		#asset_database.log_debug([null, 0, "", 0], "TICK RETURN ======= " + str(import_step_tick_count))
		update_global_logs()
	import_step_reentrant = false


func _scan_sources_complete(useless: Variant = null):
	update_progress_bar(5)
	var editor_filesystem: EditorFileSystem = new_editor_plugin.get_editor_interface().get_resource_filesystem()
	editor_filesystem.sources_changed.disconnect(self._scan_sources_complete)
	asset_database.log_debug([null, 0, "", 0], "Reimporting sentinel to wait for import step to finish.")
	editor_filesystem.reimport_files(PackedStringArray(["res://_sentinel_file.png"]))
	asset_database.log_debug([null, 0, "", 0], "Got signal that scan_sources is complete.")
	for tw in asset_all:
		if not asset_adapter.uses_godot_importer(tw.asset):
			continue
		var filename: String = tw.asset.pathname
		asset_database.log_debug([null, 0, tw.asset.guid, 0], filename + ":" + str(editor_filesystem.get_file_type(filename)))
		var fs_dir: EditorFileSystemDirectory = editor_filesystem.get_filesystem_path(filename.get_base_dir())
		if fs_dir == null:
			asset_database.log_fail([null, 0, tw.asset.guid, 0], "BADBAD: Filesystem directory null for " + str(filename))
		else:
			asset_database.log_debug([null, 0, tw.asset.guid, 0], "Dir " + str(filename.get_base_dir()) + " file count: " + str(fs_dir.get_file_count()))
			var idx = fs_dir.find_file_index(filename.get_file())
			if idx == -1:
				asset_database.log_fail([null, 0, tw.asset.guid, 0], "BADBAD: Index is -1 for " + str(filename))
			else:
				asset_database.log_debug([null, 0, tw.asset.guid, 0], "Import " + str(fs_dir.get_file(idx)) + " valid: " + str(fs_dir.get_file_import_is_valid(idx)))
	asset_database.log_debug([null, 0, "", 0], "Ready to start import step ticks")

	import_step_tick_count = 0
	import_step_reentrant = false
	if import_step_timer != null:
		import_step_timer.queue_free()
	import_step_timer = Timer.new()
	import_step_timer.wait_time = 0.1
	import_step_timer.autostart = true
	import_step_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	new_editor_plugin.get_editor_interface().get_base_control().add_child(import_step_timer, true)
	import_step_timer.timeout.connect(self._do_import_step_tick)


func _preprocess_wait_tick():
	update_global_logs()
	var editor_filesystem: EditorFileSystem = new_editor_plugin.get_editor_interface().get_resource_filesystem()
	if _currently_preprocessing_assets == 0 and not editor_filesystem.is_scanning():
		update_progress_bar(5)
		asset_database.log_debug([null, 0, "", 0], "Done preprocessing. ready to trigger scan_sources!")
		preprocess_timer.timeout.disconnect(self._preprocess_wait_tick)
		preprocess_timer.queue_free()
		preprocess_timer = null
		var cfile = ConfigFile.new()
		cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
		cfile.set_value("remap", "importer", "keep")
		cfile.save("res://_sentinel_file.png.import")
		asset_database.log_debug([null, 0, "", 0], "Writing res://_sentinel_file.png")
		asset_adapter.write_sentinel_png("res://_sentinel_file.png")
		editor_filesystem.sources_changed.connect(self._scan_sources_complete, CONNECT_DEFERRED)
		editor_filesystem.scan_sources()


func _asset_tree_window_confirmed():
	hide_button.text = "            Hide            "
	pause_button = main_dialog.add_button("        Pause        ", false, "pause_import")
	pause_button.toggle_mode = true
	pause_button.toggled.connect(self._pause_toggled)
	abort_button = Button.new()
	abort_button.text = "        Abort        "
	abort_button.pressed.connect(self._abort_clicked)
	abort_button.visible = false
	pause_button.add_sibling(abort_button)
	var max_queue_size_mb: Variant = ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb")
	if typeof(max_queue_size_mb) != TYPE_NIL and max_queue_size_mb != 1022:
		asset_database.orig_max_size_mb = max_queue_size_mb
		if asset_database.orig_max_size_mb < 1022:
			ProjectSettings.set_setting("memory/limits/message_queue/max_size_mb", 1022)
	main_dialog_tree.columns = 5
	#main_dialog_tree.set_column_title(2, "\u26a0") # Warning emoji
	#main_dialog_tree.set_column_title(3, "\u26d4") # Error emoji
	if asset_database.enable_verbose_logs:
		main_dialog_tree.set_column_title(2, "Logs")
		main_dialog_tree.set_column_custom_minimum_width(2, 64)
	main_dialog_tree.set_column_clip_content(2, true)
	main_dialog_tree.set_column_expand(2, false)
	main_dialog_tree.set_column_expand_ratio(2, 0.1)
	main_dialog_tree.set_column_clip_content(3, true)
	main_dialog_tree.set_column_clip_content(4, true)
	main_dialog_tree.set_column_custom_minimum_width(3, 64)
	main_dialog_tree.set_column_custom_minimum_width(4, 64)
	main_dialog_tree.set_column_expand(3, false)
	main_dialog_tree.set_column_expand(4, false)
	main_dialog_tree.set_column_expand_ratio(3, 0.1)
	main_dialog_tree.set_column_expand_ratio(4, 0.1)

	if import_finished:
		if main_dialog:
			main_dialog.hide()
		return
	if tree_dialog_state != STATE_DIALOG_SHOWING:
		return

	var root_item := main_dialog_tree.get_root()
	var toplevel_items := root_item.get_children()
	for toplevel_child in toplevel_items:
		if toplevel_child.get_text(1) == " ":
			root_item.remove_child(toplevel_child)

	_prune_unselected_items(main_dialog_tree.get_root())
	options_vbox.visible = false
	result_log_lineedit.visible = true
	main_dialog.get_ok_button().visible = false

	global_logs_tree_item = root_item.create_child(0)
	global_logs_tree_item.set_text(0, "Global import status messages")
	global_logs_tree_item.set_text(1, " ")
	var log_column = 2
	if not asset_database.enable_verbose_logs:
		log_column = 3
	global_logs_tree_item.set_cell_mode(log_column, TreeItem.CELL_MODE_CHECK)
	global_logs_tree_item.set_checked(log_column, true)
	global_logs_tree_item.set_text_alignment(log_column, HORIZONTAL_ALIGNMENT_RIGHT)
	global_logs_tree_item.set_text(log_column, "Status")
	global_logs_tree_item.set_selectable(log_column, true)

	asset_database.log_debug([null, 0, "", 0], "Finishing meta.")
	meta_worker.stop_all_threads_and_wait()
	asset_database.log_debug([null, 0, "", 0], "Joined meta.")
	tree_dialog_state = STATE_PREPROCESSING
	written_additional_textures = false
	import_worker.asset_database = asset_database
	asset_database.in_package_import = true
	asset_database.log_debug([null, 0, "", 0], "Asset database object returned " + str(asset_database))
	import_worker.start_threads(THREAD_COUNT)  # Don't DISABLE_THREADING
	var visited = {}.duplicate()
	var second_pass: Array = [].duplicate()
	var num_processing = _preprocess_recursively(main_dialog_tree.get_root(), visited, second_pass)
	progress_bar.show_percentage = true
	progress_bar.max_value = _currently_preprocessing_assets * 12 + 80
	if _currently_preprocessing_assets > 2000:
		asset_database.log_limit_per_guid = 5000
	elif _currently_preprocessing_assets > 1000:
		asset_database.log_limit_per_guid = 10000
	elif _currently_preprocessing_assets > 500:
		asset_database.log_limit_per_guid = 20000
	else:
		asset_database.log_limit_per_guid = 100000
	status_bar.text = "Preprocessing FBX and reading assets ..."
	_preprocessing_second_pass = second_pass
	if _currently_preprocessing_assets == 0:
		_preprocess_second_pass()
		_preprocessing_second_pass = [].duplicate()
	if preprocess_timer != null:
		preprocess_timer.queue_free()
	preprocess_timer = Timer.new()
	preprocess_timer.wait_time = 0.1
	preprocess_timer.autostart = true
	preprocess_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	new_editor_plugin.get_editor_interface().get_base_control().add_child(preprocess_timer, true)
	preprocess_timer.timeout.connect(self._preprocess_wait_tick)
	if num_processing == 0:
		asset_database.log_debug([null, 0, "", 0], "No assets to process!")
		_done_preprocessing_assets()
		return
