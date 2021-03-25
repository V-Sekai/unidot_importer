@tool
extends Resource

const static_storage: GDScript = preload("./static_storage.gd")
const asset_database_class: GDScript = preload("./asset_database.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const post_import_material_remap_script: GDScript = preload("./post_import_unity_model.gd")
const convert_scene: GDScript = preload("./convert_scene.gd")

const ASSET_TYPE_YAML = 1
const ASSET_TYPE_MODEL = 2
const ASSET_TYPE_TEXTURE = 3
const ASSET_TYPE_PREFAB = 4
const ASSET_TYPE_SCENE = 5
const ASSET_TYPE_UNKNOWN = 6

var STUB_PNG_FILE: PackedByteArray = Marshalls.base64_to_raw(
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQot" +
	"tAAAAABJRU5ErkJggg==")
var STUB_GLB_FILE: PackedByteArray = Marshalls.base64_to_raw(
	"Z2xURgIAAACEAAAAcAAAAEpTT057ImFzc2V0Ijp7ImdlbmVyYXRvciI6IiIsInZlcnNpb24i" +
	"OiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibmFtZSI6IlMiLCJub2RlcyI6WzBdfV0s" +
	"Im5vZGVzIjpbeyJuYW1lIjoiTiJ9XX0g")

func write_sentinel_png(sentinel_filename: String):
	var f: File = File.new()
	f.open("res://" + sentinel_filename, _File.WRITE)
	f.store_buffer(STUB_PNG_FILE)
	f.close()

class AssetHandler:
	# WORKAROUND GDScript 4.0 BUG
	# THIS MUST BE COPIED AND PASTED FROM ABOVE.
	var ASSET_TYPE_YAML = 1
	var ASSET_TYPE_MODEL = 2
	var ASSET_TYPE_TEXTURE = 3
	var ASSET_TYPE_PREFAB = 4
	var ASSET_TYPE_SCENE = 5
	var ASSET_TYPE_UNKNOWN = 6

	var editor_interface: EditorInterface = null
	const static_storage: GDScript = preload("./static_storage.gd")
	
	func set_editor_interface(ei: EditorInterface) -> AssetHandler:
		editor_interface = ei
		return self

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String) -> String:
		return ""

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		var path: String = tmpdir + "/" + pkgasset.pathname
		var outfile: File = File.new()
		var err = outfile.open(path, File.WRITE)
		print("Open " + path + " => " + str(err))
		outfile.store_buffer(pkgasset.asset_tar_header.get_data())
		# outfile.flush()
		outfile.close()
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, path)
		if len(output_path) == 0:
			output_path = path
		print("Updating file at " + output_path)
		return output_path

	func write_godot_stub(pkgasset: Object) -> bool:
		return false

	func write_godot_asset(pkgasset: Object, temp_path: String):
		var dres = Directory.new()
		dres.open("res://")
		print("Renaming " + temp_path + " to " + pkgasset.pathname)
		pkgasset.parsed_meta.rename(pkgasset.pathname)
		dres.rename(temp_path, pkgasset.pathname)

	func get_asset_type(pkgasset: Object) -> int:
		return ASSET_TYPE_UNKNOWN

class ImageHandler extends AssetHandler:
	var STUB_PNG_FILE: PackedByteArray = PackedByteArray([])
	func create_with_constant(stub_file: PackedByteArray):
		var ret = self
		ret.STUB_PNG_FILE = stub_file
		return ret

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String) -> String:
		return ""

	func get_asset_type(pkgasset: Object) -> int:
		return self.ASSET_TYPE_TEXTURE

class YamlHandler extends AssetHandler:
	const tarfile: GDScript = preload("./tarfile.gd")

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		var path: String = tmpdir + "/" + pkgasset.pathname
		var outfile: File = File.new()
		var err = outfile.open(path, File.WRITE)
		print("Open " + path + " => " + str(err))
		var buf: PackedByteArray = pkgasset.asset_tar_header.get_data()
		outfile.store_buffer(buf)
		outfile.close()
		var sf: Object = tarfile.StringFile.new()
		sf.init(buf.get_string_from_utf8())
		pkgasset.parsed_asset = pkgasset.parsed_meta.parse_asset(sf)
		if pkgasset.parsed_asset == null:
			printerr("Parse asset failed " + pkgasset.pathname + "/" + pkgasset.guid)
		print("Done with " + path + "/" + pkgasset.guid)
		return path

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String) -> String:
		return ""

	func get_asset_type(pkgasset: Object) -> int:
		var extn: String = pkgasset.pathname.get_extension()
		if extn == "unity":
			return self.ASSET_TYPE_SCENE
		if extn == "prefab":
			return self.ASSET_TYPE_PREFAB
		return self.ASSET_TYPE_YAML

class MaterialHandler extends YamlHandler:
	func write_godot_asset(pkgasset, temp_path):
		var mat: Material = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id].create_godot_resource()
		var new_pathname: String = pkgasset.pathname.get_basename() + ".mat.tres"
		pkgasset.pathname = new_pathname
		pkgasset.parsed_meta.rename(new_pathname)
		ResourceSaver.save(pkgasset.pathname, mat)

class AnimationHandler extends YamlHandler:
	func write_godot_asset(pkgasset, temp_path):
		pass # We don't want to dump out invalid .anim files since Godot reuses this extension.
		#var anim: Animation = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id].create_godot_resource()
		#var new_pathname: String = pkgasset.pathname.get_basename() + ".anim"
		#pkgasset.pathname = new_pathname
		#pkgasset.parsed_meta.rename(new_pathname)
		#ResourceSaver.save(pkgasset.pathname, mat)

class SceneHandler extends YamlHandler:

	func write_godot_asset(pkgasset, temp_path):
		var is_prefab = pkgasset.pathname.get_extension() != "unity"
		var new_pathname: String = pkgasset.pathname.get_basename() + (".prefab.tscn" if is_prefab else ".tscn")
		pkgasset.pathname = new_pathname
		pkgasset.parsed_meta.rename(new_pathname)
		var packed_scene: PackedScene = convert_scene.new().pack_scene(pkgasset, is_prefab)
		if packed_scene != null:
			ResourceSaver.save(pkgasset.pathname, packed_scene)

class FbxHandler extends AssetHandler:
	var STUB_GLB_FILE: PackedByteArray = PackedByteArray([])
	func create_with_constant(stub_file: PackedByteArray):
		var ret = self
		ret.STUB_GLB_FILE = stub_file
		return ret

	func preprocess_asset(pkgasset, tmpdir: String, path: String) -> String:
		var user_path_base = OS.get_user_data_dir()

		print("I am an FBX " + str(path))
		var output_path: String = path.get_basename() + ".glb"
		var stdout = [].duplicate()
		var addon_path: String = post_import_material_remap_script.resource_path.get_base_dir().plus_file("FBX2glTF.exe")
		if addon_path.begins_with("res://"):
			addon_path = addon_path.substr(6)
		var ret = OS.execute(addon_path, [
			"--pbr-metallic-roughness",
			"--fbx-temp-dir", tmpdir + "/FBX_TEMP",
			"--normalize-weights", "1",
			"--binary", "--anim-framerate", "bake30",
			"-i", path,
			"-o", output_path], stdout)
		print("FBX2glTF returned " + str(ret) + " -----")
		print(str(stdout))
		print("-----------------------------")

		return output_path

	func get_asset_type(pkgasset: Object) -> int:
		return self.ASSET_TYPE_MODEL

	func write_godot_stub(pkgasset: Object) -> bool:
		var fres = File.new()
		fres.open("res://" + pkgasset.pathname, File.WRITE)
		print("Writing stub model to " + pkgasset.pathname)
		fres.store_buffer(STUB_GLB_FILE)
		fres.close()
		print("Renaming model file from " + str(pkgasset.parsed_meta.path) + " to " + pkgasset.pathname)
		pkgasset.parsed_meta.rename(pkgasset.pathname)
		return true

	func write_godot_asset(pkgasset: Object, temp_path: String):
		# super.write_godot_asset(pkgasset, temp_path)
		# Duplicate code since super causes a weird nonsensical error cannot call "importer()" function...
		var dres = Directory.new()
		dres.open("res://")
		print("Renaming " + temp_path + " to " + pkgasset.pathname)
		dres.rename(temp_path, pkgasset.pathname)

		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFile.new()
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			printerr("Failed to load .import config file for " + pkgasset.pathname)
			return
		cfile.set_value("params", "nodes/custom_script", post_import_material_remap_script.resource_path)
		cfile.set_value("params", "materials/location", 1) # Store on Mesh, not Node.
		cfile.set_value("params", "materials/storage", 0) # Store in file. post-import will export.
		cfile.set_value("params", "meshes/light_baking", 0)
		cfile.set_value("params", "animation/fps", 30)
		cfile.set_value("params", "animation/import", importer.animation_import)
		var anim_clips: Array = importer.get_animation_clips()
		# animation/clips don't seem to work at least in 4.0.... why even bother?
		# We should use an import script I guess.
		cfile.set_value("params", "animation/clips/amount", len(anim_clips))
		var idx: int = 0
		for anim_clip in anim_clips:
			idx += 1 # 1-indexed
			var prefix: String = "animation/clip_" + str(idx)
			cfile.set_value("params", prefix + "/name", anim_clip.get("name"))
			cfile.set_value("params", prefix + "/start_frame", anim_clip.get("start_frame"))
			cfile.set_value("params", prefix + "/end_frame", anim_clip.get("end_frame"))
			cfile.set_value("params", prefix + "/loops", anim_clip.get("loops"))
			# animation/import

		# FIXME: Godot has a major bug if light baking is used:
		# it leaves a file ".glb.unwrap_cache" open and causes future imports to fail.
		cfile.set_value("params", "meshes/light_baking", 0) #####cfile.set_value("params", "meshes/light_baking", importer.meshes_light_baking)
		cfile.set_value("params", "meshes/root_scale", importer.meshes_root_scale)
		# addCollider???? TODO
		var optim_setting: Dictionary = importer.animation_optimizer_settings()
		cfile.set_value("params", "animation/optimizer/enabled", optim_setting.get("enabled"))
		cfile.set_value("params", "animation/optimizer/max_linear_error", optim_setting.get("max_linear_error"))
		cfile.set_value("params", "animation/optimizer/max_angular_error", optim_setting.get("max_angular_error"))
		cfile.save("res://" + pkgasset.pathname + ".import")

var model_handler: FbxHandler = FbxHandler.new().create_with_constant(STUB_GLB_FILE)
var image_handler: ImageHandler = ImageHandler.new().create_with_constant(STUB_PNG_FILE)

var file_handlers: Dictionary = {
	"fbx": model_handler,
	"glb": model_handler,
	"jpg": image_handler,
	"png": image_handler,
	"bmp": image_handler, # Godot unsupported?
	"tga": image_handler,
	"exr": image_handler,
	"hdr": image_handler, # Godot unsupported?
	#"dds": null, # Godot unsupported?
	############"asset": YamlHandler.new(), # Generic file format
	"unity": SceneHandler.new(), # Unity Scenes
	"prefab": SceneHandler.new(), # Prefabs (sub-scenes)
	"mask": YamlHandler.new(), # Avatar Mask for animations
	############"mesh": YamlHandler.new(), # Mesh data, sometimes .asset
	"ht": YamlHandler.new(), # Human Template??
	"mat": MaterialHandler.new(), # Materials
	"playable": YamlHandler.new(), # director?
	"terrainlayer": YamlHandler.new(), # terrain, not supported
	"physicmaterial": YamlHandler.new(), # Physics Material
	"overridecontroller": YamlHandler.new(), # Animator Override Controller
	"controller": YamlHandler.new(), # Animator Controller
	"anim": AnimationHandler.new(), # Animation... # TODO: This should be by type (.asset), not extension
	# ALSO: animations can be contained inside other assets, such as controllers. we need to recognize this and extract them.
	"default": AssetHandler.new()
}

func create_temp_dir() -> String:
	var tmpdir = "temp_unityimp"
	var dres = Directory.new()
	dres.open("res://")
	dres.make_dir_recursive(tmpdir)
	dres.make_dir_recursive(tmpdir + "/FBX_TEMP")
	var f = File.new()
	f.open(tmpdir + "/.gdignore", File.WRITE)
	f.close()
	return tmpdir

func get_asset_type(pkgasset: Object) -> int:
	var path = pkgasset.pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.get_asset_type(pkgasset)
	

func preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
	var path = pkgasset.pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	var dres = Directory.new()
	dres.open("res://")
	dres.make_dir_recursive(path.get_base_dir())
	dres.make_dir_recursive(tmpdir + "/" + path.get_base_dir())

	if pkgasset.metadata_tar_header != null:
		var sf = pkgasset.metadata_tar_header.get_stringfile()
		pkgasset.parsed_meta = asset_database_class.new().parse_meta(sf, path)
		print("Parsing " + path + ": " + str(pkgasset.parsed_meta))
	if pkgasset.asset_tar_header != null:
		return asset_handler.write_and_preprocess_asset(pkgasset, tmpdir)
	return ""

# pkgasset: unitypackagefile.UnityPackageAsset type
func write_godot_stub(pkgasset: Object) -> bool:
	var path = pkgasset.pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.write_godot_stub(pkgasset)

func write_godot_asset(pkgasset: Object, temp_path: String):
	var path = pkgasset.pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	asset_handler.write_godot_asset(pkgasset, temp_path)
