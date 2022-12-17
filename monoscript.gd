extends RefCounted

# Based on "Simple MD4 digest implementation in pure Python" by bonsaiviking:
#### https://gist.github.com/bonsaiviking/5644414


class MD4:
	extends RefCounted
	var selfh: PackedInt32Array
	var count: int = 0
	var remainder: PackedByteArray = PackedByteArray()

	func leftrotate(i: int, n: int) -> int:
		return ((i << n) & 0xffffffff) | (i >> (32 - n))

	func F(x: int, y: int, z: int) -> int:
		return (x & y) | (~x & z)

	func G(x: int, y: int, z: int) -> int:
		return (x & y) | (x & z) | (y & z)

	func H(x: int, y: int, z: int) -> int:
		return x ^ y ^ z

	func _init(data: PackedByteArray = PackedByteArray()):
		self.do_init(data)

	func do_init(data: PackedByteArray):
		self.remainder = data
		self.count = 0
		self.selfh = PackedInt32Array([0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476])

	func _add_chunk(chunk: PackedByteArray):
		self.count += 1
		var i: int = 0
		var k: int = 0
		var X = []
		for val in chunk.to_int32_array():
			X.append(val)
		X.resize(80)
		var h = PackedInt32Array()
		for x in self.selfh:
			h.append(x)
		# Round 1
		var s = PackedInt32Array([3, 7, 11, 19])
		for r in range(16):
			i = (16 - r) % 4
			k = r
			h[i] = leftrotate((h[i] + F(h[(i + 1) % 4], h[(i + 2) % 4], h[(i + 3) % 4]) + X[k]) & 4294967295, s[r % 4])
		# Round 2
		s = PackedInt32Array([3, 5, 9, 13])
		for r in range(16):
			i = (16 - r) % 4
			k = 4 * (r % 4) + int(r / 4)
			h[i] = leftrotate((h[i] + G(h[(i + 1) % 4], h[(i + 2) % 4], h[(i + 3) % 4]) + X[k] + 0x5a827999) & 4294967295, s[r % 4])
		# Round 3
		s = PackedInt32Array([3, 9, 11, 15])
		var karr = PackedInt32Array([0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15])  #wish I could function
		for r in range(16):
			i = (16 - r) % 4
			h[i] = leftrotate((h[i] + H(h[(i + 1) % 4], h[(i + 2) % 4], h[(i + 3) % 4]) + X[karr[r]] + 0x6ed9eba1) & 4294967295, s[r % 4])

		i = 0
		for v in h:
			self.selfh[i] = (v + self.selfh[i]) & 4294967295
			i += 1

	func add(data: PackedByteArray):
		self.remainder.append_array(data)
		var message: PackedByteArray = self.remainder
		var r: int = len(message) % 64
		if r != 0:
			self.remainder = message.slice(len(message) - r)
		else:
			self.remainder = PackedByteArray().duplicate()
		for chunk in range(0, len(message) - r, 64):
			self._add_chunk(message.slice(chunk, chunk + 64))
		return self

	func finish() -> PackedByteArray:
		var l: int = len(self.remainder) + 64 * self.count
		var buf2 = PackedByteArray()
		buf2.resize(((55 - l) & 63) + 1)
		buf2.fill(0)
		buf2[0] = 0x80
		buf2.append_array(PackedInt32Array([l * 8, 0]).to_byte_array())
		self.add(buf2)
		# self.add( "\x80" + "\x00" * ((55 - l) % 64) + struct.pack("<Q", l * 8) )
		var out: PackedByteArray = self.selfh.to_byte_array()
		self.do_init(PackedByteArray())
		return out

	func hex_encode(d: PackedByteArray) -> String:
		var shex = ""
		for b in d:
			var bint: int = b
			shex += "%02x" % ([bint])
		return shex

	func do_test():
		var test = {
			"": "31d6cfe0d16ae931b73c59d7e0c089c0",
			"a": "bde52cb31de33e46245e05fbdbd6fb24",
			"abc": "a448017aaf21d8525fc10ae87aa6729d",
			"message digest": "d9130a8164549fe818874806e1c7014b",
			"abcdefghijklmnopqrstuvwxyz": "d79e1c308aa5bbcdeea8ed63df412da9",
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789": "043f8582f241db351ce627e153e7f0e4",
			"12345678901234567890123456789012345678901234567890123456789012345678901234567890": "e33b4ddc9c38f2199c3e7b164fcc0536"
		}
		var md = MD4.new()
		for tkey in test:
			var t: String = tkey
			var h: String = test[t]
			md.add(t.to_ascii_buffer())
			var d = md.finish()
			if hex_encode(d) == h:
				print("pass")
			else:
				print("FAIL: {0}: {1}\n\texpected: {2}".format([t, hex_encode(d), h]))


# Hash function for calculating a fileID given a classname. The assembly name determines the guid
static func get_fileid(cls_namespace: String, cls_name: String):
	var tohash: PackedByteArray = [115, 0, 0, 0]
	tohash.append_array(cls_namespace.to_utf8_buffer())
	tohash.append_array(cls_name.to_utf8_buffer())
	var hash_result: PackedByteArray = MD4.new(tohash).finish()
	return hash_result.to_int32_array()[0]


static func convert_unityref_to_npidentifier(unityref: Array) -> NodePath:
	assert(unityref[0] == null)
	assert(unityref[2] != null)  # MonoScript can never be local references.
	assert(unityref[3] == 3)
	return NodePath(unityref[2] + "/" + str(unityref[1]))
