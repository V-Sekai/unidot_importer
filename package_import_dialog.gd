# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

const unitypackagefile: GDScript = preload("./unitypackagefile.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const import_worker_class: GDScript = preload("./import_worker.gd")
const meta_worker_class: GDScript = preload("./meta_worker.gd")
const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
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

var main_dialog: AcceptDialog = null
var file_dialog: EditorFileDialog = null
var main_dialog_tree: Tree = null

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

var tree_dialog_state: int = 0
var path_to_tree_item: Dictionary
var guid_to_dependency_guids: Dictionary
var dependency_guids_to_guid: Dictionary
var ignore_dependencies: Dictionary

var _currently_preprocessing_assets: int = 0
var _preprocessing_second_pass: Array = []
var retry_tex: bool = false
var _keep_open_on_import: bool = false
var force_reimport_models_checkbox: CheckBox = null
var import_finished: bool = false
var written_additional_textures: bool = false

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

var result_log_lineedit: TextEdit 

var pkg: Object = null  # Type unitypackagefile, set in _selected_package

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
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
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
	elif is_all_unchecked:
		if ti.is_indeterminate(0) or ti.is_checked(0):
			ti.set_indeterminate(0, false)
			ti.set_checked(0, false)
			_set_indeterminate_up_recursively(ti.get_parent(), is_checked)
	else:
		if not ti.is_indeterminate(0):
			ti.set_checked(0, false)
			ti.set_indeterminate(0, true)
			ti.set_checked(0, false)
			_set_indeterminate_up_recursively(ti.get_parent(), is_checked)


func _check_recursively(ti: TreeItem, is_checked: bool, process_dependencies: bool, visited_set: Dictionary={}, is_recursive_file: bool=false) -> void:
	if visited_set.is_empty():
		visited_set = {}
	if visited_set.has(ti):
		return 
	visited_set[ti] = true
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
	if col == 0 or col == 1:
		if ti != null:  # and col == 1:
			var new_checked: bool = !ti.is_indeterminate(0) and !ti.is_checked(0)
			var process_dependencies: bool = not Input.is_key_pressed(KEY_SHIFT)
			_check_recursively(ti, new_checked, process_dependencies)
	elif col >= 2:
		ti.set_checked(col, not ti.is_checked(col))
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
			for child_ti in child_list:
				var tw: unitypackagefile.UnityPackageAsset = child_ti.get_metadata(1)
				var start_idx = len(filtered_msgs)
				if tw != null:
					if col == 2:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.all_logs)
					elif col == 3:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.warnings_fails)
					elif col == 4:
						filtered_msgs.append_array(tw.parsed_meta.log_message_holder.fails)
			if len(child_list) > 1:
				if col == 2:
					filtered_msgs.append_array(asset_database.log_message_holder.all_logs)
				elif col == 3:
					filtered_msgs.append_array(asset_database.log_message_holder.warnings_fails)
				elif col == 4:
					filtered_msgs.append_array(asset_database.log_message_holder.fails)
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
		result_log_lineedit.text = '\n'.join(visible_log_lines)
		result_log_lineedit.scroll_vertical = current_scroll
		main_dialog_tree.size_flags_stretch_ratio = 1.0
		result_log_lineedit.visible = true # not visible_log_lines.is_empty()
		result_log_lineedit.size_flags_stretch_ratio = 1.0

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
			ignore_dependencies[pkgasset.guid] = true
			_check_recursively(ti, false, false)
		if importer_type == "[MonoScript]" or importer_type == "Mono" or importer_type == "":
			ignore_dependencies[pkgasset.guid] = true
			_check_recursively(ti, false, false)
		if importer_type == "[Shader]" or importer_type == "Shader":
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
	ti.set_text(1, importer_type.replace("Default", "Scene"))
	var cls: String
	if importer_type.begins_with("["):
		cls = importer_type.substr(1, len(importer_type) - 2)
		var tmp_instance = object_adapter.instantiate_unity_object(pkgasset.parsed_meta, 0, 0, cls)
		cls = tmp_instance.get_godot_type()
	else:
		var tmp_importer = null
		if pkgasset.parsed_meta != null:
			tmp_importer = pkgasset.parsed_meta.importer
		if tmp_importer == null:
			tmp_importer = object_adapter.instantiate_unity_object(pkgasset.parsed_meta, 0, 0, importer_type + "Importer")
		var main_object_id: int = tmp_importer.get_main_object_id()
		if main_object_id == 1 or main_object_id == 100100000:
			cls = "PackedScene"
		else:
			var utype: int = main_object_id / 100000
			var tmp_instance = object_adapter.instantiate_unity_object_from_utype(pkgasset.parsed_meta, 0, utype)
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
	p_ti.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)
	p_ti.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
	p_ti.set_text(2, "Logs")
	p_ti.set_selectable(2, true)
	p_ti.set_icon(2, log_icon)
	return true


func _selected_package(p_path: String) -> void:
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
	pkg = unitypackagefile.new().init_with_filename(p_path)
	#pkg.parse_all_meta(asset_database)
	meta_worker.asset_database = asset_database
	asset_database.clear_logs()
	asset_database.in_package_import = true
	asset_database.log_debug([null, 0, "", 0], "Asset database object returned " + str(asset_database))
	meta_worker.start_threads(THREAD_COUNT)  # Don't DISABLE_THREADING

	var tree_names = ["Assets"]
	var ti: TreeItem = main_dialog_tree.create_item()
	ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	ti.set_text(0, "Assets")
	ti.set_expand_right(0, true)
	ti.set_expand_right(1, false)
	ti.set_checked(0, true)
	ti.set_icon_max_width(0, 24)
	ti.set_icon(0, folder_icon)
	ti.set_text(1, "RootDirectory")
	var tree_items = [ti]
	for path in pkg.paths:
		var pkgasset = pkg.path_to_pkgasset[path]
		var path_names: Array = path.split("/")
		var i: int = len(tree_names) - 1
		while i >= 0 and (i >= len(path_names) or path_names[i] != tree_names[i]):
			#asset_database.log_debug([null,0,"",0], "i=" + str(i) + "/" + str(len(path_names)) + "/" + str(tree_names[i]))
			tree_names.pop_back()
			tree_items.pop_back()
			i -= 1
		if i < 0:
			asset_database.log_fail([null, 0, "", 0], "Path outside of Assets: " + path)
			break
		while i < len(path_names) - 1:
			i += 1
			tree_names.push_back(path_names[i])
			ti = main_dialog_tree.create_item(tree_items[i - 1])
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


func show_reimport() -> void:
	file_dialog = null
	_show_importer_common()
	self._selected_package("")


func show_importer() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.set_title("Import Unity Package...")
	file_dialog.add_filter("*.unitypackage")
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	# FILE_MODE_OPEN_FILE = 0  –  The dialog allows selecting one, and only one file.
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(self._selected_package)
	EditorPlugin.new().get_editor_interface().get_base_control().add_child(file_dialog, true)
	_show_importer_common()
	check_fbx2gltf()


func check_fbx2gltf():
	var d = DirAccess.open("res://")
	var addon_path: String = EditorPlugin.new().get_editor_interface().get_editor_settings().get_setting("filesystem/import/fbx/fbx2gltf_path")
	if not addon_path.get_file().is_empty():
		print(addon_path)
		if not d.file_exists(addon_path):
			var error_dialog := AcceptDialog.new()
			EditorPlugin.new().get_editor_interface().get_base_control().add_child(error_dialog)
			error_dialog.title = "Unidot Importer"
			error_dialog.dialog_text = "FBX2glTF is not configured in Editor settings. This will cause corrupt imports!\nPlease install FBX2glTF in Editor Settings."
			error_dialog.popup_centered()


func show_importer_logs() -> void:
	main_dialog.show()


func _show_importer_common() -> void:
	base_control = EditorPlugin.new().get_editor_interface().get_base_control()
	main_dialog = AcceptDialog.new()
	main_dialog.title = "Select Assets to import"
	main_dialog.dialog_hide_on_ok = false
	main_dialog.confirmed.connect(self._asset_tree_window_confirmed)
	# "cancelled" ????
	main_dialog.add_cancel_button("Hide")
	main_dialog.add_button("Import and show result", false, "show_result")
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
	hbox.add_child(main_dialog_tree)
	result_log_lineedit = TextEdit.new()
	result_log_lineedit.syntax_highlighter = ErrorSyntaxHighlighter.new(self)
	result_log_lineedit.visible = false
	result_log_lineedit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_log_lineedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_log_lineedit.custom_minimum_size = Vector2(300.0, 300.0)
	result_log_lineedit.size_flags_stretch_ratio = 1.0
	hbox.add_child(result_log_lineedit)
	hbox.size_flags_stretch_ratio = 1.0
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	vbox.size_flags_stretch_ratio = 1.0
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	force_reimport_models_checkbox = CheckBox.new()
	force_reimport_models_checkbox.text = "Force reimport all models"
	force_reimport_models_checkbox.size_flags_vertical = Control.SIZE_SHRINK_END
	force_reimport_models_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_reimport_models_checkbox.size_flags_stretch_ratio = 0.0
	vbox.add_child(force_reimport_models_checkbox)
	n.add_sibling(vbox)
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
	return "_unityimp_temp" + str(tree_dialog_state) + ("_retry" if retry_tex else "") + ".png"


var _delay_tick: int = 0


func on_import_fully_completed():
	var da := DirAccess.open("res://")
	print("Import is fully completed")
	da.remove("res://_sentinel_file.png")
	da.remove("res://_sentinel_file.png.import")
	EditorPlugin.new().get_editor_interface().save_all_scenes()
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
	editor_filesystem.scan()
	import_finished = true
	if not _keep_open_on_import:
		if main_dialog:
			main_dialog.hide()


func update_task_color(tw: RefCounted):
	var ti: TreeItem = tw.extra
	if tw.did_fail and tw.asset.parsed_meta == null:
		ti.set_icon(0, status_error_icon)
		ti.set_custom_color(0, Color("#ffbb77"))
	elif tw.asset.parsed_meta == null:
		ti.set_icon(0, status_success_icon)
		ti.set_custom_color(0, Color("#ddffbb"))
	else:
		var holder: asset_meta_class.LogMessageHolder = tw.asset.parsed_meta.log_message_holder
		if tw.did_fail:
			ti.set_icon(0, status_error_icon)
			ti.set_custom_color(0, Color("#ff7733"))
		elif not tw.is_loaded:
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


func do_import_step():
	if _currently_preprocessing_assets != 0:
		asset_database.log_fail([null, 0, "", 0], "Import step called during preprocess")
		return
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()

	for tw in asset_work_completed:
		update_task_color(tw)

	if tree_dialog_state >= STATE_DONE_IMPORT:
		asset_database.save()
		on_import_fully_completed()
		return

	asset_database.log_debug([null, 0, "", 0], "Scanning percentage: " + str(editor_filesystem.get_scanning_progress()))
	while len(asset_work_waiting_scan) == 0 and len(asset_work_waiting_write) == 0:
		asset_database.save()
		asset_database.log_debug([null, 0, "", 0], "Trying to scan more things: state=" + str(tree_dialog_state))
		if tree_dialog_state == STATE_PREPROCESSING:
			tree_dialog_state = STATE_TEXTURES
			for tw in asset_textures:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_textures = [].duplicate()
			if tree_dialog_state == STATE_TEXTURES and not asset_materials_and_other.is_empty():
				break
		elif tree_dialog_state == STATE_TEXTURES:
			tree_dialog_state = STATE_IMPORTING_MATERIALS_AND_ASSETS
			for tw in asset_materials_and_other:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_materials_and_other = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MATERIALS_AND_ASSETS:
			tree_dialog_state = STATE_IMPORTING_MODELS
			for tw in asset_models:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_models = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MODELS:
			tree_dialog_state = STATE_IMPORTING_YAML_POST_MODEL
			for tw in asset_yaml_post_model:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_yaml_post_model = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_YAML_POST_MODEL:
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
			asset_work_waiting_write.reverse()
			asset_prefabs = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_PREFABS:
			tree_dialog_state = STATE_IMPORTING_SCENES
			for tw in asset_scenes:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_scenes = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_SCENES:
			tree_dialog_state = STATE_DONE_IMPORT
			break
		elif tree_dialog_state == STATE_DONE_IMPORT:
			break
		else:
			asset_database.log_fail([null, 0, "", 0], "Invalid state: " + str(tree_dialog_state))
			break

	var files_to_reimport: PackedStringArray = PackedStringArray().duplicate()
	var start_ts = Time.get_ticks_msec()
	while not asset_work_waiting_write.is_empty():
		var tw: Object = asset_work_waiting_write.pop_back()
		start_godot_import(tw)
		if not asset_adapter.uses_godot_importer(tw.asset):
			var ticks_ts = Time.get_ticks_msec()
			if ticks_ts > start_ts + 300:
				break

	var asset_work = asset_work_waiting_scan
	asset_database.log_debug([null, 0, "", 0], "Queueing work: state=" + str(tree_dialog_state))
	#for tw in asset_work:
	#	editor_filesystem.update_file(tw.asset.pathname)
	for tw in asset_work:
		asset_work_currently_importing.push_back(tw)
		if asset_adapter.uses_godot_importer(tw.asset):
			tw.asset.log_debug("asset " + str(tw.asset) + " uses godot import")
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
		editor_filesystem.reimport_files(files_to_reimport)

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

	asset_database.log_debug([null, 0, "", 0], "Done Queueing work: state=" + str(tree_dialog_state))


func _done_preprocessing_assets():
	asset_database.log_debug([null, 0, "", 0], "Finished all preprocessing!!")
	self.import_worker.stop_all_threads_and_wait()
	asset_database.log_debug([null, 0, "", 0], "Joined.")
	asset_database.save()
	import_worker2.start_threads(THREAD_COUNT)
	#asset_adapter.write_sentinel_png(generate_sentinel_png_filename())

	import_worker2.set_stage2(pkg.guid_to_pkgasset)
	var visited = {}.duplicate()
	var second_pass: Array = [].duplicate()
	var num_processing = _preprocess_recursively(main_dialog_tree.get_root(), visited, second_pass, true)


func _done_preprocessing_assets_stage2():
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
	if asset_adapter.get_asset_type(tw.asset) == asset_adapter.ASSET_TYPE_MODEL and force_reimport_models_checkbox.button_pressed:
		force_reimport = true
	if asset_database.get_meta_at_path(tw.asset.parsed_meta.path) == null:
		tw.asset.log_debug("Asset " + str(tw.asset.parsed_meta.guid) + " does not yet exist in asset database. It must be new.")
		force_reimport = true

	if not asset_modified and not import_modified and not force_reimport:
		tw.asset.log_debug("We can skip this file!")
		var ti: TreeItem = tw.extra
		if ti.get_button_count(0) > 0:
			ti.erase_button(0, 0)
		ti.set_custom_color(0, Color("#22bb66"))
		ti.set_icon(0, status_success_icon)
		return

	if asset_adapter.uses_godot_importer(tw.asset):
		asset_database.insert_meta(tw.asset.parsed_meta)
	asset_work_waiting_scan.push_back(tw)


func _asset_processing_finished(tw: Object):
	_currently_preprocessing_assets -= 1
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
		# start_godot_import_stub(tw) # We now write it directly in the preprocess function.
	if _currently_preprocessing_assets == 0:
		if not _preprocessing_second_pass.is_empty():
			_preprocess_second_pass()
			_preprocessing_second_pass = [].duplicate()
		else:
			_done_preprocessing_assets()


func _preprocess_second_pass():
	var second_pass = _preprocessing_second_pass
	_preprocessing_second_pass = [].duplicate()
	var pkgassets: Array = [].duplicate()
	for ti2 in second_pass:
		var path = ti2.get_tooltip_text(0)  # HACK! No data field in TreeItem?? Let's use the tooltip?!
		var asset = pkg.path_to_pkgasset.get(path)
		_currently_preprocessing_assets += 1
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
	assert(action_name == "show_result")
	self._keep_open_on_import = true
	_asset_tree_window_confirmed()


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
	asset_database.log_debug([null, 0, "", 0], "TICK ======= " + str(import_step_tick_count))
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
		call_deferred(&"on_import_fully_completed")
	asset_database.log_debug([null, 0, "", 0], "TICK RETURN ======= " + str(import_step_tick_count))
	import_step_reentrant = false


func _scan_sources_complete(useless: Variant = null):
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
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
	EditorPlugin.new().get_editor_interface().get_base_control().add_child(import_step_timer, true)
	import_step_timer.timeout.connect(self._do_import_step_tick)


func _preprocess_wait_tick():
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
	if _currently_preprocessing_assets == 0 and not editor_filesystem.is_scanning():
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
	main_dialog_tree.columns = 5
	#main_dialog_tree.set_column_title(2, "\u26a0") # Warning emoji
	#main_dialog_tree.set_column_title(3, "\u26d4") # Error emoji
	main_dialog_tree.set_column_title(2, "Logs")
	main_dialog_tree.set_column_clip_content(2, true)
	main_dialog_tree.set_column_clip_content(3, true)
	main_dialog_tree.set_column_clip_content(4, true)
	main_dialog_tree.set_column_custom_minimum_width(2, 64)
	main_dialog_tree.set_column_custom_minimum_width(3, 64)
	main_dialog_tree.set_column_custom_minimum_width(4, 64)
	main_dialog_tree.set_column_expand(2, false)
	main_dialog_tree.set_column_expand(3, false)
	main_dialog_tree.set_column_expand(4, false)
	main_dialog_tree.set_column_expand_ratio(2, 0.1)
	main_dialog_tree.set_column_expand_ratio(3, 0.1)
	main_dialog_tree.set_column_expand_ratio(4, 0.1)

	if import_finished:
		if main_dialog:
			main_dialog.hide()
		return
	if tree_dialog_state != STATE_DIALOG_SHOWING:
		return

	_prune_unselected_items(main_dialog_tree.get_root())
	result_log_lineedit.visible = true 

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
	EditorPlugin.new().get_editor_interface().get_base_control().add_child(preprocess_timer, true)
	preprocess_timer.timeout.connect(self._preprocess_wait_tick)
	if num_processing == 0:
		asset_database.log_debug([null, 0, "", 0], "No assets to process!")
		_done_preprocessing_assets()
		return
