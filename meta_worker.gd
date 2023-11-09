# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends "./thread_worker.gd"

const binary_parser: GDScript = preload("./deresuteme/decode.gd")
const yaml_parser: GDScript = preload("./unity_object_parser.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const unitypackagefile: GDScript = preload("./unitypackagefile.gd")


class ThreadWork:
	var asset: unitypackagefile.UnityPackageAsset
	var extra: Object


# asset: unitypackagefile.UnityPackageAsset object
func push_asset(asset: unitypackagefile.UnityPackageAsset, extra: Object):
	var tw = ThreadWork.new()
	tw.asset = asset
	tw.extra = extra
	self.push_work_obj(tw)


func _run_single_item(tw_: Object, thread_subdir: String):
	var tw: ThreadWork = tw_ as ThreadWork
	asset_processing_started.emit(tw)

	var path = tw.asset.orig_pathname
	if tw.asset.metadata_tar_header != null:
		var sf = tw.asset.metadata_tar_header.get_stringfile()
		tw.asset.parsed_meta = asset_database.parse_meta(sf, path)
	var imp_type: String = tw.asset.parsed_meta.importer_type
	tw.asset.parsed_meta.dependency_guids = {}
	print(path + ": " + imp_type)
	if imp_type == "PrefabImporter" or imp_type == "NativeFormatImporter" or imp_type == "DefaultImporter":
		if tw.asset.asset_tar_header != null:
			var buf: PackedByteArray = tw.asset.asset_tar_header.get_data()
			if buf[8] == 0 and buf[9] == 0:
				binary_parser.new(tw.asset.parsed_meta, buf, true) # writes guid references
			else:
				yaml_parser.parse_dependency_guids(buf.get_string_from_utf8(), tw.asset.parsed_meta)
	#print("" + path + ":" + str(tw.asset.parsed_meta.dependency_guids) + " : " + str(tw.asset.parsed_meta.meta_dependency_guids))
	asset_processing_finished.emit(tw)
