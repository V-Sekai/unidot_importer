@tool
extends Reference

const FORMAT_FLOAT32: int = 0
const FORMAT_FLOAT16: int = 1
const FORMAT_UNORM8: int = 2
const FORMAT_SNORM8: int = 3
const FORMAT_UNORM16: int = 4
const FORMAT_SNORM16: int = 5
const FORMAT_UINT8: int = 6
const FORMAT_SINT8: int = 7
const FORMAT_UINT16: int = 8
const FORMAT_SINT16: int = 9
const FORMAT_UINT32: int = 10
const FORMAT_SINT32: int = 11

var _buffer_words: int = 0
var _buffer: PackedByteArray = PackedByteArray()

var _float32_buf: Array # PackedFloat32Array # FIXME: Cast to Array as a GDScript bug workaround
var _float16_buf: Array # PackedFloat32Array # FIXME: Cast to Array as a GDScript bug workaround
var _int32_buf: PackedInt32Array
var _int16_buf: PackedInt32Array

var HEX_LOOKUP_TABLE: PackedByteArray = PackedByteArray([
	0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
	0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
	0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
	0,1,2,3, 4,5,6,7, 8,9,0,0, 0,0,0,0,
	0,10,11,12, 13,14,15,0, 0,0,0,0, 0,0,0,0,
	0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
	0,10,11,12, 13,14,15,0, 0,0,0,0, 0,0,0,0,
	0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]);

var FLOAT_PREFIX: PackedByteArray = var2bytes([PackedByteArray(), PackedFloat32Array()])
var INT32_PREFIX: PackedByteArray = var2bytes([PackedByteArray(), PackedInt32Array()])

func hex_decode(s: String, prefix: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var offset: int = len(prefix)
	var pba: PackedByteArray = prefix.duplicate()
	var larger_sz: int = (len(s)/2 + 12 + 3)
	pba.resize(larger_sz - (larger_sz & 3) + offset)
	var hlt: PackedByteArray = HEX_LOOKUP_TABLE
	for i in range(len(s)/2):
		pba[i + offset] = 16 * hlt[s.unicode_at(i * 2)] + hlt[s.unicode_at(i * 2 + 1)]
	return pba

func clear_views():
	_float32_buf = Array() # PackedFloat32Array() # FIXME: Cast to Array as a GDScript bug workaround
	_float16_buf = Array() # PackedFloat32Array() # FIXME: Cast to Array as a GDScript bug workaround
	_int32_buf = PackedInt32Array()
	_int16_buf = PackedInt32Array()

func set_buffer_from_hex(source_buffer):
	clear_views()
	_buffer_words = len(source_buffer) / 8
	_buffer = hex_decode(source_buffer, FLOAT_PREFIX)

func _init(source_buffer):
	set_buffer_from_hex(source_buffer)

func _replace_prefix(buffer_and_prefix):
	var prefix = buffer_and_prefix[1]
	for i in range(len(prefix) - 4):
		buffer_and_prefix[0][i] = prefix[i]
	buffer_and_prefix[0][len(prefix) - 4] = (_buffer_words & 0xff)
	buffer_and_prefix[0][len(prefix) - 3] = ((_buffer_words >> 8) & 0xff)
	buffer_and_prefix[0][len(prefix) - 2] = ((_buffer_words >> 16) & 0xff)
	buffer_and_prefix[0][len(prefix) - 1] = ((_buffer_words >> 24) & 0xff)

func _decode_view_with_prefix(buffer_and_prefix) -> Variant:
	_replace_prefix(buffer_and_prefix)
	return bytes2var(buffer_and_prefix[0])[1]

func _validate_word_alignment(offset, stride) -> bool:
	if ((stride & 3) == 0) and (stride > 0) and ((offset & 3) == 0):
		return true
	printerr("Illegal non-word-aligned stride " + str(stride) + " and offset " + str(offset))
	return false

####################### 8-bit formats

func uint8_subarray(offset_arg: int, length_arg: int, stride: int=4, cluster: int=1) -> PackedInt32Array:
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 4 - offset_arg) * cluster / stride)
	var offset: int = offset_arg + len(FLOAT_PREFIX)
	if length <= 0 or _buffer.is_empty():
		return PackedInt32Array()
	assert(_validate_word_alignment(offset_arg, stride))

	var ret: PackedInt32Array = PackedInt32Array()
	ret.resize(length)
	for cidx in range(cluster):
		for i in range(length / cluster):
			ret[i * cluster + cidx] = _buffer[offset + i * stride + cidx]
	return ret

func norm8_subarray(is_signed: bool, offset_arg: int, length_arg: int, stride: int=4, cluster: int=1) -> PackedFloat32Array:
	var sign_mul: int = 2 if is_signed else 0
	var divisor: float = 127.0 if is_signed else 255.0
	var offset: int = offset_arg + len(FLOAT_PREFIX)
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 4 - offset_arg) * cluster / stride)
	if length <= 0 or _buffer.is_empty():
		return PackedFloat32Array()
	assert(_validate_word_alignment(offset_arg, stride))

	var ret: PackedFloat32Array = PackedFloat32Array()
	# GDScript bug with F32Array # ret.resize(length)
	for i in range(length / cluster):
		for cidx in range(cluster):
			var found: int = _buffer[offset + i * stride + cidx]
			# GDScript bug with F32Array # ret[i * cluster + cidx] = (found - sign_mul * (found & 0x8000)) / divisor
			ret.push_back((found - sign_mul * (found & 0x8000)) / divisor)
	return ret

####################### 16-bit formats

func _initialize_uint16_array():
	if _int32_buf.is_empty():
		_int32_buf = _decode_view_with_prefix([_buffer, INT32_PREFIX])
	if _int16_buf.is_empty():
		_int16_buf = PackedInt32Array()
		_int16_buf.resize(len(_int32_buf) * 2)
		for i in range(len(_int32_buf)):
			_int16_buf[i * 2] = (_int32_buf[i] & 0xffff)
			_int16_buf[i * 2 + 1] = ((_int32_buf[i] >> 16) & 0xffff)

func uint16_subarray(offset: int, length_arg: int, stride: int=2, cluster: int=1) -> PackedInt32Array:
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 2 - offset) * cluster / stride)
	if length <= 0 or _buffer.is_empty():
		return PackedInt32Array()
	assert(_validate_word_alignment(offset * 2, stride * 2))
	_initialize_uint16_array()

	var ret: PackedInt32Array = PackedInt32Array()
	ret.resize(length)
	for cidx in range(cluster):
		for i in range(length / cluster):
			ret[i * cluster + cidx] = _int16_buf[(offset + i * stride) / 2 + cidx]
	return ret

func norm16_subarray(is_signed: bool, offset: int, length_arg: int, stride: int=2, cluster: int=1) -> PackedFloat32Array:
	var sign_mul: int = 2 if is_signed else 0
	var divisor: float = 32767.0 if is_signed else 65535.0
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 2 - offset) * cluster / stride)
	if length <= 0 or _buffer.is_empty():
		return PackedFloat32Array()
	assert(_validate_word_alignment(offset * 2, stride * 2))
	_initialize_uint16_array()

	var ret: PackedFloat32Array = PackedFloat32Array()
	# GDScript bug with F32Array # ret.resize(length)
	for i in range(length / cluster):
		for cidx in range(cluster):
			var found: int = _int16_buf[(offset + i * stride) / 2 + cidx]
			# GDScript bug with F32Array # ret[i * cluster + cidx] = (found - sign_mul * (found & 0x8000)) / divisor
			ret.push_back((found - sign_mul * (found & 0x8000)) / divisor)
	return ret

func float16_subarray(offset: int, length_arg: int, stride: int=2, cluster: int=1) -> PackedFloat32Array:
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 2 - offset) * cluster / stride)
	if length <= 0 or _buffer.is_empty():
		return PackedFloat32Array()
	assert(_validate_word_alignment(offset * 2, stride * 2))
	if _float16_buf.is_empty():
		_initialize_uint16_array()
		var tmp16buf: PackedByteArray = FLOAT_PREFIX.duplicate()
		var tmpoffs: int = len(tmp16buf)
		tmp16buf.resize(len(tmp16buf) + _buffer_words * 4)
		# _float16_buf
		for i in range(len(_int16_buf)):
			var rawflt: int = ((_int16_buf[i] & 0x8000) << 16) | ((((_int16_buf[i] & 0x7c00) + 114688) | (_int16_buf[i] & 0x3ff)) << 13)
			tmp16buf[tmpoffs + i * 4] = rawflt >> 24
			tmp16buf[tmpoffs + i * 4 + 1] = rawflt >> 16
			tmp16buf[tmpoffs + i * 4 + 2] = rawflt >> 8
			# tmp16buf[tmpoffs + i * 4 + 3] = 0 # rest of mantissa is zero, which is default.
		# FIXME: Cast to Array as a GDScript bug workaround
		_float16_buf = Array(_decode_view_with_prefix([tmp16buf, FLOAT_PREFIX]))

	var ret: PackedFloat32Array = PackedFloat32Array()
	# GDScript bug with F32Array # ret.resize(length)
	for i in range(length / cluster):
		for cidx in range(cluster):
			# GDScript bug with F32Array # ret[i * cluster + cidx] = _float16_buf[offset + i * stride / 2 + cidx]
			ret.push_back(_float16_buf[(offset + i * stride) / 2 + cidx])

	return ret

####################### 32-bit formats

func uint32_subarray(offset: int, length_arg: int, stride: int=4, cluster: int=1) -> PackedInt32Array:
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 4 - offset) * cluster / stride)
	if length <= 0 or _buffer.is_empty():
		return PackedInt32Array()
	assert(_validate_word_alignment(offset, stride))
	if _int32_buf.is_empty():
		_int32_buf = _decode_view_with_prefix([_buffer, INT32_PREFIX])

	var ret: PackedInt32Array = PackedInt32Array()
	ret.resize(length)
	for cidx in range(cluster):
		for i in range(length / cluster):
			ret[i * cluster + cidx] = _int32_buf[(offset + i * stride) / 4 + cidx]
	return ret

func float32_subarray(offset: int, length_arg: int, stride: int=4, cluster: int=1) -> PackedFloat32Array:
	var length: int = min(length_arg, (_buffer_words * 4 + stride - 4 - offset) * cluster / stride)
	print("float32 subarray " + str(offset) + " length_arg " + str(length_arg) + " length " + str(length) + " stride " + str(stride) + " cluster " + str(cluster))
	if length <= 0 or _buffer.is_empty():
		return PackedFloat32Array()
	assert(_validate_word_alignment(offset, stride))
	if _float32_buf.is_empty():
		# FIXME: Cast to Array as a GDScript bug workaround
		_float32_buf = Array(_decode_view_with_prefix([_buffer, FLOAT_PREFIX]))

	var ret: PackedFloat32Array = PackedFloat32Array()
	# GDScript bug with F32Array # ret.resize(length)
	for i in range(length / cluster):
		for cidx in range(cluster):
			# GDScript bug with F32Array # ret[i * cluster + cidx] = _float32_buf[offset + i * stride / 4 + cidx]
			ret.push_back(_float32_buf[(offset + i * stride) / 4 + cidx])
	return ret


static func format_byte_width(format: int) -> int:
	match format:
		FORMAT_FLOAT32, FORMAT_UINT32, FORMAT_SINT32:
			return 4
		FORMAT_FLOAT16, FORMAT_UINT16, FORMAT_SINT16, FORMAT_UNORM16, FORMAT_SNORM16:
			return 2
		FORMAT_UINT8, FORMAT_SINT8, FORMAT_UNORM8, FORMAT_SNORM8:
			return 1
		_:
			printerr("Unknown format " + str(format))
			return 4

func formatted_float_uint8_subarray(format: int, offset: int, length: int, stride: int, cluster: int=1) -> PackedByteArray:
	var float_array: PackedFloat32Array = formatted_float_subarray(format, offset, length, stride, cluster)
	var encoded_array: PackedByteArray = var2bytes([PackedByteArray(), float_array])
	return encoded_array.subarray(len(FLOAT_PREFIX), len(encoded_array) - 1) # Warning: subarray is INCLUSIVE,INCLUSIVE

func formatted_float_subarray(format: int, offset: int, length: int, stride: int, cluster: int=1) -> PackedFloat32Array:
	match format:
		FORMAT_FLOAT32:
			return float32_subarray(offset, length, stride, cluster)
		FORMAT_FLOAT16:
			return float16_subarray(offset, length, stride, cluster)
		FORMAT_UNORM8:
			return norm8_subarray(false, offset, length, stride, cluster)
		FORMAT_SNORM8:
			return norm8_subarray(true, offset, length, stride, cluster)
		FORMAT_UNORM16:
			return norm16_subarray(false, offset, length, stride, cluster)
		FORMAT_SNORM16:
			return norm16_subarray(true, offset, length, stride, cluster)
		_:
			printerr("Invalid format " + str(format) + " for float vertex array.")
			return PackedFloat32Array()

func formatted_int_subarray(format: int, offset: int, length: int, stride: int, cluster: int=1) -> PackedInt32Array:
	match format:
		# I cannot see any application or usage of sign bit for integer vertex attributes
		# (this is just bones or indices, right?)
		FORMAT_UINT8, FORMAT_SINT8:
			return uint8_subarray(offset, length, stride, cluster)
		FORMAT_UINT16, FORMAT_SINT16:
			return uint16_subarray(offset, length, stride, cluster)
		FORMAT_UINT32, FORMAT_SINT32:
			return uint32_subarray(offset, length, stride, cluster)
		_:
			printerr("Invalid format " + str(format) + " for integer vertex array.")
			return PackedInt32Array()

func formatted_vector2_subarray(format: int, offset: int, length: int, stride: int, dimension: int=2, flipv: bool=false) -> PackedVector2Array:
	# FIXME: Cast to Array as a GDScript bug workaround
	var float_array: Array = Array(formatted_float_subarray(format, offset, length * dimension, stride, dimension))
	var vec2_array: PackedVector2Array = PackedVector2Array()
	vec2_array.resize(len(float_array) / dimension)
	var flip=1.0 if flipv else 0.0
	var flop=-1.0 if flipv else 1.0
	for i in range(len(float_array) / dimension):
		vec2_array[i] = Vector2(float_array[i * dimension], flip + flop * float_array[i * dimension + 1])
	return vec2_array

# Special case: comes with a vector to flip handedness if used for vertex or normal.
func formatted_vector3_subarray(handedness_vector: Vector3, format: int, offset: int, length: int, stride: int, dimension: int=3) -> PackedVector3Array:
	# FIXME: Cast to Array as a GDScript bug workaround
	var float_array: Array = Array(formatted_float_subarray(format, offset, length * dimension, stride, dimension))
	var vec3_array: PackedVector3Array = PackedVector3Array()
	vec3_array.resize(len(float_array) / dimension)
	print("Asked for format " + str(format) + " offset " + str(offset) + " length " + str(length) + " stride " + str(stride) + " dim " + str(dimension) + " outarr " + str(len(vec3_array)) + " floatarr " + str(len(float_array)) + " buflen " + str(len(_buffer)) + " floatbuflen " + str(len(_float32_buf)))
	match dimension:
		2:
			for i in range(len(float_array) / 2):
				var x: float = float_array[i * 2]
				var y: float = float_array[i * 2 + 1]
				vec3_array[i] = handedness_vector * Vector3(x, y, sqrt(1 - x * x - y * y))
		_:
			for i in range(len(float_array) / 3):
				vec3_array[i] = handedness_vector * Vector3(float_array[i * 3], float_array[i * 3 + 1], float_array[i * 3 + 2])
	return vec3_array

func formatted_color_subarray(format: int, offset: int, length: int, stride: int, dimension: int=4) -> PackedColorArray:
	# FIXME: Cast to Array as a GDScript bug workaround
	var float_array: Array = Array(formatted_float_subarray(format, offset, length * dimension, stride, dimension))
	var color_array: PackedColorArray = PackedColorArray()
	color_array.resize(len(float_array) / dimension)
	match dimension:
		1:
			for i in range(len(float_array)):
				color_array[i] = Color(float_array[i], 0, 0, 1)
		2:
			for i in range(len(float_array) / 2):
				color_array[i] = Color(float_array[i * 2], float_array[i * 2 + 1], 0, 1)
		3:
			for i in range(len(float_array) / 3):
				color_array[i] = Color(float_array[i * 3], float_array[i * 3 + 1], float_array[i * 3 + 2], 1)
		4:
			for i in range(len(float_array) / 4):
				color_array[i] = Color(float_array[i * 4], float_array[i * 4 + 1], float_array[i * 4 + 2], float_array[i * 4 + 3])
	return color_array

func formatted_tangent_subarray(format: int, offset: int, length: int, stride: int, dimension: int=4) -> PackedFloat32Array:
	# FIXME: Cast to Array as a GDScript bug workaround
	var float_array: Array = Array(formatted_float_subarray(format, offset, length * 4, stride, 4))
	match dimension:
		2:
			for i in range(0, len(float_array), 4):
				var x: float = float_array[i * 4]
				var y: float = float_array[i * 4 + 1]
				float_array[i] *= -1
				float_array[i + 2] = sqrt(1 - x * x - y * y)
				float_array[i + 3] = 1
		3:
			for i in range(0, len(float_array), 4):
				float_array[i] *= -1
				float_array[i + 3] = 1
		_:
			for i in range(0, len(float_array), 4):
				float_array[i] *= -1
	return PackedFloat32Array(float_array) # FIXME: GDScript bug workaround
