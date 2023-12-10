# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends "./thread_worker.gd"

const tarfile: GDScript = preload("./tarfile.gd")
const package_file: GDScript = preload("./package_file.gd")

var stage2: bool = false
var guid_to_pkgasset: Dictionary
var stage2_dict_lock := Mutex.new()
var stage2_extra_asset_dict: Dictionary

func set_stage2(pkg_guid_to_pkgasset: Dictionary):
	stage2 = true
	guid_to_pkgasset = pkg_guid_to_pkgasset
	stage2_extra_asset_dict = {}


class ThreadWork:
	var asset: package_file.PkgAsset
	var tmpdir: String
	var output_path: String
	var extra: Variant
	var did_fail: bool
	var is_loaded: bool


# asset: package_file.PkgAsset object
func push_asset(asset: package_file.PkgAsset, tmpdir: String, extra: Variant = null):
	var tw = ThreadWork.new()
	tw.asset = asset
	tw.tmpdir = tmpdir
	tw.extra = extra
	if asset.parsed_meta != null:
		asset.parsed_meta.log_debug(0, "Enqueue asset " + str(asset.guid) + " " + str(asset.pathname))
	else:
		print("Enqueue asset " + str(asset.guid) + " " + str(asset.pathname))
	self.push_work_obj(tw)


func _run_single_item(tw_: Object, thread_subdir: String):
	var tw: ThreadWork = tw_ as ThreadWork
	asset_processing_started.emit(tw)
	if stage2:
		asset_adapter.preprocess_asset_stage2(tw.asset, tw.tmpdir, guid_to_pkgasset, stage2_dict_lock, stage2_extra_asset_dict)
		asset_processing_finished.emit(tw)
	else:
		tw.output_path = asset_adapter.preprocess_asset(asset_database, tw.asset, tw.tmpdir, thread_subdir)
		# It has not yet been added to the database, so do not use rename()
		if tw.output_path == "":
			tw.did_fail = true
		else:
			if tw.asset.parsed_meta != null:
				tw.asset.parsed_meta.path = tw.output_path
			tw.asset.pathname = tw.output_path
		asset_processing_finished.emit(tw)
