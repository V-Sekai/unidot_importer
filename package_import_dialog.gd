@tool
extends RefCounted

const unitypackagefile: GDScript = preload("./unitypackagefile.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const import_worker_class: GDScript = preload("./import_worker.gd")
const meta_worker_class: GDScript = preload("./meta_worker.gd")
const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
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
var meta_worker = meta_worker_class.new()
var asset_adapter = asset_adapter_class.new()

var main_dialog: AcceptDialog = null
var file_dialog: FileDialog = null
var main_dialog_tree: Tree = null

var spinner_icon: AnimatedTexture = null
var spinner_icon1: Texture = null
var fail_icon: Texture = null

var checkbox_off_unicode: String = "\u2610"
var checkbox_on_unicode: String = "\u2611"

var tmpdir: String = ""
var asset_database: Resource = null

var tree_dialog_state: int = 0
var _currently_preprocessing_assets: int = 0
var _preprocessing_second_pass: Array = []
var retry_tex: bool = false
var _keep_open_on_import: bool = false
var import_finished: bool = false
var force_reimport_models_checkbox: CheckBox = null

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

var pkg: Object = null  # Type unitypackagefile, set in _selected_package


func _resource_reimported(resources: PackedStringArray):
	if import_finished or tree_dialog_state == STATE_DIALOG_SHOWING or tree_dialog_state == STATE_DONE_IMPORT:
		return
	asset_database.log_debug([null,0,"",0], "RESOURCES REIMPORTED ============")
	for res in resources:
		asset_database.log_debug([null,0,"",0], res)
	asset_database.log_debug([null,0,"",0], "=================================")


func _resource_reloaded(resources: PackedStringArray):
	if import_finished or tree_dialog_state == STATE_DIALOG_SHOWING or tree_dialog_state == STATE_DONE_IMPORT:
		return
	asset_database.log_debug([null,0,"",0], "Got a RESOURCES RELOADED ============")
	for res in resources:
		asset_database.log_debug([null,0,"",0], res)
	asset_database.log_debug([null,0,"",0], "=====================================")


func _init():
	meta_worker.asset_processing_finished.connect(self._meta_completed, CONNECT_DEFERRED)
	import_worker.asset_processing_finished.connect(self._asset_processing_finished, CONNECT_DEFERRED)
	import_worker.asset_processing_started.connect(self._asset_processing_started, CONNECT_DEFERRED)
	tmpdir = asset_adapter.create_temp_dir()
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
	editor_filesystem.resources_reimported.connect(self._resource_reimported)
	editor_filesystem.resources_reload.connect(self._resource_reloaded)


func _check_recursively(ti: TreeItem, is_checked: bool) -> void:
	if ti.is_selectable(0):
		ti.set_checked(0, is_checked)
	#var old_prefix: String = (checkbox_on_unicode if !is_checked else checkbox_off_unicode)
	#var new_prefix: String  = (checkbox_on_unicode if is_checked else checkbox_off_unicode)
	#ti.set_text(0, new_prefix + ti.get_text(0).substr(len(old_prefix)))
	for chld in ti.get_children():
		_check_recursively(chld, is_checked)


func _cell_selected() -> void:
	var ti: TreeItem = main_dialog_tree.get_selected()
	var col: int = main_dialog_tree.get_selected_column()
	ti.deselect(col)
	if ti != null:  # and col == 1:
		var new_checked: bool = !ti.is_checked(0)
		_check_recursively(ti, new_checked)

func _meta_completed(tw: Object):
	var pkgasset = tw.asset
	var ti = tw.extra as TreeItem
	var importer_type: String = ""
	if pkgasset.parsed_meta != null:
		importer_type = pkgasset.parsed_meta.importer_type.replace("Importer", "")
	ti.set_text(1, importer_type.replace("Default", "Scene"))
	
	var color = Color(
		0.7 * fmod(importer_type.unicode_at(0)*173.0/255.0, 1.0),
		0.7 * fmod(importer_type.unicode_at(1)*139.0/255.0, 1.0),
		0.7 * fmod(importer_type.unicode_at(2)*157.0/255.0, 1.0),
		1.0)
	ti.set_custom_color(1, color)


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
	asset_database.in_package_import = true
	asset_database.log_debug([null,0,"",0], "Asset database object returned " + str(asset_database))
	meta_worker.start_threads(THREAD_COUNT)  # Don't DISABLE_THREADING

	var tree_names = ["Assets"]
	var ti: TreeItem = main_dialog_tree.create_item()
	ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	ti.set_text(0, "Assets")
	ti.set_checked(0, true)
	ti.set_icon_max_width(0, 24)
	ti.set_text(1, "")
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
			asset_database.log_fail([null,0,"",0], "Path outside of Assets: " + path)
			break
		while i < len(path_names) - 1:
			i += 1
			tree_names.push_back(path_names[i])
			ti = main_dialog_tree.create_item(tree_items[i - 1])
			tree_items.push_back(ti)
			ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			if DISABLE_TEXTURES and (path.to_lower().ends_with("png") or path.to_lower().ends_with("jpg")):
				ti.set_checked(0, false)
				ti.set_selectable(0, false)
			else:
				ti.set_checked(0, true)
				ti.set_selectable(0, true)
			if i == len(path_names) - 1:
				ti.set_tooltip_text(0, path)
			ti.set_icon_max_width(0, 24)
			#ti.set_custom_color(0, Color.DARK_BLUE)
			var icon: Texture = pkgasset.icon
			if icon != null:
				ti.set_icon(0, icon)
				# ti.add_button(0, spinner_icon1, -1, true)
			ti.set_text(0, path_names[i])
			if i == len(path_names) - 1:
				meta_worker.push_asset(pkgasset, ti)
				ti.set_text(1, "")
			else:
				ti.set_text(1, "Directory")
	main_dialog.popup_centered_ratio()
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null


func show_reimport() -> void:
	file_dialog = null
	_show_importer_common()
	self._selected_package("")


func show_importer() -> void:
	file_dialog = FileDialog.new()
	file_dialog.set_title("Import Unity Package...")
	file_dialog.add_filter("*.unitypackage")
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# FILE_MODE_OPEN_FILE = 0  –  The dialog allows selecting one, and only one file.
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(self._selected_package)
	EditorPlugin.new().get_editor_interface().get_base_control().add_child(file_dialog, true)
	_show_importer_common()


func _show_importer_common() -> void:
	main_dialog = AcceptDialog.new()
	main_dialog.title = "Select Assets to import"
	main_dialog.dialog_hide_on_ok = false
	main_dialog.confirmed.connect(self._asset_tree_window_confirmed)
	# "cancelled" ????
	main_dialog.add_cancel_button("Hide")
	main_dialog.add_button("Import and show result", false, "show_result")
	main_dialog.custom_action.connect(self._asset_tree_window_confirmed_custom)
	var n: Label = main_dialog.get_label()
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_FILL
	vbox.size_flags_horizontal = Control.SIZE_FILL
	main_dialog_tree = Tree.new()
	main_dialog_tree.columns = 2
	main_dialog_tree.set_column_titles_visible(true)
	main_dialog_tree.set_column_title(0, "Path")
	main_dialog_tree.set_column_title(1, "Importer")
	main_dialog_tree.cell_selected.connect(self._cell_selected)
	main_dialog_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_dialog_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_dialog_tree.size_flags_stretch_ratio = 1.0
	vbox.add_child(main_dialog_tree)
	force_reimport_models_checkbox = CheckBox.new()
	force_reimport_models_checkbox.text = "Force reimport all models"
	force_reimport_models_checkbox.size_flags_vertical = Control.SIZE_SHRINK_END
	force_reimport_models_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_reimport_models_checkbox.size_flags_stretch_ratio = 0.0
	vbox.add_child(force_reimport_models_checkbox)
	n.add_sibling(vbox)
	EditorPlugin.new().get_editor_interface().get_base_control().add_child(main_dialog, true)

	tree_dialog_state = STATE_DIALOG_SHOWING

	_keep_open_on_import = false
	import_finished = false
	if file_dialog != null:
		file_dialog.popup_centered_ratio()

	var base_control = EditorPlugin.new().get_editor_interface().get_base_control()
	fail_icon = base_control.get_theme_icon("ImportFail", "EditorIcons")
	spinner_icon1 = base_control.get_theme_icon("Progress1", "EditorIcons")
	spinner_icon = AnimatedTexture.new()
	for i in range(8):
		# was get_icon in 3.2
		var progress_icon = base_control.get_theme_icon("Progress" + str(i + 1), "EditorIcons")
		if progress_icon == null:
			asset_database.log_fail([null,0,"",0], "Failed to get icon!")
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
	import_finished = true
	if not _keep_open_on_import:
		if main_dialog:
			main_dialog.queue_free()
			main_dialog = null


func update_task_color(tw: RefCounted):
	var ti: TreeItem = tw.extra
	if tw.asset.parsed_meta == null:
		ti.set_custom_color(0, Color("#ddffbb"))
	elif not tw.is_loaded:
		ti.set_custom_color(0, Color("#ff4422"))
	else:
		var holder = tw.asset.parsed_meta.log_message_holder
		if holder.has_fails():
			ti.set_custom_color(0, Color("#ff8822"))
		elif holder.has_warnings():
			ti.set_custom_color(0, Color("#ccff22"))
		else:
			ti.set_custom_color(0, Color("#22ff44"))


func on_file_completed_godot_import(tw: RefCounted, loaded: bool):
	var ti: TreeItem = tw.extra
	if ti.get_button_count(0) > 0:
		ti.erase_button(0, 0)
	update_task_color(tw)
	asset_work_completed.append(tw)


func do_import_step():
	if _currently_preprocessing_assets != 0:
		asset_database.log_fail([null,0,"",0], "Import step called during preprocess")
		return
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()

	for tw in asset_work_completed:
		update_task_color(tw)

	if tree_dialog_state >= STATE_DONE_IMPORT:
		asset_database.save()
		editor_filesystem.scan()
		on_import_fully_completed()
		return

	asset_database.log_debug([null,0,"",0], "Scanning percentage: " + str(editor_filesystem.get_scanning_progress()))
	while len(asset_work_waiting_scan) == 0 and len(asset_work_waiting_write) == 0:
		asset_database.save()
		asset_database.log_debug([null,0,"",0], "Trying to scan more things: state=" + str(tree_dialog_state))
		if tree_dialog_state == STATE_PREPROCESSING:
			tree_dialog_state = STATE_TEXTURES
			for tw in asset_textures:
				asset_work_waiting_write.append(tw)
			asset_work_waiting_write.reverse()
			asset_textures = [].duplicate()
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
			asset_database.log_debug([null,0,"",0], "Toposorted prefab dependencies: " + str(tmpprint))
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
			asset_database.log_fail([null,0,"",0], "Invalid state: " + str(tree_dialog_state))
			break

	var start_ts = Time.get_ticks_msec()
	while not asset_work_waiting_write.is_empty():
		var tw: Object = asset_work_waiting_write.pop_back()
		start_godot_import(tw)
		if not asset_adapter.uses_godot_importer(tw.asset):
			var ticks_ts = Time.get_ticks_msec()
			if ticks_ts > start_ts + 300:
				break

	var asset_work = asset_work_waiting_scan
	asset_database.log_debug([null,0,"",0], "Queueing work: state=" + str(tree_dialog_state))
	var files_to_reimport: PackedStringArray = PackedStringArray().duplicate()
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
		on_file_completed_godot_import(tw, loaded_asset != null)

	asset_database.log_debug([null,0,"",0], "Done Queueing work: state=" + str(tree_dialog_state))


func _done_preprocessing_assets():
	asset_database.log_debug([null,0,"",0], "Finished all preprocessing!!")
	self.import_worker.stop_all_threads_and_wait()
	asset_database.log_debug([null,0,"",0], "Joined.")
	asset_database.save()
	#asset_adapter.write_sentinel_png(generate_sentinel_png_filename())


func start_godot_import(tw: Object):
	#var meta_data: PackedByteArray = tw.asset.metadata_tar_header.get_data()
	#var metafil = FileAccess.open("res://" + tmpdir + "/" + tw.asset.pathname + ".meta", FileAccess.WRITE_READ)
	#metafil.store_buffer(meta_data)
	#metafil.flush()
	#metafil = null
	var asset_modified: bool = asset_adapter.write_godot_asset(tw.asset, tmpdir + "/" + tw.output_path)
	var import_modified: bool = asset_adapter.write_godot_import(tw.asset)
	tw.asset.log_debug(
		(
			"Wrote file "
			+ tw.output_path
			+ " asset modified:"
			+ str(asset_modified)
			+ " import modified:"
			+ str(import_modified)
		)
	)

	var force_reimport: bool = false
	if (
		asset_adapter.get_asset_type(tw.asset) == asset_adapter.ASSET_TYPE_MODEL
		and force_reimport_models_checkbox.button_pressed
	):
		force_reimport = true
	if asset_database.get_meta_at_path(tw.asset.parsed_meta.path) == null:
		tw.asset.log_warn("Asset " + str(tw.asset.parsed_meta.guid) + " alraedy existed in project but not in database.")
		force_reimport = true

	if not asset_modified and not import_modified and not force_reimport:
		tw.asset.log_debug("We can skip this file!")
		var ti: TreeItem = tw.extra
		if ti.get_button_count(0) > 0:
			ti.erase_button(0, 0)
		ti.set_custom_color(0, Color("#22bb66"))
		return

	if asset_adapter.uses_godot_importer(tw.asset):
		asset_database.insert_meta(tw.asset.parsed_meta)
	asset_work_waiting_scan.push_back(tw)


func _asset_processing_finished(tw: Object):
	_currently_preprocessing_assets -= 1
	tw.asset.log_debug(str(tw.asset) + " preprocess finished!")
	var ti: TreeItem = tw.extra
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
	tw.asset.log_debug("For guid " + str(tw.asset.guid) + ": internal_data=" + str(tw.asset.parsed_meta.internal_data))
	tw.asset.log_debug(
		(
			"Finished processing meta path "
			+ str(tw.asset.parsed_meta.path)
			+ " guid "
			+ str(tw.asset.parsed_meta.guid)
			+ " opath "
			+ str(tw.output_path)
		)
	)
	if not asset_adapter.uses_godot_importer(tw.asset):
		asset_database.insert_meta(tw.asset.parsed_meta)
	if tw.asset.asset_tar_header != null:
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
	asset_database.log_debug([null,0,tw.asset.guid,0], "Started processing asset is " + str(tw.asset.pathname) + "/" + str(tw.asset.guid))
	var ti: TreeItem = tw.extra
	if tw.asset.parsed_meta != null:
		tw.asset.parsed_meta.clear_logs()
	ti.set_custom_color(0, Color("#228888"))


func _preprocess_recursively(ti: TreeItem, visited: Dictionary, second_pass: Array) -> int:
	var ret: int = 0
	if ti.is_checked(0):
		var path = ti.get_tooltip_text(0)  # HACK! No data field in TreeItem?? Let's use the tooltip?!
		if not path.is_empty():
			var asset = pkg.path_to_pkgasset.get(path)
			if asset == null:
				asset_database.log_fail([null,0,"",0], "Path " + str(path) + " has null asset!")
			else:
				ret += 1
				if not asset.parsed_meta.meta_dependency_guids.is_empty():
					asset.parsed_meta.log_debug(0, "Meta has dependencies " + str(asset.parsed_meta.dependency_guids))
					second_pass.append(ti)
				else:
					_currently_preprocessing_assets += 1
					var tw: RefCounted = self.import_worker.push_asset(asset, tmpdir, ti)
				# ti.set_cell_mode(0, TreeItem.CELL_MODE_ICON)
				if ti.get_button_count(0) <= 0:
					ti.add_button(0, spinner_icon, -1, true, "Loading...")
	for chld in ti.get_children():
		ret += _preprocess_recursively(chld, visited, second_pass)
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
		asset_database.log_debug([null,0,"",0], "Still working...")
		# We can safely ignore reentrant ticks.
		# it is healthy and normal to get ticked while displaying the progress bar for reimport_files.
		# asset_database.log_debug([null,0,"",0], "reentrant TICK ======= " + str(import_step_tick_count))
		return
	import_step_reentrant = true
	import_step_tick_count += 1
	asset_database.log_debug([null,0,"",0], "TICK ======= " + str(import_step_tick_count))
	OS.close_midi_inputs()  # Place to set C++ breakpoint to check for reentrancy
	do_import_step()
	if tree_dialog_state >= STATE_DONE_IMPORT:
		import_step_timer.timeout.disconnect(self._do_import_step_tick)
		import_step_timer.queue_free()
		import_step_timer = null
		asset_database.log_debug([null,0,"",0], "All done")
		asset_database.in_package_import = false
		asset_database.save()
		asset_database.log_debug([null,0,"",0], "Saved database")
		var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
		editor_filesystem.scan()
		call_deferred(&"on_import_fully_completed")
	asset_database.log_debug([null,0,"",0], "TICK RETURN ======= " + str(import_step_tick_count))
	import_step_reentrant = false


func _scan_sources_complete(useless: Variant = null):
	var editor_filesystem: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
	editor_filesystem.sources_changed.disconnect(self._scan_sources_complete)
	asset_database.log_debug([null,0,"",0], "Reimporting sentinel to wait for import step to finish.")
	editor_filesystem.reimport_files(PackedStringArray(["res://_sentinel_file.png"]))
	asset_database.log_debug([null,0,"",0], "Got signal that scan_sources is complete.")
	for tw in asset_all:
		if not asset_adapter.uses_godot_importer(tw.asset):
			continue
		var filename: String = tw.asset.pathname
		asset_database.log_debug([null,0,tw.asset.guid,0], filename + ":" + str(editor_filesystem.get_file_type(filename)))
		var fs_dir: EditorFileSystemDirectory = editor_filesystem.get_filesystem_path(filename.get_base_dir())
		if fs_dir == null:
			asset_database.log_fail([null,0,tw.asset.guid,0], "BADBAD: Filesystem directory null for " + str(filename))
		else:
			asset_database.log_debug([null,0,tw.asset.guid,0], "Dir " + str(filename.get_base_dir()) + " file count: " + str(fs_dir.get_file_count()))
			var idx = fs_dir.find_file_index(filename.get_file())
			if idx == -1:
				asset_database.log_fail([null,0,tw.asset.guid,0], "BADBAD: Index is -1 for " + str(filename))
			else:
				asset_database.log_debug([null,0,tw.asset.guid,0], "Import " + str(fs_dir.get_file(idx)) + " valid: " + str(fs_dir.get_file_import_is_valid(idx)))
	asset_database.log_debug([null,0,"",0], "Ready to start import step ticks")

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
		asset_database.log_debug([null,0,"",0], "Done preprocessing. ready to trigger scan_sources!")
		preprocess_timer.timeout.disconnect(self._preprocess_wait_tick)
		preprocess_timer.queue_free()
		preprocess_timer = null
		var cfile = ConfigFile.new()
		cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
		cfile.set_value("remap", "importer", "keep")
		cfile.save("res://_sentinel_file.png.import")
		asset_database.log_debug([null,0,"",0], "Writing res://_sentinel_file.png")
		asset_adapter.write_sentinel_png("res://_sentinel_file.png")
		editor_filesystem.sources_changed.connect(self._scan_sources_complete, CONNECT_DEFERRED)
		editor_filesystem.scan_sources()


func _asset_tree_window_confirmed():
	if import_finished:
		if main_dialog:
			main_dialog.queue_free()
			main_dialog = null
		return
	if tree_dialog_state != STATE_DIALOG_SHOWING:
		return

	asset_database.log_debug([null,0,"",0], "Finishing meta.")
	meta_worker.stop_all_threads_and_wait()
	asset_database.log_debug([null,0,"",0], "Joined meta.")
	tree_dialog_state = STATE_PREPROCESSING
	import_worker.asset_database = asset_database
	asset_database.in_package_import = true
	asset_database.log_debug([null,0,"",0], "Asset database object returned " + str(asset_database))
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
		asset_database.log_debug([null,0,"",0], "No assets to process!")
		_done_preprocessing_assets()
		return
