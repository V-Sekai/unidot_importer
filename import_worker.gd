@tool
extends RefCounted

const queue_lib: GDScript = preload("./queue_lib.gd")
const tarfile: GDScript = preload("./tarfile.gd")
const unitypackagefile: GDScript = preload("./unitypackagefile.gd")
const asset_adapter_class: GDScript = preload("./unity_asset_adapter.gd")

var asset_adapter = asset_adapter_class.new()

var thread_queue: Object  # queue_lib.BlockingQueue
var thread_count: int
var threads: Array
var disable_threads: bool = false
var asset_database: RefCounted


class ShutdownSentinel:
	pass


class ThreadWork:
	var asset: Object  # unitypackagefile.UnityPackageAsset type.
	var tmpdir: String
	var output_path: String
	var extra: Variant


signal asset_processing_started(tw: ThreadWork)
signal asset_processing_finished(tw: ThreadWork)
signal asset_failed(tw: ThreadWork)


func _init():
	thread_queue = queue_lib.BlockingQueue.new()
	thread_count = 0
	threads = [].duplicate()


func start_thread():
	thread_count += 1
	print("Starting thread")
	var thread: Thread = Thread.new()
	# Third argument is optional userdata, it can be any variable.
	thread.start(self._thread_function.bind("THR" + str(thread_count)))
	threads.push_back(thread)
	return thread


func start_threads(count: int):
	disable_threads = (count == 0)
	for i in range(count):
		start_thread()


func tell_all_threads_to_stop():
	for i in range(thread_count):
		thread_queue.push(ShutdownSentinel)
	thread_count = 0


func stop_all_threads_and_wait():
	tell_all_threads_to_stop()
	#### FIXME: CAUSES GODOT TO CRASH??
	for thread in threads:
		thread.wait_to_finish()
	thread_queue = queue_lib.BlockingQueue.new()
	threads = [].duplicate()


func push_work_obj(tw: ThreadWork):
	self.thread_queue.push(tw)


# asset: unitypackagefile.UnityPackageAsset object
func push_asset(asset: Object, tmpdir: String, extra: Variant = null):
	var tw = ThreadWork.new()
	tw.asset = asset
	tw.tmpdir = tmpdir
	tw.extra = extra
	if asset.parsed_meta != null:
		asset.parsed_meta.log_debug("Enqueue asset " + str(asset.guid) + " " + str(asset.pathname))
	else:
		print("Enqueue asset " + str(asset.guid) + " " + str(asset.pathname))
	if disable_threads:
		self.call_deferred("_run_single_item_delayed", tw)
	else:
		self.push_work_obj(tw)


func _run_single_item_delayed(tw: ThreadWork):
	self.call_deferred("_run_single_item", tw, "NOTHR")


func _run_single_item(tw: ThreadWork, thread_subdir: String):
	asset_processing_started.emit(tw)
	tw.output_path = asset_adapter.preprocess_asset(asset_database, tw.asset, tw.tmpdir, thread_subdir)
	# It has not yet been added to the database, so do not use rename()
	if tw.asset.parsed_meta != null:
		tw.asset.parsed_meta.path = tw.output_path
	tw.asset.pathname = tw.output_path
	asset_processing_finished.emit(tw)


# Run here and exit.
# The argument is the userdata passed from start().
# If no argument was passed, this one still needs to
# be here and it will be null.
func _thread_function(thread_subdir: String):
	# Print the userdata ("Wafflecopter")
	print("I'm a thread! Userdata is: ", thread_subdir)
	while true:
		var tw = thread_queue.pop()
		if tw == ShutdownSentinel:
			print("I was told to shutdown")
			break
		_run_single_item(tw, thread_subdir)
