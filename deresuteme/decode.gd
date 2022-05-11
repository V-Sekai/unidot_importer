extends RefCounted
# -!- coding: utf-8 -!-
#
# Copyright 2016 Hector Martin <marcan@marcan.st>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	 http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

const object_adapter_class: GDScript = preload("../unity_object_adapter.gd")

var object_adapter = object_adapter_class.new()

const baseStrings: Dictionary = {
	0: "AABB",
	5: "AnimationClip",
	19: "AnimationCurve",
	34: "AnimationState",
	49: "Array",
	55: "Base",
	60: "BitField",
	69: "bitset",
	76: "bool",
	81: "char",
	86: "ColorRGBA",
	106: "data",
	117: "double",
	138: "FastPropertyName",
	155: "first",
	161: "float",
	167: "Font",
	172: "GameObject",
	183: "Generic Mono",
	208: "GUID",
	222: "int",
	226: "list",
	231: "long long",
	241: "map",
	245: "Matrix4x4f",
	262: "NavMeshSettings",
	263: "MonoBehaviour",
	277: "MonoScript",
	299: "m_Curve",
	307: "m_EditorClassIdentifier",
	331: "m_EditorHideFlags",
	349: "m_Enabled",
	374: "m_GameObject",
	427: "m_Name",
	434: "m_ObjectHideFlags",
	452: "m_PrefabInternal",
	469: "m_PrefabParentObject",
	490: "m_Script",
	499: "m_StaticEditorFlags",
	519: "m_Type",
	526: "m_Version",
	536: "Object",
	543: "pair",
	548: "PPtr<Component>",
	564: "PPtr<GameObject>",
	581: "PPtr<Material>",
	596: "PPtr<MonoBehaviour>",
	616: "PPtr<MonoScript>",
	633: "PPtr<Object>",
	646: "PPtr<Prefab>",
	659: "PPtr<Sprite>",
	672: "PPtr<TextAsset>",
	688: "PPtr<Texture>",
	702: "PPtr<Texture2D>",
	718: "PPtr<Transform>",
	734: "Prefab",
	741: "Quaternionf",
	753: "Rectf",
	778: "second",
	785: "set",
	789: "short",
	795: "size",
	800: "SInt16",
	807: "SInt32",
	814: "SInt64",
	821: "SInt8",
	827: "staticvector",
	840: "string",
	847: "TextAsset",
	857: "TextMesh",
	866: "Texture",
	874: "Texture2D",
	884: "Transform",
	894: "TypelessData",
	907: "UInt16",
	914: "UInt32",
	921: "UInt64",
	928: "UInt8",
	934: "unsigned int",
	947: "unsigned long long",
	966: "unsigned short",
	981: "vector",
	988: "Vector2f",
	997: "Vector3f",
	1006: "Vector4f",
	1042: "Gradient",
	1093: "m_CorrespondingSourceObject",
	1121: "m_PrefabInstance",
	1138: "m_PrefabAsset",
}

class Stream extends StreamPeerBuffer:
	var d: PackedByteArray = self.data_array
	var reference_prefab_guid_storage: Array
	func _init(d: PackedByteArray, p: int=0):
		self.d = d
		self.data_array = d
		self.reference_prefab_guid_storage = []
		self.seek(p)
	func tell() -> int:
		return self.get_position()
	func seek_end(p: int) -> void:
		self.seek(self.get_size() - p)
	func skip(off: int) -> void:
		self.seek(self.get_position() + off)
	func read(cnt: int=-1) -> PackedByteArray:
		if cnt == -1:
			cnt = self.get_size() - self.get_position()
		return self.get_data(cnt)[1]
	func align(n: int, align_off: int=0) -> void:
		var old_pos: int = self.tell()
		var new_pos: int = ((old_pos - align_off + n - 1) & ~(n - 1)) + align_off
		# if old_pos != new_pos:
		# 	# print("align " + str(n) + " from " + str(old_pos) + " to " + str(new_pos))
		self.seek(new_pos)
	func read_str() -> String:
		var initial_pos: int = self.get_position()
		if initial_pos == self.get_size():
			push_error("Already at end for read_str " + str(initial_pos) +" " + str(self.get_size()))
			return ""
		var i: int = initial_pos
		var ilen: int = self.get_size()
		while i < ilen:
			if d[i] == 0:
				# automatically Nul-terminates.
				self.seek(i + 1)
				return self.d.slice(initial_pos, i + 1).get_string_from_ascii()
			i += 1
		return self.d.slice(initial_pos, self.get_size()).get_string_from_ascii()


class Def extends RefCounted:
	var children: Array = [].duplicate()
	var name: String = ""
	var full_name: String = ""
	var type_name: String = ""
	var size: int = 0
	var flags: int = 0
	var array: bool = false
	var parent: RefCounted = null
	var serVer: int = 1
	func _init(name: String, type_name: String, size: int, flags: int, array: bool, serVer: int):
		self.children = [].duplicate()
		self.name = name
		self.full_name = name
		self.type_name = type_name
		self.size = size
		self.flags = flags
		self.array = array
		self.serVer = serVer

	func set_parent(new_par: RefCounted):
		parent = new_par
		var par: RefCounted = new_par
		while par != null:
			self.full_name = str(par.name) + "." + self.full_name
			par = par.parent

	func read(s: Stream, referenced_guids: Array, referenced_reftypes: Array) -> Variant:
		if self.array:
			var x: int = s.tell()
			if self.children.is_empty():
				push_error("Children is empty for " + str(self.full) + " type " + str(type_name) + " size " + str(size) + " flags " + str(flags))
				return []
			# print("a " + self.full_name)
			var arrlen: int = self.children[0].read(s, referenced_guids, referenced_reftypes)
			if not (arrlen < 100000000):
				push_error("Attempting to read " + str(arrlen) + " in array " + str(self.full_name) + " type " + str(type_name) + " size " + str(size) + " flags " + str(flags))
				return []
			var child_type_name: String = self.children[1].type_name
			if child_type_name == "char":
				# print("s " + str(arrlen))
				var ret: String = s.read(arrlen).get_string_from_utf8()
				# print("reading string @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + ": " + ret)
				if self.size >= 1:
					s.seek(x + self.size)
				#s.align(4, x)
				return ret
			elif child_type_name == "UInt8":
				var ret: PackedByteArray = s.read(arrlen)
				if self.size >= 1:
					s.seek(x + self.size)
				return ret
			else:
				if not (self.children[1].size * arrlen < 400000000 and arrlen < 100000000):
					push_error("Attempting to read " + str(arrlen) + " in array " + str(self.full_name) + " type " + str(type_name) + " size " + str(size) + " flags " + str(flags))
					return []
				var i: int = 0
				var pad: bool = true
				if self.flags == 0x4000 and self.children[1].flags == 0x0:
					pad = false
				var arr_variant: Variant = null
				if (child_type_name == "SInt16" or child_type_name == "short" or
						child_type_name == "UInt16" or child_type_name == "unsigned short"):
					var arr: PackedInt32Array = PackedInt32Array().duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				elif (child_type_name == "SInt32" or child_type_name == "int" or
						child_type_name == "long" or child_type_name == "unsigned int" or
						child_type_name == "UInt32" or child_type_name == "unsigned long"):
					arr_variant = s.read(arrlen * 4).to_int32_array()
				elif (child_type_name == "SInt64" or child_type_name == "UInt64" or
						child_type_name == "long long" or child_type_name == "unsigned long long"):
					arr_variant = s.read(arrlen * 8).to_int64_array()
				elif child_type_name == "float":
					arr_variant = s.read(arrlen * 4).to_float32_array()
				elif child_type_name == "double":
					arr_variant = s.read(arrlen * 8).to_float64_array()
				elif child_type_name == "Vector2f":
					var arr: PackedVector2Array = PackedVector2Array().duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				elif child_type_name == "Vector3f":
					var arr: PackedVector3Array = PackedVector3Array().duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				elif child_type_name == "ColorRGBA":
					var arr: PackedColorArray = PackedColorArray().duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				elif child_type_name == "string":
					var arr: PackedStringArray = PackedStringArray().duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				else:
					var arr: Array = [].duplicate()
					while i < arrlen:
						arr.push_back(self.children[1].read(s, referenced_guids, referenced_reftypes))
						i += 1
					arr_variant = arr
				# print("reading arr @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + ": " + str(len(arr)))
				if self.size >= 1:
					s.seek(x + self.size)
				return arr_variant
		elif not self.children.is_empty():
			var x: int = 0 #####s.tell()
			var v: Dictionary = {}.duplicate()
			if self.serVer != 1:
				print("Adding serializedVersion to " + str(self.type_name) + " " + str(self.name) + ": " + str(self.serVer))
				v["serializedVersion"] = self.serVer
			for i in self.children:
				v[i.name] = i.read(s, referenced_guids, referenced_reftypes)
				if i.flags & 0x4000:
					s.align(4, x)
			match self.type_name:
				"string":
					if v.has("Array"):
						# print("reading array @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
						return v.get("Array")
				"map":
					var res: Dictionary = {}
					if v.has("Array"):
						for kv in v.get("Array"):
							res[kv.get("first")] = kv.get("second")
					return [res]
				"ColorRGBA":
					if v.has("rgba"):
						var color32: int = v.get("rgba")
						return Color(
							((color32&0xff000000)>>24) / 255.0,
							((color32&0xff0000)>>16) / 255.0,
							((color32&0xff00)>>8) / 255.0,
							(color32&0xff) / 255.0)
					# print("reading color @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Color(v.get("r"), v.get("g"), v.get("b"), v.get("a"))
				"Vector2f":
					# print("reading vec2 @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Vector2(v.get("x"), v.get("y"))
				"Vector3f":
					# print("reading vec3 @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Vector3(v.get("x"), v.get("y"), v.get("z"))
				"Rectf":
					# print("reading rect @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Rect2(v.get("x"), v.get("y"), v.get("width"), v.get("height"))
				"Vector4f", "Quaternionf":
					# print("reading quat @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Quaternion(v.get("x"), v.get("y"), v.get("z"), v.get("w"))
				"Matrix3x4f":
					# print("reading matrix @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(v))
					return Transform3D(
						Vector3(v.get("e00"),v.get("e10"),v.get("e20")),
						Vector3(v.get("e01"),v.get("e11"),v.get("e21")),
						Vector3(v.get("e02"),v.get("e12"),v.get("e22")),
						Vector3(v.get("e03"),v.get("e13"),v.get("e23")))
				"GUID":
					return "%08x%08x%08x%08x" % [v.get("data[0]"), v.get("data[1]"), v.get("data[2]"), v.get("data[3]")]
				_:
					#if v.has("propertyPath") and v.has("value"):
					#	v["value"] = parseValue(v.get("value"))
					if v.has("Array"):
						# print("reading array @" + str(x) + " " + self.name + "/" + self.type_name + " " + str(len(v)))
						return v.get("Array")
					if self.type_name == "pair" and self.children[1].type_name == "PPtr<Component>":
						return {"component": v.get("second")}
					if self.type_name.begins_with("PPtr"):
						if v.get("m_PathID", 0) == 0:
							return [null, v.get("m_PathID", 0), null, 0]
						elif v.get("m_FileID", 0) >= len(referenced_guids) or v.get("m_FileID", 0) < 0:
							push_error("Asset " + self.full_name + "/" + self.type_name + " invalid pptr " + str(v) + " @" + str(s.tell()))
						else:
							var ret_ref = [null, v.get("m_PathID", 0), referenced_guids[v.get("m_FileID", 0)], referenced_reftypes[v.get("m_FileID", 0)]]
							if self.name == "prototype" or self.name == "prefab":
								if ret_ref[2] != null:
									#print(" Possible Ref " + str(self.full_name) + " to " + str(ret_ref[2]))
									s.reference_prefab_guid_storage.append(ret_ref[2])
							return ret_ref
			return v
		else:
			var x: int = s.tell()
			var ret: Variant = null
			match self.type_name:
				"signed char", "SInt8":
					ret = s.get_8()
					s.skip(self.size - 1)
				"unsigned char", "char", "UInt8", "bool":
					# We parse bools as integers for consistency with yaml.
					ret = s.get_u8()
					s.skip(self.size - 1)
				#"bool":
				#	ret = s.get_u8() != 0
				#	s.skip(self.size - 1)
				"SInt16", "short":
					ret = s.get_16()
					s.skip(self.size - 2)
				"SInt32", "int", "long":
					ret = s.get_32()
					s.skip(self.size - 4)
				"SInt64", "int64", "long long":
					ret = s.get_64()
					s.skip(self.size - 8)
				"UInt16", "unsigned short":
					ret = s.get_u16()
					s.skip(self.size - 2)
				"UInt32", "unsigned int":
					ret = s.get_u32()
					s.skip(self.size - 4)
				"UInt64", "unsigned long long":
					ret = s.get_u64()
					s.skip(self.size - 8)
				"float":
					ret = s.get_float()
					s.skip(self.size - 4)
				"double":
					ret = s.get_double()
					s.skip(self.size - 8)
				_:
					s.skip(self.size)
			if self.size >= 1:
				s.seek(x + self.size)
			# print("reading @" + ("%x .. %x" % [x, s.tell()]) + " " + self.full_name + "/" + self.type_name + " " + str(ret))
			return ret

	func append(d: Variant) -> void:
		self.children.push_back(d)


var s: Stream = null
var off: int = 0
var table_size: int = 0
var data_end: int = 0
var file_gen: int = 0
var data_offset: int = 0
var version: String = ""
var platform: int = 0
var class_ids: Array = [].duplicate()
var defs: Array = [].duplicate()
var referenced_guids: Array = [].duplicate()
var referenced_reftypes: Array = [].duplicate()
var objs: Array = [].duplicate()

var meta: RefCounted = null

func _init(meta: RefCounted, file_contents: PackedByteArray):
	self.meta = meta
	self.s = Stream.new(file_contents)
	#t = self.s.read_str() # UnityRaw? or no?
	#stream_ver = s.get_32()
	#unity_version = self.s.read_str()
	#unity_revision = self.s.read_str()

	#size = s.get_32()
	#hdr_size = s.get_32()
	#count1 = s.get_32()
	#count2 = s.get_32()
	#ptr = hdr_size
	#self.s.read(count2 * 8)
	#if stream_ver >= 2:
	#	self.s.read(4)
	#if stream_ver >= 3:
	#	data_hdr_size = s.get_32()
	#	ptr += data_hdr_size
	#self.s.seek(ptr)
	#self.s = Stream(self.s.read())

	self.off = self.s.tell() # always 0

	s.big_endian = true
	self.table_size = s.get_u32()
	self.data_end = s.get_u32()
	self.file_gen = s.get_u32()
	self.data_offset = s.get_u32()
	if self.file_gen >= 16 and self.table_size == 0 and self.data_end == 0:
		file_gen += 100
		self.table_size = s.get_u64()
		self.data_end = s.get_u64()
		self.data_offset = s.get_u64()
		self.s.read(4)
	s.big_endian = false
	self.s.read(4)
	self.version = self.s.read_str()
	self.platform = s.get_32()
	self.class_ids = []
	# print("table size " + str(table_size) + " data end " + str(data_end) + " file gen " + str(file_gen) + " data offset " + str(data_offset) + " version " + str(version) + " platform " + str(platform))
	self.defs = self.decode_defs()
	# print(str(defs))
	# print("After defs... NOW AT: " + str(self.s.tell()))
	if self.file_gen < 10:
		s.get_32()
	var obj_headers: Array = self.decode_data_headers()
	# print("After headers... NOW AT: " + str(self.s.tell()))
	# print(str(obj_headers))
	self.decode_guids()
	self.objs = self.decode_data(obj_headers)

func decode_defs() -> Array:
	# File ID 9 (4.3.4f1) does not have this uint8.
	if self.file_gen >= 10:
		var are_defs: bool = s.get_8() != 0
	var count: int = s.get_32()
	if count > 10000:
		push_error("More than 10000 objects in defs: " + str(count) + ". Aborting!")
		count = 0
	var defs: Array = [].duplicate()
	var i: int = 0
	while i < count:
		var def = self.decode_attrtab()
		defs.push_back(def)
		i += 1
		if self.file_gen >= 21: # also 116 ??
			s.get_u32() # zeros
	return defs

#func decode_guids_backwards() -> void:
#	var pos: int = s.tell()
#	s.seek(table_size - 1)
#	while true:
#		# String search
#		while s.get_u8() != 0:
#			s.seek(s.tell() - 2)
#		s.seek(s.tell() - 3 - 16)
#		var guid: String = ""
#		for i in range(16):
#			var guidchr: int = s.get_u8()
#			guid = "%01X%01X" % [guidchr & 15, guidchr >> 4] + guid
#		s.seek(s.tell() - 1 - 16)
#		referenced_reftypes.push_back(s.get_u8())
#		s.seek(s.tell() - 2)

func decode_guids() -> void:
	# 02 00 00 00 01 00 00 00 5B 21 F1 AA FF FF FF FF 02 00 00 00 FA 19 14 BD FF FF FF FF
	var unkcount: int = s.get_32()
	s.skip(12 * unkcount)
	var count: int = s.get_32()
	# print("referenced guids count " + str(count) + " at " + str(s.tell()))
	# null GUID is implied!
	referenced_guids.push_back(null)
	referenced_reftypes.push_back(0)
	var i: int = 0
	while i < count:
		s.get_u8()
		var guid: String = ""
		for i in range(16):
			var guidchr: int = s.get_u8()
			guid += "%01x%01x" % [guidchr & 15, guidchr >> 4]
		referenced_reftypes.push_back(s.get_u32())
		var path: String = s.read_str()
		referenced_guids.push_back(guid)
		i += 1

func decode_data_headers() -> Array:
	var count: int = s.get_u32()
	var obj_headers: Array = [].duplicate()
	if not (count < 1024000):
		push_error("Invalid count " + str(count))
		count = 0
	var i: int = 0
	print(self.class_ids)
	# print("Doing " + str(count) + " data")
	while i < count:
		if self.file_gen >= 10:
			self.s.align(4, self.off)
		var pathId: int = -1
		var size: int = 0
		var off: int = 0
		var type_id: int = 0
		var class_id: int = 0
		var unk: int = 0
		if self.file_gen >= 17:
			# dhdr = self.s.read(20)
			pathId = s.get_u64()
			off = s.get_u32()
			if self.file_gen >= 116:
				var unused0 = s.get_u32()
			size = s.get_u32()
			type_id = s.get_u32()
			class_id = self.class_ids[type_id]
		elif self.file_gen >= 10:
			#dhdr = self.s.read(25)
			pathId = s.get_u64()
			off = s.get_u32()
			size = s.get_u32()
			type_id = s.get_u32()
			class_id = s.get_u16()
			s.get_u16()
			unk = s.get_u8()
		else:
			pathId = s.get_u32()
			off = s.get_u32()
			size = s.get_u32()
			type_id = s.get_u32()
			class_id = s.get_u16()
			s.get_u16()
			var found_idx: int = self.class_ids.find(type_id)
			# print("Finding class " + str(class_id) + " type " + str(type_id) + ": " + str(found_idx))
			if found_idx >= 0:
				type_id = found_idx
		# print("pathid " + str(pathId) + " " + str(type_id) + " " + str(class_id))
		obj_headers.push_back([off + self.data_offset + self.off, class_id, pathId, type_id])
		i += 1
	return obj_headers

func decode_data(obj_headers: Array) -> Array:
	print(str(referenced_guids) + " then " + str(referenced_reftypes))
	for g in referenced_guids:
		meta.dependency_guids[g] = 1
	var save: int = self.s.tell()
	var objs: Array = [].duplicate()
	for obj_header in obj_headers:
		self.s.seek(obj_header[0])
		var class_id: int = obj_header[1]
		var path_id: int = obj_header[2]
		var type_id: int = obj_header[3]
		var read_variant: Variant = self.defs[type_id].read(self.s, referenced_guids, referenced_reftypes)
		var type_name: String = self.defs[type_id].type_name
		var is_stripped: bool = type_name == "EditorExtension"
		if is_stripped:
			type_name = object_adapter.to_classname(class_id)
		var obj: RefCounted = object_adapter.instantiate_unity_object(meta, path_id, class_id, type_name)
		obj.is_stripped = is_stripped
		obj.keys = read_variant
		# m_SourcePrefab (new PrefabInstance) and m_ParentPrefab (legacy Prefab) used in scenes and prefabs.
		# Terrain uses prefab (trees), prototype (details) for prefab references.
		# If there are any other unusual Object->Prefab dependencies, it might be good to list them,
		# but luckily this pattern is pretty rare.
		for var_name in ["m_SourcePrefab", "m_ParentPrefab"]:
			if read_variant.has(var_name):
				var source_prefab_guid: Variant = read_variant.get(var_name)[2]
				#print(" Possible Ref " + str(var_name) + " to " + str(source_prefab_guid))
				if typeof(source_prefab_guid) == TYPE_STRING and source_prefab_guid != "":
					meta.prefab_dependency_guids[source_prefab_guid] = 1
		for source_prefab_guid in self.s.reference_prefab_guid_storage:
			meta.prefab_dependency_guids[source_prefab_guid] = 1
		objs.push_back(obj)
	self.s.seek(save)
	return objs

func lookup_string(stab: PackedByteArray, name_off: int) -> String:
	var stab_limit: int = len(stab) - 1
	if name_off & 0x80000000:
		return baseStrings.get(name_off & 0x7fffffff, str(name_off & 0x7fffffff))
	elif name_off == stab_limit + 1:
		return "" # Cannot index at end of array.
	elif name_off > stab_limit:
		push_error("Indexing past end of stab array " + str(name_off) + " " + str(stab_limit))
		return str(name_off) # Cannot index at end of array.
	else:
		return str(stab.slice(min(stab_limit, name_off), min(stab_limit, name_off + 100) + 1).get_string_from_ascii())

func decode_attrtab() -> Def:
	var code: int = 0
	var unk: int = 0
	var unk2: int = 0
	var ident: PackedByteArray = PackedByteArray()
	var attr_cnt: int = 0
	var table_len: int = 0
	var stab_len: int = 0
	if self.file_gen >= 14:
		# hdr = self.s.read(31)
		code = s.get_u32()
		unk = s.get_u16()
		unk2 = s.get_u8()
		ident = s.read(16)
		if unk2 == 0:
			s.read(16)
		attr_cnt = s.get_u32()
		stab_len = s.get_u32()
	elif self.file_gen >= 10:
		# hdr = self.s.read(28)
		code = s.get_u32()
		ident = s.read(16)
		attr_cnt = s.get_u32()
		stab_len = s.get_u32()
	else:
		code = s.get_u32()
		attr_cnt = 1
	var size_per: int = 24
	if self.file_gen >= 21: # also 114?
		size_per = 32
	var guid: String = ""
	var attrs: PackedByteArray = PackedByteArray()
	var stab: PackedByteArray = PackedByteArray()
	var attrs_spb: Stream = self.s
	if self.file_gen >= 10:
		for i in range(16):
			var guidchr: int = ident[i]
			guid += "%01x%01x" % [guidchr & 15, guidchr >> 4]
		table_len = attr_cnt*size_per
		attrs = self.s.read(table_len)
		stab = self.s.read(stab_len)
		# print("attr code " + str(code) + " attr_cnt " + str(attr_cnt) + " stab_len " + str(stab_len))
		# print("attr code " + str(code) + " unk " + str(unk) + " ident " + str(ident) + " attr_cnt " + str(attr_cnt) + " stab_len " + str(stab_len))
		#var attrs_spb: StreamPeerBuffer = StreamPeerBuffer.new()
		#attrs_spb.data_array = attrs
		attrs_spb = Stream.new(attrs)

	var def: Def = null
	if not (attr_cnt < 16384):
		push_error("Invalid attr_count " + str(attr_cnt))
		attr_cnt = 0
	var i: int = 0
	var size: int = 0
	var idx: int = 0
	var flags: int = 0
	var level: int = 0
	var name: String = ""
	var type_name: String = ""
	var unity4_nesting: Array[int] = [1]
	var a4: int = 0
	var a1: int = 0
	var a2: int = 0
	while i < attr_cnt:
		if self.file_gen >= 10:
			a1 = attrs_spb.get_u8()
			a2 = attrs_spb.get_u8()
			level = attrs_spb.get_u8()
			a4 = attrs_spb.get_u8()
			var type_off: int = attrs_spb.get_u32()
			var name_off: int = attrs_spb.get_u32()
			size = attrs_spb.get_u32()
			idx = attrs_spb.get_u32()
			flags = attrs_spb.get_u32()
			var unk_64b: int = 0
			if self.file_gen >= 21:
				unk_64b = attrs_spb.get_u64()
				if unk_64b != 0:
					# print("Found unknown unk64: " + str(unk_64b) + " code " + str(code) + " unk1/2" + str(unk) + "_" + str(unk2) + " ident " + str(guid) + " flags " + str(flags) + " idx " + str(idx) + " off "+ str(type_off) + " size " + str(size) + " idx " + str(idx) + " name_off " + str(name_off))
					pass
			name = lookup_string(stab, name_off)
			type_name = lookup_string(stab, type_off)
			# print("code " + str(code) + " unk1/2" + str(unk) + "_" + str(unk2) + " ident " + str(guid) + " name " + str(name) + " type_name " + str(type_name) + " flags " + str(flags) + " idx " + str(idx) + " off "+ str(type_off) + " size " + str(size) + " idx " + str(idx) + " name_off " + str(name_off))
		else:
			while unity4_nesting[-1] == 0:
				unity4_nesting.pop_back()
			unity4_nesting[-1] -= 1
			level = len(unity4_nesting) - 1
			type_name = attrs_spb.read_str()
			name = attrs_spb.read_str()
			size = attrs_spb.get_u32()
			idx = attrs_spb.get_u32()
			a4 = attrs_spb.get_u32()
			var unk3: int = attrs_spb.get_u32()
			flags = attrs_spb.get_u32()
			var nested_count: int = attrs_spb.get_u32()
			if nested_count != 0:
				unity4_nesting.push_back(nested_count)
				attr_cnt += nested_count
		if size == 0xffffffff:
			size = -1
		if level > 0 and def == null:
			push_error("Unable to recurse to level " + str(level) + " of null toplevel")
		elif level > 0:
			if not (level < 16):
				push_error("Level is too large: " + str(level) + " of " + str(def.name) + "/" + str(def.type_name))
				level = 1
			var d: Def = def
			for ii in range(level - 1):
				if len(d.children) == 0:
					push_error("Unable to recurse to level " + str(level) + " of " + str(def.name) + "/" + str(def.type_name))
					break
				d = d.children[-1]
			# print("level is " + str(level) + " pushing back a child " + str(name) + "/" + str(type_name) + " into " + str(d.name) + "/" + str(d.type_name))
			var newdef: Def = Def.new(name, type_name, size, flags, a4 != 0, a1)
			newdef.set_parent(d)
			d.append(newdef)
		else:
			if def == null:
				def = Def.new(name, type_name, size, flags, a4 != 0, a1)
			else:
				push_error("Found multiple top-level defs " + str(name) + " type " +  str(type_name) + " into " + str(def.name) + "/" + str(def.type_name))
		var indstr: String = ""
		for lv in range(level):
			indstr += "  "
		print("%2x %2x %2x %20s %8x %8x %2d: %s%s" % [a1, a2, a4, type_name, size, flags, idx, indstr, name])
		i += 1

	if def == null:
		push_error("Failed to find def")
	self.class_ids.append(code)
	return def

#func load_image(fd):
#	d = Asset(fd)
#	texes = [i for i in d.objs if "image data" in i]
#	for tex in texes:
#		data = tex["image data"]
#		if not data and "m_StreamData" in tex and d.fs:
#			sd = tex["m_StreamData"]
#			name = sd["path"].split("/")[-1]
#			data = d.fs.files_by_name[name][sd["offset"]:][:sd["size"]]
#			# print("Streamed")
#		if not data:
#			continue
#		width, height, fmt = tex["m_Width"], tex["m_Height"], tex["m_TextureFormat"]
#		if fmt == 7: # BGR565
#			im = Image.frombytes("RGB", (width, height), data, "raw", "BGR;16")
#		elif fmt == 13: # ABGR4444
#			im = Image.frombytes("RGBA", (width, height), data, "raw", "RGBA;4B")
#			r, g, b, a  = im.split()
#			im = Image.merge("RGBA", (a, b, g, r))
#		else:
#			continue
#		im = im.transpose(Image.FLIP_TOP_BOTTOM)
#		return im
#	else:
#		raise Exception("No supported image formats")
