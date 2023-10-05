@tool
extends Resource


class ExtractedTarFile:
	var fn: String = ""

	func _init(filename: String):
		fn = filename

	func get_data() -> PackedByteArray:
		var f = FileAccess.open(fn, FileAccess.READ)
		return f.get_buffer(f.get_length())

	func get_string() -> String:
		return get_data().get_string_from_utf8()

	func get_stringfile() -> Object:
		var f = FileAccess.open(fn, FileAccess.READ)
		return f


const tarfile: GDScript = preload("./tarfile.gd")


class UnityPackageAsset:
	extends RefCounted
	var asset_tar_header: RefCounted
	var metadata_tar_header: RefCounted
	var data_md5: PackedByteArray
	var existing_data_md5: PackedByteArray
	var pathname: String
	var orig_pathname: String
	var icon: Texture
	var guid: String
	var parsed_meta: Resource  # Type: asset_database.gd:AssetMeta / Assigned by unity_asset_adapter.preprocess_asset()
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


func external_tar_with_filename(source_file: String):
	var stdout = [].duplicate()
	var tmpdir = "temp_unityimp"
	var d: DirAccess = DirAccess.open("res://" + tmpdir)
	d.make_dir("TAR_TEMP")
	var full_tmpdir: String = tmpdir + "/TAR_TEMP"
	var tar_args: Array = ["-C", full_tmpdir, "-zxvf", source_file.replace("res://", "")]
	#if str(OS.get_name()) == "Windows" or str(OS.get_name()) == "UWP":
	print("Running tar with " + str(tar_args))
	var out_lines: Array = [].duplicate()
	if source_file.is_empty():
		var dirlist: DirAccess = DirAccess.open("res://" + full_tmpdir)
		dirlist.list_dir_begin()
		while true:
			var fn: String = dirlist.get_next()
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
		var fnparts: Array = line.trim_prefix("x").strip_edges().split("/")
		# x ./1234abcd0000ffff/
		# x ./1234abcd0000ffff/preview.png
		# x ./1234abcd0000ffff/asset
		# x ./1234abcd0000ffff/asset.meta
		# x ./1234abcd0000ffff/pathname
		if len(fnparts) < 2:
			continue
		var guid: String = fnparts[0]
		var type_part: String = fnparts[1]
		if len(fnparts[1]) == 32:
			if len(fnparts) < 3:
				continue
			guid = fnparts[1]
			type_part = fnparts[2]
		if len(guid) != 32:
			push_error("Invalid member of .unitypackage: " + str(fnparts))
			continue
		if not guid_to_pkgasset.has(guid):
			#print("Discovered Asset " + guid)
			guid_to_pkgasset[guid] = UnityPackageAsset.new()
		var pkgasset: UnityPackageAsset = guid_to_pkgasset[guid]
		pkgasset.packagefile = self
		pkgasset.guid = guid
		var this_filename: String = full_tmpdir + "/" + str(guid) + "/" + str(type_part)
		var header = ExtractedTarFile.new(this_filename)
		if fnparts[1] == "pathname":
			pkgasset.pathname = header.get_data().get_string_from_utf8().split("\n")[0].strip_edges()
			pkgasset.orig_pathname = pkgasset.pathname
		if fnparts[1] == "preview.png":
			pkgasset.icon = ImageTexture.new()
			var image = Image.new()
			image.load_png_from_buffer(header.get_data())
			image.resize(20, 20)
			pkgasset.icon.create_from_image(image)
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
			guid_to_pkgasset[fnparts[0]] = UnityPackageAsset.new()
		var pkgasset: UnityPackageAsset = guid_to_pkgasset[fnparts[0]]
		pkgasset.packagefile = self
		pkgasset.guid = fnparts[0]
		if len(fnparts) == 1 or fnparts[1] == "":
			continue
		if fnparts[1] == "pathname":
			# Some pathnames have newline followed by "00". no idea why
			pkgasset.pathname = header.get_data().get_string_from_utf8().split("\n")[0].strip_edges()
			pkgasset.orig_pathname = pkgasset.pathname
		if fnparts[1] == "preview.png":
			pkgasset.icon = ImageTexture.new()
			var image = Image.new()
			image.load_png_from_buffer(header.get_data())
			image.resize(20, 20)
			pkgasset.icon.create_from_image(image)
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


func parse_all_meta(asset_database):
	for path in path_to_pkgasset:
		var pkgasset = path_to_pkgasset[path]
		#print("PATH: " + str(path) + "  PKGASSET " + str(pkgasset))
		if pkgasset.metadata_tar_header != null:
			var sf = pkgasset.metadata_tar_header.get_stringfile()
			pkgasset.parsed_meta = asset_database.parse_meta(sf, path)
			pkgasset.log_debug("Parsing " + path + ": " + str(pkgasset.parsed_meta))
