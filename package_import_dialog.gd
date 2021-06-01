@tool
extends Reference

const unitypackagefile: GDScript = preload("./unitypackagefile.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const import_worker_class: GDScript = preload("./import_worker.gd")
const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
const asset_meta_class: GDScript = preload("./asset_meta.gd")
const static_storage: GDScript = preload("./static_storage.gd")

const STATE_DIALOG_SHOWING = 0
const STATE_PREPROCESSING = 1
const STATE_TEXTURES = 2
const STATE_IMPORTING_MATERIALS_AND_ASSETS = 3
const STATE_IMPORTING_MODELS = 4
const STATE_IMPORTING_PREFABS = 5
const STATE_IMPORTING_SCENES = 6
const STATE_DONE_IMPORT = 7

var import_worker = import_worker_class.new()
var asset_adapter = asset_adapter_class.new()

var main_dialog : AcceptDialog = null
var file_dialog : FileDialog = null
var main_dialog_tree: Tree = null
var timer: Timer = null

var spinner_icon : AnimatedTexture = null
var spinner_icon1 : Texture = null
var fail_icon: Texture = null

var checkbox_off_unicode: String = "\u2610"
var checkbox_on_unicode: String = "\u2611"

var tmpdir: String = ""
var asset_database: Resource = null

var tree_dialog_state: int = 0
var _currently_preprocessing_assets: int = 0
var retry_tex: bool = false
var _keep_open_on_import: bool = false
var import_finished: bool = false

var asset_work_waiting_scan: Array = [].duplicate()
var asset_work_currently_scanning: Array = [].duplicate()

var asset_textures: Array = [].duplicate()
var asset_materials_and_other: Array = [].duplicate()
var asset_models: Array = [].duplicate()
var asset_prefabs: Array = [].duplicate()
var asset_scenes: Array = [].duplicate()

var pkg: Object = null # Type unitypackagefile, set in _selected_package

func _init():
	import_worker.connect("asset_failed", self._asset_failed, [], CONNECT_DEFERRED)
	import_worker.connect("asset_processing_finished", self._asset_processing_finished, [], CONNECT_DEFERRED)
	import_worker.connect("asset_processing_started", self._asset_processing_started, [], CONNECT_DEFERRED)
	tmpdir = asset_adapter.create_temp_dir()
	static_storage.new().get_resource_filesystem().connect("sources_changed", self._editor_filesystem_scan_check)

func _check_recursively(ti: TreeItem, is_checked: bool) -> void:
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
	if ti != null: # and col == 1:
		var new_checked: bool = !ti.is_checked(0)
		_check_recursively(ti, new_checked)

func _selected_package(p_path: String) -> void:
	pkg = unitypackagefile.new().init_with_filename(p_path)
	var tree_names = ['Assets']
	var ti: TreeItem = main_dialog_tree.create_item()
	ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	ti.set_text(0, "Assets")
	ti.set_checked(0, true)
	ti.set_icon_max_width(0, 24)
	var tree_items = [ti]
	for path in pkg.paths:
		var path_names: Array = path.split('/')
		var i: int = len(tree_names) - 1
		while i >= 0 and (i >= len(path_names) or path_names[i] != tree_names[i]):
			#print("i=" + str(i) + "/" + str(len(path_names)) + "/" + str(tree_names[i]))
			tree_names.pop_back()
			tree_items.pop_back()
			i -= 1
		if i < 0:
			push_error("Path outside of Assets: " + path)
			break
		while i < len(path_names) - 1:
			i += 1
			tree_names.push_back(path_names[i])
			ti = main_dialog_tree.create_item(tree_items[i - 1])
			tree_items.push_back(ti)
			ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			ti.set_checked(0, true)
			ti.set_selectable(0, true)
			if i == len(path_names) - 1:
				ti.set_tooltip(0, path)
			ti.set_icon_max_width(0, 24)
			#ti.set_custom_color(0, Color.DARK_BLUE)
			var icon: Texture = pkg.path_to_pkgasset[path].icon
			if (icon != null):
				ti.set_icon(0, icon)
				# ti.add_button(0, spinner_icon1, -1, true)
			ti.set_text(0, path_names[i])
	main_dialog.popup_centered_ratio()
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null

func show_importer() -> void:
	#push_error("PKG IMPORT DIALOG INIT BEFORE " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface() if static_storage_singleton != null else null))
	#if static_storage_singleton == null:
	#	static_storage_singleton = static_storage.new().singleton()
	#static_storage.new().set_singleton(static_storage_singleton)
	#push_error("PKG IMPORT DIALOG INIT AFTER " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))
	file_dialog = FileDialog.new()
	file_dialog.set_title("Import Unity Package...")
	file_dialog.add_filter("*.unitypackage")
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	# FILE_MODE_OPEN_FILE = 0  –  The dialog allows selecting one, and only one file.
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.connect("file_selected", self._selected_package)
	static_storage.new().get_editor_interface().get_editor_main_control().add_child(file_dialog)
	#static_storage.new().get_editor_interface().get_editor_viewport().add_child(file_dialog)
	
	main_dialog = AcceptDialog.new()
	main_dialog.title = "Select Assets to import"
	main_dialog.dialog_hide_on_ok = false
	main_dialog.connect("confirmed", self._asset_tree_window_confirmed)
	# "cancelled" ????
	main_dialog.add_cancel_button("Hide")
	main_dialog.add_button("Import and show result", false, "show_result")
	main_dialog.connect("custom_action", self._asset_tree_window_confirmed_custom)
	var n: Label = main_dialog.get_label()
	main_dialog_tree = Tree.new()
	main_dialog_tree.set_column_titles_visible(false)
	main_dialog_tree.connect("cell_selected", self._cell_selected)
	n.add_sibling(main_dialog_tree)
	static_storage.new().get_editor_interface().get_editor_main_control().add_child(main_dialog)
	#static_storage.new().get_editor_interface().get_editor_viewport().add_child(main_dialog)

	tree_dialog_state = STATE_DIALOG_SHOWING

	_keep_open_on_import = false
	import_finished = false
	file_dialog.popup_centered_ratio()
	timer = Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	timer.process_mode = Timer.TIMER_PROCESS_IDLE
	static_storage.new().get_editor_interface().get_editor_main_control().add_child(timer)
	timer.connect("timeout", self._editor_filesystem_scan_tick)

	var base_control = static_storage.new().get_editor_interface().get_base_control()
	fail_icon = base_control.get_theme_icon("ImportFail", "EditorIcons")
	spinner_icon1 = base_control.get_theme_icon("Progress1", "EditorIcons")
	spinner_icon = AnimatedTexture.new()
	for i in range(8):
		# was get_icon in 3.2
		var progress_icon = base_control.get_theme_icon("Progress" + str(i + 1), "EditorIcons")
		if progress_icon == null:
			push_error("Failed to get icon!")
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

func on_file_completed_godot_import(tw: Reference, loaded: bool):
	var ti: TreeItem = tw.extra
	if ti.get_button_count(0) > 0:
		ti.erase_button(0, 0)
	if loaded:
		ti.set_custom_color(0, Color("#228822"))
	else:
		ti.set_custom_color(0, Color("#ff4422"))

func _editor_filesystem_scan_tick():
	if tree_dialog_state == STATE_DIALOG_SHOWING:
		return
	if static_storage.new().get_resource_filesystem().is_scanning():
		print("Still Scanning... Percentage: " + str(static_storage.new().get_resource_filesystem().get_scanning_progress()))
		return

	if _currently_preprocessing_assets != 0:
		print("Scanning percentage: " + str(static_storage.new().get_resource_filesystem().get_scanning_progress()))
		return

	var dres = Directory.new()
	dres.open("res://")
	if not dres.file_exists(generate_sentinel_png_filename() + ".import"):
		print(generate_sentinel_png_filename() + ".import" + " not created yet...")
		static_storage.new().get_resource_filesystem().scan()
		return

	if _delay_tick < 3:
		_delay_tick += 1
		return
	_delay_tick = 0

	print("Removing " + str(generate_sentinel_png_filename()))
	dres.remove(generate_sentinel_png_filename() + ".import")
	dres.remove(generate_sentinel_png_filename())

	if not retry_tex:
		retry_tex = true
		print("Writing " + str(generate_sentinel_png_filename()))
		asset_adapter.write_sentinel_png(generate_sentinel_png_filename())
		return

	if tree_dialog_state >= STATE_DONE_IMPORT:
		asset_database.save()
		static_storage.new().get_resource_filesystem().scan()
		on_import_fully_completed()
		timer.queue_free()
		timer = null
	
	var completed_scan: Array = asset_work_currently_scanning
	asset_work_currently_scanning = [].duplicate()
	for tw in completed_scan:
		print("Asset " + tw.asset.pathname + "/" + tw.asset.guid + " completed import.")
		var loaded_asset: Resource = ResourceLoader.load(tw.asset.pathname, "", ResourceLoader.CACHE_MODE_REPLACE)
		#var loaded_asset: Resource = load(tw.asset.pathname)
		if loaded_asset != null:
			tw.asset.parsed_meta.insert_resource(tw.asset.parsed_meta.main_object_id, loaded_asset)
		on_file_completed_godot_import(tw, loaded_asset != null)

	print("Scanning percentage: " + str(static_storage.new().get_resource_filesystem().get_scanning_progress()))
	while len(asset_work_waiting_scan) == 0 and len(asset_work_currently_scanning) == 0 and _currently_preprocessing_assets == 0:
		asset_database.save()
		print("Trying to scan more things: state=" + str(tree_dialog_state))
		if tree_dialog_state == STATE_PREPROCESSING:
			tree_dialog_state = STATE_TEXTURES
			for tw in asset_textures:
				start_godot_import(tw)
			asset_textures = [].duplicate()
		elif tree_dialog_state == STATE_TEXTURES:
			tree_dialog_state = STATE_IMPORTING_MATERIALS_AND_ASSETS
			for tw in asset_materials_and_other:
				start_godot_import(tw)
			asset_materials_and_other = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MATERIALS_AND_ASSETS:
			tree_dialog_state = STATE_IMPORTING_MODELS
			for tw in asset_models:
				start_godot_import(tw)
			asset_models = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_MODELS:
			tree_dialog_state = STATE_IMPORTING_PREFABS
			var guid_to_meta = {}.duplicate()
			var guid_to_tw = {}.duplicate()
			for tw in asset_prefabs:
				guid_to_meta[tw.asset.guid] = tw.asset.parsed_meta
				guid_to_tw[tw.asset.guid] = tw
			var toposorted: Array = asset_meta_class.toposort_prefab_recurse_toplevel(asset_database, guid_to_meta)
			var tmpprint: Array = [].duplicate()
			for meta in toposorted:
				tmpprint.push_back(meta.path)
			print("Toposorted prefab dependencies: " + str(tmpprint))
			for meta in toposorted:
				if guid_to_tw.has(meta.guid):
					start_godot_import(guid_to_tw.get(meta.guid))
			asset_prefabs = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_PREFABS:
			tree_dialog_state = STATE_IMPORTING_SCENES
			for tw in asset_scenes:
				start_godot_import(tw)
			asset_scenes = [].duplicate()
		elif tree_dialog_state == STATE_IMPORTING_SCENES:
			tree_dialog_state = STATE_DONE_IMPORT
			break
		elif tree_dialog_state == STATE_DONE_IMPORT:
			break
		else:
			push_error("Invalid state: " + str(tree_dialog_state))
			break

	var asset_work = asset_work_waiting_scan
	print("Queueing work: state=" + str(tree_dialog_state))
	#for tw in asset_work:
	#	static_storage.new().get_resource_filesystem().update_file(tw.asset.pathname)
	for tw in asset_work:
		asset_work_currently_scanning.push_back(tw)
		var ti: TreeItem = tw.extra
		if ti.get_button_count(0) <= 0:
			ti.add_button(0, spinner_icon, -1, true, "Loading...")
	asset_work_waiting_scan = [].duplicate()
	retry_tex = false
	asset_adapter.write_sentinel_png(generate_sentinel_png_filename())
	print("Writing " + str(generate_sentinel_png_filename()))

	print("Done Queueing work: state=" + str(tree_dialog_state))
	# static_storage.new().get_resource_filesystem().scan() # We wait for the next timer for this now.

func _editor_filesystem_scan_check(path_count_unused:int = 0):
	pass
	#var more_work_to_do: bool = len(asset_work_waiting_scan) != 0 or (tree_dialog_state > STATE_DIALOG_SHOWING and tree_dialog_state < STATE_DONE_IMPORT)
	#if not static_storage.new().get_resource_filesystem().is_scanning():
	#	pass
	#if more_work_to_do:
	#	self.call_deferred("_editor_filesystem_scan_check")

func _done_preprocessing_assets():
	print("Finished all preprocessing!!")
	self.import_worker.stop_all_threads_and_wait()
	print("Joined.")
	asset_database.save()
	asset_adapter.write_sentinel_png(generate_sentinel_png_filename())
	# static_storage.new().get_resource_filesystem().scan() # We wait for the next timer for this now.

func _asset_failed(tw: Object):
	_currently_preprocessing_assets -= 1
	push_error(str(tw.asset) + " preprocess failed!")
	var ti: TreeItem = tw.extra
	ti.set_custom_color(0, Color("#222288"))
	ti.erase_button(0, 0)
	ti.add_button(0, fail_icon, -1, true, "Import Failed!")
	if _currently_preprocessing_assets == 0:
		_done_preprocessing_assets()

func start_godot_import(tw: Object):
	asset_adapter.write_godot_asset(tw.asset, tw.output_path)

	var meta_data: PackedByteArray = tw.asset.metadata_tar_header.get_data()
	var metafil = File.new()
	metafil.open("res://" + tw.asset.pathname + ".meta", File.WRITE)
	metafil.store_buffer(meta_data)
	metafil.close()
	asset_work_waiting_scan.push_back(tw)

func start_godot_import_stub(tw: Object):
	tw.asset.pathname = tw.asset.pathname.get_basename() + "." + tw.output_path.get_extension()
	if asset_adapter.write_godot_stub(tw.asset):
		asset_work_waiting_scan.push_back(tw)

func _asset_processing_finished(tw: Object):
	_currently_preprocessing_assets -= 1
	print(str(tw.asset) + " preprocess finished!")
	var ti: TreeItem = tw.extra
	ti.set_custom_color(0, Color("#888822"))
	if ti.get_button_count(0) > 0:
		ti.erase_button(0, 0)
	print("Asset database object is now " + str(asset_database))
	if tw.asset.parsed_meta == null:
		tw.asset.parsed_meta = asset_database.create_dummy_meta(tw.asset.guid)
	print("For guid " + str(tw.asset.guid) + ": internal_data=" + str(tw.asset.parsed_meta.internal_data))
	asset_database.insert_meta(tw.asset.parsed_meta)
	if tw.asset.asset_tar_header != null:
		var extn = tw.output_path.get_extension()
		var asset_type = asset_adapter.get_asset_type(tw.asset)
		if asset_type == asset_adapter.ASSET_TYPE_TEXTURE:
			asset_textures.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_MODEL:
			asset_models.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_YAML:
			asset_materials_and_other.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_PREFAB:
			asset_prefabs.push_back(tw)
		elif asset_type == asset_adapter.ASSET_TYPE_SCENE:
			asset_scenes.push_back(tw)
		else: # asset_type == asset_adapter.ASSET_TYPE_UNKNOWN:
			asset_materials_and_other.push_back(tw)
		start_godot_import_stub(tw)
		_editor_filesystem_scan_check()
	if _currently_preprocessing_assets == 0:
		_done_preprocessing_assets()

func _asset_processing_started(tw: Object):
	print("Started processing asset is " + str(tw.asset.pathname) + "/" + str(tw.asset.guid))
	var ti: TreeItem = tw.extra
	ti.set_custom_color(0, Color("#228888"))

func _preprocess_recursively(ti: TreeItem) -> int:
	var ret: int = 0
	if ti.is_checked(0):
		var path = ti.get_tooltip(0) # HACK! No data field in TreeItem?? Let's use the tooltip?!
		if path != "":
			var asset = pkg.path_to_pkgasset.get(path)
			if asset == null:
				push_error("Path " + str(path) + " has null asset!")
			else:
				ret += 1
				_currently_preprocessing_assets += 1
				var tw: Reference = self.import_worker.push_asset(asset, tmpdir, ti)
				# ti.set_cell_mode(0, TreeItem.CELL_MODE_ICON)
				if ti.get_button_count(0) <= 0:
					ti.add_button(0, spinner_icon, -1, true, "Loading...")
	for chld in ti.get_children():
		ret += _preprocess_recursively(chld)
	return ret

func _asset_tree_window_confirmed_custom(action_name):
	assert(action_name == "show_result")
	self._keep_open_on_import = true
	_asset_tree_window_confirmed()

func _asset_tree_window_confirmed():
	if import_finished:
		if main_dialog:
			main_dialog.queue_free()
			main_dialog = null
		return
	if tree_dialog_state != STATE_DIALOG_SHOWING:
		return
	tree_dialog_state = STATE_PREPROCESSING
	asset_database = asset_database_class.new().get_singleton()
	print("Asset database object returned " + str(asset_database))
	import_worker.start_threads(0) # DISABLE_THREADING
	var num_processing = _preprocess_recursively(main_dialog_tree.get_root())
	if num_processing == 0:
		print("No assets to process!")
		_done_preprocessing_assets()

