class_name UnidotMesh extends UnidotObject

const aligned_byte_buffer := preload("../../aligned_byte_buffer.gd")

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

func get_primitive_format(submesh: Dictionary) -> int:
	match submesh.get("topology", 0):
		0:
			return Mesh.PRIMITIVE_TRIANGLES
		2:
			return Mesh.PRIMITIVE_TRIANGLES  # quad meshes handled specially later
		3:
			return Mesh.PRIMITIVE_LINES
		4:
			return Mesh.PRIMITIVE_LINE_STRIP
		5:
			return Mesh.PRIMITIVE_POINTS
		_:
			log_fail(str(self) + ": Unknown primitive format " + str(submesh.get("topology", 0)))
	return Mesh.PRIMITIVE_TRIANGLES

func get_godot_type() -> String:
	return "Mesh"

func get_extra_resources() -> Dictionary:
	if binds.is_empty():
		return {}
	return {-self.fileID: ".skin.tres"}

func dict_to_matrix(b: Dictionary) -> Transform3D:
	return (
		Transform3D.FLIP_X.affine_inverse()
		* Transform3D(
			Vector3(b.get("e00"), b.get("e10"), b.get("e20")),
			Vector3(b.get("e01"), b.get("e11"), b.get("e21")),
			Vector3(b.get("e02"), b.get("e12"), b.get("e22")),
			Vector3(b.get("e03"), b.get("e13"), b.get("e23")),
		)
		* Transform3D.FLIP_X
	)

func get_extra_resource(fileID: int) -> Resource:  #Skin:
	var sk: Skin = Skin.new()
	var idx: int = 0
	for b in binds:
		sk.add_bind(idx, dict_to_matrix(b))
		idx += 1
	return sk

func create_godot_resource() -> Resource:  #ArrayMesh:
	var vertex_buf: RefCounted = get_vertex_data()
	var index_buf: RefCounted = get_index_data()
	var vertex_layout: Dictionary = vertex_layout_info
	var channel_info_array: Array = vertex_layout.get("m_Channels", [])
	# https://docs.unity3d.com/2019.4/Documentation/ScriptReference/Rendering.VertexAttribute.html
	var to_godot_mesh_channels: Array = [ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL, ArrayMesh.ARRAY_TANGENT, ArrayMesh.ARRAY_COLOR, ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2, ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_CUSTOM2, ArrayMesh.ARRAY_CUSTOM3, -1, -1, ArrayMesh.ARRAY_WEIGHTS, ArrayMesh.ARRAY_BONES]
	# Old vertex layout is probably stable since Unidot 5.0
	if vertex_layout.get("serializedVersion", 1) < 2:
		# Old layout seems to have COLOR at the end.
		to_godot_mesh_channels = [ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL, ArrayMesh.ARRAY_TANGENT, ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2, ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_COLOR]

	var tmp: Array = self.pre2018_skin
	var pre2018_weights_buf: PackedFloat32Array = tmp[0]
	var pre2018_bones_buf: PackedInt32Array = tmp[1]
	var surf_idx: int = 0
	var total_vertex_count: int = vertex_layout.get("m_VertexCount", 0)
	var idx_format: int = keys.get("m_IndexFormat", 0)
	var arr_mesh = ArrayMesh.new()
	var stream_strides: Array = [0, 0, 0, 0]
	var stream_offsets: Array = [0, 0, 0, 0]
	if len(to_godot_mesh_channels) != len(channel_info_array):
		log_fail("Unidot has the wrong number of vertex channels: " + str(len(to_godot_mesh_channels)) + " vs " + str(len(channel_info_array)))

	for array_idx in range(len(to_godot_mesh_channels)):
		var channel_info: Dictionary = channel_info_array[array_idx]
		stream_strides[channel_info.get("stream", 0)] += (((channel_info.get("dimension", 4) * aligned_byte_buffer.format_byte_width(channel_info.get("format", 0))) + 3) / 4 * 4)
	for s in range(1, 4):
		stream_offsets[s] = stream_offsets[s - 1] + (total_vertex_count * stream_strides[s - 1] + 15) / 16 * 16

	for submesh in submeshes:
		var surface_arrays: Array = []
		surface_arrays.resize(ArrayMesh.ARRAY_MAX)
		var surface_index_buf: PackedInt32Array
		if idx_format == 0:
			surface_index_buf = index_buf.uint16_subarray(submesh.get("firstByte", 0), submesh.get("indexCount", -1))
		else:
			surface_index_buf = index_buf.uint32_subarray(submesh.get("firstByte", 0), submesh.get("indexCount", -1))
		if submesh.get("topology", 0) == 2:
			# convert quad mesh to tris
			var new_buf: PackedInt32Array = PackedInt32Array()
			new_buf.resize(len(surface_index_buf) / 4 * 6)
			var quad_idx = [0, 1, 2, 2, 1, 3]
			var range_6: Array = [0, 1, 2, 3, 4, 5]
			var i: int = 0
			var ilen: int = len(surface_index_buf) / 4
			while i < ilen:
				for el in range_6:
					new_buf[i * 6 + el] = surface_index_buf[i * 4 + quad_idx[el]]
				i += 1
			surface_index_buf = new_buf
		log_debug("Index count " + str(len(surface_index_buf)) + " from byte " + str(submesh.get("firstByte", 0)) + " count " + str(submesh.get("indexCount", -1)))
		var deltaVertex: int = submesh.get("firstVertex", 0)
		var baseFirstVertex: int = submesh.get("baseVertex", 0) + deltaVertex
		var vertexCount: int = submesh.get("vertexCount", 0)
		log_debug("baseFirstVertex " + str(baseFirstVertex) + " baseVertex " + str(submesh.get("baseVertex", 0)) + " deltaVertex " + str(deltaVertex) + " index0 " + str(surface_index_buf[0]))
		if deltaVertex != 0:
			var i: int = 0
			var ilen: int = len(surface_index_buf)
			while i < ilen:
				surface_index_buf[i] -= deltaVertex
				i += 1
		if not pre2018_weights_buf.is_empty():
			surface_arrays[ArrayMesh.ARRAY_WEIGHTS] = pre2018_weights_buf.slice(baseFirstVertex * 4, (vertexCount + baseFirstVertex) * 4)
			surface_arrays[ArrayMesh.ARRAY_BONES] = pre2018_bones_buf.slice(baseFirstVertex * 4, (vertexCount + baseFirstVertex) * 4)
		var compress_flags: int = 0
		for array_idx in range(len(to_godot_mesh_channels)):
			var godot_array_type = to_godot_mesh_channels[array_idx]
			if godot_array_type == -1:
				continue
			var channel_info: Dictionary = channel_info_array[array_idx]
			var stream: int = channel_info.get("stream", 0)
			var offset: int = channel_info.get("offset", 0) + stream_offsets[stream] + baseFirstVertex * stream_strides[stream]
			var format: int = channel_info.get("format", 0)
			var dimension: int = channel_info.get("dimension", 4)
			if dimension <= 0:
				continue
			match godot_array_type:
				ArrayMesh.ARRAY_BONES:
					if dimension == 8:
						compress_flags |= ArrayMesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
					log_debug("Do bones int")
					surface_arrays[godot_array_type] = vertex_buf.formatted_int_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
				ArrayMesh.ARRAY_WEIGHTS:
					log_debug("Do weights int")
					surface_arrays[godot_array_type] = vertex_buf.formatted_float_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
				ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL:
					log_debug("Do vertex or normal vec3 " + str(godot_array_type) + " " + str(format))
					surface_arrays[godot_array_type] = vertex_buf.formatted_vector3_subarray(Vector3(-1, 1, 1), format, offset, vertexCount, stream_strides[stream], dimension)
				ArrayMesh.ARRAY_TANGENT:
					log_debug("Do tangent float " + str(godot_array_type) + " " + str(format))
					surface_arrays[godot_array_type] = vertex_buf.formatted_tangent_subarray(format, offset, vertexCount, stream_strides[stream], dimension)
				ArrayMesh.ARRAY_COLOR:
					log_debug("Do color " + str(godot_array_type) + " " + str(format))
					surface_arrays[godot_array_type] = vertex_buf.formatted_color_subarray(format, offset, vertexCount, stream_strides[stream], dimension)
				ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2:
					log_debug("Do uv " + str(godot_array_type) + " " + str(format))
					log_debug("Offset " + str(offset) + " = " + str(channel_info.get("offset", 0)) + "," + str(stream_offsets[stream]) + "," + str(baseFirstVertex) + "," + str(stream_strides[stream]) + "," + str(dimension))
					surface_arrays[godot_array_type] = vertex_buf.formatted_vector2_subarray(format, offset, vertexCount, stream_strides[stream], dimension, true)
					log_debug("triangle 0: " + str(surface_arrays[godot_array_type][surface_index_buf[0]]) + ";" + str(surface_arrays[godot_array_type][surface_index_buf[1]]) + ";" + str(surface_arrays[godot_array_type][surface_index_buf[2]]))
				ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_CUSTOM2, ArrayMesh.ARRAY_CUSTOM3:
					pass  # Custom channels are currently broken in Godot master:
				ArrayMesh.ARRAY_MAX:  # ARRAY_MAX is a placeholder to disable this
					log_debug("Do custom " + str(godot_array_type) + " " + str(format))
					var custom_shift = ((ArrayMesh.ARRAY_FORMAT_CUSTOM1_SHIFT - ArrayMesh.ARRAY_FORMAT_CUSTOM0_SHIFT) * (godot_array_type - ArrayMesh.ARRAY_CUSTOM0)) + ArrayMesh.ARRAY_FORMAT_CUSTOM0_SHIFT
					if format == FORMAT_UNORM8 or format == FORMAT_SNORM8:
						# assert(dimension == 4) # Unidot docs says always word aligned, so I think this means it is guaranteed to be 4.
						surface_arrays[godot_array_type] = vertex_buf.formatted_uint8_subarray(format, offset, 4 * vertexCount, stream_strides[stream], 4)
						compress_flags |= ((ArrayMesh.ARRAY_CUSTOM_RGBA8_UNORM if format == FORMAT_UNORM8 else ArrayMesh.ARRAY_CUSTOM_RGBA8_SNORM) << custom_shift)
					elif format == FORMAT_FLOAT16:
						assert(dimension == 2 or dimension == 4)  # Unidot docs says always word aligned, so I think this means it is guaranteed to be 2 or 4.
						surface_arrays[godot_array_type] = vertex_buf.formatted_uint8_subarray(format, offset, dimension * vertexCount * 2, stream_strides[stream], dimension * 2)
						compress_flags |= ((ArrayMesh.ARRAY_CUSTOM_RG_HALF if dimension == 2 else ArrayMesh.ARRAY_CUSTOM_RGBA_HALF) << custom_shift)
						# We could try to convert SNORM16 and UNORM16 to float16 but that sounds confusing and complicated.
					else:
						assert(dimension <= 4)
						surface_arrays[godot_array_type] = vertex_buf.formatted_float_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
						compress_flags |= (ArrayMesh.ARRAY_CUSTOM_R_FLOAT + (dimension - 1)) << custom_shift
		#firstVertex: 1302
		#vertexCount: 38371
		surface_arrays[ArrayMesh.ARRAY_INDEX] = surface_index_buf
		var primitive_format: int = get_primitive_format(submesh)
		#var f= FileAccess.open("temp.temp", FileAccess.WRITE)
		#f.store_string(str(surface_arrays))
		#f.flush()
		#f = null
		for i in range(ArrayMesh.ARRAY_MAX):
			log_debug("Array " + str(i) + ": length=" + (str(len(surface_arrays[i])) if typeof(surface_arrays[i]) != TYPE_NIL else "NULL"))
		log_debug("here are some flags " + str(compress_flags))
		arr_mesh.add_surface_from_arrays(primitive_format, surface_arrays, [], {}, compress_flags)
	# arr_mesh.set_custom_aabb(local_aabb)
	arr_mesh.resource_name = self.name
	return arr_mesh

var local_aabb: AABB:
	get:
		log_debug(str(typeof(keys.get("m_LocalAABB", {}).get("m_Center"))) + "/" + str(keys.get("m_LocalAABB", {}).get("m_Center")))
		return AABB(keys.get("m_LocalAABB", {}).get("m_Center") * Vector3(-1, 1, 1), keys.get("m_LocalAABB", {}).get("m_Extent"))

var pre2018_skin: Array:
	get:
		var skin_vertices = keys.get("m_Skin", [])
		var ret = [PackedFloat32Array(), PackedInt32Array()]
		# FIXME: Godot bug with F32Array. ret[0].resize(len(skin_vertices) * 4)
		ret[1].resize(len(skin_vertices) * 4)
		var i = 0
		for vert in skin_vertices:
			ret[0].push_back(vert.get("weight[0]"))
			ret[0].push_back(vert.get("weight[1]"))
			ret[0].push_back(vert.get("weight[2]"))
			ret[0].push_back(vert.get("weight[3]"))
			#ret[0][i] = vert.get("weight[0]")
			#ret[0][i + 1] = vert.get("weight[1]")
			#ret[0][i + 2] = vert.get("weight[2]")
			#ret[0][i + 3] = vert.get("weight[3]")
			ret[1][i] = vert.get("boneIndex[0]")
			ret[1][i + 1] = vert.get("boneIndex[1]")
			ret[1][i + 2] = vert.get("boneIndex[2]")
			ret[1][i + 3] = vert.get("boneIndex[3]")
			i += 4
		return ret

var submeshes: Array:
	get:
		return keys.get("m_SubMeshes", [])

var binds: Array:
	get:
		return keys.get("m_BindPose", [])

var vertex_layout_info: Dictionary:
	get:
		return keys.get("m_VertexData", {})

func get_godot_extension() -> String:
	return ".mesh"

func get_vertex_data() -> RefCounted:
	return aligned_byte_buffer.new(keys.get("m_VertexData", ""))

func get_index_data() -> RefCounted:
	return aligned_byte_buffer.new(keys.get("m_IndexBuffer", ""))
