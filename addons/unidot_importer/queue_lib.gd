# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
class Deque:
	extends RefCounted
	var _arr: Array = []
	var _start: int = 0
	var _end: int = 0
	var _mutex: RefCounted = null

	class DummyMutex:
		extends RefCounted
		var orig_mutex: RefCounted = null

		func lock():
			pass

		func unlock():
			pass

		func try_lock():
			return OK

	func _init():
		_arr = [].duplicate()
		_mutex = DummyMutex.new()

	func _grow():
		if len(_arr) == 0:
			_arr = [null].duplicate()
			_start = 0
			_end = 0
			return 0
		elif _start == _end:
			var sz: int = len(_arr)
			# print("Grow array " + str(_start) + "/" + str(sz))
			var arr_slice: Array = _arr.slice(_start, sz)
			_arr.resize(_start)
			_arr.resize(sz + _start)
			_arr.append_array(arr_slice)
			_start += sz
			# print("Grow array done " + str(_start) + "/" + str(sz))

	func push_back(el: Variant):
		_mutex.lock()
		_grow()
		_arr[_end] = el
		_end = (_end + 1) % len(_arr)
		_mutex.unlock()

	func push_front(el: Variant):
		_mutex.lock()
		_grow()
		_start = (_start + len(_arr) - 1) % len(_arr)
		_arr[_start] = el
		_mutex.unlock()

	func back() -> Variant:
		_mutex.lock()
		if len(_arr) == 0:
			_mutex.unlock()
			return null
		var idx: int = (_end + len(_arr) - 1) % len(_arr)
		var ret: Variant = _arr[idx]
		_mutex.unlock()
		return ret

	func front() -> Variant:
		_mutex.lock()
		if len(_arr) == 0:
			_mutex.unlock()
			return null
		_mutex.unlock()
		return _arr[_start]

	func pop_back() -> Variant:
		_mutex.lock()
		if len(_arr) == 0:
			_mutex.unlock()
			return null
		_end = (_end + len(_arr) - 1) % len(_arr)
		var el: Variant = _arr[_end]
		_arr[_end] = null
		if _start == _end:
			_arr = [].duplicate()
		_mutex.unlock()
		return el

	func pop_front() -> Variant:
		_mutex.lock()
		if len(_arr) == 0:
			_mutex.unlock()
			return null
		var el: Variant = _arr[_start]
		_arr[_start] = null
		_start = (_start + 1) % len(_arr)
		if _start == _end:
			_arr = [].duplicate()
		_mutex.unlock()
		return el

	func clear():
		_mutex.lock()
		_arr = [].duplicate()
		_mutex.unlock()

	func size():
		_mutex.lock()
		var s: int = _start
		var e: int = _end
		var sz: int = len(_arr)
		_mutex.unlock()
		if sz == 0:
			return 0
		if e > s:
			return e - s
		return e + sz - s

	func lock():
		_mutex.lock()

	func try_lock():
		return _mutex.try_lock()

	func unlock():
		_mutex.unlock()

	# Iteration functions are not locked. Please surround loops with explicit lock()/unlock()
	func _iter_init(arg):
		arg[0] = _start
		return len(_arr) != 0

	func _iter_next(arg):
		arg[0] = (arg[0] + 1) % len(_arr)
		return arg[0] != _end

	func _iter_get(arg):
		return _arr[arg[0]]


class Queue:
	extends Deque

	func _init():
		_arr = [].duplicate()
		_mutex = DummyMutex.new()

	func push(v: Variant):
		push_back(v)

	func pop() -> Variant:
		return pop_front()

	func peek() -> Variant:
		return front()


class LockedDeque:
	extends Deque

	func _init():
		_arr = [].duplicate()
		_mutex = Mutex.new()


class LockedQueue:
	extends Queue

	func _init():
		_arr = [].duplicate()
		_mutex = Mutex.new()


class BlockingQueue:
	extends LockedQueue
	var _semaphore: Semaphore = null

	func _init():
		_arr = [].duplicate()
		_mutex = Mutex.new()
		_semaphore = Semaphore.new()

	func push(v: Variant):
		push_back(v)
		_semaphore.post()
		# Old Godot 3.2 api?
		#while _semaphore.post() != OK:
		#	printerr("Failed to post to BlockingQueue semaphore")
		#	lock()
		#	unlock()

	func pop() -> Variant:
		_semaphore.wait()
		# Old Godot 3.2 api?
		#while _semaphore.wait() != OK:
		#	printerr("Failed to wait for BlockingQueue semaphore")
		#	lock()
		#	unlock()
		return pop_front()


func _thread_function(bq: BlockingQueue, some_int: int):
	assert(bq.pop() == 1)
	assert(bq.pop() == 2)
	assert(bq.pop() == 3)
	print("Thread Finished")
	return "Success"


func run_test():
	var q: Queue = Queue.new()
	q.push(1)
	q.push(2)
	q.push(3)
	assert(q.pop() == 1)
	q.push(4)
	assert(q.pop() == 2)
	assert(q.pop() == 3)
	assert(q.pop() == 4)
	assert(q.pop() == null)
	q.push(5)
	q.push(6)
	assert(q.pop() == 5)
	assert(q.pop() == 6)
	assert(q.pop() == null)
	q.push(7)
	q.push(8)
	q.push(9)
	q.push(10)
	assert(q.pop() == 7)
	assert(q.pop() == 8)
	assert(q.pop() == 9)
	assert(q.pop() == 10)
	assert(q.pop() == null)
	q.push(11)
	q.push(12)
	q.push(13)
	q.push(14)
	q.push(15)
	q.push(16)
	q.push(17)
	q.push(18)
	assert(q.pop() == 11)
	assert(q.pop() == 12)
	assert(q.pop() == 13)
	assert(q.pop() == 14)
	assert(q.pop() == 15)
	assert(q.pop() == 16)
	assert(q.pop() == 17)
	assert(q.pop() == 18)
	assert(q.pop() == null)
	print("Test 1 Finished")
	var bq: BlockingQueue = BlockingQueue.new()
	var t: Thread = Thread.new()
	bq.push(1)
	t.start(self._thread_function.bind(bq))
	OS.delay_msec(100)
	bq.push(2)
	bq.push(3)
	assert(t.wait_to_finish() == "Success")
	assert(null == bq.pop_back())
	print("Test 2 Finished")
