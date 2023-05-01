@tool
extends "./thread_worker.gd"

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
		tw.asset.log_debug("Parsing " + path + ": " + str(tw.asset.parsed_meta))

	asset_processing_finished.emit(tw)
