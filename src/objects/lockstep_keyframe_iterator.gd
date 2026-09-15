class_name LockstepKeyframeiterator extends RefCounted

var kf_iters: Array[KeyframeIterator]

var timestamp: float = 0.0
var is_eof: bool = false
var perform_right_handed_position_conversion: bool = false
var results: Array[float]

func _init(iters: Array[KeyframeIterator], is_position: bool):
	kf_iters = iters
	results.resize(len(kf_iters))
	if len(results) == 4:
		results[3] = 1 # normalized quaternion
	if is_position:
		perform_right_handed_position_conversion = true

func reset():
	for iter in kf_iters:
		if iter != null:
			iter.reset()
	is_eof = false
	timestamp = 0.0

func debug() -> String:
	var s: String = ""
	s += str(is_eof) + "," + str(timestamp) + "," + str(results) + ":["
	for iter in kf_iters:
		if iter == null:
			s += "null"
		else:
			s += iter.debug()
		s += ","
	s += "]"
	return s

func get_next_timestamp(timestep: float = -1.0) -> float:
	var next_timestamp: Variant = null
	for i in range(len(kf_iters)):
		if kf_iters[i] != null:
			var key_iter: KeyframeIterator = kf_iters[i]
			if key_iter.is_eof:
				continue
			key_iter.timestamp = timestamp
			if typeof(key_iter.prev_slope) == TYPE_STRING:
				key_iter.prev_slope = key_iter.prev_slope.to_float()
			if typeof(key_iter.next_slope) == TYPE_STRING:
				key_iter.next_slope = key_iter.next_slope.to_float()
			if typeof(key_iter.prev_slope) == TYPE_FLOAT and typeof(key_iter.next_slope) == TYPE_FLOAT:
				key_iter.is_constant = is_inf(key_iter.prev_slope) || is_inf(key_iter.next_slope)
			var this_next_timestamp: float = key_iter.get_next_timestamp()
			if typeof(next_timestamp) != TYPE_FLOAT or next_timestamp > this_next_timestamp:
				next_timestamp = this_next_timestamp
	if typeof(next_timestamp) != TYPE_FLOAT:
		is_eof = true
		return 0.0
	elif timestep <= 0:
		return next_timestamp
	else:
		return minf(timestamp + timestep, next_timestamp)

func next(timestep: float = -1.0) -> Variant:
	var valid_components: int = 0
	var new_eof_components: int = 0
	var next_timestamp: float = get_next_timestamp(timestep)
	if not is_eof:
		timestamp = next_timestamp
		for i in range(len(kf_iters)):
			if kf_iters[i] != null:
				var key_iter: KeyframeIterator = kf_iters[i]
				if key_iter.is_eof:
					continue
				var res: Variant
				if timestep <= 0.0:
					res = key_iter.next(timestamp - key_iter.timestamp)
				else:
					res = key_iter.next(timestep)
				if i == 3:
					if len(results) < 4:
						push_error("results len is not 4: " + str(results))
				results[i] = res as float
				if not is_finite(results[i]):
					push_error("We got a nan oh nooo " + str(i) + " from " + str(res) + " at " + str(key_iter.timestamp) + " eof=" + str(key_iter.is_eof) + " const=" + str(key_iter.is_constant) + "key_idx=" + str(key_iter.key_idx))
				valid_components += 1
				if key_iter.is_eof:
					new_eof_components += 1
				key_iter.timestamp = timestamp
	if new_eof_components == valid_components:
		is_eof = true
	if len(results) == 3:
		if perform_right_handed_position_conversion:
			return Vector3(-results[0], results[1], results[2])
		return Vector3(results[0], results[1], results[2])
	elif len(results) == 4:
		if valid_components == 0:
			pass # push_error("next() called when all sub-tracks are eof or null")
		elif Quaternion(results[0], results[1], results[2], results[3]).normalized().is_equal_approx(Quaternion.IDENTITY):
			pass # push_error("next() valid components " + str(valid_components) + " returned an identity quaternion: " + str(results))
		return Quaternion(results[0], -results[1], -results[2], results[3]).normalized()
	return results
