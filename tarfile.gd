extends RefCounted

const BLOCKSIZE: int = 512

var buffer: PackedByteArray = PackedByteArray()
var offset: int = 0


class StringFile:
	var _s: String = ""
	var _offset: int = 0
	var _eof: bool = false
	var _path: String = ""

	func init(s: String):
		_s = s
		_offset = 0
		_eof = false

	func get_path() -> String:
		return _path

	func set_path(path: String):
		_path = path

	func get_backing_string() -> String:
		return _s

	func OLD_nsquared_get_line() -> String:
		if _eof:
			return ""
		var eol: int = _s.find("\n", _offset)
		if eol == -1:
			_eof = true
			var reteof: String = _s.substr(_offset)
			_offset = 0
			return reteof

		var new_offset: int = eol + 1
		if _s.substr(eol - 1, eol) == "\r":
			eol -= 1
		var ret: String = _s.substr(_offset, eol - _offset)
		_offset = new_offset
		return ret

	var _lines_cache: Array = [].duplicate()
	var _line_offset: int = -1

	func get_line() -> String:
		if _lines_cache.is_empty():
			_lines_cache = _s.split("\n", true)
			print("------- SPLITTING STRING TO " + str(len(_lines_cache)) + " LINES")
		_line_offset += 1
		if _line_offset >= len(_lines_cache):
			_eof = true
		if _eof:
			return ""
		var ret: String = _lines_cache[_line_offset]
		var len_ret: int = len(ret)
		if len_ret > 0:
			if ret.substr(len_ret - 1, len_ret) == "\r":
				# if ret.unicode_at(len_ret - 1) == 13:
				return ret.substr(0, len_ret - 1)
		return ret

	func get_error():
		if _eof:
			return ERR_FILE_EOF
		else:
			return OK

	func close():
		pass


func init_with_buffer(new_buffer: PackedByteArray):
	buffer = new_buffer
	return self


class TarHeader:
	extends RefCounted
	var size: int = 0
	var filename: String = ""
	var buffer: PackedByteArray = PackedByteArray()
	var offset: int = 0
	var gd4hack_StringFile: Object = null

	func get_data() -> PackedByteArray:
		return buffer.slice(offset, offset + size)

	func get_string() -> String:
		return get_data().get_string_from_utf8()

	func get_stringfile() -> Object:
		var sf = gd4hack_StringFile.new()
		sf.init(get_data().get_string_from_utf8())
		sf.set_path(filename)
		return sf


static func nti(header: PackedByteArray, offset: int, xlen: int) -> int:
	var idx: int = offset
	var end: int = offset + xlen
	var n: int = 0
	if header[offset] == 128 or header[offset] == 255:
		# GNU format, untested?
		while idx < end:
			n = (n << 8) + header[idx]
			idx += 1
		if header[offset] == 255:
			n = -((1 << (8 * (xlen - 1))) - n)
		return n
	while idx < end and header[idx] != 0:
		if header[idx] >= 48:
			n = (n << 3) + (header[idx] - 48)
		idx += 1
	return n


func read_header() -> TarHeader:
	if self.offset + BLOCKSIZE > len(self.buffer):
		return null
	var header_obj = TarHeader.new()
	header_obj.gd4hack_StringFile = StringFile
	var idx: int = 0
	while idx < 100 and self.buffer[self.offset + idx] != 0:
		idx += 1
	header_obj.filename = self.buffer.slice(self.offset + 0, self.offset + idx).get_string_from_utf8()
	header_obj.size = nti(self.buffer, self.offset + 124, 12)
	self.offset += BLOCKSIZE
	header_obj.buffer = self.buffer
	header_obj.offset = self.offset
	self.offset += ((header_obj.size - 1 + BLOCKSIZE) & ~(BLOCKSIZE - 1))
	return header_obj
