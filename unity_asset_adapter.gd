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
var STUB_OBJ_FILE: PackedByteArray = "o a\nv 0 0 0\nf 1 1 1".to_ascii_buffer()
var STUB_DAE_FILE: PackedByteArray = ("""
<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4">
  <library_visual_scenes>
	<visual_scene id="A" name="A">
	  <node id="a" name="a" type="NODE">
		<matrix sid="transform">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix>
	  </node>
	</visual_scene>
  </library_visual_scenes>
  <scene>
	<instance_visual_scene url="#A"/>
  </scene>
</COLLADA>
""").to_ascii_buffer() # vscode syntax hack: "#"

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
			push_error("Parse asset failed " + pkgasset.pathname + "/" + pkgasset.guid)
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

	func write_godot_asset(pkgasset: Object, temp_path: String):
		if pkgasset.parsed_meta.main_object_id == -1 or pkgasset.parsed_meta.main_object_id == 0:
			push_error("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has no main object id!")
			return
		if pkgasset.parsed_asset == null:
			push_error("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has was not parsed as YAML")
			return
		var main_asset = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id]
		var godot_resource: Resource = main_asset.create_godot_resource()
		if godot_resource != null:
			var new_pathname: String = pkgasset.pathname.get_basename() + main_asset.get_godot_extension() # ".mat.tres"
			pkgasset.pathname = new_pathname
			pkgasset.parsed_meta.rename(new_pathname)
			ResourceSaver.save(pkgasset.pathname, godot_resource)
		var extra_resources: Dictionary = main_asset.get_extra_resources()
		for extra_asset_fileid in extra_resources:
			var file_ext: String = extra_resources.get(extra_asset_fileid)
			var created_res: Resource = main_asset.create_extra_resource(extra_asset_fileid)
			if created_res != null:
				var new_pathname: String = pkgasset.pathname.get_basename() + file_ext # ".skin.tres"
				ResourceSaver.save(new_pathname, created_res)
				created_res = load(new_pathname)
				pkgasset.parsed_meta.insert_resource(extra_asset_fileid, created_res)

class SceneHandler extends YamlHandler:

	func write_godot_asset(pkgasset, temp_path):
		var is_prefab = pkgasset.pathname.get_extension() != "unity"
		var new_pathname: String = pkgasset.pathname.get_basename() + (".prefab.tscn" if is_prefab else ".tscn")
		pkgasset.pathname = new_pathname
		pkgasset.parsed_meta.rename(new_pathname)
		var packed_scene: PackedScene = convert_scene.new().pack_scene(pkgasset, is_prefab)
		if packed_scene != null:
			ResourceSaver.save(pkgasset.pathname, packed_scene)

class BaseModelHandler extends AssetHandler:
	var stub_file: PackedByteArray = PackedByteArray([])
	func create_with_constant(stub_file: PackedByteArray):
		var ret = self
		ret.stub_file = stub_file
		return ret

	func get_asset_type(pkgasset: Object) -> int:
		return self.ASSET_TYPE_MODEL

	func write_godot_stub(pkgasset: Object) -> bool:
		var dres = Directory.new()
		dres.open("res://")
		var fres = File.new()
		fres.open("res://" + pkgasset.pathname, File.WRITE)
		print("Writing stub model to " + pkgasset.pathname)
		fres.store_buffer(stub_file)
		fres.close()
		var import_path = pkgasset.pathname + ".import"
		if not dres.file_exists(import_path):
			fres = File.new()
			fres.open("res://" + import_path, File.WRITE)
			print("Writing stub import file to " + import_path)
			fres.store_buffer("[remap]\n\nimporter=\"scene\"\nimporter_version=1\n".to_ascii_buffer())
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
			push_error("Failed to load .import config file for " + pkgasset.pathname)
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
		cfile.set_value("params", "meshes/root_scale", 1.0) # pkgasset.parsed_meta.internal_data.get("scale_correction_factor", 1.0))
		# addCollider???? TODO
		var optim_setting: Dictionary = importer.animation_optimizer_settings()
		cfile.set_value("params", "animation/optimizer/enabled", optim_setting.get("enabled"))
		cfile.set_value("params", "animation/optimizer/max_linear_error", optim_setting.get("max_linear_error"))
		cfile.set_value("params", "animation/optimizer/max_angular_error", optim_setting.get("max_angular_error"))
		cfile.save("res://" + pkgasset.pathname + ".import")

class FbxHandler extends BaseModelHandler:

	# From core/string/ustring.cpp
	func find_in_buffer(p_buf: PackedByteArray, p_str: PackedByteArray, p_from: int=0, p_to: int=-1) -> int:
		if (p_from < 0):
			return -1
		var src_len: int = len(p_str)
		var xlen: int = len(p_buf)
		if p_to != -1 and xlen > p_to:
			xlen = p_to
		if (src_len == 0 or xlen == 0):
			return -1 # won't find anything!
		for i in range(p_from, xlen - src_len):
			var found: bool = true
			for j in range(src_len):
				var read_pos: int = i + j
				if (read_pos >= xlen):
					push_error("read_pos>=len")
					return -1
				if (p_buf[read_pos] != p_str[j]):
					found = false
					break

			if (found):
				return i

		return -1

	func _adjust_fbx_scale(pkgasset: Object, fbx_scale: float, useFileScale: bool, globalScale: float) -> float:
		pkgasset.parsed_meta.internal_data["input_fbx_scale"] = fbx_scale
		pkgasset.parsed_meta.internal_data["meta_scale_factor"] = globalScale
		pkgasset.parsed_meta.internal_data["meta_convert_units"] = useFileScale
		var desired_scale: float = 0
		if useFileScale:
			# Cases:
			# (FBX All) fbx_scale=100; globalScale=1 -> 100
			# (FBX All) fbx_scale=12.3; globalScale = 8.130081 -> 100
			# (All Local) fbx_scale=1; globalScale=8.130081
			# (All Local, No apply unit) fbx_scale=1; globalScale = 1 -> 1
			desired_scale = fbx_scale * globalScale
		else:
			# Cases:
			# (FBX All)fbx_scale=12.3; globalScale=1 -> 100
			# (All Local) fbx_scale=1; globalScale=0.08130081 -> 8.130081
			# (All Local, No apply unit) fbx_scale=1; globalScale = 0.01 -> 1
			desired_scale = 100.0 * globalScale
		
		var output_scale: float = desired_scale
		# FBX2glTF does not implement scale correctly, so we must set it to 1.0 and correct it later
		# Godot's new built-in FBX importer works correctly and does not need this correction.
		output_scale = 1.0
		pkgasset.parsed_meta.internal_data["scale_correction_factor"] = desired_scale / output_scale
		pkgasset.parsed_meta.internal_data["output_fbx_scale"] = output_scale
		return output_scale

	func _preprocess_fbx_scale(pkgasset: Object, fbx_file_binary: PackedByteArray, useFileScale: bool, globalScale: float) -> PackedByteArray:
		var filename: String = pkgasset.pathname
		if useFileScale and is_equal_approx(globalScale, 1.0):
			print("TODO: when we switch to the Godot FBX implementation, we can short-circuit this code and return early.")
			#return fbx_file_binary
		var output_buf: PackedByteArray = fbx_file_binary
		var is_binary: bool = (find_in_buffer(fbx_file_binary, "Kaydara FBX Binary".to_ascii_buffer(), 0, 64) != -1)
		if is_binary:
			var needle_buf: PackedByteArray = "\u0001PS\u000F...UnitScaleFactorS".to_ascii_buffer()
			needle_buf[4] = 0
			needle_buf[5] = 0
			needle_buf[6] = 0
			var scale_factor_pos: int = find_in_buffer(fbx_file_binary, needle_buf)
			if scale_factor_pos == -1:
				push_error(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
				return output_buf

			var spb: StreamPeerBuffer = StreamPeerBuffer.new()
			spb.data_array = fbx_file_binary
			spb.seek(scale_factor_pos + len(needle_buf))
			var datatype: String = spb.get_string(spb.get_32())
			if spb.get_8() != ("S").to_ascii_buffer()[0]: # ord() is broken?!
				push_error(filename + ": not a string, or datatype invalid " + datatype)
				return output_buf
			var subdatatype: String = spb.get_string(spb.get_32())
			if spb.get_8() != ("S").to_ascii_buffer()[0]:
				push_error(filename + ": not a string, or subdatatype invalid " + datatype + " " + subdatatype)
				return output_buf
			var extratype: String = spb.get_string(spb.get_32())
			var number_type = spb.get_8()
			var scale = 1.0
			var is_double: bool = false
			if number_type == ("F").to_ascii_buffer()[0]:
				scale = spb.get_float()
			elif number_type == ("D").to_ascii_buffer()[0]:
				scale = spb.get_double()
				is_double = true
			else:
				push_error(filename + ": not a float or double " + str(number_type))
				return output_buf
			var new_scale: float = _adjust_fbx_scale(pkgasset, scale, useFileScale, globalScale)
			print(filename + ": Binary FBX: UnitScaleFactor=" + str(scale) + " -> " + str(new_scale) +
					" (Scale Factor = " + str(globalScale) +
					"; Convert Units = " + ("on" if useFileScale else "OFF") + ")")
			if is_double:
				spb.seek(spb.get_position() - 8)
				print("double - Seeked to " + str(spb.get_position()))
				spb.put_double(new_scale)
			else:
				spb.seek(spb.get_position() - 4)
				print("float - Seeked to " + str(spb.get_position()))
				spb.put_float(new_scale)
			return spb.data_array
		else:
			var buffer_as_ascii: String = fbx_file_binary.get_string_from_ascii()
			var scale_factor_pos: int = buffer_as_ascii.find("\"UnitScaleFactor\"")
			if scale_factor_pos == -1:
				push_error(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
				return output_buf
			var newline_pos: int = buffer_as_ascii.find("\n", scale_factor_pos)
			var comma_pos: int = buffer_as_ascii.rfind(",", newline_pos)
			if newline_pos == -1 or comma_pos == -1:
				push_error(filename + ": Failed to find value for UnitScaleFactor in ASCII FBX.")
				return output_buf

			var scale: float = buffer_as_ascii.substr(comma_pos + 1, newline_pos - comma_pos - 1).strip_edges().to_float()
			var new_scale: float = _adjust_fbx_scale(pkgasset, scale, useFileScale, globalScale)
			print(filename + ": ASCII FBX: UnitScaleFactor=" + str(scale) + " -> " + str(new_scale) +
					" (Scale Factor = " + str(globalScale) +
					"; Convert Units = " + ("on" if useFileScale else "OFF") + ")")
			output_buf = fbx_file_binary.subarray(0, comma_pos) # subarray endpoint is inclusive!!
			output_buf += str(new_scale).to_ascii_buffer()
			output_buf += fbx_file_binary.subarray(newline_pos, len(fbx_file_binary) - 1)
		return output_buf

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		var path: String = tmpdir + "/" + pkgasset.pathname
		var outfile: File = File.new()
		var err = outfile.open(path, File.WRITE)
		print("Open " + path + " => " + str(err))
		var importer = pkgasset.parsed_meta.importer

		var fbx_file: PackedByteArray = pkgasset.asset_tar_header.get_data()
		fbx_file = _preprocess_fbx_scale(pkgasset, fbx_file, importer.useFileScale, importer.globalScale)
		outfile.store_buffer(fbx_file)
		# outfile.flush()
		outfile.close()
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, path)
		if len(output_path) == 0:
			output_path = path
		print("Updating file at " + output_path)
		return output_path

	func preprocess_asset(pkgasset, tmpdir: String, path: String) -> String:
		var user_path_base = OS.get_user_data_dir()
		print("I am an FBX " + str(path))
		var output_path: String = path.get_basename() + ".glb"
		var stdout = [].duplicate()
		var addon_path: String = post_import_material_remap_script.resource_path.get_base_dir().plus_file("FBX2glTF.exe")
		if addon_path.begins_with("res://"):
			addon_path = addon_path.substr(6)
		# --long-indices auto
		# --compute-normals never|broken|missing|always
		# --blend-shape-normals --blend-shape-tangents
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

var obj_handler: BaseModelHandler = BaseModelHandler.new().create_with_constant(STUB_OBJ_FILE)
var dae_handler: BaseModelHandler = BaseModelHandler.new().create_with_constant(STUB_DAE_FILE)
var model_handler: FbxHandler = FbxHandler.new().create_with_constant(STUB_GLB_FILE) # FBX needs to rewrite to GLB for compatibility.
var image_handler: ImageHandler = ImageHandler.new().create_with_constant(STUB_PNG_FILE)

var file_handlers: Dictionary = {
	"fbx": model_handler,
	"obj": obj_handler,
	"dae": dae_handler,
	"glb": model_handler,
	"jpg": image_handler,
	"png": image_handler,
	"bmp": image_handler, # Godot unsupported?
	"tga": image_handler,
	"exr": image_handler,
	"hdr": image_handler, # Godot unsupported?
	#"dds": null, # Godot unsupported?
	"asset": YamlHandler.new(), # Generic file format
	"unity": SceneHandler.new(), # Unity Scenes
	"prefab": SceneHandler.new(), # Prefabs (sub-scenes)
	"mask": YamlHandler.new(), # Avatar Mask for animations
	"mesh": YamlHandler.new(), # Mesh data, sometimes .asset
	"ht": YamlHandler.new(), # Human Template??
	"mat": YamlHandler.new(), # Materials
	"playable": YamlHandler.new(), # director?
	"terrainlayer": YamlHandler.new(), # terrain, not supported
	"physicmaterial": YamlHandler.new(), # Physics Material
	"overridecontroller": YamlHandler.new(), # Animator Override Controller
	"controller": YamlHandler.new(), # Animator Controller
	"anim": YamlHandler.new(), # Animation... # TODO: This should be by type (.asset), not extension
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
