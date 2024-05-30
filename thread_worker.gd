# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

const queue_lib := preload("./queue_lib.gd")
const asset_adapter_class := preload("./asset_adapter.gd")

var asset_adapter = asset_adapter_class.new()

var thread_queue: queue_lib.BlockingQueue
var thread_count: int
var threads: Array
var disable_threads: bool = false
var asset_database: RefCounted


class ShutdownSentinel:
	pass


signal asset_processing_started(tw: Object)
signal asset_processing_finished(tw: Object)


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


# asset: package_file.PkgAsset object
func push_work_obj(tw: Object):
	if disable_threads:
		self.call_deferred("_run_single_item_delayed", tw)
	else:
		self.thread_queue.push(tw)


func _run_single_item_delayed(tw: Object):
	self.call_deferred("_run_single_item", tw, "NOTHR")


# OVERRIDE This!
func _run_single_item(tw: Object, thread_subdir: String):
	asset_processing_started.emit(tw)
	pass
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
		#print(tw)
		if tw == ShutdownSentinel:
			print("I was told to shutdown")
			break
		_run_single_item(tw, thread_subdir)
