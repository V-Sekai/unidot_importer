@tool
extends Reference

const unitypackagefile: GDScript = preload("./unitypackagefile.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const import_worker_class: GDScript = preload("./import_worker.gd")
const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
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
	if is_checked:
		if ti.get_button_count(0) <= 0:
			# ti.set_cell_mode(0, TreeItem.CELL_MODE_ICON)
			ti.add_button(0, spinner_icon, -1, true, "Loading...")
			ti.set_custom_color(0, Color("#888822"))
	#var old_prefix: String = (checkbox_on_unicode if !is_checked else checkbox_off_unicode)
	#var new_prefix: String  = (checkbox_on_unicode if is_checked else checkbox_off_unicode)
	#ti.set_text(0, new_prefix + ti.get_text(0).substr(len(old_prefix)))
	var chld = ti.get_children()
	while chld != null:
		_check_recursively(chld, is_checked)
		chld = chld.get_next()

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
			printerr("Path outside of Assets: " + path)
			break
		while i < len(path_names) - 1:
			i += 1
			tree_names.push_back(path_names[i])
			ti = main_dialog_tree.create_item(tree_items[i - 1])
			tree_items.push_back(ti)
			ti.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			ti.set_checked(0, true)
			ti.set_selectable(0, true)
			ti.set_tooltip(0, path)
			ti.set_icon_max_width(0, 24)
			#ti.set_custom_color(0, Color.darkblue)
			var icon: Texture = pkg.path_to_pkgasset[path].icon
			if (icon != null):
				ti.set_icon(0, icon)
				# ti.add_button(0, spinner_icon1, -1, true)
			ti.set_text(0, path_names[i])
	main_dialog.popup_centered_ratio()

func show_importer() -> void:
	#printerr("PKG IMPORT DIALOG INIT BEFORE " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface() if static_storage_singleton != null else null))
	#if static_storage_singleton == null:
	#	static_storage_singleton = static_storage.new().singleton()
	#static_storage.new().set_singleton(static_storage_singleton)
	#printerr("PKG IMPORT DIALOG INIT AFTER " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))
	file_dialog = FileDialog.new()
	file_dialog.set_title("Import Unity Package...")
	file_dialog.add_filter("*.unitypackage")
	#file_dialog.mode = FileDialog.FILE_MODE_OPEN_FILE
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
	main_dialog.add_cancel_button("Cancel")
	var n: Label = main_dialog.get_label()
	main_dialog_tree = Tree.new()
	main_dialog_tree.set_column_titles_visible(false)
	main_dialog_tree.connect("cell_selected", self._cell_selected)
	n.add_sibling(main_dialog_tree)
	static_storage.new().get_editor_interface().get_editor_main_control().add_child(main_dialog)
	#static_storage.new().get_editor_interface().get_editor_viewport().add_child(main_dialog)

	tree_dialog_state = STATE_DIALOG_SHOWING

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
			printerr("Failed to get icon!")
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
	return "_unityimp_temp" + str(tree_dialog_state) + ".png"

var _delay_tick: int = 0

func _editor_filesystem_scan_tick():
	if tree_dialog_state == STATE_DIALOG_SHOWING:
		return
	if tree_dialog_state >= STATE_DONE_IMPORT:
		timer.queue_free()
		timer = null
	if static_storage.new().get_resource_filesystem().is_scanning():
		print("Still Scanning... Percentage: " + str(static_storage.new().get_resource_filesystem().get_scanning_progress()))
		return
	var dres = Directory.new()
	dres.open("res://")
	if not dres.file_exists(generate_sentinel_png_filename() + ".import"):
		print(generate_sentinel_png_filename() + ".import" + " not created yet...")
		static_storage.new().get_resource_filesystem().scan()
		return

	if _delay_tick < 20:
		_delay_tick += 1
		return
	_delay_tick = 0

	var completed_scan: Array = asset_work_currently_scanning
	for tw in completed_scan:
		print("Asset " + tw.asset.pathname + "/" + tw.asset.guid + " completed import.")
		var loaded_asset = load(tw.asset.pathname)
		if loaded_asset != null:
			tw.asset.parsed_meta.insert_resource(tw.asset.parsed_meta.main_object_id, loaded_asset)
	asset_work_currently_scanning = [].duplicate()

	print("Scanning percentage: " + str(static_storage.new().get_resource_filesystem().get_scanning_progress()))
	while len(asset_work_waiting_scan) == 0 and len(asset_work_currently_scanning) == 0 and _currently_preprocessing_assets == 0:
		dres.remove(generate_sentinel_png_filename() + ".import")
		dres.remove(generate_sentinel_png_filename())
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
			for tw in asset_prefabs:
				start_godot_import(tw)
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
			printerr("Invalid state: " + str(tree_dialog_state))
			break

	var asset_work = asset_work_waiting_scan
	print("Queueing work: state=" + str(tree_dialog_state))
	#for tw in asset_work:
	#	static_storage.new().get_resource_filesystem().update_file(tw.asset.pathname)
	for tw in asset_work:
		asset_work_currently_scanning.push_back(tw)
	asset_work_waiting_scan = [].duplicate()
	asset_adapter.write_sentinel_png(generate_sentinel_png_filename())

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
	print("I FINISHED PREPROCESSING EVERYTHING!!")
	self.import_worker.stop_all_threads_and_wait()
	print("Joined.")
	asset_database.save()
	asset_adapter.write_sentinel_png(generate_sentinel_png_filename())
	# static_storage.new().get_resource_filesystem().scan() # We wait for the next timer for this now.

func _asset_failed(tw: Object):
	_currently_preprocessing_assets -= 1
	printerr(str(tw.asset) + " preprocess failed!")
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
	ti.set_custom_color(0, Color("#228822"))
	ti.erase_button(0, 0)
	if tw.asset.parsed_meta == null:
		tw.asset.parsed_meta = asset_database.create_dummy_meta(tw.asset.guid)
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
	ti.set_custom_color(0, Color("#888822"))

func _preprocess_recursively(ti: TreeItem) -> int:
	var ret: int = 0
	if ti.is_checked(0):
		if ti.get_button_count(0) <= 0:
			ti.add_button(0, spinner_icon, -1, true, "Loading...")
		var path = ti.get_tooltip(0) # HACK! No data field in TreeItem?? Let's use the tooltip?!
		var asset = pkg.path_to_pkgasset.get(path)
		if asset == null:
			printerr("Path " + str(path) + " has null asset!")
		else:
			ret += 1
			_currently_preprocessing_assets += 1
			self.import_worker.push_asset(asset, tmpdir, ti)
	var chld: TreeItem = ti.get_children()
	while chld != null:
		ret += _preprocess_recursively(chld)
		chld = chld.get_next()
	return ret


func _asset_tree_window_confirmed():
	if tree_dialog_state != STATE_DIALOG_SHOWING:
		return
	tree_dialog_state = STATE_PREPROCESSING
	asset_database = asset_database_class.get_singleton()
	import_worker.start_threads(0) # DISABLE_THREADING
	var num_processing = _preprocess_recursively(main_dialog_tree.get_root())
	if num_processing == 0:
		print("No assets to process!")
		_done_preprocessing_assets()

