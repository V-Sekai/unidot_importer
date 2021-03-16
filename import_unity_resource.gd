@tool
extends EditorImportPlugin

const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")
const yaml_parser_class: GDScript = preload("./unity_object_parser.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
const static_storage: GDScript = preload("./static_storage.gd")

func get_importer_name():
	return "unityimp.unity_resource"

func get_visible_name():
	return "unity yaml asset importer"

func get_recognized_extensions():
	return [
		"asset",
		"mat",
		"mesh",
		# "mask",
		# "ht",
		# "playable",
		# "terrainlayer",
		"physicmaterial",
		# "overridecontroller",
		# "controller",
		#"anim",
	]

func get_save_extension():
	return "res"

func get_resource_type():
	return "Resource"

func get_preset_count():
	return 1

func get_preset_name(i):
	return "Default"

func get_option_visibility(i):
	return true

func get_import_options(i):
	return [{"name": "my_option", "default_value": false}]

func import(source_file, save_path, options, platform_variants, gen_files):
	var rel_path = source_file.replace("res://", "")
	print("Parsing scene at " + source_file)
	var asset_database = asset_database_class.get_singleton()

	var metaobj: Resource = asset_database.get_meta_at_path(rel_path)
	var f: File
	if metaobj == null:
		f = File.new()
		if f.open(source_file + ".meta", File.READ) != OK:
			metaobj = asset_database.create_dummy_meta(rel_path)
		else:
			metaobj = asset_database.parse_meta(f, rel_path)
			f.close()
		asset_database.insert_meta(metaobj)

	f = File.new()
	var e = f.open(source_file, File.READ)
	if e != OK:
		return e
	var parsed: Reference = metaobj.parse_asset(f)
	f.close()
	if e != OK:
		return e
	
	var arr: Array = [].duplicate()

	# FIXME: Numeric vs named types. we need 1-to-1 lookup table.
	# FIXME: How to get "main" asset type for a given asset?

	for asset in parsed.assets.values():
		if asset.type == "GameObject" and asset.toplevel:
			arr.push_back(asset)

	#var node_state: Object = object_adapter_class.create_node_state(asset_database, metaobj, scene_contents)
#
	#arr.sort_custom(customComparison)
	#for asset in arr:
	#	# print(str(asset) + " position " + str(asset.transform.godot_transform))
	#	asset.create_godot_node(node_state, scene_contents)
	#	#var new_node: Node3D = Node3D.new()
	#	#scene_contents.add_child(new_node)
		

	#printerr("IMPORT BEFORE " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface() if static_storage_singleton != null else null))
	#if static_storage_singleton == null:
	#	static_storage_singleton = static_storage.new().singleton()
	#static_storage.new().set_singleton(static_storage_singleton)
	#printerr("IMPORT AFTER " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))
	#var packagefile = unitypackagefile.new().init_with_filename(source_file)
	#if packagefile == null:
	#	return FAILED

	#for path in packagefile.paths:
	#	var pkgasset: Object = packagefile.path_to_pkgasset[path]
	#	asset_adapter_class.new().save_asset(pkgasset)

	var dummy = Resource.new()
	# Fill the Mesh with data read in "file", left as an exercise to the reader

	var filename = save_path + "." + get_save_extension()
	ResourceSaver.save(filename, dummy)
	return OK

