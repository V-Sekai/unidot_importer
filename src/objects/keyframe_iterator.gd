class_name KeyframeIterator extends RefCounted

var curve: Dictionary
var keyframes: Array
var init_key: Dictionary
var final_key: Dictionary
var prev_key: Dictionary
var prev_slope: Variant = null
var next_key: Dictionary
var next_slope: Variant = null
var has_slope: bool
var key_idx: int = 0
var is_eof: bool = false
var is_constant: bool = false
var is_mirrored: bool = false

const CONSTANT_KEYFRAME_TIMESTAMP = 0.001

var timestamp: float = 0.0

func _init(p_curve: Dictionary):
	curve = p_curve
	keyframes = curve["m_Curve"]
	is_mirrored = curve.get("unidot-mirror", false)
	init_key = keyframes[0]
	final_key = keyframes[-1]
	prev_key = init_key
	next_key = init_key # if len(keyframes) == 1 else keyframes[1]
	if prev_key.has("outSlope"):
		has_slope = true # serializedVersion=3 has inSlope/outSlope while version=2 does not
		# Assets can actually mix and match version 2 and 3 even for related tracks.
		prev_slope = prev_key["outSlope"]
		next_slope = next_key["inSlope"]
	is_constant = false

func reset():
	key_idx = 0
	prev_key = init_key
	next_key = init_key
	is_eof = false
	timestamp = 0.0
	is_constant = false

func debug() -> String:
	var s: String = ""
	s += "{" + str(is_eof) + "," + str(timestamp) + "," + str("const" if is_constant else "linear")
	s += "," + str(prev_slope) + "," + str(next_slope)
	s += " @" + str(key_idx) + ":" + str(prev_key["time"]) + "=>" + str(next_key["time"]) + "}"
	return s

func get_next_timestamp(timestep: float = -1.0) -> float:
	if is_eof:
		return 0.0
	if len(keyframes) == 1:
		return 0.0
	if is_constant and timestamp < next_key["time"] - CONSTANT_KEYFRAME_TIMESTAMP:
		# Make a new keyframe with the previous value CONSTANT_KEYFRAME_TIMESTAMP before the next.
		return next_key["time"] - CONSTANT_KEYFRAME_TIMESTAMP
	if timestep <= 0:
		return next_key["time"]
	elif timestamp + timestep >= next_key["time"]:
		return next_key["time"]
	else:
		return timestamp + timestep

func fixup_strings(val: Variant) -> Variant:
	if typeof(val) == TYPE_STRING:
		val = val.to_float()
	if is_mirrored:
		# Every value comes through here, so it's a good place to make sure we negate everything
		val = -val
	return val

func next(timestep: float = -1.0) -> Variant:
	if is_eof:
		return null
	if typeof(prev_slope) == TYPE_STRING:
		prev_slope = prev_slope.to_float()
	if typeof(next_slope) == TYPE_STRING:
		next_slope = next_slope.to_float()
	if typeof(prev_slope) == TYPE_FLOAT:
		is_constant = not (is_finite(prev_slope) && is_finite(next_slope))
		# is_constant = (typeof(key_iter.prev_slope) == TYPE_STRING || typeof(key_iter.next_slope) == TYPE_STRING || is_inf(key_iter.prev_slope) || is_inf(key_iter.next_slope))
	elif typeof(prev_slope) == TYPE_VECTOR3:
		is_constant = not (is_finite(prev_slope.x) && is_finite(next_slope.x) && is_finite(prev_slope.y) && is_finite(next_slope.y) && is_finite(prev_slope.z) && is_finite(next_slope.z))
	elif typeof(prev_slope) == TYPE_QUATERNION:
		is_constant = not (is_finite(prev_slope.x) && is_finite(next_slope.x) && is_finite(prev_slope.y) && is_finite(next_slope.y) && is_finite(prev_slope.z) && is_finite(next_slope.z) && is_finite(prev_slope.w) && is_finite(next_slope.w))

	if len(keyframes) == 1:
		timestamp = 0.0
		is_eof = true
		return fixup_strings(init_key["value"])
	var constant_end_timestamp: float = next_key["time"] - CONSTANT_KEYFRAME_TIMESTAMP
	if is_constant and timestamp < constant_end_timestamp:
		# Make a new keyframe with the previous value CONSTANT_KEYFRAME_TIMESTAMP before the next.
		if timestep <= 0:
			timestamp = constant_end_timestamp
		else:
			timestamp = min(timestamp + timestep, constant_end_timestamp)
		return fixup_strings(prev_key["value"])
	if timestep <= 0:
		timestamp = next_key["time"]
	else:
		timestamp += timestep
	if timestamp >= next_key["time"] - CONSTANT_KEYFRAME_TIMESTAMP:
		prev_key = next_key
		prev_slope = prev_key.get("outSlope")
		timestamp = prev_key["time"]
		key_idx += 1
		if key_idx >= len(keyframes):
			is_eof = true
		else:
			next_key = keyframes[key_idx]
			next_slope = next_key.get("inSlope")
		return fixup_strings(prev_key["value"])
	# Todo: have caller determine desired keyframe depending on slope and accuracy
	# and clip length, to decide whether to use default linear interpolation or add more keyframes.
	# We could also have a setting to use cubic instead of linear for more smoothness but less accuracy.
	# FIXME: Assuming linear interpolation
	if not is_equal_approx(next_key["time"], prev_key["time"]) and timestamp >= prev_key["time"] and timestamp <= next_key["time"]:
		return lerp(fixup_strings(prev_key["value"]), fixup_strings(next_key["value"]), (timestamp - prev_key["time"]) / (next_key["time"] - prev_key["time"]))
	return fixup_strings(next_key["value"])
