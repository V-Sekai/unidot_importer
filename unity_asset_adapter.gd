# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends Resource

const object_adapter_class: GDScript = preload("./unity_object_adapter.gd")
const post_import_material_remap_script: GDScript = preload("./post_import_unity_model.gd")
const convert_scene: GDScript = preload("./convert_scene.gd")
const raw_parsed_asset: GDScript = preload("./raw_parsed_asset.gd")
const bone_map_editor_plugin: GDScript = preload("./bone_map_editor_plugin.gd")
const unidot_utils_class = preload("./unidot_utils.gd")

var unidot_utils = unidot_utils_class.new()

const ASSET_TYPE_YAML = 1
const ASSET_TYPE_MODEL = 2
const ASSET_TYPE_TEXTURE = 3
const ASSET_TYPE_ANIM = 4
const ASSET_TYPE_YAML_POST_MODEL = 5
const ASSET_TYPE_PREFAB = 6
const ASSET_TYPE_SCENE = 7
const ASSET_TYPE_UNKNOWN = 8

const SHOULD_CONVERT_TO_GLB: bool = false
const USE_BUILTIN_FBX: bool = false # true

const SILHOUETTE_FIX_THRESHOLD: float = 3.0 # 28.0

var STUB_PNG_FILE: PackedByteArray = Marshalls.base64_to_raw("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQot" + "tAAAAABJRU5ErkJggg==")

#const DEBUG_RAW_PARSED_ASSET_TYPES := ".anim.tres"
const DEBUG_RAW_PARSED_ASSET_TYPES := ".disabled"

func write_sentinel_png(sentinel_filename: String):
	var f: FileAccess = FileAccess.open(sentinel_filename, FileAccess.WRITE)
	f.store_buffer(STUB_PNG_FILE)
	f.flush()
	f.close()
	f = null


class AssetHandler:
	var unidot_utils = unidot_utils_class.new()
	var editor_interface: EditorInterface = null

	func _init():
		var ep = EditorPlugin.new()
		editor_interface = ep.get_editor_interface()
		ep.queue_free()

	class ConfigFileCompare:
		extends ConfigFile
		var modified: bool = false
		var pkgasset: RefCounted = null

		func _init(pkgasset: RefCounted):
			self.pkgasset = pkgasset

		func set_value_compare(section: String, key: String, value: Variant) -> bool:
			var ret: bool = false
			if not self.has_section_key(section, key):
				pkgasset.log_debug("Added new section:" + section + " key:" + key + " : " + str(value))
				ret = true
			else:
				var existing_val = self.get_value(section, key)
				if typeof(existing_val) != typeof(value):
					pkgasset.log_debug("Modified type section:" + section + " key:" + key + " : " + str(existing_val) + " => " + str(value))
					ret = true
				elif existing_val != value:
					pkgasset.log_debug("Modified section:" + section + " key:" + key + " : " + str(existing_val) + " => " + str(value))
					ret = true
			modified = modified or ret
			if ret:
				self.set_value(section, key, value)
			return ret

		func was_modified() -> bool:
			return modified

	func calc_existing_md5(fname: String) -> PackedByteArray:
		var dres: DirAccess = DirAccess.open("res://")
		if not dres.file_exists(fname):
			return PackedByteArray()
		var fres: FileAccess = FileAccess.open(fname, FileAccess.READ)
		if fres == null:
			return PackedByteArray()
		var flen: int = fres.get_length()
		var buf = fres.get_buffer(flen)
		fres.close()
		fres = null
		if len(buf) != flen:
			return PackedByteArray()
		return calc_md5(buf)

	func calc_md5(pba: PackedByteArray) -> PackedByteArray:
		var md5 = HashingContext.new()
		md5.start(HashingContext.HASH_MD5)
		md5.update(pba)
		return md5.finish()

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String) -> String:
		var path: String = pkgasset.pathname
		if len(path) == 0:
			pkgasset.log_fail("pkgasset.pathname is empty")
		var data_buf: PackedByteArray = pkgasset.asset_tar_header.get_data()
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, thread_subdir, path, data_buf)
		if len(output_path) == 0:
			pkgasset.existing_data_md5 = calc_existing_md5(path)
			pkgasset.data_md5 = calc_md5(data_buf)
			if pkgasset.existing_data_md5 != pkgasset.data_md5:
				var outfile: FileAccess = FileAccess.open(tmpdir + "/" + path, FileAccess.WRITE_READ)
				outfile.store_buffer(data_buf)
				outfile.flush()
				outfile.close()
				outfile = null
			output_path = pkgasset.pathname
		if len(output_path) == 0:
			pkgasset.log_fail("output_path became empty " + str(pkgasset.pathname))
		pkgasset.log_debug("Updating file at " + output_path)
		return output_path

	func write_godot_import(pkgasset: Object, force_keep: bool) -> bool:
		return false

	func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
		if pkgasset.existing_data_md5 != pkgasset.data_md5:
			var dres = DirAccess.open("res://")
			pkgasset.log_debug("Renaming " + temp_path + " to " + pkgasset.pathname)
			dres.rename(temp_path, pkgasset.pathname)
			return true
		return false

	func get_asset_type(pkgasset: Object) -> int:
		return ASSET_TYPE_UNKNOWN

	func uses_godot_importer(pkgasset: Object) -> bool:
		return true

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		return ""

	func finished_import(pkgasset: Object, res: Resource):
		if res == null:
			var dres = DirAccess.open("res://")
			pkgasset.log_fail("Due to failed import, renaming " + pkgasset.pathname + " to " + pkgasset.pathname + ".failed_import")
			dres.rename(pkgasset.pathname, pkgasset.pathname + ".failed_import")
		else:
			pkgasset.log_debug("Successfully imported " + str(pkgasset.pathname) + " as " + str(res.resource_name) + " " + str(res))


class DefaultHandler:
	extends AssetHandler
	pass


class ImageHandler:
	extends AssetHandler

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		var user_path_base = OS.get_user_data_dir()
		var is_psd: bool = (data_buf[0] == 0x38 and data_buf[1] == 0x42 and data_buf[2] == 0x50 and data_buf[3] == 0x53)
		var is_tiff: bool = (data_buf[0] == 0x49 and data_buf[1] == 0x49 and data_buf[2] == 0x2A and data_buf[3] == 0x00) or (data_buf[0] == 0x4D and data_buf[1] == 0x4D and data_buf[2] == 0x00 and data_buf[3] == 0x2A)
		var is_png: bool = (data_buf[0] == 0x89 and data_buf[1] == 0x50 and data_buf[2] == 0x4E and data_buf[3] == 0x47) or is_tiff
		var full_output_path: String = pkgasset.pathname
		if not is_png and path.get_extension().to_lower() == "png":
			pkgasset.log_debug("I am a JPG pretending to be a " + str(path.get_extension()) + " " + str(path))
			full_output_path = full_output_path.get_basename() + ".jpg"
		elif is_png and path.get_extension().to_lower() != "png":
			pkgasset.log_debug("I am a PNG pretending to be a " + str(path.get_extension()) + " " + str(path))
			full_output_path = full_output_path.get_basename() + ".png"
		pkgasset.log_debug("PREPROCESS_IMAGE " + str(is_tiff or is_psd) + "/" + str(is_png) + " path " + str(path) + " to " + str(full_output_path))
		var temp_output_path: String = tmpdir + "/" + full_output_path
		if is_tiff or is_psd:
			var ext: String = '.tif' if is_tiff else '.psd'
			var outfile: FileAccess = FileAccess.open(temp_output_path.get_basename() + ext, FileAccess.WRITE_READ)
			outfile.store_buffer(data_buf)
			outfile.flush()
			outfile.close()
			outfile = null
			var stdout: Array = [].duplicate()
			var d = DirAccess.open("res://")
			var addon_path: String = post_import_material_remap_script.resource_path.get_base_dir().path_join("convert.exe")
			if addon_path.begins_with("res://"):
				if not d.file_exists(addon_path):
					pkgasset.log_warn("Not converting tiff to png because convert.exe is not present.")
					return ""
				addon_path = addon_path.substr(6)
			var ret = OS.execute(addon_path, [temp_output_path.get_basename() + ext, temp_output_path], stdout)
			d.remove(temp_output_path.get_basename() + ext)
			var res_file: FileAccess = FileAccess.open(temp_output_path, FileAccess.READ)
			pkgasset.data_md5 = calc_md5(res_file.get_buffer(res_file.get_length()))
			res_file.close()
			res_file = null
			pkgasset.existing_data_md5 = calc_existing_md5(full_output_path)
			if pkgasset.existing_data_md5 == pkgasset.data_md5:
				d.remove(temp_output_path)
		else:
			pkgasset.existing_data_md5 = calc_existing_md5(full_output_path)
			pkgasset.data_md5 = calc_md5(data_buf)
			if pkgasset.existing_data_md5 != pkgasset.data_md5:
				var outfile: FileAccess = FileAccess.open(temp_output_path, FileAccess.WRITE_READ)
				outfile.store_buffer(data_buf)
				outfile.flush()
				outfile.close()
				outfile = null
		return full_output_path

	func get_asset_type(pkgasset: Object) -> int:
		return ASSET_TYPE_TEXTURE

	func write_godot_import(pkgasset: Object, force_keep: bool) -> bool:
		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFileCompare.new(pkgasset)
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			pkgasset.log_debug("Failed to load .import config file for " + pkgasset.pathname)
			cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
			match importer.keys.get("textureShape", 0):
				2:
					cfile.set_value("remap", "type", "CompressedCubemap")
				4:
					cfile.set_value("remap", "type", "CompressedTexture2DArray")
				8:
					cfile.set_value("remap", "type", "CompressedTexture3D")
				_: # 1 = standard 2D texture
					cfile.set_value("remap", "type", "CompressedTexture2D")
		if force_keep:
			cfile.set_value("remap", "importer", "keep")
			if cfile.has_section_key("remap", "type"):
				cfile.erase_section_key("remap", "type")
			if pkgasset.pathname.validate_filename().is_empty():
				pkgasset.log_fail("pathname became empty: " + str(pkgasset.pathname))
				return false
			cfile.save("res://" + pkgasset.pathname + ".import")
			return true

		match importer.keys.get("textureShape", 0):
			2:
				var image_file := Image.load_from_file(pkgasset.pathname)
				var wid: int = 0
				var hei: int = 0
				if image_file != null:
					pkgasset.log_debug("Detecting Cubemap from image size " + str(image_file.get_size()))
					wid = image_file.get_width()
					hei = image_file.get_height()
				cfile.set_value_compare("remap", "type", "CompressedCubemap")
				cfile.set_value_compare("remap", "importer", "cubemap_texture")
				# Godot "slices/arrangement", PROPERTY_HINT_ENUM, "1x6,2x3,3x2,6x1"
				var gen_cube: int = importer.keys.get("generateCubemap", 0)
				if image_file == null:
					pkgasset.log_fail("Was unable to load the image file " + str(pkgasset.pathname) + " to determine cubemap format")
				elif hei == wid or (gen_cube != 1 or gen_cube == 3 or gen_cube == 4):
					pkgasset.log_fail("Spherical cubemap layout is not supported. Godot expects a 2x3 or 1x6 grid")
				elif gen_cube == 2:
					pkgasset.log_fail("Cylindrical cubemap layout is not supported. Godot expects a 2x3 or 1x6 grid")
				elif float(wid) / hei > 5.5:
					# Very wide, 1 tall
					cfile.set_value_compare("params", "slices/arrangement", 3)
				elif float(hei) / wid > 5.5:
					# Very tall, 1 wide
					cfile.set_value_compare("params", "slices/arrangement", 0)
				elif float(hei) / wid > 1.3 and float(hei) / wid < 1.4:
					pkgasset.log_fail("Cross cubemap layout is not supported. Godot expects 2x3 grid")
					# More tall than wide
					cfile.set_value_compare("params", "slices/arrangement", 1)
				elif float(wid) / hei > 1.3 and float(wid) / hei < 1.4:
					pkgasset.log_fail("Cross cubemap layout is not supported. Godot expects 3x2 grid")
					# More wide than tall
					cfile.set_value_compare("params", "slices/arrangement", 2)
				elif float(hei) / wid > 1.4 and float(hei) / wid < 1.6:
					# More tall than wide: godot compatible 2x3
					cfile.set_value_compare("params", "slices/arrangement", 1)
				elif float(wid) / hei > 1.4 and float(wid) / hei < 1.6:
					# More wide than tall: godot compatible 3x2
					cfile.set_value_compare("params", "slices/arrangement", 2)
				elif float(wid) / hei > 1.9 and float(wid) / hei < 2.1:
					pkgasset.log_fail("Cylinder cubemap layout is not supported. Godot expects a 2x3 or 1x6 grid")
					# More wide than tall: godot compatible 3x2
					cfile.set_value_compare("params", "slices/arrangement", 2)
				else:
					pkgasset.log_fail("Unknown cubemap layout! Godot expects a 2x3 or 1x6 grid")
			4:
				cfile.set_value_compare("remap", "type", "CompressedTexture2DArray")
				cfile.set_value_compare("remap", "importer", "2d_array_texture")
				if importer.keys.get("flipbookColumns", 0) > 0:
					cfile.set_value_compare("params", "slices/horizontal", importer.keys.get("flipbookColumns", 0))
				if importer.keys.get("flipbookRows", 0) > 0:
					cfile.set_value_compare("params", "slices/vertical", importer.keys.get("flipbookRows", 0))
			8:
				cfile.set_value_compare("remap", "type", "CompressedTexture3D")
				cfile.set_value_compare("remap", "importer", "3d_texture")
				if importer.keys.get("flipbookColumns", 0) > 0:
					cfile.set_value_compare("params", "slices/horizontal", importer.keys.get("flipbookColumns", 0))
				if importer.keys.get("flipbookRows", 0) > 0:
					cfile.set_value_compare("params", "slices/vertical", importer.keys.get("flipbookRows", 0))
			_: # 1 = standard 2D texture
				cfile.set_value_compare("remap", "type", "CompressedTexture2D")
				cfile.set_value_compare("remap", "importer", "texture")
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
		cfile.set_value_compare("params", "compress/mode", 2 if use_tc > 0 else 0)
		cfile.set_value_compare("params", "compress/bptc_ldr", 1 if use_tc == 2 else 0)
		cfile.set_value_compare("params", "compress/lossy_quality", tc_level / 100.0)
		var is_normal: int = importer.keys.get("bumpmap", {}).get("convertToNormalMap", 0)
		if is_normal == 0:
			# Detect/Enabled/Disabled
			# Detect may crash Godot later on.
			is_normal = 2
		if importer.keys.get("textureType", 0) == 1:
			is_normal = 1
		cfile.set_value_compare("params", "compress/normal_map", is_normal)
		cfile.set_value_compare("params", "detect_3d/compress_to", 0)  # 0 = Disable (avoid crash)
		# Roughness mode: Detect/Disable/Red/Green/etc.
		# 1 = avoids crash later on.
		# TODO: We may want an import setting to invert a channel for roughness use.
		cfile.set_value_compare("params", "roughness/mode", 1)
		# FIXME: No way yet to use premultiplied alpha in Godot 3D shaders
		# importer.keys.get("alphaIsTransparency", 0) != 0)
		cfile.set_value_compare("params", "process/premult_alpha", 0)
		cfile.set_value_compare("params", "process/size_limit", max_texture_size)
		cfile.set_value_compare("params", "mipmaps/generate", importer.keys.get("mipmaps", {}).get("enableMipMap", 0) != 0)
		if pkgasset.pathname.validate_filename().is_empty():
			pkgasset.log_fail("pathname became empty for image: " + str(pkgasset.pathname))
			return false
		cfile.save("res://" + pkgasset.pathname + ".import")
		return cfile.was_modified()


class AudioHandler:
	extends AssetHandler
	var importer: String = "wav"
	var resource_type: String = "AudioStreamSample"

	func create_with_type(importer: String, resource_type: String):
		var ret = self
		ret.importer = importer
		ret.resource_type = resource_type
		return ret

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		return ""

	func write_godot_import(pkgasset: Object, force_keep: bool) -> bool:
		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFileCompare.new(pkgasset)
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			pkgasset.log_debug("Failed to load .import config file for " + pkgasset.pathname)
			cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
		if force_keep:
			cfile.set_value("remap", "importer", "keep")
			if cfile.has_section_key("remap", "type"):
				cfile.erase_section_key("remap", "type")
			if pkgasset.pathname.validate_filename().is_empty():
				pkgasset.log_fail("pathname became empty audio: " + str(pkgasset.pathname))
				return false
			cfile.save("res://" + pkgasset.pathname + ".import")
			return true

		cfile.set_value_compare("remap", "type", self.resource_type)
		cfile.set_value_compare("remap", "importer", self.importer)
		# TODO "params":
		# (MP3/OGG): loop=true, loop_offset=0
		# (WAV): edit/loop_mode=0, edit/loop_begin=0, edit/loop_end=-1
		# (WAV): compress/mode=0
		# (WAV): force/8_bit, force/mono, force/max_rate, force/max_rate_hz
		if pkgasset.pathname.validate_filename().is_empty():
			pkgasset.log_fail("pathname became empty for audio: " + str(pkgasset.pathname))
			return false
		cfile.save("res://" + pkgasset.pathname + ".import")
		return cfile.was_modified()

	func get_asset_type(pkgasset: Object) -> int:
		return ASSET_TYPE_TEXTURE


class YamlHandler:
	extends AssetHandler
	const tarfile: GDScript = preload("./tarfile.gd")

	func parse_yaml_or_binary(pkgasset: Object, temp_path: String) -> void:
		var outfile: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE_READ)
		if outfile == null:
			pkgasset.log_fail("Failed to open temporary path " + temp_path)
			return
		var buf: PackedByteArray = pkgasset.asset_tar_header.get_data()
		outfile.store_buffer(buf)
		outfile.flush()
		outfile.close()
		outfile = null
		if buf[8] == 0 and buf[9] == 0:
			pkgasset.parsed_asset = pkgasset.parsed_meta.parse_binary_asset(buf)
		else:
			var sf: Object = tarfile.StringFile.new()
			sf.init(buf.get_string_from_utf8())
			pkgasset.parsed_asset = pkgasset.parsed_meta.parse_asset(sf)
		if pkgasset.parsed_asset == null:
			pkgasset.log_fail("Parse asset failed " + pkgasset.pathname + "/" + pkgasset.guid)

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String) -> String:
		# .anim assets contain nested structs for each keyframe
		# If importing dozens of animations at once, godot may run out of memory.
		var temp_path: String = tmpdir + "/" + pkgasset.pathname
		if get_file_extension_without_early_parse(pkgasset) == "":
			parse_yaml_or_binary(pkgasset, temp_path)
		pkgasset.log_debug("Done with " + temp_path + "/" + pkgasset.guid)
		return preprocess_asset(pkgasset, tmpdir, thread_subdir, pkgasset.pathname, PackedByteArray())

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		var early_file_ext: String = get_file_extension_without_early_parse(pkgasset)
		if early_file_ext != "":
			var new_pathname = pkgasset.pathname.get_basename() + early_file_ext
			return new_pathname
		if pkgasset.parsed_asset == null:
			pkgasset.log_fail("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has was not parsed as YAML")
			return ""
		var main_asset: RefCounted = null
		var godot_resource: Resource = null

		if pkgasset.parsed_meta.main_object_id != -1 and pkgasset.parsed_meta.main_object_id != 0:
			if pkgasset.parsed_asset.assets.has(pkgasset.parsed_meta.main_object_id):
				main_asset = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id]
			else:
				pkgasset.log_fail("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " missing main object id " + str(pkgasset.parsed_meta.main_object_id) + "!")
		else:
			pkgasset.log_fail("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has no main object id!")
		var new_pathname: String = pkgasset.pathname
		if main_asset != null:
			new_pathname = pkgasset.pathname.get_basename() + main_asset.get_godot_extension()  # ".mat.tres"
		return new_pathname

	func get_asset_type(pkgasset: Object) -> int:
		var extn: String = pkgasset.orig_pathname.get_extension().to_lower()
		if extn == "unity":
			return ASSET_TYPE_SCENE
		if extn == "prefab":
			return ASSET_TYPE_PREFAB
		if extn == "anim":
			# FIXME: need to find PPtr dependencies and toposort.
			return ASSET_TYPE_ANIM
		if extn == "controller" or extn == "overridecontroller":
			return ASSET_TYPE_YAML_POST_MODEL
		if pkgasset.parsed_meta.type_to_fileids.has("TerrainData"):
			# TerrainData depends on prefab assets.
			return ASSET_TYPE_PREFAB
		return ASSET_TYPE_YAML

	func uses_godot_importer(pkgasset: Object) -> bool:
		return false

	func get_file_extension_without_early_parse(pkgasset: Object) -> String:
		if get_asset_type(pkgasset) == ASSET_TYPE_ANIM:
			# If we parse too many .anim files which are too big, we can use too much RAM
			if pkgasset.asset_tar_header.get_size() > 50000:
				# Returning a file extension here short-circuits the early parse.
				# So we will parse the big animation files in the main thread one-by-one.
				return ".anim.tres"
		return ""

	func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
		if get_file_extension_without_early_parse(pkgasset) != "":
			parse_yaml_or_binary(pkgasset, temp_path)
		if pkgasset.parsed_asset == null:
			pkgasset.log_fail("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has was not parsed as YAML")
			return false
		var main_asset: RefCounted = null
		var godot_resource: Resource = null

		if pkgasset.parsed_meta.main_object_id != 0 and pkgasset.parsed_asset.assets.has(pkgasset.parsed_meta.main_object_id):
			main_asset = pkgasset.parsed_asset.assets[pkgasset.parsed_meta.main_object_id]
		else:
			pkgasset.log_fail("Asset " + pkgasset.pathname + " guid " + pkgasset.parsed_meta.guid + " has no main object id " + str(pkgasset.parsed_meta.main_object_id) + "!")

		var extra_resources: Dictionary = {}
		if main_asset != null:
			extra_resources = main_asset.get_extra_resources()
		for extra_asset_fileid in extra_resources:
			var file_ext: String = extra_resources.get(extra_asset_fileid)
			var created_res: Resource = main_asset.get_extra_resource(extra_asset_fileid)
			pkgasset.log_debug("Creating " + str(extra_asset_fileid) + " is " + str(created_res) + " at " + str(pkgasset.pathname.get_basename() + file_ext))
			if created_res != null:
				var new_pathname: String = "res://" + pkgasset.orig_pathname.get_basename() + file_ext  # ".skin.tres"
				created_res.resource_name = pkgasset.orig_pathname.get_basename().get_file()
				unidot_utils.save_resource(created_res, new_pathname)
				#created_res = load(new_pathname)
				pkgasset.parsed_meta.insert_resource(extra_asset_fileid, created_res)

		if main_asset != null:
			godot_resource = main_asset.create_godot_resource()

		if get_file_extension_without_early_parse(pkgasset) != "" or get_asset_type(pkgasset) == ASSET_TYPE_ANIM:
			pkgasset.parsed_asset.assets.clear()
			pkgasset.parsed_asset = null
			pkgasset.parsed_meta.parsed = null

		if godot_resource == pkgasset.parsed_meta:
			return false
		if godot_resource != null:
			# Save main resource at end, so that it can reference extra resources.
			unidot_utils.save_resource(godot_resource, pkgasset.pathname)
		if godot_resource == null or pkgasset.pathname.ends_with(DEBUG_RAW_PARSED_ASSET_TYPES):
			var rpa = raw_parsed_asset.new()
			rpa.path = pkgasset.pathname
			rpa.guid = pkgasset.guid
			rpa.meta = pkgasset.parsed_meta.duplicate()
			for key in pkgasset.parsed_asset.assets:
				var parsed_obj: RefCounted = pkgasset.parsed_asset.assets[key]
				rpa.objects[str(key) + ":" + str(parsed_obj.type)] = pkgasset.parsed_asset.assets[key].keys
			rpa.resource_name + pkgasset.pathname.get_basename().get_file()
			unidot_utils.save_resource(rpa, pkgasset.pathname + ".raw.tres")
		return true


class SceneHandler:
	extends YamlHandler

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		var is_prefab = pkgasset.orig_pathname.get_extension().to_lower() != "unity"
		var new_pathname: String = pkgasset.pathname.get_basename() + (".prefab.tscn" if is_prefab else ".tscn")
		return new_pathname

	func write_godot_asset(pkgasset, temp_path) -> bool:
		var is_prefab = pkgasset.orig_pathname.get_extension().to_lower() != "unity"
		var packed_scene: PackedScene = convert_scene.new().pack_scene(pkgasset, is_prefab)
		if packed_scene != null:
			unidot_utils.save_resource(packed_scene, "res://" + pkgasset.pathname)
			unidot_utils.editor_interface.reload_scene_from_path("res://" + pkgasset.pathname)
			return true
		return false


class BaseModelHandler:
	extends AssetHandler

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		var already_rewrote_file = false
		if str(pkgasset.pathname).to_lower().ends_with(".dae"):
			var buffer_as_ascii: String = data_buf.get_string_from_utf8()  # may contain unicode
			var pos: int = buffer_as_ascii.find("up_axis")
			if pos != -1:
				pos = buffer_as_ascii.find(">", pos)
				if pos != -1:
					var next_pos: int = buffer_as_ascii.find("<", pos)
					var up_axis = buffer_as_ascii.substr(pos + 1, next_pos - pos - 1).strip_edges()
					pkgasset.parsed_meta.internal_data["up_axis"] = up_axis
					if up_axis != "Y_UP":
						var outfile: FileAccess = FileAccess.open(tmpdir + "/" + pkgasset.pathname, FileAccess.WRITE_READ)
						outfile.store_buffer(data_buf.slice(0, pos + 1))
						outfile.store_string("Y_UP")
						outfile.store_buffer(data_buf.slice(next_pos))
						outfile.flush()
						var fpos = outfile.get_position()
						outfile.seek(0)
						pkgasset.data_md5 = calc_md5(outfile.get_buffer(fpos))
						outfile.close()
						outfile = null
						pkgasset.existing_data_md5 = calc_existing_md5(pkgasset.pathname)
						already_rewrote_file = true
		if already_rewrote_file:
			return pkgasset.pathname
		return ""

	func get_asset_type(pkgasset: Object) -> int:
		return ASSET_TYPE_MODEL

	func write_godot_import(pkgasset: Object, force_keep: bool) -> bool:
		var importer = pkgasset.parsed_meta.importer
		var cfile = ConfigFileCompare.new(pkgasset)
		if cfile.load("res://" + pkgasset.pathname + ".import") != OK:
			pkgasset.log_debug("Failed to load .import config file for " + pkgasset.pathname)
			cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
			cfile.set_value("remap", "importer_version", 1)
		if force_keep:
			cfile.set_value("remap", "importer", "keep")
			if cfile.has_section_key("remap", "type"):
				cfile.erase_section_key("remap", "type")
			cfile.set_value("params", "import_script/path", "")
			if pkgasset.pathname.validate_filename().is_empty():
				pkgasset.log_fail("pathname became empty in model: " + str(pkgasset.pathname))
				return false
			cfile.save("res://" + pkgasset.pathname + ".import")
			return true

		cfile.set_value_compare("remap", "importer", "scene")
		cfile.set_value("params", "import_script/path", post_import_material_remap_script.resource_path)
		# I think these are the default settings now?? The option no longer exists???
		### cfile.set_value("params", "materials/location", 1) # Store on Mesh, not Node.
		### cfile.set_value("params", "materials/storage", 0) # Store in file. post-import will export.

		cfile.set_value_compare("params", "animation/fps", pkgasset.parsed_meta.internal_data.get("anim_bake_fps", 30))
		# fps should match the bake30 option passed to FBX2glTF, it may ignore the original framerate...
		# Unity seems to operate in terms of frames but no indication of time here....
		cfile.set_value_compare("params", "animation/import", importer.animation_import)
		# Humanoid animations in particular are sensititve to immutable tracks being shared across rigs.
		cfile.set_value_compare("params", "animation/remove_immutable_tracks", false)

		# FIXME: Godot has a major bug if light baking is used:
		# it leaves a file ".glb.unwrap_cache" open and causes future imports to fail.
		cfile.set_value_compare("params", "meshes/light_baking", importer.meshes_light_baking)
		cfile.set_value_compare("params", "meshes/ensure_tangents", importer.ensure_tangents)
		cfile.set_value_compare("params", "meshes/create_shadow_meshes", false)  # Until visual artifacts with shadow meshes get fixed
		cfile.set_value_compare("params", "nodes/root_scale", pkgasset.parsed_meta.internal_data.get("scale_correction_factor", 1.0))
		cfile.set_value_compare("params", "nodes/apply_root_scale", true)
		cfile.set_value_compare("params", "nodes/root_name", "Root Scene")
		# addCollider???? TODO

		# ??? animation/optimizer setting seems to be missing?
		var subresources: Dictionary = cfile.get_value("params", "_subresources", {})
		var anim_clips: Array[Dictionary] = importer.get_animation_clips()
		## animation/clips don't seem to work at least in 4.0.... why even bother?
		## We should use an import script I guess.
		#cfile.set_value("params", "animation/clips/amount", len(anim_clips))
		#var idx: int = 0
		subresources["animations"] = {}

		var fps_ratio: float = pkgasset.parsed_meta.internal_data.get("anim_frames_fps_ratio", 1.0)
		var used_animation_names: Dictionary = pkgasset.parsed_meta.internal_data.get("used_animation_names", {})
		for anim_clip in anim_clips:
			var take_name = anim_clip["take_name"]
			if not used_animation_names.has(take_name):
				for key in used_animation_names:
					pkgasset.log_warn("Substituting requested takeName " + str(take_name) + " for first animation " + str(key))
					take_name = key # Usually just one. Often "Take 001"
					break
			if not subresources["animations"].has(take_name):
				subresources["animations"][take_name] = {}
			var take: Dictionary = subresources["animations"][take_name]
			var idx: int = take.get("slices/amount", 0) + 1  # 1-indexed
			var prefix: String = "slice_" + str(idx)

			# FIXME: If take_name == name, godot won't actually apply the slice data.
			take[prefix + "/name"] = anim_clip.get("name")
			take[prefix + "/start_frame"] = fps_ratio * anim_clip.get("start_frame")
			take[prefix + "/end_frame"] = fps_ratio * anim_clip.get("end_frame")
			take["settings/loop_mode"] = anim_clip.get("loop_mode")
			take[prefix + "/loop_mode"] = anim_clip.get("loop_mode")
			take[prefix + "/save_to_file/enabled"] = false  # TODO
			take[prefix + "/save_to_file/keep_custom_tracks"] = false # Buggy through 4.2
			take[prefix + "/save_to_file/path"] = ""  # TODO
			take["slices/amount"] = idx  # 1-indexed
			# animation/import

		if not subresources.has("nodes"):
			subresources["nodes"] = {}
		if not subresources["nodes"].has("PATH:AnimationPlayer"):
			subresources["nodes"]["PATH:AnimationPlayer"] = {}
		if importer.keys.get("animationType", 2) == 3:
			if not subresources["nodes"].has("PATH:Skeleton3D"):
				subresources["nodes"]["PATH:Skeleton3D"] = {}
			var bone_map: BoneMap = importer.generate_bone_map_from_human()
			# TODO: Allow generating BoneMap from Avatar object, too.
			subresources["nodes"]["PATH:Skeleton3D"]["retarget/bone_map"] = bone_map
			# FIXME: Disabled fix_silhouette because the pre-silhouette matrix is not being calculated yet
			# This would break skins and unpacked prefabs.
			subresources["nodes"]["PATH:Skeleton3D"]["retarget/rest_fixer/fix_silhouette/enable"] = false
			#subresources["nodes"]["PATH:Skeleton3D"]["retarget/rest_fixer/fix_silhouette/threshold"] = SILHOUETTE_FIX_THRESHOLD
		var anim_player_settings: Dictionary = subresources["nodes"]["PATH:AnimationPlayer"]
		var optim_setting: Dictionary = importer.animation_optimizer_settings()
		anim_player_settings["optimizer/enabled"] = optim_setting.get("enabled", false)
		anim_player_settings["optimizer/max_linear_error"] = optim_setting.get("max_linear_error", 0.0)
		anim_player_settings["optimizer/max_angular_error"] = optim_setting.get("max_angular_error", 0.0)
		cfile.set_value("params", "_subresources", subresources)
		#cfile.set_value_compare("params", "animation/optimizer/enabled", optim_setting.get("enabled"))
		#cfile.set_value_compare("params", "animation/optimizer/max_linear_error", optim_setting.get("max_linear_error"))
		#cfile.set_value_compare("params", "animation/optimizer/max_angular_error", optim_setting.get("max_angular_error"))
		if pkgasset.pathname.validate_filename().is_empty():
			pkgasset.log_fail("pathname became empty for model: " + str(pkgasset.pathname))
			return false
		cfile.save("res://" + pkgasset.pathname + ".import")
		return cfile.was_modified()

	func finished_import(pkgasset: Object, res: Resource):
		super.finished_import(pkgasset, res)
		if res != null:
			pass
		var cfile := ConfigFile.new()
		if pkgasset.pathname.validate_filename().is_empty():
			pkgasset.log_fail("pathname became empty in finished_import: " + str(pkgasset.pathname))
			return
		var import_file_path: String = "res://" + pkgasset.pathname + ".import"
		if cfile.load(import_file_path) != OK:
			pkgasset.log_fail("Unable to load " + str(import_file_path) + " to remove post-import script")
			return
		cfile.set_value("params", "import_script/path", "")
		var subresources: Dictionary = cfile.get_value("params", "_subresources", {})
		if not subresources.has("animations"):
			subresources["animations"] = {}
		var unused_anims: Dictionary = pkgasset.parsed_meta.imported_animation_paths.duplicate()
		for take_name in subresources["animations"]:
			var anim_properties = subresources["animations"][take_name]
			var active_slices: Dictionary
			var has_slices: bool = false
			for keys in anim_properties:
				var key: String = keys
				if key.begins_with("slice_") and key.ends_with("/name") and anim_properties[key]:
					# Slice has a name, so it is active
					has_slices = true
					if unused_anims.has(anim_properties[key]):
						active_slices[key.split('/')[0]] = unused_anims[anim_properties[key]]
						unused_anims.erase(anim_properties[key])
			for slice_key in active_slices:
				anim_properties[slice_key + "/save_to_file/enabled"] = true
				anim_properties[slice_key + "/save_to_file/keep_custom_tracks"] = false # Buggy through 4.2
				anim_properties[slice_key + "/save_to_file/path"] = active_slices[slice_key]
		for take_name in unused_anims:
			if not (subresources["animations"].has(take_name)):
				subresources["animations"][take_name] = {}
			subresources["animations"][take_name]["save_to_file/enabled"] = true
			subresources["animations"][take_name]["save_to_file/keep_custom_tracks"] = true # Non-slices are not buggy
			subresources["animations"][take_name]["save_to_file/path"] = unused_anims[take_name]
		if not subresources.has("meshes"):
			subresources["meshes"] = {}
		for mesh_name in pkgasset.parsed_meta.imported_mesh_paths:
			if not (subresources["meshes"].has(mesh_name)):
				subresources["meshes"][mesh_name] = {}
			subresources["meshes"][mesh_name]["save_to_file/enabled"] = true
			subresources["meshes"][mesh_name]["save_to_file/make_streamable"] = ""
			subresources["meshes"][mesh_name]["save_to_file/path"] = pkgasset.parsed_meta.imported_mesh_paths[mesh_name]
		if not subresources.has("materials"):
			subresources["materials"] = {}
		for material_name in pkgasset.parsed_meta.imported_material_paths:
			if not (subresources["materials"].has(material_name)):
				subresources["materials"][material_name] = {}
			subresources["materials"][material_name]["use_external/enabled"] = true
			subresources["materials"][material_name]["use_external/path"] = pkgasset.parsed_meta.imported_material_paths[material_name]
		cfile.set_value("params", "_subresources", subresources)
		#cfile.set_value_compare("params", "animation/optimizer/enabled", optim_setting.get("enabled"))
		#cfile.set_value_compare("params", "animation/optimizer/max_linear_error", optim_setting.get("max_linear_error"))
		#cfile.set_value_compare("params", "animation/optimizer/max_angular_error", optim_setting.get("max_angular_error"))
		cfile.save(import_file_path)

	func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
		# super.write_godot_asset(pkgasset, temp_path)
		# Duplicate code since super causes a weird nonsensical error cannot call "importer()" function...
		if USE_BUILTIN_FBX or pkgasset.existing_data_md5 != pkgasset.data_md5:
			var dres = DirAccess.open("res://")
			pkgasset.log_debug("Renaming " + temp_path + " to " + pkgasset.pathname)
			dres.rename(temp_path, pkgasset.pathname)
			if temp_path.ends_with(".gltf"):
				dres.rename(temp_path.get_basename() + ".bin", pkgasset.pathname.get_basename() + ".bin")
			return true
		return false


class FbxHandler:
	extends BaseModelHandler

	# From core/string/ustring.cpp
	func find_in_buffer(p_buf: PackedByteArray, p_str: PackedByteArray, p_from: int = 0, p_to: int = -1) -> int:
		if p_from < 0:
			return -1
		var src_len: int = len(p_str)
		var xlen: int = len(p_buf)
		if p_to != -1 and xlen > p_to:
			xlen = p_to
		if src_len == 0 or xlen == 0:
			return -1  # won't find anything!
		var i: int = p_from
		var ilen: int = xlen - src_len
		while i < ilen:
			var found: bool = true
			var j: int = 0
			while j < src_len:
				var read_pos: int = i + j
				if read_pos >= xlen:
					push_error("FBX fail read_pos>=len")
					return -1
				if p_buf[read_pos] != p_str[j]:
					found = false
					break
				j += 1

			if found:
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

	func convert_to_int(s: String) -> int:
		return s.to_int()

	func _is_fbx_binary(fbx_file_binary: PackedByteArray) -> bool:
		return find_in_buffer(fbx_file_binary, "Kaydara FBX Binary".to_ascii_buffer(), 0, 64) != -1

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
				var fn_utf8: PackedByteArray = spb.get_data(strlen)[1]  # NOTE: Do we need to detect charset? FBX should be unicode
				strlist.append(fn_utf8.get_string_from_ascii())
		return strlist

	func _extract_fbx_textures_ascii(pkgasset: Object, buffer_as_ascii: String) -> PackedStringArray:
		var strlist: PackedStringArray = PackedStringArray()
		var texname1_needle = '"XRefUrl",'
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
				nextpos = buffer_as_ascii.find('"', nextpos + 1)
				nextpos = buffer_as_ascii.find('"', nextpos + 1)
				nextpos = buffer_as_ascii.find('"', nextpos + 1)
			elif texname2_pos != -1:
				nextpos = texname2_pos + len(texname2_needle)
				newlinepos = buffer_as_ascii.find("\n", nextpos)
				texname2_pos = buffer_as_ascii.find(texname2_needle, texname2_pos + 1)
				nextpos = buffer_as_ascii.find('"', nextpos + 1)
			var lastquote: int = buffer_as_ascii.find('"', nextpos + 1)
			if lastquote > newlinepos:
				pkgasset.log_warn("Failed to parse texture from " + buffer_as_ascii.substr(nextpos, newlinepos - nextpos))
			else:
				strlist.append(buffer_as_ascii.substr(nextpos + 1, lastquote - nextpos - 1))
		return strlist

	func _preprocess_fbx_scale_binary(pkgasset: Object, fbx_file_binary: PackedByteArray, useFileScale: bool, globalScale: float) -> PackedByteArray:
		if useFileScale and is_equal_approx(globalScale, 1.0):
			pkgasset.log_debug("TODO: when we switch to the Godot FBX implementation, we can short-circuit this code and return early.")
			#return fbx_file_binary
		var filename: String = pkgasset.pathname
		var needle_buf: PackedByteArray = "\u0001PS\u000F...UnitScaleFactorS".to_ascii_buffer()
		needle_buf[4] = 0
		needle_buf[5] = 0
		needle_buf[6] = 0
		var scale_factor_pos: int = find_in_buffer(fbx_file_binary, needle_buf)
		if scale_factor_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return fbx_file_binary

		# TODO: If any Model has Visibility == 0.0, then the mesh gets lost in FBX2glTF
		# Find all instances of VisibilityS\0\0\0S\1\0\0\0AD followed by 0.0 Double or 0.0 Float and replace with 1.0
		# in ASCII, it is   P: "Visibility", "Visibility", "", "A",0 -> 1

		var spb: StreamPeerBuffer = StreamPeerBuffer.new()
		spb.data_array = fbx_file_binary
		spb.big_endian = false
		spb.seek(scale_factor_pos + len(needle_buf))
		var datatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:  # ord() is broken?!
			pkgasset.log_fail(filename + ": not a string, or datatype invalid " + datatype)
			return fbx_file_binary
		var subdatatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:
			pkgasset.log_fail(filename + ": not a string, or subdatatype invalid " + datatype + " " + subdatatype)
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
			pkgasset.log_fail(filename + ": not a float or double " + str(number_type))
			return fbx_file_binary
		var new_scale: float = _adjust_fbx_scale(pkgasset, scale, useFileScale, globalScale)
		pkgasset.log_debug(filename + ": Binary FBX: UnitScaleFactor=" + str(scale) + " -> " + str(new_scale) + " (Scale Factor = " + str(globalScale) + "; Convert Units = " + ("on" if useFileScale else "OFF") + ")")
		if is_double:
			spb.seek(spb.get_position() - 8)
			pkgasset.log_debug("double - Seeked to " + str(spb.get_position()))
			spb.put_double(new_scale)
		else:
			spb.seek(spb.get_position() - 4)
			pkgasset.log_debug("float - Seeked to " + str(spb.get_position()))
			spb.put_float(new_scale)
		return spb.data_array

	func _preprocess_fbx_scale_ascii(pkgasset: Object, fbx_file_binary: PackedByteArray, buffer_as_ascii: String, useFileScale: bool, globalScale: float) -> PackedByteArray:
		if useFileScale and is_equal_approx(globalScale, 1.0):
			pkgasset.log_debug("TODO: when we switch to the Godot FBX implementation, we can short-circuit this code and return early.")
			#return fbx_file_binary
		var filename: String = pkgasset.pathname
		var output_buf: PackedByteArray = fbx_file_binary
		var scale_factor_pos: int = buffer_as_ascii.find('"UnitScaleFactor"')
		if scale_factor_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return output_buf
		var newline_pos: int = buffer_as_ascii.find("\n", scale_factor_pos)
		var comma_pos: int = buffer_as_ascii.rfind(",", newline_pos)
		if newline_pos == -1 or comma_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find value for UnitScaleFactor in ASCII FBX.")
			return output_buf

		var scale_string: Variant = buffer_as_ascii.substr(comma_pos + 1, newline_pos - comma_pos - 1).strip_edges()
		pkgasset.log_debug("Scale as string is " + str(scale_string))
		var scale: float = convert_to_float(str(scale_string + str(NodePath())))
		var new_scale: float = _adjust_fbx_scale(pkgasset, scale, useFileScale, globalScale)
		pkgasset.log_debug(filename + ": ASCII FBX: UnitScaleFactor=" + str(scale) + " -> " + str(new_scale) + " (Scale Factor = " + str(globalScale) + "; Convert Units = " + ("on" if useFileScale else "OFF") + ")")
		output_buf = fbx_file_binary.slice(0, comma_pos + 1)
		output_buf += str(new_scale).to_ascii_buffer()
		output_buf += fbx_file_binary.slice(newline_pos, len(fbx_file_binary))
		return output_buf

	const fbx_time_modes: Dictionary = {
		# 0 (default) Appears to equate to KTIME_ONE_SECOND, or 46186158000 FPS.
		0: 30, # However, the importer treats TimeMode=0 as 30fps, which is all we care about.
		1: 120,
		2: 100,
		3: 60,
		4: 50,
		5: 48,
		6: 30,
		7: 30, # No idea... assume default = 60
		8: 29.97, # "NTSC"
		9: 29.97,
		10: 25, # "PAL"
		11: 24, # "CINEMA"
		12: 1000, # milliseconds
		13: 23.976, # cinematic
	}

	func _preprocess_fbx_anim_fps_binary(pkgasset: Object, fbx_file_binary: PackedByteArray) -> float:
		var filename: String = pkgasset.pathname
		var needle_buf: PackedByteArray = "\u0001PS\u0008...TimeModeS\u0004...enumS".to_ascii_buffer()
		needle_buf[4] = 0
		needle_buf[5] = 0
		needle_buf[6] = 0
		needle_buf[17] = 0
		needle_buf[18] = 0
		needle_buf[19] = 0
		var fps = 1.0
		var time_mode_pos: int = find_in_buffer(fbx_file_binary, needle_buf)
		if time_mode_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find TimeMode in Binary FBX.")
			return 30
		var spb := StreamPeerBuffer.new()
		spb.data_array = fbx_file_binary
		spb.big_endian = false
		spb.seek(time_mode_pos + len(needle_buf))
		var tmps: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:
			pkgasset.log_fail(filename + ": time mode type not a string, or subdatatype invalid " + str(tmps) + "|" + str(spb.get_position()))
			return 30
		spb.get_string(spb.get_32())
		if spb.get_8() != ("I").to_ascii_buffer()[0]:
			pkgasset.log_fail(filename + ": TimeMode enum value not an integer")
			return 30
		var enum_value: int = spb.get_32()
		if fbx_time_modes.has(enum_value):
			fps = fbx_time_modes[enum_value]
			pkgasset.log_debug(filename + ": FBX standard framerate " + str(fps))
			return fps

		needle_buf = "\u0001PS\u000F...CustomFrameRateS".to_ascii_buffer()
		needle_buf[4] = 0
		needle_buf[5] = 0
		needle_buf[6] = 0
		var custom_fps_pos: int = find_in_buffer(fbx_file_binary, needle_buf)
		if custom_fps_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find TimeMode in Binary FBX.")
			return 30
		spb.seek(custom_fps_pos + len(needle_buf))
		var datatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:  # ord() is broken?!
			pkgasset.log_fail(filename + ": not a string, or datatype invalid " + datatype)
			return 30
		var subdatatype: String = spb.get_string(spb.get_32())
		if spb.get_8() != ("S").to_ascii_buffer()[0]:
			pkgasset.log_fail(filename + ": not a string, or subdatatype invalid " + datatype + " " + subdatatype)
			return 30
		var extratype: String = spb.get_string(spb.get_32())
		var number_type = spb.get_8()
		var is_double: bool = false
		if number_type == ("F").to_ascii_buffer()[0]:
			fps = spb.get_float()
		elif number_type == ("D").to_ascii_buffer()[0]:
			fps = spb.get_double()
			is_double = true
		else:
			pkgasset.log_fail(filename + ": not a float or double " + str(number_type))
			return 30

		pkgasset.log_debug(filename + ": Binary FBX: Custom Anim Framerate=" + str(fps))
		# assets will have CustomFrameRate = -1 if TimeMode != 14
		if fps < 0 or is_zero_approx(fps):
			pkgasset.log_warn(filename + ": invalid CustomFrameRate: " + str(fps) + ": from time mode=" + str(enum_value))
			return 30
		return fps

	func _preprocess_fbx_anim_fps_ascii(pkgasset: Object, buffer_as_ascii: String) -> float:
		var filename: String = pkgasset.pathname
		var time_mode_pos: int = buffer_as_ascii.find('"TimeMode"')
		if time_mode_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return 30
		var newline_pos: int = buffer_as_ascii.find("\n", time_mode_pos)
		var comma_pos: int = buffer_as_ascii.rfind(",", newline_pos)
		if newline_pos == -1 or comma_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find value for UnitScaleFactor in ASCII FBX.")
			return 30

		var fps: float = 1
		var time_mode_str: String = buffer_as_ascii.substr(comma_pos + 1, newline_pos - comma_pos - 1).strip_edges()
		pkgasset.log_debug("TimeMode as string is " + str(time_mode_str))
		var enum_value: int = convert_to_int(str(time_mode_str))
		if fbx_time_modes.has(enum_value):
			fps = fbx_time_modes[enum_value]
			pkgasset.log_debug(filename + ": ASCII FBX standard framerate " + str(fps))
			return fps

		var framerate_pos: int = buffer_as_ascii.find('"CustomFrameRate"')
		if framerate_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find UnitScaleFactor in ASCII FBX.")
			return 30
		newline_pos = buffer_as_ascii.find("\n", framerate_pos)
		comma_pos = buffer_as_ascii.rfind(",", newline_pos)
		if newline_pos == -1 or comma_pos == -1:
			pkgasset.log_fail(filename + ": Failed to find value for UnitScaleFactor in ASCII FBX.")
			return 30

		var custom_fps_str: String = buffer_as_ascii.substr(comma_pos + 1, newline_pos - comma_pos - 1).strip_edges()
		pkgasset.log_debug("CustomFrameRate as string is " + str(custom_fps_str))
		fps = convert_to_float(str(custom_fps_str))
		pkgasset.log_debug(filename + ": ASCII FBX: Custom Anim Framerate=" + str(fps))
		# assets will have CustomFrameRate = -1 if TimeMode != 14
		if fps < 0 or is_zero_approx(fps):
			pkgasset.log_warn(filename + ": invalid CustomFrameRate: " + str(fps) + ": from time mode=" + str(enum_value))
			return 30
		return fps

	func _get_parent_textures_paths(source_file_path: String) -> Dictionary:
		# return source_file_path.get_basename() + "." + str(fileId) + extension
		var retlist: Dictionary = {}
		var basedir: String = source_file_path.get_base_dir()
		var texfn: String = source_file_path.get_file()
		var relpath: String = ""
		while basedir != "res://" and basedir != "/" and not basedir.is_empty() and basedir != ".":
			retlist[basedir + "/" + texfn] = relpath + texfn
			retlist[basedir + "/textures/" + texfn] = relpath + "textures/" + texfn
			retlist[basedir + "/Textures/" + texfn] = relpath + "Textures/" + texfn
			basedir = basedir.get_base_dir()
			relpath += "../"
		retlist[texfn] = relpath + texfn
		retlist["textures/" + texfn] = relpath + "textures/" + texfn
		retlist["Textures/" + texfn] = relpath + "Textures/" + texfn
		#pkgasset.log_debug("Looking in directories " + str(retlist))
		return retlist

	func _make_relative_to(filename: String, basedir: String):
		var path_beginning: String = ""
		while not filename.begins_with(basedir + "/"):
			path_beginning += "../"
			basedir = basedir.get_base_dir()
			if basedir == "":
				break
		if not basedir.is_empty():
			filename = filename.substr(len(basedir) + 1)
		return path_beginning + filename

	func _scan_project_for_textures(filename_dict: Dictionary, efsdir: EditorFileSystemDirectory = null):
		if efsdir == null:
			var fs: EditorFileSystem = EditorPlugin.new().get_editor_interface().get_resource_filesystem()
			efsdir = fs.get_filesystem()
		for i in range(efsdir.get_file_count()):
			var lowerfn: String = efsdir.get_file(i).to_lower()
			for texname in filename_dict.keys():
				if lowerfn == texname.to_lower():
					filename_dict[texname] = efsdir.get_path() + "/" + efsdir.get_file(i)
		for i in range(efsdir.get_subdir_count()):
			_scan_project_for_textures(filename_dict, efsdir.get_subdir(i))

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String) -> String:
		var full_tmpdir: String = tmpdir + "/" + thread_subdir
		var input_path: String = thread_subdir + "/" + "input.fbx"
		var temp_input_path: String = tmpdir + "/" + input_path
		if USE_BUILTIN_FBX:
			input_path = pkgasset.pathname
			temp_input_path = input_path
		var importer = pkgasset.parsed_meta.importer

		var fbx_file: PackedByteArray = pkgasset.asset_tar_header.get_data()

		var debug_outfile: FileAccess = FileAccess.open(tmpdir + "/" + pkgasset.pathname, FileAccess.WRITE_READ)
		if debug_outfile:
			debug_outfile.store_buffer(fbx_file)
			debug_outfile.flush()
			debug_outfile.close()
			debug_outfile = null

		var is_binary: bool = _is_fbx_binary(fbx_file)
		var fps: float
		var texture_name_list: PackedStringArray = PackedStringArray()
		if is_binary:
			texture_name_list = _extract_fbx_textures_binary(pkgasset, fbx_file)
			fps = _preprocess_fbx_anim_fps_binary(pkgasset, fbx_file)
			fbx_file = _preprocess_fbx_scale_binary(pkgasset, fbx_file, importer.keys.get("meshes", {}).get("useFileScale", 0) == 1, importer.keys.get("meshes", {}).get("globalScale", 1))
		else:
			var buffer_as_ascii: String = fbx_file.get_string_from_utf8()  # may contain unicode
			texture_name_list = _extract_fbx_textures_ascii(pkgasset, buffer_as_ascii)
			fps = _preprocess_fbx_anim_fps_ascii(pkgasset, buffer_as_ascii)
			fbx_file = _preprocess_fbx_scale_ascii(pkgasset, fbx_file, buffer_as_ascii, importer.keys.get("meshes", {}).get("useFileScale", 0) == 1, importer.keys.get("meshes", {}).get("globalScale", 1))
		var d := DirAccess.open("res://")
		var closest_bake_fps: float = 30
		if fps <= 25:
			closest_bake_fps = 24
		if fps >= 40:
			closest_bake_fps = 60
		var fps_ratio: float = closest_bake_fps / fps
		pkgasset.parsed_meta.internal_data["anim_orig_fbx_fps"] = fps
		pkgasset.parsed_meta.internal_data["anim_bake_fps"] = closest_bake_fps
		pkgasset.parsed_meta.internal_data["anim_frames_fps_ratio"] = fps_ratio
		d.rename(temp_input_path, temp_input_path + "x")
		d.remove(temp_input_path + "x")
		var outfile: FileAccess = FileAccess.open(temp_input_path, FileAccess.WRITE_READ)
		outfile.store_buffer(fbx_file)
		outfile.flush()
		pkgasset.log_debug("Flushed " + str(temp_input_path))
		outfile.close()
		pkgasset.log_debug("Closed " + str(temp_input_path))
		var retry_count: int = 0
		while not FileAccess.open(temp_input_path, FileAccess.READ_WRITE) and retry_count < 40:
			pkgasset.log_debug("Retry " + str(temp_input_path) + " " + str(retry_count))
			OS.delay_msec(500)
			retry_count += 1
		outfile = null
		var unique_texture_map: Dictionary = {}
		var texture_dirname = full_tmpdir
		var output_dirname = pkgasset.pathname.get_base_dir()
		pkgasset.log_debug("Referenced texture list: " + str(texture_name_list))
		for fn in texture_name_list:
			var fn_filename: String = fn.get_file()
			var replaced_extension = "png"
			if fn_filename.get_extension().to_lower() == "jpg":
				replaced_extension = "jpg"
			unique_texture_map[fn_filename.get_basename() + "." + replaced_extension] = fn_filename
		pkgasset.log_debug("Referenced textures: " + str(unique_texture_map.keys()))
		var tex_not_exists = {}
		for fn in unique_texture_map.keys():
			if not d.file_exists(texture_dirname + "/" + fn):
				pkgasset.log_debug("Creating dummy texture: " + str(texture_dirname + "/" + fn))
				var tmpf = FileAccess.open(texture_dirname + "/" + fn, FileAccess.WRITE_READ)
				tmpf.close()
				tmpf = null
			var candidate_texture_dict = _get_parent_textures_paths(output_dirname + "/" + unique_texture_map[fn])
			var tex_exists: bool = false
			for candidate_fn in candidate_texture_dict:
				#pkgasset.log_debug("candidate " + str(candidate_fn) + " INPKG=" + str(pkgasset.packagefile.path_to_pkgasset.has(candidate_fn)) + " FILEEXIST=" + str(d.file_exists(candidate_fn)))
				if pkgasset.packagefile.path_to_pkgasset.has(candidate_fn) or d.file_exists(candidate_fn):
					unique_texture_map[fn] = candidate_texture_dict[candidate_fn]
					tex_exists = true
					break
			if not tex_exists:
				tex_not_exists[fn] = ""
		if not tex_not_exists.is_empty():
			for fn in pkgasset.packagefile.path_to_pkgasset:
				for texname in tex_not_exists.keys():
					if fn.get_file().to_lower() == texname.to_lower():
						unique_texture_map[texname] = _make_relative_to(fn, output_dirname)
						tex_not_exists.erase(texname)
		if not tex_not_exists.is_empty():
			_scan_project_for_textures(tex_not_exists)
			for texname in tex_not_exists.keys():
				if not tex_not_exists[texname].is_empty():
					unique_texture_map[texname] = _make_relative_to(tex_not_exists[texname], output_dirname)
		var output_path: String = self.preprocess_asset(pkgasset, tmpdir, thread_subdir, input_path, fbx_file, unique_texture_map)
		#if len(output_path) == 0:
		#	output_path = path
		if not USE_BUILTIN_FBX:
			d.remove(temp_input_path)  # delete "input.fbx"
		for fn in unique_texture_map.keys():
			d.remove(texture_dirname + "/" + fn)
		pkgasset.log_debug("Updating file at " + output_path)
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
		var replacement_char: String = ""
		if Engine.get_version_info()["minor"] >= 1 || Engine.get_version_info()["major"] > 4:
			replacement_char = "_"
		var xret = bone_name.replace("%", replacement_char).replace("/", replacement_char).replace(":", replacement_char).replace(".", replacement_char).replace("@", replacement_char).replace('"', replacement_char)
		return xret

	func sanitize_anim_name(anim_name: String) -> String:
		return sanitize_unique_name(anim_name).replace("[", "").replace(",", "")

	func gltf_to_transform3d(node: Dictionary) -> Transform3D:
		if node.has("matrix"):
			var mat: Array = node.get("matrix", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
			var basis: Basis = Basis(Vector3(mat[0], mat[1], mat[2]), Vector3(mat[4], mat[5], mat[6]), Vector3(mat[8], mat[9], mat[10]))
			var origin = Vector3(mat[12], mat[13], mat[14])
			return Transform3D(basis, origin)
		var tra: Array = node.get("translation", [0, 0, 0])
		var rot: Array = node.get("rotation", [0, 0, 0, 1])
		var sca: Array = node.get("scale", [1, 1, 1])
		var basis: Basis = Basis(Quaternion(rot[0], rot[1], rot[2], rot[3]))
		basis = basis.scaled(Vector3(sca[0], sca[1], sca[2]))
		return Transform3D(basis, Vector3(tra[0], tra[1], tra[2]))

	func gltf_transform3d_into_json(json_node: Dictionary, xform: Transform3D) -> void:
		# To test scale folding:
		#json["nodes"][json["scenes"][json.get("scene", 0)]["nodes"][0]]["translation"] = [0.125,0.25,0.5]
		#json["nodes"][json["scenes"][json.get("scene", 0)]["nodes"][0]]["rotation"] = [0.707,0.0,0.707,0.0]
		#json["nodes"][json["scenes"][json.get("scene", 0)]["nodes"][0]]["scale"] = [1.0,2.0,0.5]
		if json_node.has("matrix"):
			json_node.erase("matrix")
		json_node["translation"] = [xform.origin.x, xform.origin.y, xform.origin.z]
		var quat = xform.basis.get_rotation_quaternion()
		json_node["rotation"] = [quat.x, quat.y, quat.z, quat.w]
		var scale = xform.basis.get_scale()
		json_node["scale"] = [scale.x, scale.y, scale.z]

	func add_empty_animation(json: Dictionary, name: String):
		var has_reset: bool = false
		if not json.has("animations"):
			json["animations"] = []
		for anim in json["animations"]:
			if anim.get("name", "") == name:
				has_reset = true
		if not has_reset:
			json["animations"].append({"channels": [], "name": name, "samplers": []})

	func add_accessor(json: Dictionary, glb_bin: PackedByteArray, acc_type: String, count: int, bin_data: PackedByteArray) -> int:
		if not json.has("accessors"):
			json["accessors"] = []
		if not json.has("bufferViews"):
			json["bufferViews"] = []
		if not json.has("buffers"):
			json["buffers"] = [{"byteLength": len(glb_bin)}]
		json["buffers"][0]["byteLength"] += len(bin_data)
		var acc: Dictionary = {
			"bufferView": len(json["bufferViews"]),
			"byteOffset": 0,
			"componentType": 5126,
			"count": count,
			"type": acc_type,
		}
		if acc_type == "SCALAR":
			acc["min"] = [0]
			acc["max"] = [0]
		var ret: int = len(json["accessors"])
		json["accessors"].append(acc)
		json["bufferViews"].append({"buffer": 0, "byteLength": len(bin_data), "byteOffset": len(glb_bin)})
		glb_bin.append_array(bin_data)
		return ret

	func add_missing_humanoid_tracks_to_animations(pkgasset: Object, json: Dictionary, glb_bin: PackedByteArray, humanoid_bone_dict: Dictionary):
		const TRANSLATION_PFX: String = "Translation$"
		var node_names_to_index: Dictionary
		var json_nodes = json.get("nodes", [])
		for node_idx in range(len(json_nodes)):
			node_names_to_index[json_nodes[node_idx].get("name", "")] = node_idx
		var single_element_input_accessor_idx: int = -1
		for anim in json.get("animations", []):
			var human_tracks_used: Dictionary
			for gltf_bone_name in humanoid_bone_dict:
				if humanoid_bone_dict[gltf_bone_name] == "Hips" or humanoid_bone_dict[gltf_bone_name] == "Root":
					human_tracks_used[TRANSLATION_PFX + gltf_bone_name] = false
				human_tracks_used[gltf_bone_name] = false
			for channel in anim["channels"]:
				if not channel["target"].has("node"):
					continue
				if channel["target"]["path"] == "rotation":
					var node_name: String = json.nodes[channel["target"]["node"]].get("name", "")
					if human_tracks_used.has(node_name):
						human_tracks_used[node_name] = true
				if channel["target"]["path"] == "translation":
					var node_name: String = json.nodes[channel["target"]["node"]].get("name", "")
					if human_tracks_used.has(TRANSLATION_PFX + node_name):
						human_tracks_used[TRANSLATION_PFX + node_name] = true
			for node_name in human_tracks_used:
				if human_tracks_used[node_name] == true:
					continue
				var is_translation: bool = node_name.begins_with(TRANSLATION_PFX)
				if is_translation:
					node_name = node_name.substr(len(TRANSLATION_PFX))
				var node_idx: int = node_names_to_index[node_name]
				# pkgasset.log_debug("anim " + str(anim.get("name", "")) + " : Adding missing track " + str(node_name) + " node_idx " + str(node_idx) + " @" + str(len(glb_bin)))
				var json_node: Dictionary = json["nodes"][node_idx]
				var pba: PackedByteArray
				var spb: StreamPeerBuffer = StreamPeerBuffer.new()
				if single_element_input_accessor_idx == -1:
					spb.big_endian = false
					spb.data_array = pba
					spb.put_float(0.0)
					single_element_input_accessor_idx = add_accessor(json, glb_bin, "SCALAR", 1, spb.data_array)
				pba = PackedByteArray()
				spb = StreamPeerBuffer.new()
				spb.big_endian = false
				spb.data_array = pba
				bone_map_editor_plugin.gltf_matrix_to_trs(json_node)
				var value_accessor: int = -1
				if is_translation:
					var json_pos: Array = json_node.get("translation", [0.0, 0.0, 0.0])
					pkgasset.log_debug("Got " + str(node_name) + " translation: " + str(json_pos))
					for flt in range(3):
						spb.put_float(json_pos[flt])
					value_accessor = add_accessor(json, glb_bin, "VEC3", 1, spb.data_array)
				else:
					var json_quat: Array = json_node.get("rotation", [0.0, 0.0, 0.0, 1.0])
					for flt in range(4):
						spb.put_float(json_quat[flt])
					value_accessor = add_accessor(json, glb_bin, "VEC4", 1, spb.data_array)
				var sampler: int = len(anim["samplers"])
				# pkgasset.log_debug("animation on node " + str(node_name) + ": " + str(sampler))
				anim["samplers"].append({"input": single_element_input_accessor_idx, "output": value_accessor})
				anim["channels"].append({"sampler": sampler, "target": {"node": node_idx, "path": "translation" if is_translation else "rotation"}})

	func gltf_remove_node(json: Dictionary, node_idx: int):
		json["nodes"].remove_at(node_idx)  # remove_at index
		for node in json["nodes"]:
			var children: Array = node.get("children", [])
			children.erase(node_idx)  # erase by value
			for i in range(len(children)):
				if children[i] > node_idx:
					children[i] -= 1
		for sk in json.get("skins", []):
			var joints: Array = sk.get("joints", [])
			for i in range(len(joints)):
				if joints[i] > node_idx:
					joints[i] -= 1
			if sk.get("skeleton", -1) > node_idx:
				sk["skeleton"] -= 1
		for scene in json["scenes"]:
			var nodes: Array = scene.get("nodes", [])
			nodes.erase(node_idx)  # erase by value
			for i in range(len(nodes)):
				if nodes[i] > node_idx:
					nodes[i] -= 1
		for anim in json.get("animations", []):
			var channels: Array = anim.get("channels", [])
			for channel_idx in range(len(channels) - 1, -1, -1):
				var channel: Dictionary = channels[channel_idx]
				if channel.get("target", {}).get("node", -1) == node_idx:
					channels.remove_at(channel_idx)
			for channel in channels:
				if channel.get("target", {}).get("node", -1) > node_idx:
					channel["target"]["node"] -= 1

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		var user_path_base: String = OS.get_user_data_dir()
		pkgasset.log_debug("I am an FBX " + str(path))
		var full_output_path: String = tmpdir + "/" + pkgasset.pathname
		var gltf_output_path: String = full_output_path.get_basename() + ".gltf"
		var bin_output_path: String = full_output_path.get_basename() + ".bin"
		var output_path: String = gltf_output_path
		var return_output_path: String = pkgasset.pathname.get_basename() + ".gltf"
		var tmp_gltf_output_path: String = tmpdir + "/" + thread_subdir + "/output.gltf"
		var tmp_bin_output_path: String = tmpdir + "/" + thread_subdir + "/buffer.bin"
		if SHOULD_CONVERT_TO_GLB:
			output_path = full_output_path.get_basename() + ".glb"
		if USE_BUILTIN_FBX:
			return pkgasset.pathname
		var stdout: Array = [].duplicate()
		var d = DirAccess.open("res://")
		var addon_path: String = editor_interface.get_editor_settings().get_setting("filesystem/import/fbx/fbx2gltf_path")
		if not addon_path.get_file().is_empty():
			if not d.file_exists(addon_path):
				pkgasset.log_warn("Not converting fbx to glb because FBX2glTF.exe is not present.")
				return ""
			if addon_path.begins_with("res://"):
				addon_path = addon_path.substr(6)
		# --long-indices auto
		# --compute-normals never|broken|missing|always
		# --blend-shape-normals --blend-shape-tangents
		var fps_bake_mode: String = "bake" + str(pkgasset.parsed_meta.internal_data.get("anim_bake_fps", 30))
		var cmdline_args := ["--pbr-metallic-roughness", "--fbx-temp-dir", tmpdir + "/" + thread_subdir, "--normalize-weights", "1", "--anim-framerate", fps_bake_mode, "-i", tmpdir + "/" + path, "-o", tmp_gltf_output_path]
		pkgasset.log_debug(addon_path + " " + " ".join(cmdline_args))
		var ret = OS.execute(addon_path, cmdline_args, stdout)
		for i in range(5):
			OS.delay_msec(500)
			#d.rename(tmpdir + "/" + path, tmpdir + "/x" + path)
			#d.copy(tmpdir + "/x" + path, tmpdir + "/" + path)
			#d.remove(tmpdir + "/x" + path)
			OS.delay_msec(500)
			# Hack, but I don't know what to do about this for now. The .close() is async or something.
			if ret == 1 and "".join(stdout).strip_edges().is_empty():
				pkgasset.log_warn("Attempt to rerun FBX2glTF to mitigate windows file close race " + str(i) + ".")
				ret = OS.execute(addon_path, cmdline_args, stdout)
		pkgasset.log_debug("FBX2glTF returned " + str(ret) + " -----")
		pkgasset.log_debug(str(stdout))
		pkgasset.log_debug("-----------------------------")
		d.rename(tmp_bin_output_path, bin_output_path)
		d.rename(tmp_gltf_output_path, gltf_output_path)
		var f: FileAccess = FileAccess.open(gltf_output_path, FileAccess.READ)
		if f == null:
			pkgasset.log_fail("Failed to open gltf output " + gltf_output_path)
			return ""
		var data: String = f.get_buffer(f.get_length()).get_string_from_utf8()
		f.close()
		f = null
		var jsonres = JSON.new()
		jsonres.parse(data)
		var json: Dictionary = jsonres.get_data()
		var bindata: PackedByteArray

		# Optional step:
		### Remove RootNode and migrate root nodes into the scene.
		var default_scene: Dictionary = json["scenes"][json.get("scene", 0)]
		# Godot prepends the scene name to the name of meshes, for some reason...
		# "Root Scene" is hardcoded in post_import_unity_model.gd so we use it here.
		default_scene["name"] = "Root Scene"
		# default_scene["name"] = pkgasset.pathname.get_file().get_basename()
		if len(default_scene["nodes"]) == 1:  # Remove redundant "RootNode" node from FBX2glTF.
			var root_node_idx: int = default_scene["nodes"][0]
			var root_node: Dictionary = json["nodes"][root_node_idx]
			if root_node.get("name", "") == "RootNode" and not root_node.get("children", []).is_empty():
				if root_node.get("mesh", -1) == -1 and root_node.get("skin", -1) == -1 and root_node.get("extensions", []).is_empty() and root_node.get("camera", -1) == -1:
					var root_xform = gltf_to_transform3d(root_node)
					if root_xform.is_equal_approx(Transform3D.IDENTITY):
						var root_children: Array = root_node["children"]
						default_scene["nodes"] = []
						root_node.erase("children")
						for child_idx in root_children:
							default_scene["nodes"].append(child_idx)
							var child_node: Dictionary = json["nodes"][child_idx]
							if not root_xform.is_equal_approx(Transform3D.IDENTITY):
								gltf_transform3d_into_json(child_node, root_xform * gltf_to_transform3d(child_node))
						gltf_remove_node(json, root_node_idx)
		f = FileAccess.open(bin_output_path, FileAccess.READ)
		bindata = f.get_buffer(f.get_length())
		var bindata_orig_length: int = len(bindata)
		f.close()
		f = null
		if SHOULD_CONVERT_TO_GLB:
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

		var importer = pkgasset.parsed_meta.importer
		var humanoid_original_transforms: Dictionary = {} # name -> Transform3D
		var original_rotations: Dictionary = {} # name -> Quaternion
		var orig_hip_position: Vector3
		var orig_root_position: Vector3
		var human_skin_nodes: Array = []
		var is_humanoid: bool = importer.keys.get("animationType", 2) == 3
		var bone_map_dict: Dictionary
		var copy_avatar: bool = false
		if is_humanoid and json.has("nodes") and importer.keys.get("avatarSetup", 1) >= 1:
			if importer.keys.get("avatarSetup", 1) == 2 or importer.keys.get("copyAvatar", 0) == 1:
				var src_ava = importer.keys.get("lastHumanDescriptionAvatarSource", [null, 0, "", 0])
				var src_ava_meta = pkgasset.meta_dependencies.get(src_ava[2], null)
				if src_ava_meta == null:
					pkgasset.log_fail("Unable to lookup meta copy avatar dependency", "lastHumanDescriptionAvatarSource", src_ava)
				else:
					bone_map_dict = src_ava_meta.importer.generate_bone_map_dict_from_human()
					humanoid_original_transforms = src_ava_meta.internal_data.get("humanoid_original_transforms", {}).duplicate()
					orig_hip_position = src_ava_meta.internal_data.get("hips_position", Vector3())
					orig_root_position = src_ava_meta.internal_data.get("root_position", Vector3())
					original_rotations = src_ava_meta.internal_data.get("original_rotations", {}).duplicate()
					pkgasset.log_debug("Copying from avatar " + str(src_ava_meta.path) + " " + str(src_ava_meta.guid) + " orig transforms " + str(len(src_ava_meta.internal_data.get("humanoid_original_transforms", {}))))
					copy_avatar = true

			if not copy_avatar and len(importer.keys.get("humanDescription", {}).get("human", [])) < 10:
				var skel: Skeleton3D = Skeleton3D.new()
				for node in json["nodes"]:
					var node_name = node.get("name", "")
					skel.add_bone(node_name)
				var i: int = 0
				for node in json["nodes"]:
					var node_name = node.get("name", "")
					for chld in node.get("children", ""):
						skel.set_bone_parent(chld, i)
					i += 1
				i = 0
				for node in json["nodes"]:
					var xform: Transform3D = gltf_to_transform3d(node)
					skel.set_bone_rest(i, xform)
					skel.set_bone_pose_position(i, xform.origin)
					skel.set_bone_pose_rotation(i, xform.basis.get_rotation_quaternion())
					skel.set_bone_pose_scale(i, xform.basis.get_scale())
					i += 1
				pkgasset.parsed_meta.autodetected_bone_map_dict = bone_map_editor_plugin.auto_mapping_process_dictionary(skel)
				skel.free()

			if not copy_avatar:
				pkgasset.log_debug("AAAA set to humanoid and has nodes")
				bone_map_dict = importer.generate_bone_map_dict_from_human()
				pkgasset.log_debug(str(bone_map_dict))

			# Discover missing Root bone if any, and correct for name conflicts.
			var node_idx = 0
			var hips_node_idx = -1
			for node in json["nodes"]:
				var node_name = node.get("name", "")
				# pkgasset.log_debug("AAAA node name " + str(node_name))
				if bone_map_dict.has(node_name):
					var godot_human_name: String = bone_map_dict[node_name]
					if godot_human_name == "Hips":
						hips_node_idx = node_idx
					human_skin_nodes.push_back(node_idx)
				node_idx += 1
			var root_bone_name: String = ""
			for key in bone_map_dict:
				if bone_map_dict[key] == "Root":
					root_bone_name = bone_map_dict[key]
			# Add up to three levels up into the skeleton. Our goal is to make the toplevel Armature node be a skeleton, so that we are guaranteed a root bone.
			for i in range(3):
				if hips_node_idx == -1:
					break
				node_idx = 0
				var new_root_idx = -1
				var scene_nodes = json["scenes"][0]["nodes"].duplicate()
				for node in json["nodes"]:
					# "RootNode" is always created by the FBX2glTF conversion, so we promote these to gltf root scene nodes.
					if node["name"] == "RootNode":
						scene_nodes.append_array(node.get("children", []))
						continue
					for child in node.get("children", []):
						if child == hips_node_idx:
							pkgasset.log_debug("Found the child " + str(child) + " type " + str(typeof(child)) + " hni type " + str(typeof(hips_node_idx)))
							pkgasset.parsed_meta.internal_data["humanoid_root_bone"] = node["name"]
							if root_bone_name != "":
								bone_map_dict.erase(root_bone_name)
							bone_map_dict[node["name"]] = "Root"
							root_bone_name = node["name"]
							new_root_idx = node_idx
							human_skin_nodes.push_back(new_root_idx)
							break
					if new_root_idx != -1:
						break
					node_idx += 1
				if scene_nodes.find(new_root_idx) != -1:
					break # FIXME: Try to avoid putting the root of a scene into the skeleton.
				hips_node_idx = new_root_idx

			pkgasset.log_debug("human_skin_nodes is now " +str(human_skin_nodes))

			# Based on a conversation with other devs, RESET is expected to be the initial pose, before silhouette fix
			add_empty_animation(json, "RESET")
			# This will both fill out RESET and add missing tracks into all animations.
			add_missing_humanoid_tracks_to_animations(pkgasset, json, bindata, bone_map_dict)

			# Now we correct the silhouette, either by copying from another model, or applying silhouette fixer.
			if copy_avatar:
				for node in json["nodes"]:
					var node_name: String = node.get("name", "")
					if original_rotations.has(node_name):
						var quat: Quaternion = original_rotations[node_name]
						bone_map_editor_plugin.gltf_matrix_to_trs(node)
						node["rotation"] = [quat.x, quat.y, quat.z, quat.w]
					if bone_map_dict.get(node_name, "") == "Hips":
						node["translation"] = [orig_hip_position.x, orig_hip_position.y, orig_hip_position.z]
					if bone_map_dict.get(node_name, "") == "Root":
						node["translation"] = [orig_root_position.x, orig_root_position.y, orig_root_position.z]
			else:
				bone_map_editor_plugin.silhouette_fix_gltf(json, importer.generate_bone_map_from_human(), SILHOUETTE_FIX_THRESHOLD)
				for node in json["nodes"]:
					var node_name: String = node.get("name", "")
					bone_map_editor_plugin.gltf_matrix_to_trs(node)
					var rot: Array = node.get("rotation", [0, 0, 0, 1])
					original_rotations[node_name] = Quaternion(rot[0], rot[1], rot[2], rot[3])
					var trans: Array = node.get("translation", [0, 0, 0])
					if bone_map_dict.get(node_name, "") == "Hips":
						pkgasset.parsed_meta.internal_data["hips_position"] = Vector3(trans[0], trans[1], trans[2])
					if bone_map_dict.get(node_name, "") == "Root":
						pkgasset.parsed_meta.internal_data["root_position"] = Vector3(trans[0], trans[1], trans[2])

			# Adding missing tracks just to the T-Pose animation after silhouette fix generates a T-Pose
			add_empty_animation(json, "_T-Pose_")
			add_missing_humanoid_tracks_to_animations(pkgasset, json, bindata, bone_map_dict)

			# Finally, record the original post-silhouette transforms for transform_fileid_to_rotation_delta
			for node in json["nodes"]:
				var node_name = node.get("name", "")
				if bone_map_dict.has(node_name):
					var godot_human_name: String = bone_map_dict[node_name]
					if godot_human_name not in humanoid_original_transforms:
						humanoid_original_transforms[godot_human_name] = gltf_to_transform3d(node)

		if not human_skin_nodes.is_empty():
			if not json.has("skins"):
				json["skins"] = []
			json["skins"].append({"joints": human_skin_nodes})

		# skinned_parents use the original gltf names before the remap.
		pkgasset.parsed_meta.internal_data["skinned_parents"] = assign_skinned_parents({}.duplicate(), json["nodes"], "", json["scenes"][json.get("scene", 0)]["nodes"])
		pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"] = {"bone_name": {}}
		var used_animation_names: Dictionary
		# Anything after this point will be using sanitized names, and should go through godot_sanitized_to_orig_remap / bone_map_dict
		for key in ["scenes", "nodes", "meshes", "skins", "images", "materials", "animations"]:
			pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"][key] = {}
			if not json.has(key):
				continue
				
			var used_names: Dictionary = {}.duplicate()
			if key == "nodes":
				used_names["Root Scene"] = true
				used_names["Skeleton3D"] = true
				used_names["GeneralSkeleton"] = true
				used_names["AnimationPlayer"] = true
				used_names["AnimationTree"] = true
				used_names["Mesh"] = true
				used_names["Camera"] = true
				used_names["Camera3D"] = true
				used_names["Light"] = true
				used_names["Skin"] = true
			if is_humanoid and key == "nodes":
				var human_profile = SkeletonProfileHumanoid.new()
				for i in human_profile.bone_size:
					if not bone_map_dict.has(human_profile.get_bone_name(i)):
						# We don't want to end up with Hips -> Hips 1 and invalid BoneMap
						used_names[human_profile.get_bone_name(i)] = true
			var jk: Array = json[key]
			for elem in range(jk.size()):
				if jk[elem].get("name", "") == "":
					if key == "nodes":
						pkgasset.log_warn("glTF node " + str(elem) + " without a name: " + str(jk[elem].keys()))
					if key == "meshes" or key == "materials" or key == "animations" or key == "images":
						pkgasset.log_debug("glTF " + key + " " + str(elem) + " without a name: " + str(jk[elem].keys()))
					continue
				var orig_name: String = jk[elem].get("name")
				var try_name: String = orig_name
				# TODO: Should we prevent empty names?

				var next_num: int = used_names.get(orig_name, 1)
				# Ensure that objects have a unique name in compliance with Unity's uniqueness rules
				# Godot's rule is Gizmo, Gizmo2, Gizmo3.
				# Unity's rule is Gizmo, Gizmo 1, Gizmo 2
				# While we ignore the extra space anyway, the off-by-one here is killer. :'-(
				# So we must proactively rename nodes to avoid duplicates...
				while used_names.has(try_name):
					try_name = "%s %d" % [orig_name, next_num]
					next_num += 1
				#if key == "nodes" and humanoid_original_transforms.has(orig_name):
				#	humanoid_original_transforms[try_name] = humanoid_original_transforms[orig_name]
				json[key][elem]["name"] = try_name
				var sanitized_try_name: String = sanitize_unique_name(try_name)
				if key == "animations":
					sanitized_try_name = sanitize_anim_name(try_name)
					used_animation_names[sanitized_try_name] = elem
				if orig_name != sanitized_try_name:
					pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"][key][sanitized_try_name] = orig_name
				if key == "nodes":
					var sanitized_bone_try_name = sanitize_bone_name(try_name)
					if orig_name != sanitized_bone_try_name:
						pkgasset.parsed_meta.internal_data["godot_sanitized_to_orig_remap"]["bone_name"][sanitized_bone_try_name] = orig_name
				used_names[orig_name] = next_num
				used_names[try_name] = 1

		if is_humanoid and json.has("nodes") and importer.keys.get("avatarSetup", 1) >= 1:
			for node in json["nodes"]:
				var node_name: String = node.get("name", "")
				if bone_map_dict.has(node_name):
					node_name = bone_map_dict[node_name]
				if not humanoid_original_transforms.has(node_name):
					humanoid_original_transforms[node_name] = gltf_to_transform3d(node)
		# humanoid_original_transforms uses post-sanitized node names.
		pkgasset.parsed_meta.internal_data["humanoid_original_transforms"] = humanoid_original_transforms
		pkgasset.parsed_meta.internal_data["original_rotations"] = original_rotations
		pkgasset.parsed_meta.internal_data["used_animation_names"] = used_animation_names

		var out_json_data: PackedByteArray = JSON.new().stringify(json).to_utf8_buffer()
		var full_output: PackedByteArray = out_json_data
		if SHOULD_CONVERT_TO_GLB:
			var out_json_data_length: int = out_json_data.size()
			var bindata_length: int = bindata.size()
			var spb: StreamPeerBuffer = StreamPeerBuffer.new()
			full_output = PackedByteArray()
			spb.data_array = full_output
			spb.big_endian = false
			spb.put_32(0x46546C67)
			spb.put_32(2)
			spb.put_32(20 + out_json_data_length + 8 + bindata_length + 4)
			spb.put_32(out_json_data_length)
			spb.put_32(0x4E4F534A)
			spb.put_data(out_json_data)
			spb.put_32(bindata_length)
			spb.put_32(0x4E4942)
			spb.put_data(bindata)
			spb.put_32(0)
		elif len(bindata) != bindata_orig_length:
			f = FileAccess.open(bin_output_path, FileAccess.READ_WRITE)
			f.seek_end(0)
			f.store_buffer(bindata.slice(bindata_orig_length))
			f.flush()
			f.close()
			f = null

		pkgasset.data_md5 = calc_md5(full_output)
		if not SHOULD_CONVERT_TO_GLB:
			pkgasset.data_md5.append_array(calc_md5(bindata))
		pkgasset.existing_data_md5 = calc_existing_md5(return_output_path)
		if not SHOULD_CONVERT_TO_GLB:
			pkgasset.existing_data_md5.append_array(calc_existing_md5(return_output_path.get_basename() + ".bin"))
		if pkgasset.existing_data_md5 != pkgasset.data_md5:
			f = FileAccess.open(output_path, FileAccess.WRITE_READ)
			f.store_buffer(full_output)
			f.flush()
			f.close()
			f = null
		else:
			d.remove(gltf_output_path)
			if not SHOULD_CONVERT_TO_GLB:
				d.remove(bin_output_path)

		return return_output_path


class TextHandler:
	extends AssetHandler

	func get_asset_type(pkgasset: Object):
		return ASSET_TYPE_TEXTURE

	func uses_godot_importer(pkgasset: Object) -> bool:
		return false

	func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
		super.write_godot_asset(pkgasset, temp_path)
		return false # Tells package dialog that this resource cannot be loaded so it shouldn't show an error


class DisabledHandler:
	extends AssetHandler

	func preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String, path: String, data_buf: PackedByteArray, unique_texture_map: Dictionary = {}) -> String:
		return "asset_not_supported"

	func write_and_preprocess_asset(pkgasset: Object, tmpdir: String, thread_subdir: String) -> String:
		return "asset_not_supported"

	func uses_godot_importer(pkgasset: Object) -> bool:
		return false

	func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
		return false


func get_class_name(obj):
	if obj is DisabledHandler:
		return "DisabledHandler"
	if obj is FbxHandler:
		return "FbxHandler"
	if obj is BaseModelHandler:
		return "BaseModelHandler"
	if obj is SceneHandler:
		return "SceneHandler"
	if obj is YamlHandler:
		return "YamlHandler"
	if obj is AudioHandler:
		return "AudioHandler"
	if obj is ImageHandler:
		return "ImageHandler"
	if obj is AssetHandler:
		return "AssetHandler"
	return obj.get_class()


var image_handler: ImageHandler = ImageHandler.new()

var file_handlers: Dictionary = {
	"fbx": FbxHandler.new(),
	"obj": BaseModelHandler.new(),
	"dae": BaseModelHandler.new(),
	#"obj": DisabledHandler.new(), # .obj is broken due to multithreaded importer
	#"dae": DisabledHandler.new(), # .dae is broken due to multithreaded importer
	"glb": FbxHandler.new(),
	"gltf": FbxHandler.new(),
	"jpg": image_handler,
	"jpeg": image_handler,
	"png": image_handler,
	"bmp": image_handler,
	"tga": image_handler,
	# Disabling for convenience...
	# EXR have very slow import times, and neither reflection probes nor lightmaps currently get used.
	# "exr": image_handler,
	"hdr": image_handler,
	"dds": image_handler,
	"psd": image_handler, # convert.exe
	"tif": image_handler, # convert.exe
	"tiff": image_handler, # convert.exe
	"webp": image_handler,
	"svg": image_handler,
	"svgz": image_handler,
	"wav": AudioHandler.new().create_with_type("wav", "AudioStreamSample"),
	"ogg": AudioHandler.new().create_with_type("oggvorbisstr", "AudioStreamOGG"),
	"mp3": AudioHandler.new().create_with_type("mp3", "AudioStreamMP3"),
	# "aif": audio_handler, # Unsupported.
	# "tif": image_handler, # Unsupported.
	"asset": YamlHandler.new(),  # Generic file format
	"unity": SceneHandler.new(),  # Unity Scenes
	"prefab": SceneHandler.new(),  # Prefabs (sub-scenes)
	"mask": YamlHandler.new(),  # Avatar Mask for animations
	"mesh": YamlHandler.new(),  # Mesh data, sometimes .asset
	"ht": YamlHandler.new(),  # Human Template??
	"mat": YamlHandler.new(),  # Materials
	"playable": YamlHandler.new(),  # director?
	"terrainlayer": YamlHandler.new(),  # terrain, not supported
	"physicmaterial": YamlHandler.new(),  # Physics Material
	"overridecontroller": YamlHandler.new(),  # Animator Override Controller
	"controller": YamlHandler.new(),  # Animator Controller
	"anim": YamlHandler.new(),  # Animation... # TODO: This should be by type (.asset), not extension
	# ALSO: animations can be contained inside other assets, such as controllers. we need to recognize this and extract them.
	"default": DefaultHandler.new(),
	"txt": TextHandler.new(),
	"html": TextHandler.new(),
	"htm": TextHandler.new(),
	"pdf": TextHandler.new(),
	"xml": TextHandler.new(),
	"bytes": TextHandler.new(),
	"json": TextHandler.new(),
	"csv": TextHandler.new(),
	"yaml": TextHandler.new(),
	"fnt": AudioHandler.new().create_with_type("font_data_bmfont", "FontFile"),
	"font": AudioHandler.new().create_with_type("font_data_bmfont", "FontFile"),
	"ttf": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"ttc": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"otf": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"otc": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"woff": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"woff2": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"pfb": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
	"pfm": AudioHandler.new().create_with_type("font_data_dynamic", "FontFile"),
}


func create_temp_dir() -> String:
	var tmpdir = ".godot/unidot_temp"
	var dres = DirAccess.open("res://")
	dres.make_dir_recursive(tmpdir)
	var f = FileAccess.open(tmpdir + "/.gdignore", FileAccess.WRITE_READ)
	f.flush()
	f.close()
	f = null
	return tmpdir


func get_asset_type(pkgasset: Object) -> int:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	pkgasset.log_debug("get_asset_type " + path + ", " + pkgasset.pathname + ", " + str(get_class_name(file_handlers.get("default"))) + ", " + str(get_class_name(asset_handler)) + ", " + str(asset_handler.get_asset_type(pkgasset)))
	var typ: int = asset_handler.get_asset_type(pkgasset)
	return typ


func uses_godot_importer(pkgasset: Object) -> bool:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.uses_godot_importer(pkgasset)


func preprocess_asset(asset_database: Object, pkgasset: Object, tmpdir: String, thread_subdir: String) -> String:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	var dres = DirAccess.open("res://")
	dres.make_dir_recursive(path.get_base_dir())
	dres.make_dir_recursive(tmpdir + "/" + path.get_base_dir())
	dres.make_dir_recursive(tmpdir + "/" + thread_subdir)

	if pkgasset.metadata_tar_header != null and pkgasset.parsed_meta == null:
		var sf = pkgasset.metadata_tar_header.get_stringfile()
		pkgasset.parsed_meta = asset_database.parse_meta(sf, path)
		pkgasset.log_debug("Parsing " + path + ": " + str(pkgasset.parsed_meta))
	if pkgasset.asset_tar_header != null:
		var ret_output_path = asset_handler.write_and_preprocess_asset(pkgasset, tmpdir, thread_subdir)
		if not ret_output_path.is_empty():
			pkgasset.pathname = ret_output_path
			if not dres.file_exists(pkgasset.pathname):
				if asset_handler.write_godot_import(pkgasset, true):
					# Make an empty file so it will be found by a scan!
					var f: FileAccess = FileAccess.open(pkgasset.pathname, FileAccess.WRITE_READ)
					f.close()
					f = null
		return ret_output_path
	return ""


func write_additional_import_dependencies_scan_only(pkgasset: Object, guid_to_pkgasset: Dictionary):
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	if pkgasset.parsed_asset == null:
		pkgasset.parsed_meta.log_debug(0, "Asset was not parsed " + str(path))
		return
	for key in pkgasset.parsed_asset.assets:
		var obj = pkgasset.parsed_asset.assets[key]
		if obj.type == "Material":
			var ret: String = obj.bake_roughness_texture_if_needed(true, guid_to_pkgasset)
			if not ret.is_empty():
				pkgasset.parsed_meta.log_debug(0, "Asset " + str(obj.keys.get("m_Name", "")) + " baked a roughness texture " + str(ret))
			else:
				pkgasset.parsed_meta.log_debug(0, "Asset " + str(obj.keys.get("m_Name", "")) + " did not have a roughness texture")


func write_additional_import_dependencies(pkgasset: Object, force_keep: bool=false) -> Array[String]:
	var path = pkgasset.orig_pathname
	pkgasset.parsed_meta.log_debug(0, "Write additional " + str(path))
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	var dependencies: Array[String]
	if pkgasset.parsed_asset == null:
		pkgasset.parsed_meta.log_debug(0, "Asset was not parsed " + str(path))
		return dependencies
	for key in pkgasset.parsed_asset.assets:
		var obj = pkgasset.parsed_asset.assets[key]
		if obj.type == "Material":
			var ret: String = obj.bake_roughness_texture_if_needed(false)
			if not ret.is_empty():
				pkgasset.parsed_meta.log_debug(0, "Asset " + str(obj.keys.get("m_Name", "")) + " baked a roughness texture " + str(ret))
				dependencies.append(ret)
			else:
				pkgasset.parsed_meta.log_debug(0, "Asset " + str(obj.keys.get("m_Name", "")) + " did not have a roughness texture")
	pkgasset.parsed_meta.log_debug(0, "Returning extra dependencies " + str(dependencies))
	return dependencies


# pkgasset: unitypackagefile.UnityPackageAsset type
func write_godot_asset(pkgasset: Object, temp_path: String) -> bool:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.write_godot_asset(pkgasset, temp_path)


func write_godot_import(pkgasset: Object) -> bool:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.write_godot_import(pkgasset, false)


func finished_import(pkgasset: Object, loaded_resource: Resource) -> void:
	var path = pkgasset.orig_pathname
	var asset_handler: AssetHandler = file_handlers.get(path.get_extension().to_lower(), file_handlers.get("default"))
	return asset_handler.finished_import(pkgasset, loaded_resource)
