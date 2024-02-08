# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends Resource


class ExtractedTarFile:
	var fn: String = ""
	var size: int

	func _init(filename: String):
		fn = filename
		var f = FileAccess.open(fn, FileAccess.READ)
		size = f.get_length()

	func get_size() -> int:
		return size

	func get_data() -> PackedByteArray:
		var f = FileAccess.open(fn, FileAccess.READ)
		return f.get_buffer(size)

	func get_string() -> String:
		return get_data().get_string_from_utf8()

	func get_stringfile() -> Object:
		var f = FileAccess.open(fn, FileAccess.READ)
		return f


const tarfile: GDScript = preload("./tarfile.gd")


class PkgAsset:
	extends RefCounted
	var asset_tar_header: RefCounted
	var metadata_tar_header: RefCounted
	var data_md5: PackedByteArray
	var existing_data_md5: PackedByteArray
	var pathname: String
	var orig_pathname: String
	var icon: Texture
	var guid: String
	var parsed_meta: Resource  # Type: asset_database.gd:AssetMeta / Assigned by asset_adapter.preprocess_asset()
	var parsed_asset: RefCounted
	var parsed_resource: Resource  # For specific assets which do work in the thread.
	var packagefile: Resource  # outer class
	var meta_dependencies: Dictionary

	# Log messages related to this asset
	func log_debug(msg: String):
		parsed_meta.log_debug(0, msg)

	# Anything that is unexpected but does not necessarily imply corruption.
	# For example, successfully loaded a resource with default fileid
	func log_warn(msg: String, field: String = "", remote_ref: Variant = [null, 0, "", null]):
		if typeof(remote_ref) == TYPE_ARRAY:
			parsed_meta.log_warn(0, msg, field, remote_ref)
		elif typeof(remote_ref) == TYPE_OBJECT and remote_ref:
			parsed_meta.log_warn(0, msg, field, [null, remote_ref.fileID, remote_ref.meta.guid, 0])
		else:
			parsed_meta.log_warn(0, msg, field)

	# Anything that implies the asset will be corrupt / lost data.
	# For example, some reference or field could not be assigned.
	func log_fail(msg: String, field: String = "", remote_ref: Variant = [null, 0, "", null]):
		if typeof(remote_ref) == TYPE_ARRAY:
			parsed_meta.log_fail(0, msg, field, remote_ref)
		elif typeof(remote_ref) == TYPE_OBJECT and remote_ref:
			parsed_meta.log_fail(0, msg, field, [null, remote_ref.fileID, remote_ref.meta.guid, 0])
		else:
			parsed_meta.log_fail(0, msg, field)


var paths: Array = [].duplicate()
var path_to_pkgasset: Dictionary = {}.duplicate()
var guid_to_pkgasset: Dictionary = {}.duplicate()


func external_tar_with_filename(source_file: String, full_tmpdir: String=""):
	var stdout = [].duplicate()
	var tmpdir = ".godot"
	var d: DirAccess = DirAccess.open("res://" + tmpdir)
	d.make_dir("unidot_extracted_tar")
	if full_tmpdir.is_empty():
		full_tmpdir = d.get_current_dir() + "/unidot_extracted_tar"
	var tar_args: Array = ["-C", full_tmpdir.replace("res://", ""), "-zxvf", source_file.replace("res://", "")]
	#if str(OS.get_name()) == "Windows" or str(OS.get_name()) == "UWP":
	var out_lines: Array = [].duplicate()
	if source_file.is_empty():
		print("Looking for extracted package files in " + full_tmpdir)
		# Re-import the previously imported/extracted tar packages.
		var dirlist: DirAccess = DirAccess.open(full_tmpdir)
		dirlist.list_dir_begin()
		while true:
			var fn: String = dirlist.get_next()
			print(fn)
			if fn.is_empty():
				break
			#print(fn)
			if not fn.begins_with(".") and dirlist.file_exists(fn + "/pathname"):
				for fnpiece in ["/pathname", "/asset", "/asset.meta", "/preview.png"]:
					#print(fn + "/" + fnpiece)
					out_lines.append(fn)
					if dirlist.file_exists("./" + fn + fnpiece):
						out_lines.append(fn + fnpiece)
	else:
		print("Running tar with " + str(tar_args))
		OS.execute("tar", tar_args, stdout, true)
		if stdout[0].find("resolve failed") != -1:
			print("Rerunning with --force-local")
			tar_args.append("--force-local")
			stdout = []
			OS.execute("tar", tar_args, stdout, true)
		# print("executed " + str(tar_args) + ": " + str(stdout))
		out_lines = stdout[0].split("\n")
	var guids_to_remove = [].duplicate()
	for line in out_lines:
		var fnparts: Array = line.trim_prefix("x").strip_edges().trim_prefix("./").split("/")
		# x ./1234abcd0000ffff/
		# x ./1234abcd0000ffff/preview.png
		# x ./1234abcd0000ffff/asset
		# x ./1234abcd0000ffff/asset.meta
		# x ./1234abcd0000ffff/pathname
		if len(fnparts) < 2:
			continue
		var guid: String = fnparts[0]
		var type_part: String = fnparts[1]
		if len(guid) != 32:
			push_error("Invalid member of .unitypackage: " + str(fnparts))
			continue
		if type_part.is_empty():
			# The directory entries sometimes print "x ./" or "x ./01234/"
			continue
		if not guid_to_pkgasset.has(guid):
			#print("Discovered Asset " + guid)
			guid_to_pkgasset[guid] = PkgAsset.new()
		var pkgasset: PkgAsset = guid_to_pkgasset[guid]
		pkgasset.packagefile = self
		pkgasset.guid = guid
		var this_filename: String = full_tmpdir + "/" + str(guid) + "/" + str(type_part)
		var header = ExtractedTarFile.new(this_filename)
		if fnparts[1] == "pathname":
			pkgasset.pathname = header.get_data().get_string_from_utf8().split("\n")[0].strip_edges()
			var ext = pkgasset.pathname.get_extension().to_lower()
			if not ext.is_empty():
				if ext.begins_with("uni") and len(ext) <= 6: # Unidot scenes
					ext = "scene"
				pkgasset.pathname = pkgasset.pathname.get_basename() + "." + ext
			pkgasset.orig_pathname = pkgasset.pathname
		if fnparts[1] == "preview.png":
			var image = Image.new()
			image.load_png_from_buffer(header.get_data())
			image.resize(20, 20)
			pkgasset.icon = ImageTexture.create_from_image(image)
		if fnparts[1] == "asset.meta":
			pkgasset.metadata_tar_header = header
		if fnparts[1] == "asset":
			pkgasset.asset_tar_header = header

	for guid in guid_to_pkgasset:
		var pkgasset = guid_to_pkgasset[guid]
		var path = pkgasset.pathname
		if not pkgasset.asset_tar_header:
			guids_to_remove.append(pkgasset.guid)
		elif path.find("../") != -1 or path.find("/") == -1 or path.find("\\") != -1:
			#if path != "Assets":
			push_error("Asset " + pkgasset.guid + ": Illegal path " + path)
			guids_to_remove.append(pkgasset.guid)
		else:
			# print("Asset " + pkgasset.guid + ": " + path)
			path_to_pkgasset[path] = pkgasset
			paths.push_back(path)

	for guid in guids_to_remove:
		guid_to_pkgasset.erase(guid)
	paths.sort()
	return self


func init_with_filename(source_file: String):
	if source_file.is_empty():
		return external_tar_with_filename("")

	var file = FileAccess.open(source_file, FileAccess.READ)
	if not file:
		return null

	var flen: int = file.get_length()  # NOTE: 32-bit only
	if flen > 300000000:
		return external_tar_with_filename(source_file)
	var decompress_buf: PackedByteArray = file.get_buffer(flen).decompress(2147483647, 3)  # COMPRESSION_GZIP = 3
	print("Decompressed " + str(flen) + " to " + str(len(decompress_buf)))
	var buf: PackedByteArray = PackedByteArray()
	buf.append_array(decompress_buf)
	decompress_buf = buf
	var tar = tarfile.new().init_with_buffer(decompress_buf)
	var guids_to_remove = [].duplicate()
	while true:
		var header = tar.read_header()
		if header == null:
			break
		if header.filename.begins_with("./"):
			header.filename = header.filename.substr(2)
		if header.filename == "" or header.filename == "/" or header.filename == ".":
			# Ignore root folder.
			continue
		var fnparts = header.filename.split("/")
		if len(fnparts[0]) != 32:
			push_error("Invalid member of .unitypackage: " + str(header.filename))
			continue
		if not guid_to_pkgasset.has(fnparts[0]):
			# print("Discovered Asset " + fnparts[0])
			guid_to_pkgasset[fnparts[0]] = PkgAsset.new()
		var pkgasset: PkgAsset = guid_to_pkgasset[fnparts[0]]
		pkgasset.packagefile = self
		pkgasset.guid = fnparts[0]
		if len(fnparts) == 1 or fnparts[1] == "":
			continue
		if fnparts[1] == "pathname":
			# Some pathnames have newline followed by "00". no idea why
			pkgasset.pathname = header.get_data().get_string_from_utf8().split("\n")[0].strip_edges()
			var ext = pkgasset.pathname.get_extension().to_lower()
			if not ext.is_empty():
				if ext.begins_with("uni") and len(ext) <= 6: # Unidot scenes
					ext = "scene"
				pkgasset.pathname = pkgasset.pathname.get_basename() + "." + ext
			pkgasset.orig_pathname = pkgasset.pathname
		if fnparts[1] == "preview.png":
			var image = Image.new()
			image.load_png_from_buffer(header.get_data())
			image.resize(16, 16)
			image.convert(Image.FORMAT_RGBA8)
			for x in range(16):
				for y in range(16):
					if (image.get_pixel(x, y).to_argb32() & 0xffffff) == 0x525252:
						image.set_pixel(x, y, Color.TRANSPARENT)
			pkgasset.icon = ImageTexture.create_from_image(image)
		if fnparts[1] == "asset.meta":
			pkgasset.metadata_tar_header = header
		if fnparts[1] == "asset":
			pkgasset.asset_tar_header = header

	for guid in guid_to_pkgasset:
		var pkgasset = guid_to_pkgasset[guid]
		var path = pkgasset.pathname
		if not pkgasset.asset_tar_header:
			guids_to_remove.append(pkgasset.guid)
		elif path.find("../") != -1 or path.find("/") == -1 or path.find("\\") != -1:
			#if path != "Assets":
			push_error("Asset " + pkgasset.guid + ": Illegal path " + path)
			guids_to_remove.append(pkgasset.guid)
		else:
			# print("Asset " + pkgasset.guid + ": " + path)
			path_to_pkgasset[path] = pkgasset
			paths.push_back(path)

	for guid in guids_to_remove:
		guid_to_pkgasset.erase(guid)
	paths.sort()
	return self


func get_all_files(path: String, file_ext: String, files: Array[String]):
	# Based on https://gist.github.com/hiulit/772b8784436898fd7f942750ad99e33e by hiulit
	var dir = DirAccess.open(path)
	dir.include_hidden = true
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while not file_name.is_empty():
			if dir.current_is_dir():
				get_all_files(dir.get_current_dir().path_join(file_name), file_ext, files)
			else:
				if not file_ext.is_empty() and file_name.get_extension().to_lower() != file_ext:
					file_name = dir.get_next()
					continue
				files.append(dir.get_current_dir().path_join(file_name))
			file_name = dir.get_next()
	else:
		push_error("An error occurred in Unidot when trying to recurse to %s." % path)


func read_guid_from_meta_file(sf: Object) -> String:# e.g. stringfile
	var magic = sf.get_line()
	var guid: String
	if not magic.begins_with("fileFormatVersion:"):
		push_error("Failed to parse meta file! " + sf.get_path())
		return ""
	while true:
		var line = sf.get_line()
		line = line.replace("\r", "")
		while line.ends_with("\r"):
			line = line.substr(0, len(line) - 1)
		if line.begins_with("guid:"):
			guid = line.split(":")[1].strip_edges()
			break
		if sf.get_error() == ERR_FILE_EOF:
			break
	if len(guid) != 32:
		push_error("Failed to parse correct guid " + str(guid) + "! " + sf.get_path())
	return guid


func init_with_asset_dir(source_file: String):
	var dirlist: DirAccess = DirAccess.open(source_file)
	var common_parent_dir := dirlist.get_current_dir().replace("\\", "/")
	if common_parent_dir.contains("/Assets/"):
		common_parent_dir = common_parent_dir.get_slice("/Assets/", 0)
	else:
		common_parent_dir = common_parent_dir.get_base_dir()
	var meta_filenames: Array[String]
	get_all_files(source_file, "meta", meta_filenames)
	var valid_filenames: Array[String] = []
	for fn in meta_filenames:
		if fn.is_empty():
			break
		if fn.ends_with(".meta"):
			var file_substr: String = fn.substr(0, len(fn) - 5)
			if FileAccess.file_exists(file_substr) and not DirAccess.dir_exists_absolute(file_substr):
				valid_filenames.append(file_substr)
	var guids_to_remove = [].duplicate()
	for fn in valid_filenames:
		var meta_fn = fn + ".meta"
		var relative_pathname: String = fn.substr(len(common_parent_dir)).lstrip("/\\")
		var ext = relative_pathname.get_extension().to_lower()
		if not ext.is_empty():
			if ext.begins_with("uni") and len(ext) <= 6: # Unidot scenes
				ext = "scene"
			relative_pathname = relative_pathname.get_basename() + "." + ext
		var pkgasset := PkgAsset.new()
		pkgasset.metadata_tar_header = ExtractedTarFile.new(meta_fn)
		var sf = pkgasset.metadata_tar_header.get_stringfile()
		var guid: String = read_guid_from_meta_file(sf)
		if len(guid) != 32:
			push_warning(str(meta_fn) + ": Invalid guid: " + str(guid))
			continue
		pkgasset.asset_tar_header = ExtractedTarFile.new(fn)
		pkgasset.pathname = relative_pathname
		pkgasset.orig_pathname = relative_pathname
		pkgasset.guid = guid
		pkgasset.packagefile = self
		if not guid_to_pkgasset.has(guid):
			guid_to_pkgasset[guid] = pkgasset

	for guid in guid_to_pkgasset:
		var pkgasset = guid_to_pkgasset[guid]
		var path = pkgasset.pathname
		if not pkgasset.asset_tar_header:
			guids_to_remove.append(pkgasset.guid)
		elif path.find("../") != -1 or path.find("/") == -1 or path.find("\\") != -1:
			#if path != "Assets":
			push_error("Asset " + pkgasset.guid + ": Illegal path " + path)
			guids_to_remove.append(pkgasset.guid)
		else:
			# print("Asset " + pkgasset.guid + ": " + path)
			path_to_pkgasset[path] = pkgasset
			paths.push_back(path)

	for guid in guids_to_remove:
		guid_to_pkgasset.erase(guid)
	paths.sort()
	return self


func parse_all_meta(asset_database):
	for path in path_to_pkgasset:
		var pkgasset = path_to_pkgasset[path]
		#print("PATH: " + str(path) + "  PKGASSET " + str(pkgasset))
		if pkgasset.metadata_tar_header != null:
			var sf = pkgasset.metadata_tar_header.get_stringfile()
			pkgasset.parsed_meta = asset_database.parse_meta(sf, path)
			pkgasset.log_debug("Parsing " + path + ": " + str(pkgasset.parsed_meta))
