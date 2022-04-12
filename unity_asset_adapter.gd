@tool
extends Resource

const asset_database_class: GDScript = preload("./asset_database.gd")
const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const post_import_material_remap_script: GDScript = preload("./post_import_unity_model.gd")
const convert_scene: GDScript = preload("./convert_scene.gd")
const raw_parsed_asset: GDScript = preload("./raw_parsed_asset.gd")

const ASSET_TYPE_YAML = 1
const ASSET_TYPE_MODEL = 2
const ASSET_TYPE_TEXTURE = 3
const ASSET_TYPE_PREFAB = 4
const ASSET_TYPE_SCENE = 5
const ASSET_TYPE_UNKNOWN = 6

const SHOULD_CONVERT_TO_GLB: bool = false

var STUB_PNG_FILE: PackedByteArray = Marshalls.base64_to_raw(
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQot" +
	"tAAAAABJRU5ErkJggg==")
var STUB_GLB_FILE: PackedByteArray = Marshalls.base64_to_raw(
	"Z2xURgIAAACEAAAAcAAAAEpTT057ImFzc2V0Ijp7ImdlbmVyYXRvciI6IiIsInZlcnNpb24i" +
	"OiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibmFtZSI6IlMiLCJub2RlcyI6WzBdfV0s" +
	"Im5vZGVzIjpbeyJuYW1lIjoiTiJ9XX0g")
var STUB_GLTF_FILE: PackedByteArray = ('{"asset":{"generator":"","version":"2.0"},"scene":0,' +
	'"scenes":[{"name":"temp","nodes":[0]}],"nodes":[{"name":"temp"}]}').to_ascii_buffer()
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
	f.open("res://" + sentinel_filename, File.WRITE)
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
	
	func set_editor_interface(ei: EditorInterface) -> AssetHandler:
		editor_interface = ei
		return self

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		var path: String = tmpdir + "/" + pkgasset.pathname
		var data_buf: PackedByteArray = pkgasset.asset_tar_header.get_data()
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, path, data_buf)
		if len(output_path) == 0:
			var outfile: File = File.new()
			var err = outfile.open(path, File.WRITE)
			outfile.store_buffer(data_buf)
			outfile.close()
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

class DefaultHandler extends AssetHandler:
	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary={}) -> String:
		return ""

class ImageHandler extends AssetHandler:
	var STUB_PNG_FILE: PackedByteArray = PackedByteArray([])
	func create_with_constant(stub_file: PackedByteArray):
		var ret = self
		ret.STUB_PNG_FILE = stub_file
		return ret

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary={}) -> String:
		var user_path_base = OS.get_user_data_dir()
		var is_tiff: bool = ((data_buf[0] == 0x49 and data_buf[1] == 0x49 and data_buf[2] == 0x2A and data_buf[3] == 0x00) or 
				(data_buf[0] == 0x4D and data_buf[1] == 0x4D and data_buf[2] == 0x00 and data_buf[3] == 0x2A))
		var is_png: bool = (data_buf[0] == 0x89 and data_buf[1] == 0x50 and data_buf[2] == 0x4E and data_buf[3] == 0x47) or is_tiff
		var full_output_path: String = path
		if not is_png and path.get_extension().to_lower() == "png":
			print("I am a JPG pretending to be a " + str(path.get_extension()) + " " + str(path))
			full_output_path = full_output_path.get_basename() + ".jpg"
		elif is_png and path.get_extension().to_lower() != "png":
			print("I am a PNG pretending to be a " + str(path.get_extension()) + " " + str(path))
			full_output_path = full_output_path.get_basename() + ".png"
		print("PREPROCESS_IMAGE " + str(is_tiff) + "/" + str(is_png) + " path " + str(path) + " to " + str(full_output_path))
		if is_tiff:
			var outfile: File = File.new()
			var err = outfile.open(full_output_path + ".tif", File.WRITE)
			outfile.store_buffer(data_buf)
			outfile.close()
			var stdout: Array = [].duplicate()
			var d = Directory.new()
			d.open("res://")
			var addon_path: String = post_import_material_remap_script.resource_path.get_base_dir().plus_file("convert.exe")
			if addon_path.begins_with("res://"):
				if not d.file_exists(addon_path):
					push_warning("Not converting tiff to png because convert.exe is not present.")
					return ""
				addon_path = addon_path.substr(6)
			var ret = OS.execute(addon_path, [
				full_output_path + ".tif", full_output_path], stdout)
			d.remove(full_output_path + ".tif")
		else:
			var outfile: File = File.new()
			var err = outfile.open(full_output_path, File.WRITE)
			outfile.store_buffer(data_buf)
			outfile.close()
		return full_output_path

	func get_asset_type(pkgasset: Object) -> int:
		return self.ASSET_TYPE_TEXTURE

	func write_godot_asset(pkgasset: Object, temp_path: String):
		# super.write_godot_asset(pkgasset, temp_path)
		# Duplicate code since super causes a weird nonsensical error cannot call "importer()" function...
		var dres = Directory.new()
		dres.open("res://")
		print("Renaming " + temp_path + " to " + pkgasset.pathname)
		pkgasset.parsed_meta.rename(pkgasset.pathname)
		dres.rename(temp_path, pkgasset.pathname)

		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFile.new()
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			print("Failed to load .import config file for " + pkgasset.pathname)
			cfile.set_value("remap", "importer", "texture")
			cfile.set_value("remap", "path", "unidot_default_remap_path") # must be non-empty. hopefully ignored.
			cfile.set_value("remap", "type", "StreamTexture2D")
		var chosen_platform = {}
		for platform in importer.keys.get("platformSettings", []):
			if platform.get("buildTarget", "") == "DefaultTexturePlatform":
				chosen_platform = platform
		for platform in importer.keys.get("platformSettings", []):
			if platform.get("buildTarget", "") == "Standalone":
				chosen_platform = platform
		var use_tc = chosen_platform.get("textureCompression", importer.keys.get("textureCompression", 1))
		var tc_level = chosen_platform.get("compressionQuality", importer.keys.get("compressionQuality", 50))
		var max_texture_size = chosen_platform.get("maxTextureSize", importer.keys.get("maxTextureSize", 0))
		if max_texture_size < 0:
			max_texture_size = 0
		#cfile.set_value("params", "import_script/path", post_import_material_remap_script.resource_path)
		# TODO: If low quality (use_tc==2) then we may want to disable bptc on this file
		cfile.set_value("params", "compress/mode", 2 if use_tc > 0 else 0)
		cfile.set_value("params", "compress/bptc_ldr", 1 if use_tc == 2 else 0)
		cfile.set_value("params", "compress/lossy_quality", tc_level / 100.0)
		cfile.set_value("params", "compress/normal_map", importer.keys.get("bumpmap", {}).get("convertToNormalMap", 0))
		cfile.set_value("params", "detect_3d/compress_to", 0)
		cfile.set_value("params", "process/premult_alpha", importer.keys.get("alphaIsTransparency", 0) != 0)
		cfile.set_value("params", "process/size_limit", max_texture_size)
		cfile.set_value("params", "mipmaps/generate", importer.keys.get("mipmaps", {}).get("enableMipMap", 0) != 0)
		cfile.save("res://" + pkgasset.pathname + ".import")


class AudioHandler extends AssetHandler:

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary={}) -> String:
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
		if buf[8] == 0 and buf[9] == 0:
			pkgasset.parsed_asset = pkgasset.parsed_meta.parse_binary_asset(buf)
		else:
			var sf: Object = tarfile.StringFile.new()
			sf.init(buf.get_string_from_utf8())
			pkgasset.parsed_asset = pkgasset.parsed_meta.parse_asset(sf)
		if pkgasset.parsed_asset == null:
			push_error("Parse asset failed " + pkgasset.pathname + "/" + pkgasset.guid)
		print("Done with " + path + "/" + pkgasset.guid)
		return path

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary={}) -> String:
		return ""

	func get_asset_type(pkgasset: Object) -> int:
		var extn: String = pkgasset.pathname.get_extension()
		if extn == "unity":
			return self.ASSET_TYPE_SCENE
		if extn == "prefab":
			return self.ASSET_TYPE_PREFAB
		if pkgasset.parsed_meta.type_to_fileids.has("TerrainData"):
			# TerrainData depends on prefab assets.
			return self.ASSET_TYPE_PREFAB
		return self.ASSET_TYPE_YAML

	func write_godot_asset(pkgasset: Object, temp_path: String):
		if pkgasset.parsed_asset == null:
			push_error("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has was not parsed as YAML")
			return
		var main_asset: RefCounted = null
		var godot_resource: Resource = null
		if pkgasset.parsed_meta.main_object_id != -1 and pkgasset.parsed_meta.main_object_id != 0:
			main_asset = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id]
			godot_resource = main_asset.create_godot_resource()
		else:
			push_error("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has no main object id!")
		if godot_resource == null:
			var rpa = raw_parsed_asset.new()
			rpa.path = pkgasset.pathname
			rpa.guid = pkgasset.guid
			rpa.meta = pkgasset.parsed_meta.duplicate()
			for key in pkgasset.parsed_asset.assets:
				var parsed_obj: RefCounted = pkgasset.parsed_asset.assets[key]
				rpa.objects[str(key) + ":" + str(parsed_obj.type)] = pkgasset.parsed_asset.assets[key].keys
			rpa.resource_name + pkgasset.pathname.get_basename().get_file()
			var new_pathname: String = pkgasset.pathname + ".tres"
			pkgasset.pathname = new_pathname
			pkgasset.parsed_meta.rename(new_pathname)
			ResourceSaver.save(pkgasset.pathname, rpa)
		else:
			var new_pathname: String = pkgasset.pathname.get_basename() + main_asset.get_godot_extension() # ".mat.tres"
			pkgasset.pathname = new_pathname
			pkgasset.parsed_meta.rename(new_pathname)
			var extra_resources: Dictionary = main_asset.get_extra_resources()
			for extra_asset_fileid in extra_resources:
				var file_ext: String = extra_resources.get(extra_asset_fileid)
				var created_res: Resource = main_asset.create_extra_resource(extra_asset_fileid)
				if created_res != null:
					new_pathname = pkgasset.pathname.get_basename() + file_ext # ".skin.tres"
					ResourceSaver.save(new_pathname, created_res)
					created_res = load(new_pathname)
					pkgasset.parsed_meta.insert_resource(extra_asset_fileid, created_res)
			# Save main resource at end, so that it can reference extra resources.
			ResourceSaver.save(pkgasset.pathname, godot_resource)

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
		var fres = File.new()
		dres.open("res://")
		# Note: even after one import has successfully completed, materials and texture files may have moved since the last import.
		# Godot's EditorFileSystem does not expose a reimport() function, so overwriting with a stub file doubles as a hacky workaround.
		#if not dres.file_exists(pkgasset.pathname):
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
		if temp_path.ends_with(".gltf"):
			dres.rename(temp_path.get_basename() + ".bin", pkgasset.pathname.get_basename() + ".bin")

		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFile.new()
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			push_error("Failed to load .import config file for " + pkgasset.pathname)
			return
		cfile.set_value("params", "import_script/path", post_import_material_remap_script.resource_path)
		# I think these are the default settings now?? The option no longer exists???
		### cfile.set_value("params", "materials/location", 1) # Store on Mesh, not Node.
		### cfile.set_value("params", "materials/storage", 0) # Store in file. post-import will export.
		cfile.set_value("params", "animation/fps", 30)
		cfile.set_value("params", "animation/import", importer.animation_import)
		#var anim_clips: Array = importer.get_animation_clips()
		## animation/clips don't seem to work at least in 4.0.... why even bother?
		## We should use an import script I guess.
		#cfile.set_value("params", "animation/clips/amount", len(anim_clips))
		#var idx: int = 0
		#for anim_clip in anim_clips:
		#	idx += 1 # 1-indexed
		#	var prefix: String = "animation/clip_" + str(idx)
		#	cfile.set_value("params", prefix + "/name", anim_clip.get("name"))
		#	cfile.set_value("params", prefix + "/start_frame", anim_clip.get("start_frame"))
		#	cfile.set_value("params", prefix + "/end_frame", anim_clip.get("end_frame"))
		#	cfile.set_value("params", prefix + "/loops", anim_clip.get("loops"))
		#	# animation/import

		# FIXME: Godot has a major bug if light baking is used:
		# it leaves a file ".glb.unwrap_cache" open and causes future imports to fail.
		cfile.set_value("params", "meshes/light_baking", importer.meshes_light_baking)
		cfile.set_value("params", "meshes/ensure_tangents", importer.ensure_tangents)
		cfile.set_value("params", "meshes/create_shadow_meshes", false) # Until visual artifacts with shadow meshes get fixed
		cfile.set_value("params", "nodes/root_scale", 1.0) # pkgasset.parsed_meta.internal_data.get("scale_correction_factor", 1.0))
		cfile.set_value("params", "nodes/root_name", "Root Scene")
		# addCollider???? TODO
		
		# ??? animation/optimizer setting seems to be missing?
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
		var i: int = p_from
		var ilen: int = (xlen - src_len)
		while i < ilen:
			var found: bool = true
			var j: int = 0
			while j < src_len:
				var read_pos: int = i + j
				if (read_pos >= xlen):
					push_error("read_pos>=len")
					return -1
				if (p_buf[read_pos] != p_str[j]):
					found = false
					break
				j += 1

			if (found):
				return i
			i += 1

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

	func convert_to_float(s: String) -> Variant:
		return s.to_float()

	func _is_fbx_binary(fbx_file_binary: PackedByteArray) -> bool:
		return (find_in_buffer(fbx_file_binary, "Kaydara FBX Binary".to_ascii_buffer(), 0, 64) != -1)

	func _extract_fbx_textures_binary(pkgasset: Object, fbx_file_binary: PackedByteArray) -> PackedStringArray:
		var spb: StreamPeerBuffer = StreamPeerBuffer.new()
		spb.data_array = fbx_file_binary
		spb.big_endian = false
		var strlist: PackedStringArray = PackedStringArray()

		var texname1_needle_buf: PackedByteArray = "...\u0010RelativeFilenameS".to_ascii_buffer()
		texname1_needle_buf[0] = 0
		texname1_needle_buf[1] = 0
		texname1_needle_buf[2] = 0
		var texname2_needle_buf: PackedByteArray = "S\u0007...XRefUrlS....S".to_ascii_buffer()
		texname2_needle_buf[2] = 0
		texname2_needle_buf[3] = 0
		texname2_needle_buf[4] = 0
		texname2_needle_buf[13] = 0
		texname2_needle_buf[14] = 0
		texname2_needle_buf[15] = 0
		texname2_needle_buf[16] = 0

		var texname1_pos: int = find_in_buffer(fbx_file_binary, texname1_needle_buf)
		var texname2_pos: int = find_in_buffer(fbx_file_binary, texname2_needle_buf)
		while texname1_pos != -1 or texname2_pos != -1:
			var nextpos: int = -1
			var ftype: int = 0
			if texname1_pos != -1 and (texname2_pos == -1 or texname1_pos < texname2_pos):
				nextpos = texname1_pos + len(texname1_needle_buf)
				texname1_pos = find_in_buffer(fbx_file_binary, texname1_needle_buf, texname1_pos + 1)
				ftype = 1
			elif texname2_pos != -1:
				nextpos = texname2_pos + len(texname2_needle_buf)
				texname2_pos = find_in_buffer(fbx_file_binary, texname2_needle_buf, texname2_pos + 1)
				ftype = 2
			spb.seek(nextpos)
			var strlen: int = spb.get_32()
			spb.seek(nextpos + 4)
			if strlen > 0 and strlen < 1024:
				var fn_utf8: PackedByteArray = spb.get_data(strlen)[1] # NOTE: Do we need to detect charset? FBX should be unicode
				strlist.append(fn_utf8.get_string_from_ascii())
		return strlist

	func _extract_fbx_textures_ascii(pkgasset: Object, buffer_as_ascii: String) -> PackedStringArray:
		var strlist: PackedStringArray = PackedStringArray()
		var texname1_needle = "\"XRefUrl\","
		var texname2_needle = "RelativeFilename:"

		var texname1_pos: int = buffer_as_ascii.find(texname1_needle)
		var texname2_pos: int = buffer_as_ascii.find(texname2_needle)
		while texname1_pos != -1 or texname2_pos != -1:
			var nextpos: int = -1
			var newlinepos: int = -1
			if texname1_pos != -1 and (texname2_pos == -1 or texname1_pos < texname2_pos):
				nextpos = texname1_pos + len(texname1_needle)
				newlinepos = buffer_as_ascii.find("\n", nextpos)
				texname1_pos = buffer_as_ascii.find(texname1_needle, texname1_pos + 1)
				nextpos = buffer_as_ascii.find("\"", nextpos + 1)
				nextpos = buffer_as_ascii.find("\"", nextpos + 1)
				nextpos = buffer_as_ascii.find("\"", nextpos + 1)
			elif texname2_pos != -1:
				nextpos = texname2_pos + len(texname2_needle)
				newlinepos = buffer_as_ascii.find("\n", nextpos)
				texname2_pos = buffer_as_ascii.find(texname2_needle, texname2_pos + 1)
				nextpos = buffer_as_ascii.find("\"", nextpos + 1)
			var lastquote: int = buffer_as_ascii.find("\"", nextpos + 1)
			if lastquote > newlinepos:
				push_warning("Failed to parse texture from " + buffer_as_ascii.substr(nextpos, newlinepos - nextpos))
			else:
				strlist.append(buffer_as_ascii.substr(nextpos + 1, lastquote - nextpos - 1))
		return strlist

	func _preprocess_fbx_scale_binary(pkgasset: Object, fbx_file_binary: PackedByteArray, useFileScale: bool, globalScale: float) -> PackedByteArray:
		if useFileScale and is_equal_approx(globalScale, 1.0):
			print("TODO: when we switch to the Godot FBX implementation, we can short-circuit this code and return early.")
			#return fbx_file_binary
		var filename: String = pkgasset.pathname
		var needle_buf: PackedByteArray = "\u0001PS\u000F...UnitScaleFactorS".to_ascii_buffer()
		needle_buf[4] = 0
		needle_buf[5] = 0
		needle_buf[6] = 0
		var scale_factor_pos: int = find_in_buffer(fbx_file_binary, needle_buf)
		if scale_factor_pos == -1:
			push_error(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return fbx_file_binary

		# TODO: If any Model has Visibility == 0.0, then the mesh gets lost in FBX2glTF
		# Find all instances of VisibilityS\0\0\0S\1\0\0\0AD followed by 0.0 Double or 0.0 Float and replace with 1.0
		# in ASCII, it is   P: "Visibility", "Visibility", "", "A",0 -> 1

		var spb: StreamPeerBuffer = StreamPeerBuffer.new()
		spb.data_array = fbx_file_binary
		spb.big_endian = false
		spb.seek(scale_factor_pos + len(needle_buf))
		var datatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]: # ord() is broken?!
			push_error(filename + ": not a string, or datatype invalid " + datatype)
			return fbx_file_binary
		var subdatatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:
			push_error(filename + ": not a string, or subdatatype invalid " + datatype + " " + subdatatype)
			return fbx_file_binary
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
			return fbx_file_binary
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

	func _preprocess_fbx_scale_ascii(pkgasset: Object, fbx_file_binary: PackedByteArray, buffer_as_ascii: String, useFileScale: bool, globalScale: float) -> PackedByteArray:
		if useFileScale and is_equal_approx(globalScale, 1.0):
			print("TODO: when we switch to the Godot FBX implementation, we can short-circuit this code and return early.")
			#return fbx_file_binary
		var filename: String = pkgasset.pathname
		var output_buf: PackedByteArray = fbx_file_binary
		var scale_factor_pos: int = buffer_as_ascii.find("\"UnitScaleFactor\"")
		if scale_factor_pos == -1:
			push_error(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return output_buf
		var newline_pos: int = buffer_as_ascii.find("\n", scale_factor_pos)
		var comma_pos: int = buffer_as_ascii.rfind(",", newline_pos)
		if newline_pos == -1 or comma_pos == -1:
			push_error(filename + ": Failed to find value for UnitScaleFactor in ASCII FBX.")
			return output_buf

		var scale_string: Variant = buffer_as_ascii.substr(comma_pos + 1, newline_pos - comma_pos - 1).strip_edges()
		print("Scale as string is " + str(scale_string))
		var scale: float = convert_to_float(str(scale_string + str(NodePath())))
		print("Scale as string 2 type is " + str(typeof(str(scale_string + str(NodePath())))))
		print(str(scale_string + str(NodePath())).to_float())
		print("Scale is " + str(scale))
		print("Also Scale is " + str(scale + 0.0))
		var new_scale: float = _adjust_fbx_scale(pkgasset, scale, useFileScale, globalScale)
		print(filename + ": ASCII FBX: UnitScaleFactor=" + str(scale) + " -> " + str(new_scale) +
				" (Scale Factor = " + str(globalScale) +
				"; Convert Units = " + ("on" if useFileScale else "OFF") + ")")
		output_buf = fbx_file_binary.slice(0, comma_pos + 1)
		output_buf += str(new_scale).to_ascii_buffer()
		output_buf += fbx_file_binary.slice(newline_pos, len(fbx_file_binary))
		return output_buf

	func _get_parent_textures_paths(source_file_path: String) -> Dictionary:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		var retlist: Dictionary = {}
		var basedir: String = source_file_path.get_base_dir()
		var texfn: String = source_file_path.get_file()
		var relpath: String = ""
		while basedir != "res://" and basedir != "/" and basedir != "" and basedir != ".":
			retlist[basedir + "/" + texfn] = relpath + texfn
			retlist[basedir + "/textures/" + texfn] = relpath + "textures/" + texfn
			retlist[basedir + "/Textures/" + texfn] = relpath + "Textures/" + texfn
			basedir = basedir.get_base_dir()
			relpath += "../"
		retlist[texfn] = relpath + texfn
		retlist["textures/" + texfn] = relpath + "textures/" + texfn
		retlist["Textures/" + texfn] = relpath + "Textures/" + texfn
		#print("Looking in directories " + str(retlist))
		return retlist

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		var path: String = tmpdir + "/FBX_TEMP/" + "input.fbx"
		var outfile: File = File.new()
		var err = outfile.open(path, File.WRITE)
		print("Open " + path + " => " + str(err))
		var importer = pkgasset.parsed_meta.importer

		var fbx_file: PackedByteArray = pkgasset.asset_tar_header.get_data()
		var is_binary: bool = _is_fbx_binary(fbx_file)
		var texture_name_list: PackedStringArray = PackedStringArray()
		if is_binary:
			texture_name_list = _extract_fbx_textures_binary(pkgasset, fbx_file)
			fbx_file = _preprocess_fbx_scale_binary(pkgasset, fbx_file, importer.useFileScale, importer.globalScale)
		else:
			var buffer_as_ascii: String = fbx_file.get_string_from_utf8() # may contain unicode
			texture_name_list = _extract_fbx_textures_ascii(pkgasset, buffer_as_ascii)
			fbx_file = _preprocess_fbx_scale_ascii(pkgasset, fbx_file, buffer_as_ascii, importer.useFileScale, importer.globalScale)
		outfile.store_buffer(fbx_file)
		# outfile.flush()
		outfile.close()
		var unique_texture_map: Dictionary = {}
		var texture_dirname = path.get_base_dir()
		var output_dirname = pkgasset.pathname.get_base_dir()
		print("Referenced texture list: " + str(texture_name_list))
		for fn in texture_name_list:
			var fn_filename: String = fn.get_file()
			var replaced_extension = "png"
			if fn_filename.get_extension().to_lower() == "jpg":
				replaced_extension = "jpg"
			unique_texture_map[fn_filename.get_basename() + "." + replaced_extension] = fn_filename
		print("Referenced textures: " + str(unique_texture_map.keys()))
		var d = Directory.new()
		d.open("res://")
		for fn in unique_texture_map.keys():
			if not d.file_exists(texture_dirname + "/" + fn):
				print("Creating dummy texture: " + str(texture_dirname + "/" + fn))
				var tmpf = File.new()
				tmpf.open(texture_dirname + "/" + fn, File.WRITE)
				tmpf.close()
			var candidate_texture_dict = _get_parent_textures_paths(output_dirname + "/" + unique_texture_map[fn])
			for candidate_fn in candidate_texture_dict:
				#print("candidate " + str(candidate_fn) + " INPKG=" + str(pkgasset.packagefile.path_to_pkgasset.has(candidate_fn)) + " FILEEXIST=" + str(d.file_exists(candidate_fn)))
				if pkgasset.packagefile.path_to_pkgasset.has(candidate_fn) or d.file_exists(candidate_fn):
					unique_texture_map[fn] = candidate_texture_dict[candidate_fn]
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, path, fbx_file, unique_texture_map)
		if len(output_path) == 0:
			output_path = path
		print("Updating file at " + output_path)
		return output_path

	func assign_skinned_parents(p_out_map, gltf_nodes, parent_node_name, cur_children):
		var out_map = p_out_map
		if cur_children.is_empty():
			return out_map
		var this_children = []
		for child in cur_children:
			if gltf_nodes[child].get("skin", -1) >= 0 and gltf_nodes[child].get("mesh", -1) >= 0:
				this_children.append(gltf_nodes[child]["name"])
			out_map = assign_skinned_parents(out_map, gltf_nodes, gltf_nodes[child]["name"], gltf_nodes[child].get("children", []))
		if not this_children.is_empty():
			out_map[parent_node_name] = this_children
		return out_map

	func sanitize_bone_name(bone_name: String) -> String:
		var xret = bone_name.replace(":", "").replace("/", "")
		return xret

	func sanitize_unique_name(bone_name: String) -> String:
		var xret = bone_name.replace("/", "").replace(":", "").replace(".", "").replace("@", "").replace("\"", "")
		return xret

	func sanitize_anim_name(anim_name: String) -> String:
		return sanitize_unique_name(anim_name).replace("[", "").replace(",", "")

	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary) -> String:
		var user_path_base: String = OS.get_user_data_dir()
		print("I am an FBX " + str(path))
		var full_output_path: String = tmpdir + "/" + pkgasset.pathname
		var gltf_output_path: String = full_output_path.get_basename() + ".gltf"
		var bin_output_path: String = full_output_path.get_basename() + ".bin"
		var output_path: String = gltf_output_path
		var tmp_gltf_output_path: String = tmpdir + "/FBX_TEMP/" + gltf_output_path.get_file()
		var tmp_bin_output_path: String = tmpdir + "/FBX_TEMP/buffer.bin"
		if SHOULD_CONVERT_TO_GLB:
			output_path = full_output_path.get_basename() + ".glb"
		var stdout: Array = [].duplicate()
		var d = Directory.new()
		d.open("res://")
		var addon_path: String = post_import_material_remap_script.resource_path.get_base_dir().plus_file("FBX2glTF.exe")
		if addon_path.begins_with("res://"):
			if not d.file_exists(addon_path):
				push_warning("Not converting fbx to glb because FBX2glTF.exe is not present.")
				return ""
			addon_path = addon_path.substr(6)
		# --long-indices auto
		# --compute-normals never|broken|missing|always
		# --blend-shape-normals --blend-shape-tangents
		var ret = OS.execute(addon_path, [
			"--pbr-metallic-roughness",
			"--fbx-temp-dir", tmpdir + "/FBX_TEMP",
			"--normalize-weights", "1",
			"--anim-framerate", "bake30",
			"-i", path,
			"-o", tmp_gltf_output_path], stdout)
		print("FBX2glTF returned " + str(ret) + " -----")
		print(str(stdout))
		print("-----------------------------")
		d.rename(tmp_bin_output_path, bin_output_path)
		d.rename(tmp_gltf_output_path, gltf_output_path)
		var f: File = File.new()
		f.open(gltf_output_path, File.READ)
		var data: String = f.get_buffer(f.get_length()).get_string_from_utf8()
		f.close()
		var jsonres = JSON.new()
		jsonres.parse(data)
		var json: Dictionary = jsonres.get_data()
		var bindata: PackedByteArray
		if SHOULD_CONVERT_TO_GLB:
			f = File.new()
			f.open(bin_output_path, File.READ)
			bindata = f.get_buffer(f.get_length())
			f.close()
			json["buffers"][0].erase("uri")
		else:
			json["buffers"][0]["uri"] = bin_output_path.get_file()
		if json.has("images"):
			for img in json["images"]:
				var img_name: String = img.get("name")
				var img_uri: String = img.get("uri", "data:")
				if unique_texture_map.has(img_uri):
					img_uri = unique_texture_map.get(img_uri)
					img_name = img_uri
				else:
					if img_uri.begins_with("data:"):
						img_uri = img_name
					if unique_texture_map.has(img_name):
						img_uri = unique_texture_map.get(img_name)
						img_name = img_uri
				img["uri"] = img_uri
				img["name"] = img_name.get_file().get_basename()
		if json.has("materials"):
			var material_to_texture_name = {}.duplicate()
			for mat in json["materials"]:
				#if "pbrMetallicRoughness" in mat and "baseColorTexture" in mat["pbrMetallicRoughness"]:
				for key in mat:
					if typeof(mat[key]) == TYPE_DICTIONARY and mat[key].has("baseColorTexture"):
						var basecolor_index: int = mat[key]["baseColorTexture"].get("index", 0)
						var image_index: int = json.get("textures", [])[basecolor_index].get("source", 0)
						var image_name: String = json.get("images", [])[image_index].get("name", "")
						material_to_texture_name[mat.name] = image_name
			pkgasset.parsed_meta.internal_data["material_to_texture_name"] = material_to_texture_name
		pkgasset.parsed_meta.internal_data["skinned_parents"] = assign_skinned_parents({}.duplicate(), json["nodes"], "", json["scenes"][json.get("scene", 0)]["nodes"])
		pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"] = {"bone_name": {}}
		for key in ["scenes", "nodes", "meshes", "skins", "images", "textures", "materials", "samplers", "animations"]:
			pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"][key] = {}
			if not json.has(key):
				continue
			var used_names: Dictionary = {}.duplicate()
			var jk: Array = json[key]
			for elem in range(jk.size()):
				if not jk[elem].has("name"):
					continue
				var orig_name: String = jk[elem].get("name")
				var try_name: String = orig_name
				var next_num: int = used_names.get(orig_name, 1)
				# Ensure that objects have a unique name in compliance with Unity's uniqueness rules
				# Godot's rule is Gizmo, Gizmo2, Gizmo3.
				# Unity's rule is Gizmo, Gizmo 1, Gizmo 2
				# While we ignore the extra space anyway, the off-by-one here is killer. :'-(
				# So we must proactively rename nodes to avoid duplicates...
				while used_names.has(try_name):
					try_name = "%s %d" % [orig_name, next_num]
					next_num += 1
				json[key][elem]["name"] = try_name
				var sanitized_try_name: String = sanitize_unique_name(try_name)
				if key == "animations":
					sanitized_try_name = sanitize_anim_name(try_name)
				if orig_name != sanitized_try_name:
					pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"][key][sanitized_try_name] = orig_name
				if key == "nodes":
					var sanitized_bone_try_name = sanitize_bone_name(try_name)
					if orig_name != sanitized_bone_try_name:
						pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"]["bone_name"][sanitized_bone_try_name] = orig_name
				used_names[orig_name] = next_num
				used_names[try_name] = 1
		var out_json_data: PackedByteArray = JSON.new().stringify(json).to_utf8_buffer()
		if SHOULD_CONVERT_TO_GLB:
			var out_json_data_length: int = out_json_data.size()
			var bindata_length: int = bindata.size()
			f = File.new()
			f.open(output_path, File.WRITE)
			f.store_32(0x46546C67)
			f.store_32(2)
			f.store_32(20 + out_json_data_length + 8 + bindata_length + 4)
			f.store_32(out_json_data_length)
			f.store_32(0x4E4F534A)
			f.store_buffer(out_json_data)
			f.store_32(bindata_length)
			f.store_32(0x4E4942)
			f.store_buffer(bindata)
			f.store_32(0)
			f.close()
		else:
			f = File.new()
			f.open(output_path, File.WRITE)
			f.store_buffer(out_json_data)
			f.close()
		return output_path

class DisabledHandler extends AssetHandler:
	func preprocess_asset(pkgasset: Object, tmpdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary={}) -> String:
		return "asset_not_supported"

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String) -> String:
		return "asset_not_supported"

	func write_godot_asset(pkgasset: Object, temp_path: String):
		pass

var obj_handler: BaseModelHandler = BaseModelHandler.new().create_with_constant(STUB_OBJ_FILE)
var dae_handler: BaseModelHandler = BaseModelHandler.new().create_with_constant(STUB_DAE_FILE)
var image_handler: ImageHandler = ImageHandler.new().create_with_constant(STUB_PNG_FILE)

var file_handlers: Dictionary = {
	"fbx": FbxHandler.new().create_with_constant(STUB_GLB_FILE if SHOULD_CONVERT_TO_GLB else STUB_GLTF_FILE),
	"obj": obj_handler,
	"dae": dae_handler,
	#"obj": DisabledHandler.new(), # .obj is broken due to multithreaded importer
	#"dae": DisabledHandler.new(), # .dae is broken due to multithreaded importer
	"glb": FbxHandler.new().create_with_constant(STUB_GLB_FILE),
	"gltf": FbxHandler.new().create_with_constant(STUB_GLTF_FILE),
	"jpg": image_handler,
	"jpeg": image_handler,
	"png": image_handler,
	"bmp": image_handler,
	"tga": image_handler,
	"exr": image_handler,
	"hdr": image_handler,
	"dds": image_handler,
	"tif": image_handler,
	"tiff": image_handler,
	"webp": image_handler,
	"svg": image_handler,
	"svgz": image_handler,
	"wav": AudioHandler.new(),
	"ogg": AudioHandler.new(),
	"mp3": AudioHandler.new(),
	# "aif": audio_handler, # Unsupported.
	# "tif": image_handler, # Unsupported.
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
	"default": DefaultHandler.new()
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
