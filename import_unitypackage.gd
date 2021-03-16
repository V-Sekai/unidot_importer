@tool
extends EditorImportPlugin

var tarfile = preload("./tarfile.gd")
var unitypackagefile = preload("./unitypackagefile.gd")
var asset_adapter = preload("./unity_asset_adapter.gd").new()

const static_storage: GDScript = preload("./static_storage.gd")
#var static_storage_singleton = null

#func set_editor_interface(ei: EditorInterface):
#	print("SET EDITOR INTERFACE: " + str(self) + ":" + str(asset_adapter) + ":" + str(ei))
#	OS.set("editor_interface", ei)
#	asset_adapter.init_file_handlers(ei)
 
#func init2():
#	static_storage_singleton = static_storage.new().singleton()
#	printerr("WAT INIT2 CALLED " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))

#func _init():
#	static_storage_singleton = static_storage.new().singleton()
#	printerr("WAT INIT CALLED " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))
#func duplicate():
#	printerr("WAT DUP CALLED " + str(self))

# Steps to achieve UNITY within the UNITED states
# 
# 1. Export unitypackage with the data we want.
# 2. For every FBX, we wish to export a GLB using UnityGLTF!! ALTERNATIVELY, a pipeline can be created using fbx2gltf. I'm open to trying this as well.
# 2b. We still care about the .fbx.meta and its mapping ModelImporter: fileIDToRecycleName: 
# 3. 
# 
func get_importer_name():
	return "unityimp.unitypackage"

func get_visible_name():
	return "unitypackage archive importer"

func get_recognized_extensions():
	return ["unitypackage"]

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
	#printerr("IMPORT BEFORE " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface() if static_storage_singleton != null else null))
	#if static_storage_singleton == null:
	#	static_storage_singleton = static_storage.new().singleton()
	#static_storage.new().set_singleton(static_storage_singleton)
	#printerr("IMPORT AFTER " + str(self) + ": " + str(static_storage_singleton) + "/" + str(static_storage.new().get_editor_interface()))
	var packagefile = unitypackagefile.new().init_with_filename(source_file)
	if packagefile == null:
		return FAILED

	for path in packagefile.paths:
		var pkgasset: Object = packagefile.path_to_pkgasset[path]
		asset_adapter.save_asset(pkgasset)

	var mesh = Resource.new()
	# Fill the Mesh with data read in "file", left as an exercise to the reader

	var filename = save_path + "." + get_save_extension()
	ResourceSaver.save(filename, mesh)
	return OK

