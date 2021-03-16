@tool
extends Resource

const tarfile: GDScript = preload("./tarfile.gd")

class UnityPackageAsset extends Reference:
	var asset_tar_header: Reference
	var metadata_tar_header: Reference
	var pathname: String
	var icon: Texture
	var guid: String
	var parsed_meta: Resource # Type: asset_database.gd:AssetMeta / Assigned by unity_asset_adapter.preprocess_asset()
	var parsed_asset: Reference
	var parsed_resource: Resource # For specific assets which do work in the thread.


var paths: Array = [].duplicate()
var path_to_pkgasset: Dictionary = {}.duplicate()
var guid_to_pkgasset: Dictionary = {}.duplicate()


func init_with_filename(source_file):
	var file = File.new()
	if file.open(source_file, File.READ) != OK:
		return null

	var flen: int = file.get_len() # NOTE: 32-bit only
	var decompress_buf: PackedByteArray = file.get_buffer(flen).decompress(2147483647, 3) # COMPRESSION_GZIP = 3
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
		if (header.filename == "" or header.filename == "/"):
			# Ignore root folder.
			continue
		var fnparts = header.filename.split("/")
		if len(fnparts[0]) != 32:
			printerr("Invalid member of .unitypackage: " + str(header.filename))
			continue
		if not guid_to_pkgasset.has(fnparts[0]):
			print("Discovered Asset " + fnparts[0])
			guid_to_pkgasset[fnparts[0]] = UnityPackageAsset.new()
		var pkgasset: UnityPackageAsset = guid_to_pkgasset[fnparts[0]]
		pkgasset.guid = fnparts[0]
		if len(fnparts) == 1 or fnparts[1] == '':
			continue
		if fnparts[1] == 'pathname':
			pkgasset.pathname = header.get_data().get_string_from_utf8()
			var path = pkgasset.pathname
			if path.find("../") != -1 or path.find("/") == -1 or path.find("\\") != -1:
				#if path != "Assets":
				printerr("Asset " + pkgasset.guid + ": Illegal path " + path)
				guids_to_remove.append(pkgasset.guid)
			else:
				print("Asset " + pkgasset.guid + ": " + path)
				path_to_pkgasset[path] = pkgasset
				paths.push_back(path)
		if fnparts[1] == 'preview.png':
			pkgasset.icon = ImageTexture.new()
			var image = Image.new()
			image.load_png_from_buffer(header.get_data())
			image.resize(20, 20)
			pkgasset.icon.create_from_image(image)
		if fnparts[1] == 'asset.meta':
			pkgasset.metadata_tar_header = header
		if fnparts[1] == 'asset':
			pkgasset.asset_tar_header = header

	for guid in guids_to_remove:
		guid_to_pkgasset.erase(guid)
	paths.sort()
	return self
