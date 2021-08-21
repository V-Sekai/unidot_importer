@tool
extends RefCounted

const aligned_byte_buffer: GDScript = preload("./aligned_byte_buffer.gd")

const STRING_KEYS: Dictionary = {
	"value": 1,
	"m_Name": 1,
	"m_TagString": 1,
	"name": 1,
	"first": 1,
	"propertyPath": 1,
	"path": 1,
	"attribute": 1,
	"m_ShaderKeywords": 1,
	"typelessdata": 1, # Mesh m_VertexData; Texture image data
	"m_IndexBuffer": 1,
	"Hash": 1,
}

func to_classname(utype: int) -> String:
	var ret = utype_to_classname.get(utype, "")
	if ret == "":
		return "[UnknownType:" + str(utype) + "]"
	return ret


func to_utype(classname: String) -> int:
	return classname_to_utype.get(classname, 0)


func instantiate_unity_object(meta: Object, fileID: int, utype: int, type: String) -> UnityObject:
	var ret: UnityObject = null
	var actual_type = type
	if utype != 0 and utype_to_classname.has(utype):
		actual_type = utype_to_classname[utype]
		if actual_type != type and (type != "Behaviour" or actual_type != "FlareLayer") and (type != "Prefab" or actual_type != "PrefabInstance"):
			push_error("Mismatched type for " + meta.guid + ":" + str(fileID) + " type:" + type + " vs. utype:" + str(utype) + ":" + actual_type)
	if _type_dictionary.has(actual_type):
		# print("Will instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		ret = _type_dictionary[actual_type].new()
	else:
		push_error("Failed to instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		if type.ends_with("Importer"):
			ret = UnityAssetImporter.new()
		else:
			ret = UnityObject.new()
	ret.meta = meta
	ret.adapter = self
	ret.fileID = fileID
	if utype != 0 and utype != classname_to_utype.get(actual_type, utype):
		push_error("Mismatched utype " + str(utype) + " for " + type)
	ret.utype = classname_to_utype.get(actual_type, utype)
	ret.type = actual_type
	return ret


func instantiate_unity_object_from_utype(meta: Object, fileID: int, utype: int) -> UnityObject:
	var ret: UnityObject = null
	if not utype_to_classname.has(utype):
		push_error("Unknown utype " + str(utype) + " for " + str(fileID))
		return
	var actual_type: String = utype_to_classname[utype]
	if _type_dictionary.has(actual_type):
		ret = _type_dictionary[actual_type].new()
	else:
		push_error("Failed to instantiate object of type " + str(actual_type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		ret = UnityObject.new()
	ret.meta = meta
	ret.adapter = self
	ret.fileID = fileID
	ret.utype = classname_to_utype.get(actual_type, utype)
	ret.type = actual_type
	return ret


# Unity types follow:
### ================ BASE OBJECT TYPE ================
class UnityObject extends RefCounted:
	var meta: Resource = null # AssetMeta instance
	var keys: Dictionary = {}
	var fileID: int = 0 # Not set in .meta files
	var type: String = ""
	var utype: int = 0 # Not set in .meta files
	var _cache_uniq_key: String = ""
	var adapter: RefCounted = null # RefCounted to containing scope.

	const FLIP_X: Transform3D = Transform3D.FLIP_X # Transform3D(-1,0,0,0,1,0,0,0,1,0,0,0)
	const BAS_FLIP_X: Basis = Basis.FLIP_X # Basis(-1,0,0,1,0,0,1,0,0)

	# Some components or game objects within a prefab are "stripped" dummy objects.
	# Setting the stripped flag is not required...
	# and properties of prefabbed objects seem to have no effect anyway.
	var is_stripped: bool = false

	func is_stripped_or_prefab_instance() -> bool:
		return is_stripped or is_non_stripped_prefab_reference

	var uniq_key: String:
		get:
			if _cache_uniq_key.is_empty():
				_cache_uniq_key = str(utype)+":"+str(keys.get("m_Name",""))+":"+str(meta.guid) + ":" + str(fileID)
			return _cache_uniq_key

	func _to_string() -> String:
		#return "[" + str(type) + " @" + str(fileID) + ": " + str(len(keys)) + "]" # str(keys) + "]"
		#return "[" + str(type) + " @" + str(fileID) + ": " + JSON.print(keys) + "]"
		return "[" + str(type) + " " + uniq_key + "]"

	var name: String:
		get:
			return get_name()

	func get_name() -> String:
		return str(keys.get("m_Name","NO_NAME:"+uniq_key))

	var toplevel: bool:
		get:
			return is_toplevel()

	func is_toplevel() -> bool:
		return true

	func is_collider() -> bool:
		return false

	var transform: Object:
		get:
			return get_transform()

	func get_transform() -> Object:
		return null

	var gameObject: UnityGameObject:
		get:
			return get_gameObject()

	func get_gameObject() -> UnityGameObject:
		return null

	# Belongs in UnityComponent, but we haven't implemented all types yet.
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var new_node: Node = Node.new()
		new_node.name = type
		assign_object_meta(new_node)
		state.add_child(new_node, new_parent, self)
		return new_node

	func get_extra_resources() -> Dictionary:
		return {}

	func create_extra_resource(fileID: int) -> Resource:
		return null

	func create_godot_resource() -> Resource:
		return null

	func get_godot_extension() -> String:
		return ".res"

	func assign_object_meta(ret: Object) -> void:
		if ret != null:
			ret.set_meta("unidot_keys", self.keys)

	func configure_skeleton_bone(skel: Skeleton3D, bone_name: String):
		configure_skeleton_bone_props(skel, bone_name, self.keys)

	func configure_skeleton_bone_props(skel: Skeleton3D, bone_name: String, uprops: Dictionary):
		var props = self.convert_skeleton_properties(skel, bone_name, uprops)
		if props.has(bone_name):
			skel.set_bone_rest(skel.find_bone(bone_name), props.get(bone_name))

	func convert_skeleton_properties(skel: Skeleton3D, bone_name: String, uprops: Dictionary):
		var props: Dictionary = self.convert_properties(skel, uprops)
		var matn: Transform3D = skel.get_bone_rest(skel.find_bone(bone_name))
		var quat: Quaternion = matn.basis.get_rotation_quaternion()
		var scale: Vector3 = matn.basis.get_scale()
		var position: Vector3 = matn.origin

		var has_trs: bool = false
		if (props.has("_quaternion")):
			has_trs = true
			quat = props.get("_quaternion")
		elif props.has("rotation_degrees"):
			has_trs = true
			quat = Quaternion(props.get("rotation_degrees") * PI / 180.0)
		if (props.has("scale")):
			has_trs = true
			scale = props.get("scale")
		if (props.has("position")):
			has_trs = true
			position = props.get("position")

		if not has_trs:
			return props

		# FIXME: Don't we need to flip these???
		#quat = (BAS_FLIP_X.inverse() * Basis(quat) * BAS_FLIP_X).get_rotation_quat()
		#position = Vector3(-1, 1, 1) * position

		matn = Transform3D(Basis(quat).scaled(scale), position)

		props[bone_name] = matn
		return props

	func configure_node(node: Node):
		if node == null:
			return
		var props: Dictionary = self.convert_properties(node, self.keys)
		apply_node_props(node, props)

	func apply_node_props(node: Node, props: Dictionary):
		if node is MeshInstance3D:
			self.apply_mesh_renderer_props(meta, node, props)
		print(str(node.name) + ": " + str(props))
		# var has_transform_track: bool = false
		# var transform_position: Vector3 = Vector3()
		# var transform_rotation: Quaternion = Quaternion()
		# var transform_position: Vector3 = Vector3()
		if (props.has("_quaternion")):
			node.transform.basis = Basis.IDENTITY.scaled(node.scale) * Basis(props.get("_quaternion"))

		var has_position_x: bool = props.has("position:x")
		var has_position_y: bool = props.has("position:y")
		var has_position_z: bool = props.has("position:z")
		if has_position_x or has_position_y or has_position_z:
			var per_axis_position: Vector3 = node.position
			if has_position_x:
				per_axis_position.x = props.get("position:x")
			if has_position_y:
				per_axis_position.y = props.get("position:y")
			if has_position_z:
				per_axis_position.z = props.get("position:z")
			node.position = per_axis_position
		var has_scale_x: bool = props.has("scale:x")
		var has_scale_y: bool = props.has("scale:y")
		var has_scale_z: bool = props.has("scale:z")
		if has_scale_x or has_scale_y or has_scale_z:
			var per_axis_scale: Vector3 = node.scale
			if has_scale_x:
				per_axis_scale.x = props.get("scale:x")
			if has_scale_y:
				per_axis_scale.y = props.get("scale:y")
			if has_scale_z:
				per_axis_scale.z = props.get("scale:z")
			node.scale = per_axis_scale
		for propname in props:
			if typeof(props.get(propname)) == TYPE_NIL:
				continue
			elif str(propname) == "_quaternion": # .begins_with("_"):
				pass
			elif str(propname).ends_with(":x") or str(propname).ends_with(":y") or str(propname).ends_with(":z"):
				pass
			elif str(propname) == "name":
				pass # We cannot do Name here because it will break existing NodePath of outer prefab to children.
			else:
				print("SET " + str(node.name) + ":" + propname + " to " + str(props[propname]))
				node.set(propname, props.get(propname))

	func apply_mesh_renderer_props(meta: RefCounted, node: MeshInstance3D, props: Dictionary):
		const material_prefix: String = ":UNIDOT_PROXY:"
		print("Apply mesh renderer props: " + str(props) + " / " + str(node.mesh))
		var truncated_mat_prefix: String = meta.get_database().truncated_material_reference.resource_name
		var null_mat_prefix: String = meta.get_database().null_material_reference.resource_name
		var last_material: Object = null
		var old_surface_count: int = 0
		if node.mesh == null or node.mesh.get_surface_count() == 0:
			last_material = node.get_material_override()
			if last_material != null:
				old_surface_count = 1
		else:
			old_surface_count = node.mesh.get_surface_count()
			last_material = node.get_active_material(old_surface_count - 1)

		while last_material != null and last_material.resource_name.begins_with(truncated_mat_prefix):
			old_surface_count -= 1
			if old_surface_count == 0:
				last_material = null
				break
			last_material = node.get_active_material(old_surface_count - 1)

		var last_extra_material: Resource = last_material
		var current_materials: Array = [].duplicate()

		var prefix: String = material_prefix + str(old_surface_count - 1) + ":"
		var new_prefix: String = prefix

		var material_idx: int = 0
		while material_idx < old_surface_count:
			var mat: Resource = node.get_active_material(material_idx)
			if mat != null and str(mat.resource_name).begins_with(prefix):
				break
			current_materials.push_back(mat)
			material_idx += 1

		while last_extra_material != null and (str(last_extra_material.resource_name).begins_with(prefix) or str(last_extra_material.resource_name).begins_with(new_prefix)):
			if str(last_extra_material.resource_name).begins_with(new_prefix):
				prefix = new_prefix
				var guid_fileid = str(last_extra_material.resource_name).substr(len(prefix)).split(":")
				current_materials.push_back(meta.get_godot_resource([null, guid_fileid[1].to_int(), guid_fileid[0], null]))
				material_idx += 1
				new_prefix = material_prefix + str(material_idx) + ":"
			#material_idx_to_extra_material[material_idx] = last_extra_material
			last_extra_material = last_extra_material.next_pass
		if material_idx == old_surface_count - 1:
			assert(last_extra_material != null)
			current_materials.push_back(last_extra_material)
			material_idx += 1

		var new_materials_size = props.get("_materials_size", material_idx)

		if props.has("_mesh"):
			node.mesh = props.get("_mesh")
			node.material_override = null

		current_materials.resize(new_materials_size)
		for i in range(new_materials_size):
			current_materials[i] = props.get("_materials/" + str(i), current_materials[i])

		var new_surface_count: int = 0 if node.mesh == null else node.mesh.get_surface_count()
		if new_surface_count != 0 and node.mesh != null:
			if new_materials_size < new_surface_count:
				for i in range(new_materials_size, new_surface_count):
					node.set_surface_override_material(i, meta.get_database().truncated_material_reference)
			for i in range(new_materials_size):
				node.set_surface_override_material(i, current_materials[i])

		# surface_get_material
		#for i in range(new_surface_count)
		#	for i in range():
		#		node.material_override
		#else:
		#	if new_materials_size < new_surface_count:

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		return convert_properties_component(node, uprops)

	func convert_properties_component(node: Node, uprops: Dictionary) -> Dictionary:
		return {}

	static func get_ref(uprops: Dictionary, key: String) -> Array:
		var ref: Variant = uprops.get(key, null)
		if typeof(ref) == TYPE_ARRAY:
			return ref
		return [null,0,"",0]

	static func get_vector(uprops: Dictionary, key: String) -> Variant:
		if uprops.has(key):
			return uprops.get(key)
		print("key is " + str(key) + "; " + str(uprops))
		if uprops.has(key + ".x") or uprops.has(key + ".y") or uprops.has(key + ".z"):
			var xreturn: Vector3 = Vector3(
				uprops.get(key + ".x", 0.0),
				uprops.get(key + ".y", 0.0),
				uprops.get(key + ".z", 0.0))
			print("xreturn is " + str(xreturn))
			return xreturn
		return null

	static func get_quat(uprops: Dictionary, key: String) -> Variant:
		if uprops.has(key):
			return uprops.get(key)
		if uprops.has(key + ".x") and uprops.has(key + ".y") and uprops.has(key + ".z") and uprops.has(key + ".w"):
			return Quaternion(
				uprops.get(key + ".x", 0.0),
				uprops.get(key + ".y", 0.0),
				uprops.get(key + ".z", 0.0),
				uprops.get(key + ".w", 1.0))
		return null


	# Prefab source properties: Component and GameObject sub-types only:
	# UNITY 2018+:
	#  m_CorrespondingSourceObject: {fileID: 100176, guid: ca6da198c98777940835205234d6323d, type: 3}
	#  m_PrefabInstance: {fileID: 2493014228082835901}
	#  m_PrefabAsset: {fileID: 0}
	# (m_PrefabAsset is always(?) 0 no matter what. I guess we can ignore it?

	# UNITY 2017-:
	#  m_PrefabParentObject: {fileID: 4504365477183010, guid: 52b062a91263c0844b7557d84ca92dbd, type: 2}
	#  m_PrefabInternal: {fileID: 15226381}
	var prefab_source_object: Array:
		get:
			# new: m_CorrespondingSourceObject; old: m_PrefabParentObject
			return keys.get("m_CorrespondingSourceObject", keys.get("m_PrefabParentObject", [null, 0, "", 0]))

	var prefab_instance: Array:
		get:
			# new: m_PrefabInstance; old: m_PrefabInternal
			return keys.get("m_PrefabInstance", keys.get("m_PrefabInternal", [null, 0, "", 0]))

	var is_non_stripped_prefab_reference: bool:
		get:
			# Might be some 5.6 content. See arktoon Shaders/ExampleScene.unity
			# non-stripped prefab references are allowed to override properties.
			return not is_stripped and not (prefab_source_object[1] == 0 or prefab_instance[1] == 0)
	
	var is_prefab_reference: bool:
		get:
			if not is_stripped:
				#if not (prefab_source_object[1] == 0 or prefab_instance[1] == 0):
				#	print(str(self.uniq_key) + " WITHIN " + str(self.meta.guid) + " / " + str(self.meta.path) + " keys:" + str(self.keys))
				pass #assert (prefab_source_object[1] == 0 or prefab_instance[1] == 0)
			else:
				# Might have source object=0 if the object is a dummy / broken prefab?
				pass # assert (prefab_source_object[1] != 0 and prefab_instance[1] != 0)
			return (prefab_source_object[1] != 0 and prefab_instance[1] != 0)


### ================ ASSET TYPES ================
# FIXME: All of these are native Godot types. I'm not sure if these types are needed or warranted.
class UnityMesh extends UnityObject:
	const FLIP_X: Transform3D = Transform3D.FLIP_X # Transform3D(-1,0,0,0,1,0,0,0,1,0,0,0)
	
	func get_primitive_format(submesh: Dictionary) -> int:
		match submesh.get("topology", 0):
			0:
				return Mesh.PRIMITIVE_TRIANGLES
			1:
				return Mesh.PRIMITIVE_TRIANGLES # quad meshes handled specially later
			2:
				return Mesh.PRIMITIVE_LINES
			3:
				return Mesh.PRIMITIVE_LINE_STRIP
			4:
				return Mesh.PRIMITIVE_POINTS
			_:
				push_error(str(self) + ": Unknown primitive format " + str(submesh.get("topology", 0)))
		return Mesh.PRIMITIVE_TRIANGLES

	func get_extra_resources() -> Dictionary:
		if binds.is_empty():
			return {}
		return {-meta.main_object_id: ".mesh.skin.tres"}

	func dict_to_matrix(b: Dictionary) -> Transform3D:
		return FLIP_X.affine_inverse() * Transform3D(
			Vector3(b.get("e00"), b.get("e10"), b.get("e20")),
			Vector3(b.get("e01"), b.get("e11"), b.get("e21")),
			Vector3(b.get("e02"), b.get("e12"), b.get("e22")),
			Vector3(b.get("e03"), b.get("e13"), b.get("e23")),
		) * FLIP_X

	func create_extra_resource(fileID: int) -> Skin:
		var sk: Skin = Skin.new()
		var idx: int = 0
		for b in binds:
			sk.add_bind(idx, dict_to_matrix(b))
			idx += 1
		return sk

	func create_godot_resource() -> ArrayMesh:
		var vertex_buf: RefCounted = get_vertex_data()
		var index_buf: RefCounted = get_index_data()
		var vertex_layout: Dictionary = vertex_layout_info
		var channel_info_array: Array = vertex_layout.get("m_Channels", [])
		# https://docs.unity3d.com/2019.4/Documentation/ScriptReference/Rendering.VertexAttribute.html
		var unity_to_godot_mesh_channels: Array = [ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL, ArrayMesh.ARRAY_TANGENT, ArrayMesh.ARRAY_COLOR, ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2, ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_CUSTOM2, ArrayMesh.ARRAY_CUSTOM3, -1, -1, ArrayMesh.ARRAY_WEIGHTS, ArrayMesh.ARRAY_BONES]
		# Old vertex layout is probably stable since Unity 5.0
		if vertex_layout.get("serializedVersion", 1) < 2:
			# Old layout seems to have COLOR at the end.
			unity_to_godot_mesh_channels = [ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL, ArrayMesh.ARRAY_TANGENT, ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2, ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_COLOR]

		var tmp: Array = self.pre2018_skin
		var pre2018_weights_buf: PackedFloat32Array = tmp[0]
		var pre2018_bones_buf: PackedInt32Array = tmp[1]
		var surf_idx: int = 0
		var total_vertex_count: int = vertex_layout.get("m_VertexCount", 0)
		var idx_format: int = keys.get("m_IndexFormat", 0)
		var arr_mesh = ArrayMesh.new()
		var stream_strides: Array = [0, 0, 0, 0]
		var stream_offsets: Array = [0, 0, 0, 0]
		if len(unity_to_godot_mesh_channels) != len(channel_info_array):
			push_error("Unity has the wrong number of vertex channels: " + str(len(unity_to_godot_mesh_channels)) + " vs " + str(len(channel_info_array)))

		for array_idx in range(len(unity_to_godot_mesh_channels)):
			var channel_info: Dictionary = channel_info_array[array_idx]
			stream_strides[channel_info.get("stream", 0)] += (channel_info.get("dimension", 4) * aligned_byte_buffer.format_byte_width(channel_info.get("format", 0)) + 3) / 4 * 4
		for s in range(1, 4):
			stream_offsets[s] = stream_offsets[s - 1] + (total_vertex_count * stream_strides[s - 1] + 15) / 16 * 16

		for submesh in submeshes:
			var surface_arrays: Array = []
			surface_arrays.resize(ArrayMesh.ARRAY_MAX)
			var surface_index_buf: PackedInt32Array
			if idx_format == 0:
				surface_index_buf = index_buf.uint16_subarray(submesh.get("firstByte",0), submesh.get("indexCount",-1))
			else:
				surface_index_buf = index_buf.uint32_subarray(submesh.get("firstByte",0), submesh.get("indexCount",-1))
			if submesh.get("topology", 0) == 1:
				# convert quad mesh to tris
				var new_buf: PackedInt32Array = PackedInt32Array()
				new_buf.resize(len(surface_index_buf) / 4 * 6)
				var quad_idx = [0, 1, 2, 2, 1, 3]
				var range_6: Array = [0, 1, 2, 3, 4, 5]
				var i: int = 0
				var ilen: int = (len(surface_index_buf) / 4)
				while i < ilen:
					for el in range_6:
						new_buf[i * 6 + el] = surface_index_buf[i * 4 + quad_idx[el]]
					i += 1
				surface_index_buf = new_buf
			var deltaVertex: int = submesh.get("firstVertex", 0)
			var baseFirstVertex: int = submesh.get("baseVertex", 0) + deltaVertex
			var vertexCount: int = submesh.get("vertexCount", 0)
			print("baseFirstVertex "+ str(baseFirstVertex)+ " baseVertex "+ str(submesh.get("baseVertex", 0)) + " deltaVertex " + str(deltaVertex) + " index0 " + str(surface_index_buf[0]))
			if deltaVertex != 0:
				var i: int = 0
				var ilen: int = (len(surface_index_buf))
				while i < ilen:
					surface_index_buf[i] -= deltaVertex
					i += 1
			if not pre2018_weights_buf.is_empty():
				surface_arrays[ArrayMesh.ARRAY_WEIGHTS] = pre2018_weights_buf.subarray(baseFirstVertex * 4, (vertexCount + baseFirstVertex) * 4 - 1) # INCLUSIVE!!!
				surface_arrays[ArrayMesh.ARRAY_BONES] = pre2018_bones_buf.subarray(baseFirstVertex * 4, (vertexCount + baseFirstVertex) * 4 - 1) # INCLUSIVE!!!
			var compress_flags: int = 0
			for array_idx in range(len(unity_to_godot_mesh_channels)):
				var godot_array_type = unity_to_godot_mesh_channels[array_idx]
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
						print("Do bones int")
						surface_arrays[godot_array_type] = vertex_buf.formatted_int_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
					ArrayMesh.ARRAY_WEIGHTS:
						print("Do weights int")
						surface_arrays[godot_array_type] = vertex_buf.formatted_float_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
					ArrayMesh.ARRAY_VERTEX, ArrayMesh.ARRAY_NORMAL:
						print("Do vertex or normal vec3 " + str(godot_array_type) + " " + str(format))
						surface_arrays[godot_array_type] = vertex_buf.formatted_vector3_subarray(Vector3(-1,1,1), format, offset, vertexCount, stream_strides[stream], dimension)
					ArrayMesh.ARRAY_TANGENT:
						print("Do tangent float " + str(godot_array_type) + " " + str(format))
						surface_arrays[godot_array_type] = vertex_buf.formatted_tangent_subarray(format, offset, vertexCount, stream_strides[stream], dimension)
					ArrayMesh.ARRAY_COLOR:
						print("Do color " + str(godot_array_type) + " " + str(format))
						surface_arrays[godot_array_type] = vertex_buf.formatted_color_subarray(format, offset, vertexCount, stream_strides[stream], dimension)
					ArrayMesh.ARRAY_TEX_UV, ArrayMesh.ARRAY_TEX_UV2:
						print("Do uv " + str(godot_array_type) + " " + str(format))
						print("Offset " + str(offset) + " = " + str(channel_info.get("offset", 0)) + "," + str(stream_offsets[stream]) + "," + str(baseFirstVertex) + "," + str(stream_strides[stream]) + "," + str(dimension))
						surface_arrays[godot_array_type] = vertex_buf.formatted_vector2_subarray(format, offset, vertexCount, stream_strides[stream], dimension, true)
						print("triangle 0: " + str(surface_arrays[godot_array_type][surface_index_buf[0]]) + ";" + str(surface_arrays[godot_array_type][surface_index_buf[1]]) + ";" + str(surface_arrays[godot_array_type][surface_index_buf[2]]))
					ArrayMesh.ARRAY_CUSTOM0, ArrayMesh.ARRAY_CUSTOM1, ArrayMesh.ARRAY_CUSTOM2, ArrayMesh.ARRAY_CUSTOM3:
						pass # Custom channels are currently broken in Godot master:
					ArrayMesh.ARRAY_MAX: # ARRAY_MAX is a placeholder to disable this
						print("Do custom " + str(godot_array_type) + " " + str(format))
						var custom_shift = (ArrayMesh.ARRAY_FORMAT_CUSTOM1_SHIFT - ArrayMesh.ARRAY_FORMAT_CUSTOM0_SHIFT) * (godot_array_type - ArrayMesh.ARRAY_CUSTOM0) + ArrayMesh.ARRAY_FORMAT_CUSTOM0_SHIFT
						if format == aligned_byte_buffer.FORMAT_UNORM8 or format == aligned_byte_buffer.FORMAT_SNORM8:
							# assert(dimension == 4) # Unity docs says always word aligned, so I think this means it is guaranteed to be 4.
							surface_arrays[godot_array_type] = vertex_buf.formatted_uint8_subarray(format, offset, 4 * vertexCount, stream_strides[stream], 4)
							compress_flags |= (ArrayMesh.ARRAY_CUSTOM_RGBA8_UNORM if format == aligned_byte_buffer.FORMAT_UNORM8 else ArrayMesh.ARRAY_CUSTOM_RGBA8_SNORM) << custom_shift
						elif format == aligned_byte_buffer.FORMAT_FLOAT16:
							assert(dimension == 2 or dimension == 4) # Unity docs says always word aligned, so I think this means it is guaranteed to be 2 or 4.
							surface_arrays[godot_array_type] = vertex_buf.formatted_uint8_subarray(format, offset, dimension * vertexCount * 2, stream_strides[stream], dimension * 2)
							compress_flags |= (ArrayMesh.ARRAY_CUSTOM_RG_HALF if dimension == 2 else ArrayMesh.ARRAY_CUSTOM_RGBA_HALF) << custom_shift
							# We could try to convert SNORM16 and UNORM16 to float16 but that sounds confusing and complicated.
						else:
							assert(dimension <= 4)
							surface_arrays[godot_array_type] = vertex_buf.formatted_float_subarray(format, offset, dimension * vertexCount, stream_strides[stream], dimension)
							compress_flags |= (ArrayMesh.ARRAY_CUSTOM_R_FLOAT + (dimension - 1)) << custom_shift
			#firstVertex: 1302
			#vertexCount: 38371
			surface_arrays[ArrayMesh.ARRAY_INDEX] = surface_index_buf
			var primitive_format: int = get_primitive_format(submesh)
			#var f= File.new()
			#f.open("temp.temp", File.WRITE)
			#f.store_string(str(surface_arrays))
			#f.close()
			for i in range(ArrayMesh.ARRAY_MAX):
				print("Array " + str(i) + ": length=" + (str(len(surface_arrays[i])) if typeof(surface_arrays[i]) != TYPE_NIL else "NULL"))
			print("here are some flags " + str(compress_flags))
			arr_mesh.add_surface_from_arrays(primitive_format, surface_arrays, [], {}, compress_flags)
		# arr_mesh.set_custom_aabb(local_aabb)
		arr_mesh.resource_name = self.name
		return arr_mesh

	var local_aabb: AABB:
		get:
			print(str(typeof(keys.get("m_LocalAABB", {}).get("m_Center"))) +"/" + str(keys.get("m_LocalAABB", {}).get("m_Center")))
			return AABB(keys.get("m_LocalAABB", {}).get("m_Center") * Vector3(-1,1,1), keys.get("m_LocalAABB", {}).get("m_Extent"))

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
		return ".mesh.res"

	func get_vertex_data() -> RefCounted:
		return aligned_byte_buffer.new(keys.get("m_VertexData", {}).get("_typelessdata", ""))

	func get_index_data() -> RefCounted:
		return aligned_byte_buffer.new(keys.get("m_IndexBuffer", ""))

class UnityMaterial extends UnityObject:

	func get_float_properties() -> Dictionary:
		var flts = keys.get("m_SavedProperties", {}).get("m_Floats", [])
		var ret = {}.duplicate()
		for dic in flts:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_color_properties() -> Dictionary:
		var cols = keys.get("m_SavedProperties", {}).get("m_Colors", [])
		var ret = {}.duplicate()
		for dic in cols:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_tex_properties() -> Dictionary:
		var texs = keys.get("m_SavedProperties", {}).get("m_TexEnvs", [])
		var ret = {}.duplicate()
		for dic in texs:
			for key in dic:
				ret[key] = dic.get(key)
		return ret

	func get_texture(texProperties: Dictionary, name: String) -> Texture:
		var env = texProperties.get(name, {})
		var texref: Array = env.get("m_Texture", [])
		if not texref.is_empty():
			return meta.get_godot_resource(texref)
		return null

	func get_texture_scale(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var scale: Vector2 = env.get("m_Scale", Vector2(1,1))
		return Vector3(scale.x, scale.y, 0.0)

	func get_texture_offset(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var offset: Vector2 = env.get("m_Offset", Vector2(0,0))
		return Vector3(offset.x, offset.y, 0.0)

	func get_color(colorProperties: Dictionary, name: String, dfl: Color) -> Color:
		var col: Color = colorProperties.get(name, dfl)
		return col

	func get_float(floatProperties: Dictionary, name: String, dfl: float) -> float:
		var ret: float = floatProperties.get(name, dfl)
		return ret

	func get_vector(colorProperties: Dictionary, name: String, dfl: Color) -> Plane:
		var col: Color = colorProperties.get(name, dfl)
		return Plane(Vector3(col.r, col.g, col.b), col.a)

	func get_keywords() -> Dictionary:
		var ret: Dictionary = {}.duplicate()
		var kwd = keys.get("m_ShaderKeywords", "")
		if typeof(kwd) == TYPE_STRING:
			for x in kwd.split(' '):
				ret[x] = true
		return ret

	func create_godot_resource() -> Material:
		var kws = get_keywords()
		var floatProperties = get_float_properties()
		#print(str(floatProperties))
		var texProperties = get_tex_properties()
		#print(str(texProperties))
		var colorProperties = get_color_properties()
		#print(str(colorProperties))
		var ret = StandardMaterial3D.new()
		ret.resource_name = self.name
		# FIXME: Kinda hacky since transparent stuff doesn't always draw depth in Unity
		# But it seems to workaround a problem with some materials for now.
		ret.depth_draw_mode = true ##### BaseMaterial3D.DEPTH_DRAW_ALWAYS
		ret.albedo_tex_force_srgb = true # Nothing works if this isn't set to true explicitly. Stupid default.
		ret.albedo_color = get_color(colorProperties, "_Color", Color.WHITE)
		ret.albedo_texture = get_texture(texProperties, "_MainTex2") ### ONLY USED IN ONE SHADER. This case should be removed.
		if ret.albedo_texture == null:
			ret.albedo_texture = get_texture(texProperties, "_MainTex")
		if ret.albedo_texture == null:
			ret.albedo_texture = get_texture(texProperties, "_Tex")
		if ret.albedo_texture == null:
			ret.albedo_texture = get_texture(texProperties, "_Albedo")
		if ret.albedo_texture == null:
			ret.albedo_texture = get_texture(texProperties, "_Diffuse")
		ret.uv1_scale = get_texture_scale(texProperties, "_MainTex")
		ret.uv1_offset = get_texture_offset(texProperties, "_MainTex")
		# TODO: ORM not yet implemented.
		if kws.get("_NORMALMAP", false):
			ret.normal_enabled = true
			ret.normal_texture = get_texture(texProperties, "_BumpMap")
			ret.normal_scale = get_float(floatProperties, "_BumpScale", 1.0)
		if kws.get("_EMISSION", false):
			ret.emission_enabled = true
			var emis_vec: Plane = get_vector(colorProperties, "_EmissionColor", Color.BLACK)
			var emis_mag = max(emis_vec.x, max(emis_vec.y, emis_vec.z))
			ret.emission = Color.BLACK
			if emis_mag > 0:
				ret.emission = Color(emis_vec.x/emis_mag, emis_vec.y/emis_mag, emis_vec.z/emis_mag)
				ret.emission_energy = emis_mag
			ret.emission_texture = get_texture(texProperties, "_EmissionMap")
			if ret.emission_texture != null:
				ret.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		if kws.get("_PARALLAXMAP", false):
			ret.heightmap_enabled = true
			ret.heightmap_texture = get_texture(texProperties, "_ParallaxMap")
			ret.heightmap_scale = get_float(floatProperties, "_Parallax", 1.0)
		if kws.get("__SPECULARHIGHLIGHTS_OFF", false):
			ret.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if kws.get("_GLOSSYREFLECTIONS_OFF", false):
			pass
		var occlusion = get_texture(texProperties, "_OcclusionMap")
		if occlusion != null:
			ret.ao_enabled = true
			ret.ao_texture = occlusion
			ret.ao_light_affect = get_float(floatProperties, "_OcclusionStrength", 1.0) # why godot defaults to 0???
			ret.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if kws.get("_METALLICGLOSSMAP"):
			ret.metallic_texture = get_texture(texProperties, "_MetallicGlossMap")
			ret.metallic = get_float(floatProperties, "_Metallic", 0.0)
			ret.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		# TODO: Glossiness: invert color channels??
		ret.roughness = 1.0 - get_float(floatProperties, "_Glossiness", 0.0)
		if kws.get("_ALPHATEST_ON"):
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		elif kws.get("_ALPHABLEND_ON") or kws.get("_ALPHAPREMULTIPLY_ON"):
			# FIXME: No premultiply
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Godot's detail map is a bit lacking right now...
		#if kws.get("_DETAIL_MULX2"):
		#	ret.detail_enabled = true
		#	ret.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		assign_object_meta(ret)
		return ret

	func get_godot_extension() -> String:
		return ".mat.tres"

class UnityShader extends UnityObject:
	pass

class UnityTexture extends UnityObject:
	pass

class UnityAnimationClip extends UnityObject:

	func get_godot_extension() -> String:
		return ".anim.tres"

class UnityTexture2D extends UnityTexture:
	pass

class UnityTexture2DArray extends UnityTexture:
	pass

class UnityTexture3D extends UnityTexture:
	pass

class UnityCubemap extends UnityTexture:
	pass

class UnityCubemapArray extends UnityTexture:
	pass

class UnityRenderTexture extends UnityTexture:
	pass

class UnityCustomRenderTexture extends UnityRenderTexture:
	pass


### ================ GAME OBJECT TYPE ================
class UnityGameObject extends UnityObject:

	func recurse_to_child_transform(state: RefCounted, child_transform: UnityObject, new_parent: Node3D):
		if child_transform.type == "PrefabInstance":
			# PrefabInstance child of stripped Transform part of another PrefabInstance
			var prefab_instance: UnityPrefabInstance = child_transform
			prefab_instance.create_godot_node(state, new_parent)
		elif child_transform.is_prefab_reference:
			# PrefabInstance child of ordinary Transform
			if not child_transform.is_stripped:
				print("Expected a stripped transform for prefab root as child of transform")
			var prefab_instance: UnityPrefabInstance = meta.lookup(child_transform.prefab_instance)
			prefab_instance.create_godot_node(state, new_parent)
		else:
			if child_transform.is_stripped:
				push_error("*!*!*! CHILD IS STRIPPED " + str(child_transform) + "; "+ str(child_transform.is_prefab_reference) + ";" + str(child_transform.prefab_source_object) + ";" + str(child_transform.prefab_instance))
			var child_game_object: UnityGameObject = child_transform.gameObject
			if child_game_object.is_prefab_reference:
				push_error("child gameObject is a prefab reference! " + child_game_object.uniq_key)
			var new_skelley: RefCounted = state.uniq_key_to_skelley.get(child_transform.uniq_key, null) # Skelley
			if new_skelley == null and new_parent == null:
				push_error("We did not create a node for this child, but it is not a skeleton bone! " + uniq_key + " child " + child_transform.uniq_key + " gameObject " + child_game_object.uniq_key + " name " + child_game_object.name)
			elif new_skelley != null:
				# print("Go from " + transform_asset.uniq_key + " to " + str(child_game_object) + " transform " + str(child_transform) + " found skelley " + str(new_skelley))
				child_game_object.create_skeleton_bone(state, new_skelley)
			else:
				child_game_object.create_godot_node(state, new_parent)

	func create_skeleton_bone(xstate: RefCounted, skelley: RefCounted): # SceneNodeState, Skelley
		var state: Object = xstate
		var godot_skeleton: Skeleton3D = skelley.godot_skeleton
		# Instead of a transform, this sets the skeleton transform position maybe?, etc. etc. etc.
		var transform: UnityTransform = self.transform
		var skeleton_bone_index: int = transform.skeleton_bone_index
		var skeleton_bone_name: String = godot_skeleton.get_bone_name(skeleton_bone_index)
		var ret: Node3D = null
		var rigidbody = GetComponent("Rigidbody")
		if rigidbody != null:
			ret = rigidbody.create_physical_bone(state, godot_skeleton, skeleton_bone_name)
			rigidbody.configure_node(ret)
			state.add_fileID(ret, self)
			state.add_fileID(ret, transform)
		elif len(components) > 1 or state.skelley_parents.has(transform.uniq_key):
			ret = BoneAttachment3D.new()
			ret.name = self.name
			state.add_child(ret, godot_skeleton, self)
			state.add_fileID(ret, transform)
			ret.bone_name = skeleton_bone_name
		else:
			state.add_fileID(godot_skeleton, self)
			state.add_fileID(godot_skeleton, transform)
			state.add_fileID_to_skeleton_bone(skeleton_bone_name, fileID)
			state.add_fileID_to_skeleton_bone(skeleton_bone_name, transform.fileID)
		# TODO: do we need to configure GameObject here? IsActive, Name on a skeleton bone?
		transform.configure_skeleton_bone(godot_skeleton, skeleton_bone_name)
		if ret != null:
			var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
			for new_skelley in list_of_skelleys:
				ret.add_child(godot_skeleton)
				godot_skeleton.owner = state.owner

		var skip_first: bool = true

		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				assert(ret != null)
				var component = meta.lookup(component_ref.get("component"))
				var tmp = component.create_godot_node(state, ret)
				component.configure_node(tmp)

		for child_ref in transform.children_refs:
			var child_transform: UnityTransform = meta.lookup(child_ref)
			recurse_to_child_transform(state, child_transform, ret)

	func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node3D:
		var state: Object = xstate
		var ret: Node3D = null
		var components: Array = self.components
		var has_collider: bool = false
		var extra_fileID: Array = [self]
		var transform: UnityTransform = self.transform

		for component_ref in components:
			var component = meta.lookup(component_ref.get("component"))
			# Some components take priority and must be created here.
			if component.type == "Rigidbody":
				ret = component.create_physics_body(state, new_parent, name)
				transform.configure_node(ret)
				component.configure_node(ret)
				extra_fileID.push_back(transform)
				state = state.state_with_body(ret)
			if component.is_collider():
				extra_fileID.push_back(component)
				print("Has a collider " + self.name)
				has_collider = true
		var is_staticbody: bool = false
		if has_collider and (state.body == null or state.body.get_class().begins_with("StaticBody")):
			ret = StaticBody3D.new()
			print("Created a StaticBody3D " + self.name)
			is_staticbody = true
			transform.configure_node(ret)
		elif ret == null:
			ret = Node3D.new()
			transform.configure_node(ret)
		ret.name = name
		state.add_child(ret, new_parent, transform)
		if is_staticbody:
			print("Replacing state with body " + str(name))
			state = state.state_with_body(ret)
		for ext in extra_fileID:
			state.add_fileID(ret, ext)
		var skip_first: bool = true

		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				var component = meta.lookup(component_ref.get("component"))
				var tmp = component.create_godot_node(state, ret)
				component.configure_node(tmp)

		var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
		for new_skelley in list_of_skelleys:
			if not new_skelley.godot_skeleton:
				push_error("Skelley " + str(new_skelley) + " is missing a godot_skeleton")
			else:
				ret.add_child(new_skelley.godot_skeleton)
				new_skelley.godot_skeleton.owner = state.owner

		for child_ref in transform.children_refs:
			var child_transform: UnityTransform = meta.lookup(child_ref)
			recurse_to_child_transform(state, child_transform, ret)

		return ret

	var components: Variant: # Array:
		get:
			if is_stripped:
				push_error("Attempted to access the component array of a stripped " + type + " " + uniq_key)
				# FIXME: Stripped objects do not know their name.
				return 12345.678 # ???? 
			return keys.get("m_Component")

	func get_transform() -> Variant: # UnityTransform:
		if is_stripped:
			push_error("Attempted to access the transform of a stripped " + type + " " + uniq_key)
			# FIXME: Stripped objects do not know their name.
			return 12345.678 # ???? 
		if typeof(components) != TYPE_ARRAY:
			push_error(uniq_key + " has component array: " + str(components))
		elif len(components) < 1 or typeof(components[0]) != TYPE_DICTIONARY:
			push_error(uniq_key + " has invalid first component: " + str(components))
		elif len(components[0].get("component", [])) < 3:
			push_error(uniq_key + " has invalid component: " + str(components))
		else:
			var component = meta.lookup(components[0].get("component"))
			if component.type != "Transform" and component.type != "RectTransform":
				push_error(str(self) + " does not have Transform as first component! " + str(component.type) + ": components " + str(components))
			return component
		return null

	func GetComponent(typ: String) -> RefCounted:
		for component_ref in components:
			var component = meta.lookup(component_ref.get("component"))
			if component.type == typ:
				return component
		return null

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = convert_properties_component(node, uprops)
		if uprops.has("m_IsActive"):
			outdict["visible"] = uprops.get("m_IsActive")
		if uprops.has("m_Name"):
			outdict["name"] = uprops.get("m_Name")
		return outdict

	var meshFilter: UnityMeshFilter = null
	func get_meshFilter() -> UnityMeshFilter:
		if meshFilter != null:
			return meshFilter
		return GetComponent("MeshFilter")

	var enabled: bool:
		get:
			return keys.get("m_IsActive", 0) != 0

	func is_toplevel() -> Variant: # bool
		if is_stripped:
			# Stripped objects are part of a Prefab, so by definition will never be toplevel
			# (The PrefabInstance itself will be the toplevel object)
			return false
		if typeof(transform) == TYPE_NIL:
			push_error(uniq_key + " has no transform in toplevel: " + str(transform))
			return null
		if typeof(transform.parent_ref) != TYPE_ARRAY:
			push_error(uniq_key + " has invalid or missing parent_ref: " + str(transform.parent_ref))
			return null
		return transform.parent_ref[1] == 0

	func get_gameObject() -> UnityGameObject:
		return self


# Is a PrefabInstance a GameObject? Unity seems to treat it that way at times. Other times not...
# Is this canon? We'll never know because the documentation denies even the existence of a "PrefabInstance" class
class UnityPrefabInstance extends UnityGameObject:

	func is_stripped_or_prefab_instance() -> bool:
		return true

	func set_owner_rec(node: Node, owner: Node):
		node.owner = owner
		for n in node.get_children():
			set_owner_rec(n, owner)

	# When you see a PrefabInstance, load() the scene.
	# If it is_prefab_reference but not the root, log an error.

	# For all Transform in scene, find transforms whose parent has is_prefab_reference=true. These subtrees must be mapped from PrefabInstance.

	# TODO: Create map from corresponding source object id (stripped id, PrefabInstanceId^target object id) and do so recursively, to target path...

	# For all PrefabInstance in scene, make map from m_TransformParent 
	# Note also: a PrefabInstance with m_TransformParent=0 in a prefab defines a "Prefab Variant". In Godot terms, this is an "inhereted" or instanced scene.
	# COMPLICATED!!!

	# Rules about skeletons: If any skinned mesh has bones, which are part of a prefab instance, mark all bones as belonging to that prefab instance (no consideration is made as to whether they link two separate skeletons together.)
	# Then, repeat one more time and makwe sure no overlap
	# all transforms are marked as parented to the prefab.

	func set_editable_children(state: RefCounted, instanced_scene: Node) -> Node:
		state.owner.set_editable_instance(instanced_scene, true)
		return instanced_scene

	# Generally, all transforms which are sub-objects of a prefab will be marked as such ("Create map from corresponding source object id (stripped id, PrefabInstanceId^target object id) and do so recursively, to target path...")
	func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node3D:
		meta.prefab_id_to_guid[self.fileID] = self.source_prefab[2] # UnityRef[2] is guid
		var state: RefCounted = xstate # scene_node_state
		var ps: RefCounted = state.prefab_state # scene_node_state.PrefabState
		var target_prefab_meta = meta.lookup_meta(source_prefab)
		if target_prefab_meta == null or target_prefab_meta.guid == self.meta.guid:
			push_error("Unable to load prefab dependency " + str(source_prefab) + " from " + str(self.meta.guid))
			return null
		var packed_scene: PackedScene = target_prefab_meta.get_godot_resource(source_prefab)
		if packed_scene == null:
			push_error("Failed to instantiate prefab with guid " + uniq_key + " from " + str(self.meta.guid))
			return null
		print("Instancing PackedScene at " + str(packed_scene.resource_path) + ": " + str(packed_scene.resource_name))
		var instanced_scene: Node3D = null
		if new_parent == null:
			# This is the "Inherited Scene" case (Godot), or "Prefab Variant" as it is called.
			# Godot does not have an API to create an inherited scene. However, luckily, the file format is simple.
			# We just need a [instance=ExtResource(1)] attribute on the root node.

			# FIXME: This may be unstable across Godot versions, if .tscn format ever changes.
			# node->set_scene_inherited_state(sdata->get_state()) is not exposed to GDScript. Let's HACK!!!
			var stub_filename = "res://_temp_scene.tscn"
			var fres = File.new()
			fres.open(stub_filename, File.WRITE)
			print("Writing stub scene to " + stub_filename)
			var to_write: String = ('[gd_scene load_steps=2 format=2]\n\n' +
				'[ext_resource path="' + str(packed_scene.resource_path) + '" type="PackedScene" id=1]\n\n' +
				'[node name="" instance=ExtResource( 1 )]\n')
			fres.store_string(to_write)
			print(to_write)
			fres.close()
			var temp_packed_scene: PackedScene = ResourceLoader.load(stub_filename, "", ResourceLoader.CACHE_MODE_IGNORE)
			instanced_scene = temp_packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			state.add_child(instanced_scene, new_parent, self)
		else:
			# Traditional instanced scene case: It only requires calling instantiate() and setting the filename.
			instanced_scene = packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			#instanced_scene.filename = packed_scene.resource_path
			state.add_child(instanced_scene, new_parent, self)

			if set_editable_children(state, instanced_scene) != instanced_scene:
				instanced_scene.filename = ""
				set_owner_rec(instanced_scene, state.owner)
		## using _bundled.editable_instance happens after the data is discarded...
		## This whole system doesn't work. We need an engine mod instead that allows set_editable_instance.
		##if new_parent != null:
			# In this case, we must also set editable children later in convert_scene.gd
			# Here is how we keep track of it:
		##	ps.prefab_instance_paths.push_back(state.owner.get_path_to(instanced_scene))
		# state = state.state_with_owner(instanced_scene)

		state.add_bones_to_prefabbed_skeletons(self.uniq_key, target_prefab_meta, instanced_scene)

		print("Prefab " + str(packed_scene.resource_path) + " ------------")
		print("Adding to parent " + str(new_parent))
		print(str(target_prefab_meta.fileid_to_nodepath))
		print(str(target_prefab_meta.prefab_fileid_to_nodepath))
		print(str(target_prefab_meta.fileid_to_skeleton_bone))
		print(str(target_prefab_meta.prefab_fileid_to_skeleton_bone))
		print(" ------------")

		var fileID_to_keys = {}.duplicate()
		var nodepath_to_first_virtual_object = {}.duplicate()
		var nodepath_to_keys = {}.duplicate()
		for mod in modifications:
			print("Preparing to apply mod: Mod is " + str(mod))
			var property_key: String = mod.get("propertyPath", "")
			var source_obj_ref: Array = mod.get("target", [null,0,"",null])
			var obj_value: Array = mod.get("objectReference", [null,0,"",null])
			var value: String = mod.get("value", "")
			var fileID: int = source_obj_ref[1]
			if not fileID_to_keys.has(fileID):
				fileID_to_keys[fileID] = {}.duplicate()
			if STRING_KEYS.has(property_key):
				fileID_to_keys.get(fileID)[property_key] = value
			elif value.is_empty():
				fileID_to_keys.get(fileID)[property_key] = obj_value
			elif obj_value[1] != 0:
				push_error("Object has both value " + str(value) + " and objref " + str(obj_value) + " for " + str(mod))
				fileID_to_keys.get(fileID)[property_key] = obj_value
			elif len(value) < 24 and value.is_valid_int():
				fileID_to_keys.get(fileID)[property_key] = value.to_int()
			elif len(value) < 32 and value.is_valid_float():
				fileID_to_keys.get(fileID)[property_key] = value.to_float()
			else:
				fileID_to_keys.get(fileID)[property_key] = value
		# Some legacy unity "feature" where objects part of a prefab might be not stripped
		# In that case, the 'non-stripped' copy will override even the modifications.
		for asset in ps.non_stripped_prefab_references.get(self.fileID, []):
			var fileID: int = asset.prefab_source_object[1]
			if not fileID_to_keys.has(fileID):
				fileID_to_keys[fileID] = {}.duplicate()
			for key in asset.keys:
				# print("Legacy prefab override fileID " + str(fileID) + " key " + str(key) + " value " + str(asset.keys[key]))
				fileID_to_keys[fileID][key] = asset.keys[key]
		for fileID in fileID_to_keys:
			var target_utype: int = target_prefab_meta.fileid_to_utype.get(fileID,
					target_prefab_meta.prefab_fileid_to_utype.get(fileID, 0))
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(fileID,
					target_prefab_meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(fileID,
					target_prefab_meta.prefab_fileid_to_skeleton_bone.get(fileID, ""))
			print("XXXc")
			var virtual_unity_object: UnityObject = adapter.instantiate_unity_object_from_utype(meta, fileID, target_utype)
			print("XXXd " + str(target_prefab_meta.guid) +"/" + str(fileID) + "/" + str(target_nodepath))
			var uprops: Dictionary = fileID_to_keys.get(fileID)
			var existing_node = instanced_scene.get_node(target_nodepath)
			print("Looking up instanced object at " + str(target_nodepath) + ": " + str(existing_node))
			if target_skel_bone.is_empty() and existing_node == null:
				push_error("FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(uprops))
			elif target_skel_bone.is_empty():
				if existing_node.has_meta("unidot_keys"):
					var orig_meta: Variant = existing_node.get_meta("unidot_keys")
					var exist_prop: Variant = orig_meta
					for uprop in uprops:
						var last_key: String = ""
						var this_key: String = ""
						var skip_first_piece: bool = true
						for prop_piece in uprop.split("."):
							if skip_first_piece:
								skip_first_piece = false
								continue
							if typeof(exist_prop) == TYPE_DICTIONARY:
								last_key = this_key
								this_key = prop_piece
								exist_prop = exist_prop.get(prop_piece, {})
							elif typeof(exist_prop) == TYPE_ARRAY:
								if prop_piece == "Array":
									continue
								if prop_piece == "size":
									continue
								print("Splitting array key: " + str(uprop) + " prop_piece " + str(prop_piece) + ": " + str(exist_prop) + " / all props: " + str(uprops))
								var idx: int = (prop_piece.split("[")[1].split("]")[0]).to_int()
								exist_prop = exist_prop[idx]
							else:
								match prop_piece:
									"x":
										exist_prop.x = uprops[uprop]
									"y":
										exist_prop.y = uprops[uprop]
									"z":
										exist_prop.z = uprops[uprop]
									"w":
										exist_prop.w = uprops[uprop]
									"r":
										exist_prop.r = uprops[uprop]
									"g":
										exist_prop.g = uprops[uprop]
									"b":
										exist_prop.b = uprops[uprop]
									"a":
										exist_prop.a = uprops[uprop]
						if typeof(exist_prop) == typeof(uprops[uprop]):
							exist_prop = uprops[uprop]
						if typeof(exist_prop) != TYPE_DICTIONARY:
							if last_key.is_empty():
								orig_meta[this_key] = exist_prop
							else:
								orig_meta[last_key][this_key] = exist_prop
					existing_node.set_meta("unidot_keys", orig_meta)
				if not nodepath_to_first_virtual_object.has(target_nodepath):
					nodepath_to_first_virtual_object[target_nodepath] = virtual_unity_object
					nodepath_to_keys[target_nodepath] = virtual_unity_object.convert_properties(existing_node, uprops)
				else:
					var dict: Dictionary = nodepath_to_keys.get(target_nodepath)
					var converted: Dictionary = virtual_unity_object.convert_properties(existing_node, uprops)
					for key in converted:
						dict[key] = converted.get(key)
					nodepath_to_keys[target_nodepath] = dict
			else:
				if existing_node != null:
					# Test this:
					print("Applying mod to skeleton bone " + str(existing_node) + " at path " + str(target_nodepath) + ":" + str(target_skel_bone) + "!! Mod is " + str(uprops))
					virtual_unity_object.configure_skeleton_bone_props(existing_node, target_skel_bone, uprops)
				else:
					push_error("FAILED to get_node to apply mod to skeleton at path " + str(target_nodepath) + ":" + target_skel_bone + "!! Mod is " + str(uprops))
		for target_nodepath in nodepath_to_keys:
			var virtual_unity_object: UnityObject = nodepath_to_first_virtual_object.get(target_nodepath)
			var existing_node = instanced_scene.get_node(target_nodepath)
			var uprops: Dictionary = fileID_to_keys.get(fileID)
			var props: Dictionary = nodepath_to_keys.get(target_nodepath)
			if existing_node != null:
				print("Applying mod to node " + str(existing_node) + " at path " + str(target_nodepath) + "!! Mod is " + str(props) + "/" + str(props.has("name")))
				virtual_unity_object.apply_node_props(existing_node, props)
				if target_nodepath == NodePath(".") and props.has("name"):
					print("Applying name " + str(props.get("name")))
					existing_node.name = props.get("name")
			else:
				push_error("FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(props))

		# NOTE: We have duplicate code here for GameObject and then Transform
		# The issue is, we will be parented to a stripped GameObject or Transform, but we do not
		# know the corresponding ID of the other stripped object.
		# Additionally, while IDs are predictable in Prefab Variants, they are chosen arbitrarily
		# in Scenes, so we cannot guess the ID of the corresponding Transform from the GameObject.

		# Therefore, the only way seems to be to process all GameObjects, and
		# then process all Transforms, as if they are separate objects...

		var nodepath_bone_to_stripped_gameobject: Dictionary = {}.duplicate()
		var gameobject_fileid_to_attachment: Dictionary = {}.duplicate()
		var gameobject_fileid_to_body: Dictionary = {}.duplicate()
		var orig_state_body: CollisionObject3D = state.body
		for gameobject_asset in ps.gameobjects_by_parented_prefab.get(fileID, {}).values():
			# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
			var par: UnityGameObject = gameobject_asset
			var source_obj_ref = par.prefab_source_object
			print("Checking stripped GameObject " + str(par.uniq_key) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
			assert(target_prefab_meta.guid == source_obj_ref[2])
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1],
					target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1],
					target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
			nodepath_bone_to_stripped_gameobject[str(target_nodepath) + "/" + str(target_skel_bone)] = gameobject_asset
			print("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.filename))
			var target_parent_obj = instanced_scene.get_node(target_nodepath)
			var attachment: Node3D = target_parent_obj
			if (attachment == null):
				push_error("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path))
				continue
			print("Found gameobject: " + str(target_parent_obj.name))
			if target_skel_bone != "" or target_parent_obj is BoneAttachment3D:
				var godot_skeleton: Node3D = target_parent_obj
				if target_parent_obj is BoneAttachment3D:
					attachment = target_parent_obj
					godot_skeleton = target_parent_obj.get_parent()
				for comp in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
					if comp.type == "Rigidbody":
						var physattach: PhysicalBone3D = comp.create_physical_bone(state, godot_skeleton, target_skel_bone)
						state.body = physattach
						attachment = physattach
						state.add_fileID(attachment, gameobject_asset)
						comp.configure_node(physattach)
						gameobject_fileid_to_attachment[gameobject_asset.fileID] = attachment
						#state.fileid_to_nodepath[transform_asset.fileID] = gameobject_asset.fileID
				if attachment == null:
					# Will not include the Transform.
					if len(ps.components_by_stripped_id.get(gameobject_asset.fileID, [])) >= 1:
						attachment = BoneAttachment3D.new()
						attachment.name = target_skel_bone # target_parent_obj.name if not stripped??
						attachment.bone_name = target_skel_bone
						state.add_child(attachment, godot_skeleton, gameobject_asset)
						gameobject_fileid_to_attachment[gameobject_asset.fileID] = attachment
			for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				if component.type == "MeshFilter":
					gameobject_asset.meshFilter = component
			for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				var tmp = component.create_godot_node(state, attachment)
				component.configure_node(tmp)
			gameobject_fileid_to_body[gameobject_asset.fileID] = state.body
			state.body = orig_state_body

		# And now for the analogous code to process stripped Transforms.
		for transform_asset in ps.transforms_by_parented_prefab.get(fileID, {}).values():
			# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
			var par: UnityTransform = transform_asset
			var source_obj_ref = par.prefab_source_object
			print("Checking stripped Transform " + str(par.uniq_key) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
			assert(target_prefab_meta.guid == source_obj_ref[2])
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1],
					target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1],
					target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
			var gameobject_asset: UnityGameObject = nodepath_bone_to_stripped_gameobject.get(str(target_nodepath) + "/" + str(target_skel_bone), null)
			print("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.filename))
			var target_parent_obj = instanced_scene.get_node(target_nodepath)
			var attachment: Node3D = target_parent_obj
			var already_has_attachment: bool = false
			if (attachment == null):
				push_error("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path))
				continue
			print("Found transform: " + str(target_parent_obj.name))
			if gameobject_asset != null:
				state.body = gameobject_fileid_to_body.get(gameobject_asset.fileID, state.body)
			if gameobject_asset != null and gameobject_fileid_to_attachment.has(gameobject_asset.fileID):
				print("We already got one! " + str(gameobject_asset.fileID) + " " + str(target_skel_bone))
				attachment = state.owner.get_node(state.fileid_to_nodepath.get(gameobject_asset.fileID))
				state.add_fileID(attachment, transform_asset)
				already_has_attachment = true
			elif !already_has_attachment and (target_skel_bone != "" or target_parent_obj is BoneAttachment3D): # and len(state.skelley_parents.get(transform_asset.uniq_key, [])) >= 1):
				var godot_skeleton: Node3D = target_parent_obj
				if target_parent_obj is BoneAttachment3D:
					attachment = target_parent_obj
					godot_skeleton = target_parent_obj.get_parent()
				else:
					attachment = BoneAttachment3D.new()
					attachment.name = target_skel_bone # target_parent_obj.name if not stripped??
					attachment.bone_name = target_skel_bone
					print("Made a new attachment! " + str(target_skel_bone))
					state.add_child(attachment, godot_skeleton, transform_asset)
			print("It's Peanut Butter Skelley time: " + str(transform_asset.uniq_key))

			var list_of_skelleys: Array = state.skelley_parents.get(transform_asset.uniq_key, [])
			for new_skelley in list_of_skelleys:
				attachment.add_child(new_skelley.godot_skeleton)
				new_skelley.godot_skeleton.owner = state.owner

			for child_transform in ps.child_transforms_by_stripped_id.get(transform_asset.fileID, []):
				# child_transform usually Transform; occasionally can be PrefabInstance
				recurse_to_child_transform(state, child_transform, attachment)

			state.body = orig_state_body

		# TODO: detect skeletons which overlap with existing prefab, and add bones to them.
		# TODO: implement modifications:
		# I think we should separate out the **CREATION OF STRUCTURE** from the **SETTING OF STATE**
		# If we do this, prefab modification properties would work the same way as normal properties:
		# prefab:
		#    instantiate scene
		#    assign property modifications
		# top-level (scene):
		#    build structure with create_godot_nodes
		#    now we have what is basically an instantiated scene.
		#    assign property modifications

		#calculate_prefab_nodepaths(state, instanced_scene, target_fileid, target_prefab_meta)
		#for target_fileid in target_prefab_meta.fileid_to_nodepath:
		#	var stripped_id = int(target_fileid)^fileID
		#	prefab_fileid_to_nodepath = 
		#stripped_id_to_nodepath
		#for mod in self.modifications:
		#	# TODO: Assign godot properties for each modification
		#	pass
		return instanced_scene

	func get_transform() -> UnityPrefabInstance: # Not really... but there usually isn't a stripped transform for the prefab instance itself.
		return self

	var rootOrder: int:
		get:
			return 0 # no idea..

	func get_gameObject() -> UnityPrefabInstance:
		return self

	var parent_ref: Array: # UnityRef
		get:
			return keys.get("m_Modification", {}).get("m_TransformParent", [null,0,"",0])

	# Special case: this is used to find a common ancestor for Skeletons. We stop at the prefab instance and do not go further.
	var parent_no_stripped: UnityObject: # Array #UnityRef
		get:
			return null # meta.lookup(parent_ref)

	var parent: UnityObject:
		get:
			return meta.lookup(parent_ref)

	func is_toplevel() -> bool:
		return not is_legacy_parent_prefab and parent_ref[1] == 0

	var modifications: Array:
		get:
			return keys.get("m_Modification", {}).get("m_Modifications", [])

	var removed_components: Array:
		get:
			return keys.get("m_Modification", {}).get("m_RemovedComponents", [])

	var source_prefab: Array: # UnityRef
		get:
			# new: m_SourcePrefab; old: m_ParentPrefab
			return keys.get("m_SourcePrefab", keys.get("m_ParentPrefab", [null, 0, "", 0]))

	var is_legacy_parent_prefab: bool:
		get:
			# Legacy prefabs will stick one of these at the root of the Prefab file. It serves no purpose
			# the legacy "prefab parent" object has a m_RootGameObject reference, but you can determine that
			# the same way modern prefabs do, the only GameObject whose Transform has m_Father == null
			return keys.get("m_IsPrefabParent", false)

class UnityPrefabLegacyUnused extends UnityPrefabInstance:
	# I think this will never exist in practice, but it's here anyway:
	# Old Unity's "Prefab" used utype 1001 which is now "PrefabInstance", not 1001480554.
	# so those objects should instantiate UnityPrefabInstance anyway.
	pass




### ================ COMPONENT TYPES ================
class UnityComponent extends UnityObject:

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var new_node: Node = Node.new()
		new_node.name = type
		state.add_child(new_node, new_parent, self)
		assign_object_meta(new_node)
		new_node.editor_description = str(self)
		return new_node

	func get_gameObject() -> Variant: # UnityGameObject
		if is_stripped:
			push_error("Attempted to access the gameObject of a stripped " + type + " " + uniq_key)
			# FIXME: Stripped objects do not know their name.
			return 12345.678 # ???? 
		return meta.lookup(keys.get("m_GameObject", []))

	func get_name() -> Variant:
		if is_stripped:
			push_error("Attempted to access the name of a stripped " + type + " " + uniq_key)
			# FIXME: Stripped objects do not know their name.
			# FIXME: Make the calling function crash, since we don't have stacktraces wwww
			return 12345.678 # ????
		return str(gameObject.name)

	func is_toplevel() -> bool:
		return false


class UnityBehaviour extends UnityComponent:
	func convert_properties_component(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = {}
		if uprops.has("m_Enabled"):
			outdict["visible"] = uprops.get("m_Enabled") != 0
		return outdict

	var enabled: bool:
		get:
			return keys.get("m_Enabled", 0) != 0

class UnityTransform extends UnityComponent:

	var skeleton_bone_index: int = -1
	const FLIP_X: Transform3D = Transform3D.FLIP_X # Transform3D(-1,0,0,0,1,0,0,0,1,0,0,0)
	const BAS_FLIP_X: Basis = Basis.FLIP_X # Transform3D(-1,0,0,0,1,0,0,0,1,0,0,0)

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node3D:
		return null

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		print("Node " + str(node.name) + " uprops " + str(uprops))
		var outdict = convert_properties_component(node, uprops)
		if uprops.has("m_LocalPosition.x"):
			outdict["position:x"] = -1.0 * uprops.get("m_LocalPosition.x") # * FLIP_X
		if uprops.has("m_LocalPosition.y"):
			outdict["position:y"] = 1.0 * uprops.get("m_LocalPosition.y")
		if uprops.has("m_LocalPosition.z"):
			outdict["position:z"] = 1.0 * uprops.get("m_LocalPosition.z")
		if uprops.has("m_LocalPosition"):
			var pos_vec: Variant = get_vector(uprops, "m_LocalPosition")
			outdict["position"] = Vector3(-1,1,1) * pos_vec # * FLIP_X
		var rot_vec: Variant = get_quat(uprops, "m_LocalRotation")
		if typeof(rot_vec) == TYPE_QUATERNION:
			outdict["_quaternion"] = (BAS_FLIP_X.inverse() * Basis(rot_vec) * BAS_FLIP_X).get_rotation_quaternion()
		var tmp: float
		if uprops.has("m_LocalScale.x"):
			tmp = 1.0 * uprops.get("m_LocalScale.x")
			outdict["scale:x"] = 1e-7 if tmp > -1e-7 && tmp < 1e-7 else tmp
		if uprops.has("m_LocalScale.y"):
			tmp = 1.0 * uprops.get("m_LocalScale.y")
			outdict["scale:y"] = 1e-7 if tmp > -1e-7 && tmp < 1e-7 else tmp
		if uprops.has("m_LocalScale.z"):
			tmp = 1.0 * uprops.get("m_LocalScale.z")
			outdict["scale:z"] = 1e-7 if tmp > -1e-7 && tmp < 1e-7 else tmp
		if uprops.has("m_LocalScale"):
			var scale: Variant = get_vector(uprops, "m_LocalScale")
			if typeof(scale) == TYPE_VECTOR3:
				if scale.x > -1e-7 && scale.x < 1e-7:
					scale.x = 1e-7
				if scale.y > -1e-7 && scale.y < 1e-7:
					scale.y = 1e-7
				if scale.z > -1e-7 && scale.z < 1e-7:
					scale.z = 1e-7
			outdict["scale"] = scale
		return outdict


	var rootOrder: int:
		get:
			return keys.get("m_RootOrder", 0)

	var parent_ref: Variant: # Array: # UnityRef
		get:
			if is_stripped:
				push_error("Attempted to access the parent of a stripped " + type + " " + uniq_key)
				return 12345.678 # FIXME: Returning bogus value to crash whoever does this
			return keys.get("m_Father", [null,0,"",0])

	var parent_no_stripped: UnityObject: # UnityTransform
		get:
			if is_stripped or is_non_stripped_prefab_reference:
				return meta.lookup(self.prefab_instance) # Not a UnityTransform, but sufficient for determining a common "ancestor" for skeleton bones.
			return meta.lookup(parent_ref)

	var parent: Variant: # UnityTransform:
		get:
			if is_stripped:
				push_error("Attempted to access the parent of a stripped " + type + " " + uniq_key)
				return 12345.678 # FIXME: Returning bogus value to crash whoever does this
			return meta.lookup(parent_ref)

	var children_refs: Array:
		get:
			return keys.get("m_Children")


class UnityRectTransform extends UnityTransform:
	pass

class UnityCollider extends UnityBehaviour:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var new_node: CollisionShape3D = CollisionShape3D.new()
		print("Creating collider at " + self.name + " type " + self.type + " parent name " + str(new_parent.name if new_parent != null else "NULL") + " path " + str(state.owner.get_path_to(new_parent) if new_parent != null else NodePath()) + " body name " + str(state.body.name if state.body != null else "NULL") + " path " + str(state.owner.get_path_to(state.body) if state.body != null else NodePath()))
		if state.body == null:
			state.body = StaticBody3D.new()
			new_parent.add_child(state.body)
			state.body.owner = state.owner
		new_node.name = self.type
		state.add_child(new_node, state.body, self)
		var path_to_body = new_parent.get_path_to(state.body)
		var cur_node: Node3D = new_parent
		var xform = Transform3D()
		for i in range(path_to_body.get_name_count()):
			if path_to_body.get_name(i) == ".":
				continue
			elif path_to_body.get_name(i) == "..":
				xform = cur_node.transform * xform
				cur_node = cur_node.get_parent()
				if cur_node == null:
					break
			else:
				cur_node = cur_node.get_node(str(path_to_body.get_name(i)))
				if cur_node == null:
					break
				print("Found node " + str(cur_node) + " class " + str(cur_node.get_class()))
				print("Found node " + str(cur_node) + " transform " + str(cur_node.transform))
				xform = cur_node.transform.affine_inverse() * xform
		#while cur_node != state.body and cur_node != null:
		#	xform = cur_node.transform * xform
		#	cur_node = cur_node.get_parent()
		#if cur_node == null:
		#	xform = Transform3D(self.basis, self.center)
		new_node.shape = self.shape
		if not xform.is_equal_approx(Transform3D()):
			var xform_storage: Node3D = Node3D.new()
			xform_storage.name = "__xform_storage"
			new_node.add_child(xform_storage)
			xform_storage.owner = state.owner
			xform_storage.transform = xform
		return new_node

	# TODO: Colliders are complicated because of the transform hierarchy issue above.
	func convert_properties_collider(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		var complex_xform: Node3D = null
		if node.has_node("__xform_storage"):
			complex_xform = node.get_node("__xform_storage")
		var center: Vector3 = Vector3()
		var basis: Basis = Basis.IDENTITY

		var center_prop: Variant = get_vector(uprops, "m_Center")
		if typeof(center_prop) == TYPE_VECTOR3:
			center = Vector3(-1.0, 1.0, 1.0) * center_prop
			if complex_xform != null:
				outdict["transform"] = complex_xform.transform * Transform3D(basis, center)
			else:
				outdict["position"] = center
		if uprops.has("m_Direction"):
			basis = get_basis_from_direction(uprops.get("m_Direction"))
			if complex_xform != null:
				outdict["transform"] = complex_xform.transform * Transform3D(basis, center)
			else:
				outdict["rotation_degrees"] = basis.get_euler() * 180 / PI
		return outdict

	func get_basis_from_direction(direction: int):
		return Basis()

	var shape: Shape3D:
		get:
			return get_shape()

	func get_shape() -> Shape3D:
		return null

	func is_collider() -> bool:
		return true

class UnityBoxCollider extends UnityCollider:
	func get_shape() -> Shape3D:
		var bs: BoxShape3D = BoxShape3D.new()
		return bs

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		var size = get_vector(uprops, "m_Size")
		if typeof(size) != TYPE_NIL:
			outdict["shape:size"] = size
		return outdict

class UnitySphereCollider extends UnityCollider:
	func get_shape() -> Shape3D:
		var bs: SphereShape3D = SphereShape3D.new()
		return bs

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		if uprops.has("m_Radius"):
			outdict["shape:radius"] = uprops.get("m_Radius")
		print("**** SPHERE COLLIDER RADIUS " + str(outdict))
		return outdict

class UnityCapsuleCollider extends UnityCollider:
	func get_shape() -> Shape3D:
		var bs: CapsuleShape3D = CapsuleShape3D.new()
		return bs

	func get_basis_from_direction(direction: int):
		if direction == 0: # Along the X-Axis
			return Basis(Vector3(0.0, 0.0, PI/2.0))
		if direction == 1: # Along the Y-Axis (Godot default)
			return Basis(Vector3(0.0, 0.0, 0.0))
		if direction == 2: # Along the Z-Axis
			return Basis(Vector3(PI/2.0, 0.0, 0.0))

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		var radius = node.shape.radius
		if typeof(uprops.get("m_Radius")) != TYPE_NIL:
			radius = uprops.get("m_Radius")
			outdict["shape:radius"] = radius
		if typeof(uprops.get("m_Height")) != TYPE_NIL:
			var adj_height: float = uprops.get("m_Height") - 2 * radius
			if adj_height < 0.0:
				adj_height = 0.0
			outdict["shape:height"] = adj_height
		return outdict

class UnityMeshCollider extends UnityCollider:

	# Not making these animatable?
	var convex: bool:
		get:
			return keys.get("m_Convex", 0) != 0

	func get_shape() -> Shape3D:
		if convex:
			return meta.get_godot_resource(get_mesh(keys)).create_convex_shape()
		else:
			return meta.get_godot_resource(get_mesh(keys)).create_trimesh_shape()

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		var new_convex = node.shape is ConvexPolygonShape3D
		if uprops.has("m_Convex"):
			new_convex = uprops.get("m_Convex", 1 if new_convex else 0) != 0
			# We do not allow animating this without also changing m_Mesh.
		if uprops.has("m_Mesh"):
			var mesh_ref: Array = get_ref(uprops, "m_Mesh")
			var new_mesh: Mesh = null
			if mesh_ref[1] == 0 and (is_stripped or gameObject.is_stripped):
				pass
			else:
				if mesh_ref[1] == 0:
					if is_stripped or gameObject.is_stripped:
						push_error("Oh no i am stripped MC")
					var mf: RefCounted = gameObject.get_meshFilter()
					if mf != null:
						new_mesh = meta.get_godot_resource(mf.mesh)
				else:
					new_mesh = meta.get_godot_resource(mesh_ref)
				if new_mesh != null:
					if new_convex:
						outdict["shape"] = new_mesh.create_convex_shape()
					else:
						outdict["shape"] = new_mesh.create_trimesh_shape()
			
		return outdict

	func get_mesh(uprops: Dictionary) -> Array: # UnityRef
		var ret = get_ref(uprops, "m_Mesh")
		if ret[1] == 0:
			if is_stripped or gameObject.is_stripped:
				push_error("Oh no i am stripped MCgm")
			var mf: RefCounted = gameObject.get_meshFilter()
			if mf != null:
				return mf.mesh
		return ret

class UnityRigidbody extends UnityComponent:

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func create_physics_body(state: RefCounted, new_parent: Node3D, name: String) -> Node:
		var new_node: Node3D;
		if keys.get("m_IsKinematic") != 0:
			var kinematic: CharacterBody3D = CharacterBody3D.new()
			new_node = kinematic
		else:
			var rigid: RigidBody3D = RigidBody3D.new()
			new_node = rigid

		new_node.name = name # Not type: This replaces the usual transform node.
		state.add_child(new_node, new_parent, self)
		return new_node

	# TODO: Add properties for rigidbody (e.g. mass, etc.).
	# NOTE: We do not allow changing m_IsKinematic because that's a Godot type change!
	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		return outdict

	func create_physical_bone(state: RefCounted, godot_skeleton: Skeleton3D, name: String):
		var new_node: PhysicalBone3D = PhysicalBone3D.new()
		new_node.bone_name = name
		new_node.name = name
		state.add_child(new_node, godot_skeleton, self)
		return new_node



class UnityMeshFilter extends UnityComponent:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_Mesh"):
			var mesh_ref: Array = get_ref(uprops, "m_Mesh")
			var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
			print("MeshFilter " + str(self.uniq_key) + " ref " + str(mesh_ref) + " new mesh " + str(new_mesh) + " old mesh " + str(node.mesh))
			outdict["_mesh"] = new_mesh # property track?
		return outdict

	func get_filter_mesh() -> Array: # UnityRef
		return keys.get("m_Mesh", [null,0,"",null])

class UnityRenderer extends UnityBehaviour:
	pass

class UnityMeshRenderer extends UnityRenderer:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return create_godot_node_orig(state, new_parent, type)

	func create_godot_node_orig(state: RefCounted, new_parent: Node3D, component_name: String) -> Node:
		var new_node: MeshInstance3D = MeshInstance3D.new()
		new_node.name = component_name
		state.add_child(new_node, new_parent, self)
		assign_object_meta(new_node)
		new_node.editor_description = str(self)
		new_node.mesh = meta.get_godot_resource(self.get_mesh())

		if is_stripped or gameObject.is_stripped:
			push_error("Oh no i am stripped MRcgno")
		var mf: RefCounted = gameObject.get_meshFilter()
		if mf != null:
			state.add_fileID(new_node, mf)
		var idx: int = 0
		for m in keys.get("m_Materials", []):
			new_node.set_surface_override_material(idx, meta.get_godot_resource(m))
			idx += 1
		return new_node

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_Materials"):
			outdict["_materials_size"] = len(uprops.get("m_Materials"))
			var idx: int = 0
			for m in uprops.get("m_Materials", []):
				outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
				idx += 1
			print("Converted mesh prop " + str(outdict))
		else:
			if uprops.has("m_Materials.Array.size"):
				outdict["_materials_size"] = uprops.get("m_Materials.Array.size")
			const MAT_ARRAY_PREFIX: String = "m_Materials.Array.data["
			for prop in uprops:
				if str(prop).begins_with(MAT_ARRAY_PREFIX) and str(prop).ends_with("]"):
					var idx: int = str(prop).substr(len(MAT_ARRAY_PREFIX), len(str(prop)) - 1 - len(MAT_ARRAY_PREFIX)).to_int()
					var m: Array = get_ref(uprops, prop)
					outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
			print("Converted mesh prop " + str(outdict) + "  for uprop " + str(uprops))
		return outdict

	# TODO: convert_properties
	# both material properties as well as material references??
	# anything else to animate?

	func get_mesh() -> Array: # UnityRef
		if is_stripped or gameObject.is_stripped:
			push_error("Oh no i am stripped MR")
		var mf: RefCounted = gameObject.get_meshFilter()
		if mf != null:
			return mf.get_filter_mesh()
		return [null,0,"",null]

class UnitySkinnedMeshRenderer extends UnityMeshRenderer:

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		if len(bones) == 0:
			var cloth: UnityCloth = gameObject.GetComponent("Cloth")
			if cloth != null:
				return create_cloth_godot_node(state, new_parent, type, cloth)
			return create_godot_node_orig(state, new_parent, type)
		else:
			return null

	func create_cloth_godot_node(state: RefCounted, new_parent: Node3D, component_name: String, cloth: UnityCloth) -> Node:
		var new_node: MeshInstance3D = cloth.create_cloth_godot_node(state, new_parent, type, self, self.mesh, null, [])
		var idx: int = 0
		for m in keys.get("m_Materials", []):
			new_node.set_surface_override_material(idx, meta.get_godot_resource(m))
			idx += 1
		return new_node

	func create_skinned_mesh(state: RefCounted) -> Node:
		var bones: Array = self.bones
		if len(self.bones) == 0:
			return null
		var first_bone_obj: RefCounted = meta.lookup(bones[0])
		#if first_bone_obj.is_stripped:
		#	push_error("Cannot create skinned mesh on stripped skeleton!")
		#	return null
		var first_bone_key: String = first_bone_obj.uniq_key
		print("SkinnedMeshRenderer: Looking up " + first_bone_key + " for " + str(self.gameObject))
		var skelley: RefCounted = state.uniq_key_to_skelley.get(first_bone_key, null) # Skelley
		if skelley == null:
			push_error("Unable to find Skelley to add a mesh " + name + " for " + first_bone_key)
			return null
		var gdskel: Skeleton3D = skelley.godot_skeleton
		if gdskel == null:
			push_error("Unable to find skeleton to add a mesh " + name + " for " + first_bone_key)
			return null
		var component_name: String = type
		if not self.gameObject.is_stripped:
			component_name = self.gameObject.name
		var cloth: UnityCloth = gameObject.GetComponent("Cloth")
		var ret: MeshInstance3D = null
		if cloth != null:
			ret = create_cloth_godot_node(state, gdskel, component_name, cloth)
		else:
			ret = create_godot_node_orig(state, gdskel, component_name)
		# ret.skeleton = NodePath("..") # default?
		# TODO: skin??
		ret.skin = meta.get_godot_resource(get_skin())
		if ret.skin == null:
			push_error("Mesh " + component_name + " at " + str(state.owner.get_path_to(ret)) + " mesh " + str(ret.mesh) + " has bones " + str(len(bones)) + " has null skin")
		elif len(bones) != ret.skin.get_bind_count():
			push_error("Mesh " + component_name + " at " + str(state.owner.get_path_to(ret)) + " mesh " + str(ret.mesh) + " has bones " + str(len(bones)) + " mismatched with bind bones " + str(ret.skin.get_bind_count()))
		else:
			var edited: bool = false
			for idx in range(len(bones)):
				var bone_transform: UnityTransform = meta.lookup(bones[idx])
				if ret.skin.get_bind_bone(idx) != bone_transform.skeleton_bone_index:
					edited = true
					break
			if edited:
				ret.skin = ret.skin.duplicate()
				for idx in range(len(bones)):
					var bone_transform: UnityTransform = meta.lookup(bones[idx])
					ret.skin.set_bind_bone(idx, bone_transform.skeleton_bone_index)
					ret.skin.set_bind_name(idx, gdskel.get_bone_name(bone_transform.skeleton_bone_index))
		# TODO: duplicate skin and assign the correct bone names to match self.bones array
		return ret

	var bones: Array:
		get:
			return keys.get("m_Bones", [])

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_Mesh"):
			var mesh_ref: Array = get_ref(uprops, "m_Mesh")
			var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
			outdict["_mesh"] = new_mesh # property track?
			var skin_ref: Array = mesh_ref
			skin_ref = [null, -skin_ref[1], skin_ref[2], skin_ref[3]]
			var new_skin: Mesh = meta.get_godot_resource(skin_ref)
			outdict["skin"] = new_skin # property track?

			# TODO: blend shapes

			# TODO: m_Bones modifications? what even is the syntax. I think we shouldn't allow changes to bones.
		return outdict

	func get_skin() -> Array: # UnityRef
		var ret: Array = keys.get("m_Mesh", [null,0,"",null])
		return [null, -ret[1], ret[2], ret[3]]

	func get_mesh() -> Array: # UnityRef
		return keys.get("m_Mesh", [null,0,"",null])

class UnityCloth extends UnityBehaviour:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func get_bone_transform(skel: Skeleton3D, bone_idx: int) -> Transform3D:
		var transform: Transform3D = Transform3D.IDENTITY
		while bone_idx != -1:
			transform = skel.get_bone_rest(bone_idx) * transform
			bone_idx = skel.get_bone_parent(bone_idx)
		return transform

	func get_or_upgrade_bone_attachment(skel: Skeleton3D, state: RefCounted, bone_transform: UnityTransform) -> BoneAttachment3D:
		var fileID: int = bone_transform.fileID
		var target_nodepath: NodePath = meta.fileid_to_nodepath.get(fileID,
				meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
		var ret: Node3D = skel
		if target_nodepath != NodePath():
			ret = state.owner.get_node(target_nodepath)
		if ret is Skeleton3D:
			ret = BoneAttachment3D.new()
			ret.name = skel.get_bone_name(bone_transform.skeleton_bone_index) # target_skel_bone
			state.add_child(ret, skel, bone_transform)
			state.remove_fileID_to_skeleton_bone(bone_transform.fileID)
			ret.bone_name = ret.name
			return ret
		else:
			return ret

	func create_cloth_godot_node(state: RefCounted, new_parent: Node3D, component_name: String, smr: UnityObject, mesh: Array, skel: Skeleton3D, bones: Array) -> SoftBody3D:
		var new_node: SoftBody3D = SoftBody3D.new()
		new_node.name = component_name
		state.add_child(new_node, new_parent, smr)
		state.add_fileID(new_node, self)
		new_node.editor_description = str(self)
		new_node.mesh = meta.get_godot_resource(mesh)
		new_node.ray_pickable = false
		new_node.linear_stiffness = self.linear_stiffness
		# new_node.angular_stiffness = self.angular_stiffness # Removed in 4.0 - how to set Bending stiffness??
		# parent_collision_ignore?????? # NodePath to a CollisionObject this SoftBody should avoid clipping. ????
		new_node.damping_coefficient = self.damping_coefficient
		new_node.drag_coefficient = self.drag_coefficient
		# m_CapsuleColliders ??? 
		# m_SphereColliders ???
		# m_Enabled # FIXME: No way to disable?!?!
		# FIXME: no GRAVITY?????
		# world velocity / world acceleration?
		# collision mass?
		# sleep threshold?
		if new_node.mesh == null:
			return new_node
		var max_dist: float = 0.01
		for coef in self.coefficients:
			var dist: float = coef.get("maxDistance", 1.0)
			if dist < 1.0e+10:
				max_dist = max(max_dist, dist)
		# We might not be able to use Unity's "m_Coefficients" because it depends on vertex ordering
		# which might be well defined, but even if so, Unity does some black magic to deduplicate vertices
		# across UV and normal seams. Does Godot also do this? If not, how does it keep the mesh from
		# falling apart at UV seams? If yes, how to map the two engines' algorithms here.
		var mesh_arrays: Array = new_node.mesh.surface_get_arrays(0) # Godot SoftBody ignores other surfaces.
		var mesh_verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
		var mesh_bones: PackedInt32Array = mesh_arrays[Mesh.ARRAY_BONES]
		var mesh_weights: Array = Array(mesh_arrays[Mesh.ARRAY_WEIGHTS])
		var bone_per_vert: int = len(mesh_bones) / len(mesh_verts)
		var vertex_info_to_dedupe_index: Dictionary = {}.duplicate()
		var bone_idx_to_bone_transform: Dictionary = {}.duplicate()
		var bone_idx_to_attachment_path: Dictionary = {}.duplicate()
		var dedupe_vertices: PackedInt32Array = PackedInt32Array()
		var vert_idx: int = 0
		# De-duplication of vertices to deal with UV-seams and sharp normals.
		# Seems to match Unity's logic (for meshes with only one surface at least!)
		# For example 1109/1200 or 104/129 verts
		# FIXME: I noticed some differences in vertex ordering in some cases. Hmm....
		var idx: int = 0
		var idxlen: int = (len(mesh_verts))
		while idx < idxlen:
			var vert: Vector3 = mesh_verts[idx]
			var key = str(vert.x) + "," + str(vert.y) + "," + str(vert.z)
			if not bones.is_empty() and not mesh_bones.is_empty():
				key += str(0.5 * mesh_weights[idx * bone_per_vert] + mesh_bones[idx * bone_per_vert])
			if vertex_info_to_dedupe_index.has(key):
				dedupe_vertices.push_back(vertex_info_to_dedupe_index.get(key))
			else:
				vertex_info_to_dedupe_index[key] = vert_idx
				dedupe_vertices.push_back(vert_idx)
				vert_idx += 1
			idx += 1

		print("Verts " + str(len(mesh_verts)) + " " + str(len(mesh_bones)) + " " + str(len(mesh_weights)) + " dedupe_len=" + str(vert_idx) + " unity_len=" + str(len(self.coefficients)))

		var pinned_points: PackedInt32Array = PackedInt32Array()
		var bones_paths: Array = [].duplicate()
		var offsets: Array = [].duplicate()
		var unity_coefficients = self.coefficients
		vert_idx = 0
		idxlen = (len(mesh_verts))
		while vert_idx < idxlen:
			var dedupe_idx = dedupe_vertices[vert_idx]
			if dedupe_idx >= len(unity_coefficients):
				vert_idx += 1
				continue
			var coef = unity_coefficients[dedupe_idx]
			if coef.get("maxDistance", max_dist) / max_dist < 0.01:
				pinned_points.push_back(vert_idx)
				if bones.is_empty():
					bones_paths.push_back(NodePath("."))
					offsets.push_back(mesh_verts[vert_idx])
				else:
					var most_weight: float = 0.0
					var most_bone: int = 0
					for boneidx in range(bone_per_vert):
						var weight: float = mesh_weights[vert_idx * bone_per_vert + boneidx]
						if weight >= most_weight:
							most_weight = weight
							most_bone = mesh_bones[vert_idx * bone_per_vert + boneidx]
					if not bone_idx_to_attachment_path.has(most_bone):
						var attachment: BoneAttachment3D = get_or_upgrade_bone_attachment(skel, state, meta.lookup(bones[most_bone]))
						bone_idx_to_bone_transform[most_bone] = get_bone_transform(skel, skel.find_bone(attachment.bone_name)).affine_inverse()
						bone_idx_to_attachment_path[most_bone] = new_node.get_path_to(attachment)
					bones_paths.push_back(bone_idx_to_attachment_path.get(most_bone))
					offsets.push_back(bone_idx_to_bone_transform[most_bone] * mesh_verts[vert_idx])
			vert_idx += 1
		# It may be necessary to add BoneAttachment for each vertex, and
		# then, give a node path and vertex offset for the maximally weighted vertex.
		# This property isn't even documented, so IDK whatever.
		new_node.set("pinned_points", pinned_points)
		for i in range(len(pinned_points)):
			new_node.set("attachments/" + str(i) + "/spatial_attachment_path", bones_paths[i])
			new_node.set("attachments/" + str(i) + "/offset", offsets[i])
		return new_node

	# TODO: convert to properties!

	var coefficients:
		get:
			return keys.get("m_Coefficients", [])

	var drag_coefficient:
		get:
			return keys.get("m_Friction", 0)

	var damping_coefficient:
		get:
			return keys.get("m_Damping", 0)

	var linear_stiffness:
		get:
			return keys.get("m_StretchingStiffness", 1)

	var angular_stiffness:
		get:
			return keys.get("m_BendingStiffness", 1)


class UnityLight extends UnityBehaviour:

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var light: Light3D
		# TODO: Change Light to use set()
		var unityLightType = lightType
		if unityLightType == 0:
			# Assuming default cookie
			# Assuming Legacy pipeline:
			# Scriptable Rendering Pipeline: shape and innerSpotAngle not supported.
			# Assuming RenderSettings.m_SpotCookie: == {fileID: 10001, guid: 0000000000000000e000000000000000, type: 0}
			var spot_light: SpotLight3D = SpotLight3D.new()
			spot_light.set_param(Light3D.PARAM_SPOT_ANGLE, spotAngle * 0.5)
			spot_light.set_param(Light3D.PARAM_SPOT_ATTENUATION, 0.5) # Eyeball guess for Unity's default spotlight texture
			spot_light.set_param(Light3D.PARAM_ATTENUATION, 0.333) # Was 1.0
			spot_light.set_param(Light3D.PARAM_RANGE, lightRange)
			light = spot_light
		elif unityLightType == 1:
			# depth_range? max_disatance? blend_splits? bias_split_scale?
			#keys.get("m_ShadowNearPlane")
			var dir_light: DirectionalLight3D = DirectionalLight3D.new()
			dir_light.set_param(Light3D.PARAM_SHADOW_NORMAL_BIAS, shadowNormalBias)
			light = dir_light
		elif unityLightType == 2:
			var omni_light: OmniLight3D = OmniLight3D.new()
			light = omni_light
			omni_light.set_param(Light3D.PARAM_ATTENUATION, 1.0)
			omni_light.set_param(Light3D.PARAM_RANGE, lightRange)
		elif unityLightType == 3:
			push_error("Rectangle Area Light not supported!")
			# areaSize?
			return super.create_godot_node(state, new_parent)
		elif unityLightType == 4:
			push_error("Disc Area Light not supported!")
			return super.create_godot_node(state, new_parent)

		# TODO: Layers
		if keys.get("useColorTemperature"):
			push_error("Color Temperature not implemented.")
		light.name = type
		state.add_child(light, new_parent, self)
		light.transform = Transform3D(Basis(Vector3(0.0, PI, 0.0)))
		light.light_color = color
		light.set_param(Light3D.PARAM_ENERGY, intensity)
		light.set_param(Light3D.PARAM_INDIRECT_ENERGY, bounceIntensity)
		light.shadow_enabled = shadowType != 0
		light.set_param(Light3D.PARAM_SHADOW_BIAS, shadowBias)
		if lightmapBakeType == 1:
			light.light_bake_mode = Light3D.BAKE_DYNAMIC # INDIRECT??
		elif lightmapBakeType == 2:
			light.light_bake_mode = Light3D.BAKE_DYNAMIC # BAKE_ALL???
			light.editor_only = true
		else:
			light.light_bake_mode = Light3D.BAKE_DISABLED
		return light

	# TODO: convert to properties!

	var color: Color:
		get:
			return keys.get("m_Color")
	
	var lightType: float:
		get:
			return keys.get("m_Type", 1)
	
	var lightRange: float:
		get:
			return keys.get("m_Range")

	var intensity: float:
		get:
			return keys.get("m_Intensity")
	
	var bounceIntensity: float:
		get:
			return keys.get("m_BounceIntensity")
	
	var spotAngle: float:
		get:
			return keys.get("m_SpotAngle")

	var lightmapBakeType: int:
		get:
			return keys.get("m_Lightmapping")

	var shadowType: int:
		get:
			return keys.get("m_Shadows").get("m_Type")

	var shadowBias: float:
		get:
			return keys.get("m_Shadows").get("m_Bias")

	var shadowNormalBias: float:
		get:
			return keys.get("m_Shadows").get("m_NormalBias")

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_CullingMask"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
		elif uprops.has("m_CullingMask.m_Bits"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask.m_Bits")
		return outdict

class UnityAudioSource extends UnityBehaviour:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var audio: Node = null
		var panlevel_curve: Dictionary = keys.get("panLevelCustomCurve", {})
		var curves: Array = panlevel_curve.get("m_Curve", [])
		#if len(curves) == 1:
		#	print("Curve is " + str(curves) + " value is " + str(curves[0].get("value", 1.0)))
		if len(curves) == 1 and str(curves[0].get("value", 1.0)).to_float() < 0.001:
			# Completely 2D: use non-spatialized player.
			audio = AudioStreamPlayer.new()
		else:
			audio = AudioStreamPlayer3D.new()
		assign_object_meta(audio)
		state.add_child(audio, new_parent, self)
		return audio

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_CullingMask"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
		elif uprops.has("m_CullingMask.m_Bits"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask.m_Bits")
		if uprops.has("m_Pitch"):
			outdict["pitch_scale"] = uprops.get("m_Pitch")
		if uprops.has("m_Volume"):
			var volume_linear: float = 1.0 * uprops.get("m_Volume")
			var volume_db: float = -80.0
			if volume_linear > 0.0001:
				volume_db = 20.0 * log(volume_linear) / log(10.0)
			outdict["volume_db"] = volume_db
			outdict["unit_db"] = volume_db
			outdict["max_db"] = volume_db
		if uprops.has("m_PlayOnAwake"):
			outdict["autoplay"] = uprops.get("m_PlayOnAwake") == 1
		if uprops.has("Mute"):
			outdict["stream_paused"] = uprops.get("Mute") == 1
		# "Loop" not supported?
		if uprops.has("m_audioClip"):
			outdict["stream"] = meta.get_godot_resource(get_ref(uprops, "m_audioClip"))
		if uprops.has("MaxDistance"):
			outdict["max_distance"] = uprops.get("MaxDistance")
		# TODO: how does MinDistance work with falloff curves? Are max_db and unit_db affected?
		if uprops.get("rolloffMode", -1) == 0:
			outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		if uprops.get("rolloffMode", -1) == 1:
			outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		if uprops.get("rolloffMode", -1) == 2:
			# Guess which slope curve it is closest to.
			var slope_estimate: float = 0.0
			var curve_points: Array = uprops.get("rolloffCustomCurve", {}).get("m_Curve", [{}])
			for curvept in curve_points:
				slope_estimate += curvept.get("outSlope", 0.0)
			slope_estimate /= len(curve_points)
			if slope_estimate < -5.0:
				outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
			elif slope_estimate < -0.1:
				outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			else:
				outdict["attenuation_model"] = AudioStreamPlayer3D.ATTENUATION_DISABLED
			# TODO: How does unit_size work?
		return outdict

class UnityCamera extends UnityBehaviour:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var par: Node = new_parent
		var texref: Array = keys.get("m_TargetTexture", [null, 0, null, null])
		if texref[1] != 0:
			var rendertex: UnityObject = meta.lookup(texref)
			var viewport: SubViewport = SubViewport.new()
			new_parent.add_child(viewport)
			viewport.owner = state.owner
			viewport.size = Vector2(
				rendertex.keys.get("m_Width"),
				rendertex.keys.get("m_Height"))
			if keys.get("m_AllowMSAA", 0) == 1:
				if rendertex.keys.get("m_AntiAliasing", 0) == 1:
					viewport.msaa = Viewport.MSAA_8X
			viewport.use_occlusion_culling = keys.get("m_OcclusionCulling", 0)
			viewport.clear_mode = SubViewport.CLEAR_MODE_ALWAYS if keys.get("m_ClearFlags") < 3 else SubViewport.CLEAR_MODE_NEVER
			# Godot is always HDR? if keys.get("m_AllowHDR", 0) == 1
			par = viewport
		var cam: Camera3D = Camera3D.new()
		if keys.get("m_ClearFlags") == 2:
			var cenv: Environment = Environment.new() if state.env == null else state.env.duplicate()
			cam.environment = cenv
			cenv.background_mode = Environment.BG_COLOR
			var ccol: Color = keys.get("m_BackGroundColor", Color.BLACK)
			var eng = max(ccol.r, max(ccol.g, ccol.b))
			if eng > 1:
				ccol /= eng
			else:
				eng = 1
			cenv.background_color = ccol
			cenv.background_energy = eng
		assign_object_meta(cam)
		state.add_child(cam, par, self)
		cam.transform = Transform3D(Basis(Vector3(0.0, PI, 0.0)))
		return cam

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_CullingMask"):
			outdict["cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
		elif uprops.has("m_CullingMask.m_Bits"):
			outdict["cull_mask"] = uprops.get("m_CullingMask.m_Bits")
		if uprops.has("far clip plane"):
			outdict["far"] = uprops.get("far clip plane")
		if uprops.has("near clip plane"):
			outdict["near"] = uprops.get("near clip plane")
		if uprops.has("field of view"):
			outdict["fov"] = uprops.get("field of view")
		if uprops.has("orthographic"):
			outdict["projection_mode"] = uprops.get("orthographic")
		if uprops.has("orthographic size"):
			outdict["size"] = uprops.get("orthographic size")
		return outdict

class UnityLightProbeGroup extends UnityComponent:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		for pos in keys.get("m_SourcePositions", []):
			var probe: LightmapProbe = LightmapProbe.new()
			new_parent.add_child(probe)
			probe.owner = state.owner
			probe.position = pos
		return null

class UnityReflectionProbe extends UnityBehaviour:
	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var probe: ReflectionProbe = ReflectionProbe.new()
		assign_object_meta(probe)
		state.add_child(probe, new_parent, self)
		return probe

	func convert_properties(node: Node3D, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_BoxProjection"):
			outdict["interior"] = true if uprops.get("m_BoxProjection") else false
			outdict["box_projection"] = true if uprops.get("m_BoxProjection") else false
		if uprops.has("m_BoxOffset"):
			outdict["position"] = uprops.get("m_BoxOffset")
			outdict["origin_offset"] = -uprops.get("m_BoxOffset")
		if uprops.has("m_BoxSize"):
			outdict["extents"] = uprops.get("m_BoxSize")
		if uprops.has("m_CullingMask"):
			outdict["cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
		elif uprops.has("m_CullingMask.m_Bits"):
			outdict["cull_mask"] = uprops.get("m_CullingMask.m_Bits")
		if uprops.has("m_FarClip"):
			outdict["max_distance"] = uprops.get("m_FarClip")
		if uprops.get("m_Mode", 0) == 0:
			push_error("Reflection Probe = Baked is not supported. Treating as Realtime / Once")
		if uprops.get("m_Mode", 0) == 2:
			push_error("Reflection Probe = Custom is not supported. Treating as Realtime / Once")
		if uprops.get("m_Mode", 0) == 1 and uprops.get("m_RefreshMode", 0) == 1:
			outdict["update_mode"] = 1
		if uprops.has("m_Mode"):
			if uprops.get("m_Mode") == 1:
				if uprops.get("m_RefreshMode", 1) != 1:
					outdict["update_mode"] = 0
			else:
				outdict["update_mode"] = 0
		elif uprops.get("m_RefreshMode", 1) != 1:
			outdict["update_mode"] = 0
		return outdict

class UnityMonoBehaviour extends UnityBehaviour:
	var script: Array:
		get:
			return keys.get("m_Script", [null,0,null,null])

	# No need yet to override create_godot_node...
	func create_godot_resource() -> Resource:
		if script[1] == 11500000:
			if script[2] == "8e6292b2c06870d4495f009f912b9600":
				return create_post_processing_profile()
		return null

	func create_post_processing_profile() -> Environment:
		var env: Environment = Environment.new()
		for setting in keys.get("settings"):
			var sobj = meta.lookup(setting)
			match str(sobj.script[2]):
				"adb84e30e02715445aeb9959894e3b4d": # Tonemap
					env.set_meta("glow", sobj.keys)
				"48a79b01ea5641d4aa6daa2e23605641": # Glow
					env.set_meta("glow", sobj.keys)
		return env

### ================ IMPORTER TYPES ================
class UnityAssetImporter extends UnityObject:
	func get_main_object_id() -> int:
		return 0 # Unknown
	var main_object_id: int:
		get:
			return get_main_object_id() # Unknown

	func get_external_objects() -> Dictionary:
		var eo: Dictionary = {}.duplicate()
		var extos: Variant = keys.get("externalObjects")
		if typeof(extos) != TYPE_ARRAY:
			return eo
		for srcAssetIdent in extos:
			var type_str: String = srcAssetIdent.get("first", {}).get("type","")
			var type_key: String = type_str.split(":")[-1]
			var key: Variant = srcAssetIdent.get("first", {}).get("name","") # FIXME: Returns null sometimes????
			var val: Array = srcAssetIdent.get("second", [null,0,"",null]) # UnityRef
			if typeof(key) != TYPE_NIL and key != "" and type_str.begins_with("UnityEngine"):
				if not eo.has(type_key):
					eo[type_key] = {}.duplicate()
				eo[type_key][key] = val
		return eo


class UnityModelImporter extends UnityAssetImporter:

	var addCollider: bool:
		get:
			return keys.get("meshes").get("addCollider") == 1

	func get_animation_clips() -> Array:
		var unityClips = keys.get("animations").get("clipAnimations", [])
		var outClips = [].duplicate()
		for unityClip in unityClips:
			var clip = {}.duplicate()
			outClips.push_back(clip)
			clip["name"] = unityClip.get("name", "")
			clip["start_frame"] = unityClip.get("firstFrame", 0.0)
			clip["end_frame"] = unityClip.get("lastFrame", 0.0)
			# "loop" also exists but appears to be unused at least
			clip["loops"] = unityClip.get("loopTime", 0) != 0
			# TODO: Root motion?
			#cycleOffset: -0
			#loop: 0
			#hasAdditiveReferencePose: 0
			#loopTime: 1
			#loopBlend: 1
			#loopBlendOrientation: 0
			#loopBlendPositionY: 1
			#loopBlendPositionXZ: 0
			#keepOriginalOrientation: 0
			#keepOriginalPositionY: 0
			#keepOriginalPositionXZ: 0
			# TODO: Humanoid retargeting?
			# humanDescription:
			#   serializedVersion: 2
			#   human:
			#   - boneName: RightUpLeg
			#     humanName: RightUpperLeg
		return outClips

	var meshes_light_baking: int:
		get:
			# Godot uses: Disabled,Dynamic,Static,StaticLightmaps
			# 2 = Static (defauylt setting)
			# 3 = StaticLightmaps
			return keys.get("meshes").get("generateSecondaryUV", 0) + 2

	# The following parameters have special meaning when importing FBX files and do not map one-to-one with godot importer.
	var useFileScale: bool:
		get:
			return keys.get("meshes").get("useFileScale", 0) == 1

	var extractLegacyMaterials: bool:
		get:
			return keys.get("materials").get("materialLocation", 0) == 0

	var globalScale: float:
		get:
			return keys.get("meshes").get("globalScale", 1)

	var animation_import: bool:
		# legacyGenerateAnimations = 4 ??
		# animationType = 3 ??
		get:
			return (keys.get("importAnimation") and
				keys.get("animationType") != 0)

	var fileIDToRecycleName: Dictionary:
		get:
			return keys.get("fileIDToRecycleName", {})

	# 0: No compression; 1: keyframe reduction; 2: keyframe reduction and compress
	# 3: all of the above and choose best curve for runtime memory.
	func animation_optimizer_settings() -> Dictionary:
		var rotError: float = keys.get("animations").get("animationRotationError", 0.5) # Degrees
		var rotErrorHalfRevs: float = rotError / 180 # p_alowed_angular_err is defined this way (divides by PI)
		return {
			"enabled": keys.get("animations").get("animationCompression") != 0,
			"max_linear_error": keys.get("animations").get("animationPositionError", 0.5),
			"max_angular_error": rotErrorHalfRevs, # Godot defaults this value to 
		}

	func get_main_object_id() -> int:
		return 100100000 # a model is a type of Prefab

class UnityShaderImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		return 4800000 # Shader

class UnityTextureImporter extends UnityAssetImporter:
	var textureShape: int:
		get:
			# 1: Texture2D
			# 2: Cubemap
			# 3: Texture2DArray (Unity 2020)
			# 4: Texture3D (Unity 2020)
			return keys.get("textureShape", 0) # Some old files do not have this

	# TODO: implement textureType. Currently unused
	var textureType: int:
		get:
			# -1: Unknown
			# 0: Default
			# 1: NormalMap
			# 2: GUI
			# 3: Sprite
			# ...
			# bumpmap.convertToNormalMap?
			return keys.get("textureType", 0)

	func get_main_object_id() -> int:
		match textureShape:
			0, 1:
				return 2800000 # "Texture2D",
			2:
				return 8900000 # "Cubemap",
			3:
				return 18700000 # "Texture2DArray",
			4:
				return 11700000 # "Texture3D",
			_:
				return 0

class UnityTrueTypeFontImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		return 12800000 # Font

class UnityNativeFormatImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		return keys.get("mainObjectFileID", 0)

class UnityPrefabImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		# PrefabInstance is 1001. Multiply by 100000 to create default ID.
		return 100100000 # Always should be this ID.

class UnityTextScriptImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		return 4900000 # TextAsset

class UnityAudioImporter extends UnityAssetImporter:
	func get_main_object_id() -> int:
		return 8300000 # AudioClip

class UnityDefaultImporter extends UnityAssetImporter:
	# Will depend on filetype or file extension?
	# Check file extension from `meta.path`???
	func get_main_object_id() -> int:
		match meta.path.get_extension():
			"unity":
				# Scene file.
				# 1: OcclusionCullingSettings (29),
				# 2: RenderSettings (104),
				# 3: LightmapSettings (157),
				# 4: NavMeshSettings (196),
				# We choose 1 to represent the default id, but there is no actual root node.
				return 1
			"txt", "html", "htm", "xml", "bytes", "json", "csv", "yaml", "fnt":
				# Supported file extensions for text (.bytes is special)
				return 4900000 # TextAsset
			_:
				# Folder, or unsupported type.
				return 102900000 # DefaultAsset

class DiscardUnityComponent extends UnityComponent:
	func create_godot_node(state: RefCounted, new_parent: Node) -> Node:
		return null

var _type_dictionary: Dictionary = {
	# "AimConstraint": UnityAimConstraint,
	# "AnchoredJoint2D": UnityAnchoredJoint2D,
	# "Animation": UnityAnimation,
	"AnimationClip": UnityAnimationClip,
	# "Animator": UnityAnimator,
	# "AnimatorController": UnityAnimatorController,
	# "AnimatorOverrideController": UnityAnimatorOverrideController,
	# "AnimatorState": UnityAnimatorState,
	# "AnimatorStateMachine": UnityAnimatorStateMachine,
	# "AnimatorStateTransition": UnityAnimatorStateTransition,
	# "AnimatorTransition": UnityAnimatorTransition,
	# "AnimatorTransitionBase": UnityAnimatorTransitionBase,
	# "AnnotationManager": UnityAnnotationManager,
	# "AreaEffector2D": UnityAreaEffector2D,
	# "AssemblyDefinitionAsset": UnityAssemblyDefinitionAsset,
	# "AssemblyDefinitionImporter": UnityAssemblyDefinitionImporter,
	# "AssemblyDefinitionReferenceAsset": UnityAssemblyDefinitionReferenceAsset,
	# "AssemblyDefinitionReferenceImporter": UnityAssemblyDefinitionReferenceImporter,
	# "AssetBundle": UnityAssetBundle,
	# "AssetBundleManifest": UnityAssetBundleManifest,
	# "AssetDatabaseV1": UnityAssetDatabaseV1,
	"AssetImporter": UnityAssetImporter,
	# "AssetImporterLog": UnityAssetImporterLog,
	# "AssetImportInProgressProxy": UnityAssetImportInProgressProxy,
	# "AssetMetaData": UnityAssetMetaData,
	# "AudioBehaviour": UnityAudioBehaviour,
	# "AudioBuildInfo": UnityAudioBuildInfo,
	# "AudioChorusFilter": UnityAudioChorusFilter,
	# "AudioClip": UnityAudioClip,
	# "AudioDistortionFilter": UnityAudioDistortionFilter,
	# "AudioEchoFilter": UnityAudioEchoFilter,
	# "AudioFilter": UnityAudioFilter,
	# "AudioHighPassFilter": UnityAudioHighPassFilter,
	"AudioImporter": UnityAudioImporter,
	"AudioListener": DiscardUnityComponent,
	# "AudioLowPassFilter": UnityAudioLowPassFilter,
	# "AudioManager": UnityAudioManager,
	# "AudioMixer": UnityAudioMixer,
	# "AudioMixerController": UnityAudioMixerController,
	# "AudioMixerEffectController": UnityAudioMixerEffectController,
	# "AudioMixerGroup": UnityAudioMixerGroup,
	# "AudioMixerGroupController": UnityAudioMixerGroupController,
	# "AudioMixerLiveUpdateBool": UnityAudioMixerLiveUpdateBool,
	# "AudioMixerLiveUpdateFloat": UnityAudioMixerLiveUpdateFloat,
	# "AudioMixerSnapshot": UnityAudioMixerSnapshot,
	# "AudioMixerSnapshotController": UnityAudioMixerSnapshotController,
	# "AudioReverbFilter": UnityAudioReverbFilter,
	# "AudioReverbZone": UnityAudioReverbZone,
	"AudioSource": UnityAudioSource,
	# "Avatar": UnityAvatar,
	# "AvatarMask": UnityAvatarMask,
	# "BaseAnimationTrack": UnityBaseAnimationTrack,
	# "BaseVideoTexture": UnityBaseVideoTexture,
	"Behaviour": UnityBehaviour,
	# "BillboardAsset": UnityBillboardAsset,
	# "BillboardRenderer": UnityBillboardRenderer,
	# "BlendTree": UnityBlendTree,
	"BoxCollider": UnityBoxCollider,
	# "BoxCollider2D": UnityBoxCollider2D,
	# "BuildReport": UnityBuildReport,
	# "BuildSettings": UnityBuildSettings,
	# "BuiltAssetBundleInfoSet": UnityBuiltAssetBundleInfoSet,
	# "BuoyancyEffector2D": UnityBuoyancyEffector2D,
	# "CachedSpriteAtlas": UnityCachedSpriteAtlas,
	# "CachedSpriteAtlasRuntimeData": UnityCachedSpriteAtlasRuntimeData,
	"Camera": UnityCamera,
	# "Canvas": UnityCanvas,
	# "CanvasGroup": UnityCanvasGroup,
	# "CanvasRenderer": UnityCanvasRenderer,
	"CapsuleCollider": UnityCapsuleCollider,
	# "CapsuleCollider2D": UnityCapsuleCollider2D,
	# "CGProgram": UnityCGProgram,
	# "CharacterController": UnityCharacterController,
	# "CharacterJoint": UnityCharacterJoint,
	# "CircleCollider2D": UnityCircleCollider2D,
	"Cloth": UnityCloth,
	# "ClusterInputManager": UnityClusterInputManager,
	"Collider": UnityCollider,
	# "Collider2D": UnityCollider2D,
	# "Collision": UnityCollision,
	# "Collision2D": UnityCollision2D,
	"Component": UnityComponent,
	# "CompositeCollider2D": UnityCompositeCollider2D,
	# "ComputeShader": UnityComputeShader,
	# "ComputeShaderImporter": UnityComputeShaderImporter,
	# "ConfigurableJoint": UnityConfigurableJoint,
	# "ConstantForce": UnityConstantForce,
	# "ConstantForce2D": UnityConstantForce2D,
	"Cubemap": UnityCubemap,
	"CubemapArray": UnityCubemapArray,
	"CustomRenderTexture": UnityCustomRenderTexture,
	# "DefaultAsset": UnityDefaultAsset,
	"DefaultImporter": UnityDefaultImporter,
	# "DelayedCallManager": UnityDelayedCallManager,
	# "Derived": UnityDerived,
	# "DistanceJoint2D": UnityDistanceJoint2D,
	# "EdgeCollider2D": UnityEdgeCollider2D,
	# "EditorBuildSettings": UnityEditorBuildSettings,
	# "EditorExtension": UnityEditorExtension,
	# "EditorExtensionImpl": UnityEditorExtensionImpl,
	# "EditorProjectAccess": UnityEditorProjectAccess,
	# "EditorSettings": UnityEditorSettings,
	# "EditorUserBuildSettings": UnityEditorUserBuildSettings,
	# "EditorUserSettings": UnityEditorUserSettings,
	# "Effector2D": UnityEffector2D,
	# "EmptyObject": UnityEmptyObject,
	# "FakeComponent": UnityFakeComponent,
	# "FBXImporter": UnityFBXImporter,
	# "FixedJoint": UnityFixedJoint,
	# "FixedJoint2D": UnityFixedJoint2D,
	# "Flare": UnityFlare,
	"FlareLayer": DiscardUnityComponent,
	# "float": Unityfloat,
	# "Font": UnityFont,
	# "FrictionJoint2D": UnityFrictionJoint2D,
	# "GameManager": UnityGameManager,
	"GameObject": UnityGameObject,
	# "GameObjectRecorder": UnityGameObjectRecorder,
	# "GlobalGameManager": UnityGlobalGameManager,
	# "GraphicsSettings": UnityGraphicsSettings,
	# "Grid": UnityGrid,
	# "GridLayout": UnityGridLayout,
	# "Halo": UnityHalo,
	"HaloLayer": DiscardUnityComponent,
	# "HierarchyState": UnityHierarchyState,
	# "HingeJoint": UnityHingeJoint,
	# "HingeJoint2D": UnityHingeJoint2D,
	# "HumanTemplate": UnityHumanTemplate,
	# "IConstraint": UnityIConstraint,
	# "IHVImageFormatImporter": UnityIHVImageFormatImporter,
	# "InputManager": UnityInputManager,
	# "InspectorExpandedState": UnityInspectorExpandedState,
	# "Joint": UnityJoint,
	# "Joint2D": UnityJoint2D,
	# "LensFlare": UnityLensFlare,
	# "LevelGameManager": UnityLevelGameManager,
	# "LibraryAssetImporter": UnityLibraryAssetImporter,
	"Light": UnityLight,
	# "LightingDataAsset": UnityLightingDataAsset,
	# "LightingDataAssetParent": UnityLightingDataAssetParent,
	# "LightmapParameters": UnityLightmapParameters,
	"LightmapSettings": DiscardUnityComponent,
	"LightProbeGroup": UnityLightProbeGroup,
	# "LightProbeProxyVolume": UnityLightProbeProxyVolume,
	# "LightProbes": UnityLightProbes,
	# "LineRenderer": UnityLineRenderer,
	# "LocalizationAsset": UnityLocalizationAsset,
	# "LocalizationImporter": UnityLocalizationImporter,
	# "LODGroup": UnityLODGroup,
	# "LookAtConstraint": UnityLookAtConstraint,
	# "LowerResBlitTexture": UnityLowerResBlitTexture,
	"Material": UnityMaterial,
	"Mesh": UnityMesh,
	# "Mesh3DSImporter": UnityMesh3DSImporter,
	"MeshCollider": UnityMeshCollider,
	"MeshFilter": UnityMeshFilter,
	"MeshRenderer": UnityMeshRenderer,
	"ModelImporter": UnityModelImporter,
	"MonoBehaviour": UnityMonoBehaviour,
	# "MonoImporter": UnityMonoImporter,
	# "MonoManager": UnityMonoManager,
	# "MonoObject": UnityMonoObject,
	# "MonoScript": UnityMonoScript,
	# "Motion": UnityMotion,
	# "NamedObject": UnityNamedObject,
	"NativeFormatImporter": UnityNativeFormatImporter,
	# "NativeObjectType": UnityNativeObjectType,
	# "NavMeshAgent": UnityNavMeshAgent,
	# "NavMeshData": UnityNavMeshData,
	# "NavMeshObstacle": UnityNavMeshObstacle,
	# "NavMeshProjectSettings": UnityNavMeshProjectSettings,
	"NavMeshSettings": DiscardUnityComponent,
	# "NewAnimationTrack": UnityNewAnimationTrack,
	"Object": UnityObject,
	# "OcclusionArea": UnityOcclusionArea,
	# "OcclusionCullingData": UnityOcclusionCullingData,
	"OcclusionCullingSettings": DiscardUnityComponent,
	# "OcclusionPortal": UnityOcclusionPortal,
	# "OffMeshLink": UnityOffMeshLink,
	# "PackageManifest": UnityPackageManifest,
	# "PackageManifestImporter": UnityPackageManifestImporter,
	# "PackedAssets": UnityPackedAssets,
	# "ParentConstraint": UnityParentConstraint,
	# "ParticleSystem": UnityParticleSystem,
	# "ParticleSystemForceField": UnityParticleSystemForceField,
	# "ParticleSystemRenderer": UnityParticleSystemRenderer,
	# "PhysicMaterial": UnityPhysicMaterial,
	# "Physics2DSettings": UnityPhysics2DSettings,
	# "PhysicsManager": UnityPhysicsManager,
	# "PhysicsMaterial2D": UnityPhysicsMaterial2D,
	# "PhysicsUpdateBehaviour2D": UnityPhysicsUpdateBehaviour2D,
	# "PlatformEffector2D": UnityPlatformEffector2D,
	# "PlatformModuleSetup": UnityPlatformModuleSetup,
	# "PlayableDirector": UnityPlayableDirector,
	# "PlayerSettings": UnityPlayerSettings,
	# "PluginBuildInfo": UnityPluginBuildInfo,
	# "PluginImporter": UnityPluginImporter,
	# "PointEffector2D": UnityPointEffector2D,
	# "Polygon2D": UnityPolygon2D,
	# "PolygonCollider2D": UnityPolygonCollider2D,
	# "PositionConstraint": UnityPositionConstraint,
	"Prefab": UnityPrefabLegacyUnused,
	"PrefabImporter": UnityPrefabImporter,
	"PrefabInstance": UnityPrefabInstance,
	# "PreloadData": UnityPreloadData,
	# "Preset": UnityPreset,
	# "PresetManager": UnityPresetManager,
	# "Projector": UnityProjector,
	# "QualitySettings": UnityQualitySettings,
	# "RayTracingShader": UnityRayTracingShader,
	# "RayTracingShaderImporter": UnityRayTracingShaderImporter,
	"RectTransform": UnityRectTransform,
	# "ReferencesArtifactGenerator": UnityReferencesArtifactGenerator,
	"ReflectionProbe": UnityReflectionProbe,
	# "RelativeJoint2D": UnityRelativeJoint2D,
	"Renderer": UnityRenderer,
	# "RendererFake": UnityRendererFake,
	"RenderSettings": DiscardUnityComponent,
	"RenderTexture": UnityRenderTexture,
	# "ResourceManager": UnityResourceManager,
	"Rigidbody": UnityRigidbody,
	# "Rigidbody2D": UnityRigidbody2D,
	# "RootMotionData": UnityRootMotionData,
	# "RotationConstraint": UnityRotationConstraint,
	# "RuntimeAnimatorController": UnityRuntimeAnimatorController,
	# "RuntimeInitializeOnLoadManager": UnityRuntimeInitializeOnLoadManager,
	# "SampleClip": UnitySampleClip,
	# "ScaleConstraint": UnityScaleConstraint,
	# "SceneAsset": UnitySceneAsset,
	# "SceneVisibilityState": UnitySceneVisibilityState,
	# "ScriptedImporter": UnityScriptedImporter,
	# "ScriptMapper": UnityScriptMapper,
	# "SerializableManagedHost": UnitySerializableManagedHost,
	# "Shader": UnityShader,
	"ShaderImporter": UnityShaderImporter,
	# "ShaderVariantCollection": UnityShaderVariantCollection,
	# "SiblingDerived": UnitySiblingDerived,
	# "SketchUpImporter": UnitySketchUpImporter,
	"SkinnedMeshRenderer": UnitySkinnedMeshRenderer,
	# "Skybox": UnitySkybox,
	# "SliderJoint2D": UnitySliderJoint2D,
	# "SortingGroup": UnitySortingGroup,
	# "SparseTexture": UnitySparseTexture,
	# "SpeedTreeImporter": UnitySpeedTreeImporter,
	# "SpeedTreeWindAsset": UnitySpeedTreeWindAsset,
	"SphereCollider": UnitySphereCollider,
	# "SpringJoint": UnitySpringJoint,
	# "SpringJoint2D": UnitySpringJoint2D,
	# "Sprite": UnitySprite,
	# "SpriteAtlas": UnitySpriteAtlas,
	# "SpriteAtlasDatabase": UnitySpriteAtlasDatabase,
	# "SpriteMask": UnitySpriteMask,
	# "SpriteRenderer": UnitySpriteRenderer,
	# "SpriteShapeRenderer": UnitySpriteShapeRenderer,
	# "StreamingController": UnityStreamingController,
	# "StreamingManager": UnityStreamingManager,
	# "SubDerived": UnitySubDerived,
	# "SubstanceArchive": UnitySubstanceArchive,
	# "SubstanceImporter": UnitySubstanceImporter,
	# "SurfaceEffector2D": UnitySurfaceEffector2D,
	# "TagManager": UnityTagManager,
	# "TargetJoint2D": UnityTargetJoint2D,
	# "Terrain": UnityTerrain,
	# "TerrainCollider": UnityTerrainCollider,
	# "TerrainData": UnityTerrainData,
	# "TerrainLayer": UnityTerrainLayer,
	# "TextAsset": UnityTextAsset,
	# "TextMesh": UnityTextMesh,
	"TextScriptImporter": UnityTextScriptImporter,
	"Texture": UnityTexture,
	"Texture2D": UnityTexture2D,
	"Texture2DArray": UnityTexture2DArray,
	"Texture3D": UnityTexture3D,
	"TextureImporter": UnityTextureImporter,
	# "Tilemap": UnityTilemap,
	# "TilemapCollider2D": UnityTilemapCollider2D,
	# "TilemapRenderer": UnityTilemapRenderer,
	# "TimeManager": UnityTimeManager,
	# "TrailRenderer": UnityTrailRenderer,
	"Transform": UnityTransform,
	# "Tree": UnityTree,
	"TrueTypeFontImporter": UnityTrueTypeFontImporter,
	# "UnityConnectSettings": UnityUnityConnectSettings,
	# "Vector3f": UnityVector3f,
	# "VFXManager": UnityVFXManager,
	# "VFXRenderer": UnityVFXRenderer,
	# "VideoClip": UnityVideoClip,
	# "VideoClipImporter": UnityVideoClipImporter,
	# "VideoPlayer": UnityVideoPlayer,
	# "VisualEffect": UnityVisualEffect,
	# "VisualEffectAsset": UnityVisualEffectAsset,
	# "VisualEffectImporter": UnityVisualEffectImporter,
	# "VisualEffectObject": UnityVisualEffectObject,
	# "VisualEffectResource": UnityVisualEffectResource,
	# "VisualEffectSubgraph": UnityVisualEffectSubgraph,
	# "VisualEffectSubgraphBlock": UnityVisualEffectSubgraphBlock,
	# "VisualEffectSubgraphOperator": UnityVisualEffectSubgraphOperator,
	# "WebCamTexture": UnityWebCamTexture,
	# "WheelCollider": UnityWheelCollider,
	# "WheelJoint2D": UnityWheelJoint2D,
	# "WindZone": UnityWindZone,
	# "WorldAnchor": UnityWorldAnchor,
}

var utype_to_classname = {
	0: "Object",
	1: "GameObject",
	2: "Component",
	3: "LevelGameManager",
	4: "Transform",
	5: "TimeManager",
	6: "GlobalGameManager",
	8: "Behaviour",
	9: "GameManager",
	11: "AudioManager",
	13: "InputManager",
	18: "EditorExtension",
	19: "Physics2DSettings",
	20: "Camera",
	21: "Material",
	23: "MeshRenderer",
	25: "Renderer",
	27: "Texture",
	28: "Texture2D",
	29: "OcclusionCullingSettings",
	30: "GraphicsSettings",
	33: "MeshFilter",
	41: "OcclusionPortal",
	43: "Mesh",
	45: "Skybox",
	47: "QualitySettings",
	48: "Shader",
	49: "TextAsset",
	50: "Rigidbody2D",
	53: "Collider2D",
	54: "Rigidbody",
	55: "PhysicsManager",
	56: "Collider",
	57: "Joint",
	58: "CircleCollider2D",
	59: "HingeJoint",
	60: "PolygonCollider2D",
	61: "BoxCollider2D",
	62: "PhysicsMaterial2D",
	64: "MeshCollider",
	65: "BoxCollider",
	66: "CompositeCollider2D",
	68: "EdgeCollider2D",
	70: "CapsuleCollider2D",
	72: "ComputeShader",
	74: "AnimationClip",
	75: "ConstantForce",
	78: "TagManager",
	81: "AudioListener",
	82: "AudioSource",
	83: "AudioClip",
	84: "RenderTexture",
	86: "CustomRenderTexture",
	89: "Cubemap",
	90: "Avatar",
	91: "AnimatorController",
	93: "RuntimeAnimatorController",
	94: "ScriptMapper",
	95: "Animator",
	96: "TrailRenderer",
	98: "DelayedCallManager",
	102: "TextMesh",
	104: "RenderSettings",
	108: "Light",
	109: "CGProgram",
	110: "BaseAnimationTrack",
	111: "Animation",
	114: "MonoBehaviour",
	115: "MonoScript",
	116: "MonoManager",
	117: "Texture3D",
	118: "NewAnimationTrack",
	119: "Projector",
	120: "LineRenderer",
	121: "Flare",
	122: "Halo",
	123: "LensFlare",
	124: "FlareLayer",
	125: "HaloLayer",
	126: "NavMeshProjectSettings",
	128: "Font",
	129: "PlayerSettings",
	130: "NamedObject",
	134: "PhysicMaterial",
	135: "SphereCollider",
	136: "CapsuleCollider",
	137: "SkinnedMeshRenderer",
	138: "FixedJoint",
	141: "BuildSettings",
	142: "AssetBundle",
	143: "CharacterController",
	144: "CharacterJoint",
	145: "SpringJoint",
	146: "WheelCollider",
	147: "ResourceManager",
	150: "PreloadData",
	153: "ConfigurableJoint",
	154: "TerrainCollider",
	156: "TerrainData",
	157: "LightmapSettings",
	158: "WebCamTexture",
	159: "EditorSettings",
	162: "EditorUserSettings",
	164: "AudioReverbFilter",
	165: "AudioHighPassFilter",
	166: "AudioChorusFilter",
	167: "AudioReverbZone",
	168: "AudioEchoFilter",
	169: "AudioLowPassFilter",
	170: "AudioDistortionFilter",
	171: "SparseTexture",
	180: "AudioBehaviour",
	181: "AudioFilter",
	182: "WindZone",
	183: "Cloth",
	184: "SubstanceArchive",
	185: "ProceduralMaterial",
	186: "ProceduralTexture",
	187: "Texture2DArray",
	188: "CubemapArray",
	191: "OffMeshLink",
	192: "OcclusionArea",
	193: "Tree",
	195: "NavMeshAgent",
	196: "NavMeshSettings",
	198: "ParticleSystem",
	199: "ParticleSystemRenderer",
	200: "ShaderVariantCollection",
	205: "LODGroup",
	206: "BlendTree",
	207: "Motion",
	208: "NavMeshObstacle",
	210: "SortingGroup",
	212: "SpriteRenderer",
	213: "Sprite",
	214: "CachedSpriteAtlas",
	215: "ReflectionProbe",
	218: "Terrain",
	220: "LightProbeGroup",
	221: "AnimatorOverrideController",
	222: "CanvasRenderer",
	223: "Canvas",
	224: "RectTransform",
	225: "CanvasGroup",
	226: "BillboardAsset",
	227: "BillboardRenderer",
	228: "SpeedTreeWindAsset",
	229: "AnchoredJoint2D",
	230: "Joint2D",
	231: "SpringJoint2D",
	232: "DistanceJoint2D",
	233: "HingeJoint2D",
	234: "SliderJoint2D",
	235: "WheelJoint2D",
	236: "ClusterInputManager",
	237: "BaseVideoTexture",
	238: "NavMeshData",
	240: "AudioMixer",
	241: "AudioMixerController",
	243: "AudioMixerGroupController",
	244: "AudioMixerEffectController",
	245: "AudioMixerSnapshotController",
	246: "PhysicsUpdateBehaviour2D",
	247: "ConstantForce2D",
	248: "Effector2D",
	249: "AreaEffector2D",
	250: "PointEffector2D",
	251: "PlatformEffector2D",
	252: "SurfaceEffector2D",
	253: "BuoyancyEffector2D",
	254: "RelativeJoint2D",
	255: "FixedJoint2D",
	256: "FrictionJoint2D",
	257: "TargetJoint2D",
	258: "LightProbes",
	259: "LightProbeProxyVolume",
	271: "SampleClip",
	272: "AudioMixerSnapshot",
	273: "AudioMixerGroup",
	290: "AssetBundleManifest",
	300: "RuntimeInitializeOnLoadManager",
	310: "UnityConnectSettings",
	319: "AvatarMask",
	320: "PlayableDirector",
	328: "VideoPlayer",
	329: "VideoClip",
	330: "ParticleSystemForceField",
	331: "SpriteMask",
	362: "WorldAnchor",
	363: "OcclusionCullingData",
	1001: "PrefabInstance",
	1002: "EditorExtensionImpl",
	1003: "AssetImporter",
	1004: "AssetDatabaseV1",
	1005: "Mesh3DSImporter",
	1006: "TextureImporter",
	1007: "ShaderImporter",
	1008: "ComputeShaderImporter",
	1020: "AudioImporter",
	1026: "HierarchyState",
	1028: "AssetMetaData",
	1029: "DefaultAsset",
	1030: "DefaultImporter",
	1031: "TextScriptImporter",
	1032: "SceneAsset",
	1034: "NativeFormatImporter",
	1035: "MonoImporter",
	1038: "LibraryAssetImporter",
	1040: "ModelImporter",
	1041: "FBXImporter",
	1042: "TrueTypeFontImporter",
	1045: "EditorBuildSettings",
	1048: "InspectorExpandedState",
	1049: "AnnotationManager",
	1050: "PluginImporter",
	1051: "EditorUserBuildSettings",
	1055: "IHVImageFormatImporter",
	1101: "AnimatorStateTransition",
	1102: "AnimatorState",
	1105: "HumanTemplate",
	1107: "AnimatorStateMachine",
	1108: "PreviewAnimationClip",
	1109: "AnimatorTransition",
	1110: "SpeedTreeImporter",
	1111: "AnimatorTransitionBase",
	1112: "SubstanceImporter",
	1113: "LightmapParameters",
	1120: "LightingDataAsset",
	1124: "SketchUpImporter",
	1125: "BuildReport",
	1126: "PackedAssets",
	1127: "VideoClipImporter",
	100000: "int",
	100001: "bool",
	100002: "float",
	100003: "MonoObject",
	100004: "Collision",
	100005: "Vector3f",
	100006: "RootMotionData",
	100007: "Collision2D",
	100008: "AudioMixerLiveUpdateFloat",
	100009: "AudioMixerLiveUpdateBool",
	100010: "Polygon2D",
	100011: "void",
	19719996: "TilemapCollider2D",
	41386430: "AssetImporterLog",
	73398921: "VFXRenderer",
	156049354: "Grid",
	181963792: "Preset",
	277625683: "EmptyObject",
	285090594: "IConstraint",
	294290339: "AssemblyDefinitionReferenceImporter",
	334799969: "SiblingDerived",
	367388927: "SubDerived",
	369655926: "AssetImportInProgressProxy",
	382020655: "PluginBuildInfo",
	426301858: "EditorProjectAccess",
	468431735: "PrefabImporter",
	483693784: "TilemapRenderer",
	638013454: "SpriteAtlasDatabase",
	641289076: "AudioBuildInfo",
	644342135: "CachedSpriteAtlasRuntimeData",
	646504946: "RendererFake",
	662584278: "AssemblyDefinitionReferenceAsset",
	668709126: "BuiltAssetBundleInfoSet",
	687078895: "SpriteAtlas",
	747330370: "RayTracingShaderImporter",
	825902497: "RayTracingShader",
	877146078: "PlatformModuleSetup",
	895512359: "AimConstraint",
	937362698: "VFXManager",
	994735392: "VisualEffectSubgraph",
	994735403: "VisualEffectSubgraphOperator",
	994735404: "VisualEffectSubgraphBlock",
	1001480554: "Prefab",
	1027052791: "LocalizationImporter",
	1091556383: "Derived",
	1114811875: "ReferencesArtifactGenerator",
	1152215463: "AssemblyDefinitionAsset",
	1154873562: "SceneVisibilityState",
	1183024399: "LookAtConstraint",
	1268269756: "GameObjectRecorder",
	1325145578: "LightingDataAssetParent",
	1386491679: "PresetManager",
	1403656975: "StreamingManager",
	1480428607: "LowerResBlitTexture",
	1542919678: "StreamingController",
	1742807556: "GridLayout",
	1766753193: "AssemblyDefinitionImporter",
	1773428102: "ParentConstraint",
	1803986026: "FakeComponent",
	1818360608: "PositionConstraint",
	1818360609: "RotationConstraint",
	1818360610: "ScaleConstraint",
	1839735485: "Tilemap",
	1896753125: "PackageManifest",
	1896753126: "PackageManifestImporter",
	1953259897: "TerrainLayer",
	1971053207: "SpriteShapeRenderer",
	1977754360: "NativeObjectType",
	1995898324: "SerializableManagedHost",
	2058629509: "VisualEffectAsset",
	2058629510: "VisualEffectImporter",
	2058629511: "VisualEffectResource",
	2059678085: "VisualEffectObject",
	2083052967: "VisualEffect",
	2083778819: "LocalizationAsset",
	208985858483: "ScriptedImporter",
}

func invert_hashtable(ht: Dictionary) -> Dictionary:
	var outd: Dictionary = Dictionary()
	for key in ht:
		outd[ht[key]] = key
	return outd

var classname_to_utype: Dictionary = invert_hashtable(utype_to_classname)
