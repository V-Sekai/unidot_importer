# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

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

const aligned_byte_buffer: GDScript = preload("./aligned_byte_buffer.gd")
const monoscript: GDScript = preload("./monoscript.gd")
const anim_tree_runtime: GDScript = preload("./runtime/anim_tree.gd")
const human_trait = preload("./humanoid/human_trait.gd")
const humanoid_transform_util = preload("./humanoid/transform_util.gd")
const unidot_utils_class = preload("./unidot_utils.gd")

var unidot_utils = unidot_utils_class.new()

const ANIMATION_TREE_ACTIVE = true # false # Set to false to debug or avoid auto-playing animations

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
	"typelessdata": 1,  # Mesh m_VertexData; Texture image data
	"m_IndexBuffer": 1,
	"Hash": 1,
}


func to_classname(utype: Variant) -> String:
	if typeof(utype) == TYPE_NODE_PATH:
		return str(utype)
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
			meta.log_warn(fileID, "Mismatched type:" + type + " vs. utype:" + str(utype) + ":" + actual_type)
	if _type_dictionary.has(actual_type):
		# meta.log_debug(fileID, "Will instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		ret = _type_dictionary[actual_type].new()
	else:
		meta.log_fail(fileID, "Failed to instantiate object of type " + str(actual_type) + "/" + str(type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		if type.ends_with("Importer"):
			ret = UnityAssetImporter.new()
		else:
			ret = UnityObject.new()
	ret.meta = meta
	ret.adapter = self
	ret.fileID = fileID
	if utype != 0 and utype != classname_to_utype.get(actual_type, utype):
		meta.log_warn(fileID, "Mismatched utype " + str(utype) + " for " + type)
	ret.utype = classname_to_utype.get(actual_type, utype)
	ret.type = actual_type
	return ret


func instantiate_unity_object_from_utype(meta: Object, fileID: int, utype: int) -> UnityObject:
	var ret: UnityObject = null
	if not utype_to_classname.has(utype):
		meta.log_fail(fileID, "Unknown utype " + str(utype))
		return
	var actual_type: String = utype_to_classname[utype]
	if _type_dictionary.has(actual_type):
		ret = _type_dictionary[actual_type].new()
	else:
		meta.log_fail(fileID, "Failed to instantiate object of type " + str(actual_type) + "/" + str(utype) + "/" + str(classname_to_utype.get(actual_type, utype)))
		ret = UnityObject.new()
	ret.meta = meta
	ret.adapter = self
	ret.fileID = fileID
	ret.utype = classname_to_utype.get(actual_type, utype)
	ret.type = actual_type
	return ret


# Unity types follow:
### ================ BASE OBJECT TYPE ================
class UnityObject:
	extends RefCounted
	var meta: Resource = null  # AssetMeta instance
	var keys: Dictionary = {}
	var fileID: int = 0  # Not set in .meta files
	var type: String = ""
	var utype: int = 0  # Not set in .meta files
	var _cache_uniq_key: String = ""
	var adapter: RefCounted = null  # RefCounted to containing scope.

	# Log messages related to this asset
	func log_debug(msg: String):
		meta.log_debug(self.fileID, msg)

	# Anything that is unexpected but does not necessarily imply corruption.
	# For example, successfully loaded a resource with default fileid
	func log_warn(msg: String, field: String = "", remote_ref: Variant = [null, 0, "", null]):
		if typeof(remote_ref) == TYPE_ARRAY:
			meta.log_warn(self.fileID, msg, field, remote_ref)
		elif typeof(remote_ref) == TYPE_OBJECT and remote_ref:
			meta.log_warn(self.fileID, msg, field, [null, remote_ref.fileID, remote_ref.meta.guid, 0])
		else:
			meta.log_warn(self.fileID, msg, field)

	# Anything that implies the asset will be corrupt / lost data.
	# For example, some reference or field could not be assigned.
	func log_fail(msg: String, field: String = "", remote_ref: Variant = [null, 0, "", null]):
		if typeof(remote_ref) == TYPE_ARRAY:
			meta.log_fail(self.fileID, msg, field, remote_ref)
		elif typeof(remote_ref) == TYPE_OBJECT and remote_ref:
			meta.log_fail(self.fileID, msg, field, [null, remote_ref.fileID, remote_ref.meta.guid, 0])
		else:
			meta.log_fail(self.fileID, msg, field)

	# Some components or game objects within a prefab are "stripped" dummy objects.
	# Setting the stripped flag is not required...
	# and properties of prefabbed objects seem to have no effect anyway.
	var is_stripped: bool = false

	func is_stripped_or_prefab_instance() -> bool:
		return is_stripped or is_non_stripped_prefab_reference

	var uniq_key: String:
		get:
			if _cache_uniq_key.is_empty():
				_cache_uniq_key = (str(utype) + ":" + str(keys.get("m_Name", "")) + ":" + str(meta.guid) + ":" + str(fileID))
			return _cache_uniq_key

	func _to_string() -> String:
		#return "[" + str(type) + " @" + str(fileID) + ": " + str(len(keys)) + "]" # str(keys) + "]"
		#return "[" + str(type) + " @" + str(fileID) + ": " + JSON.print(keys) + "]"
		return "[" + str(type) + " " + uniq_key + "]"

	var name: String:
		get:
			return get_name()

	func get_name() -> String:
		if fileID == meta.main_object_id:
			return meta.get_main_object_name()
		return str(keys.get("m_Name", "NO_NAME:" + uniq_key))

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

	func get_godot_type() -> String:
		return "Object"

	func get_extra_resources() -> Dictionary:
		return {}

	func get_extra_resource(fileID: int) -> Resource:
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
		var bone_idx: int = skel.find_bone(bone_name)
		if props.has("quaternion"):
			skel.set_bone_pose_rotation(bone_idx, props["quaternion"])
		if props.has("position"):
			skel.set_bone_pose_position(bone_idx, props["position"])
		if props.has("scale"):
			skel.set_bone_pose_scale(bone_idx, props["scale"])
			var signs: Vector3 = (props["scale"].sign() + Vector3(0.5,0.5,0.5)).sign()
			if not signs.is_equal_approx(Vector3.ONE) and not signs.is_equal_approx(-Vector3.ONE):
				meta.transform_fileid_to_scale_signs[fileID] = signs

	func convert_skeleton_properties(skel: Skeleton3D, bone_name: String, uprops: Dictionary):
		var props: Dictionary = self.convert_properties(skel, uprops)
		return props

	func configure_node(node: Node):
		if node == null:
			return
		var props: Dictionary = self.convert_properties(node, self.keys)
		apply_component_props(node, props)
		apply_node_props(node, props)

	# Called once per component, not per-node. Only use for things that need a reference to the component
	func apply_component_props(node: Node, props: Dictionary):
		if props.has("scale"):
			var signs: Vector3 = (props["scale"].sign() + Vector3(0.5,0.5,0.5)).sign()
			if not signs.is_equal_approx(Vector3.ONE) and not signs.is_equal_approx(-Vector3.ONE):
				meta.transform_fileid_to_scale_signs[fileID] = signs

	# Called at least once per node. Most properties are set up in this way, since nodes are affected by multiple components
	# Note that self.fileID may be pointing to a random component (or the GameObject itself) in this function.
	func apply_node_props(node: Node, props: Dictionary):
		if node is MeshInstance3D:
			self.apply_mesh_renderer_props(meta, node, props)
		log_debug(str(node.name) + ": " + str(props))

		for propname in props:
			if typeof(props.get(propname)) == TYPE_NIL:
				continue
			elif str(propname).ends_with(":x") or str(propname).ends_with(":y") or str(propname).ends_with(":z"):
				log_warn("Unexpected per-axis value property in apply_node_props " + str(propname))
			elif str(propname) == "name":
				pass  # We cannot do Name here because it will break existing NodePath of outer prefab to children.
			else:
				log_debug("SET " + str(node.name) + ":" + propname + " to " + str(props[propname]))
				var dig: Variant = node
				var dig_propnames: Array = propname.split(":")  # example: dig_propnames = ["shape", "size"]
				for prop in dig_propnames.slice(0, len(dig_propnames) - 1):
					dig = dig.get(prop)  # example: dig = CollisionShape3D
				dig.set(dig_propnames[-1], props.get(propname))

	func apply_mesh_renderer_props(meta: RefCounted, node: MeshInstance3D, props: Dictionary):
		const material_prefix: String = ":UNIDOT_PROXY:"
		log_debug("Apply mesh renderer props: " + str(props) + " / " + str(node.mesh))
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

		if props.has("_lightmap_static"):
			if props["_lightmap_static"]:
				var has_uv2: bool = false
				if node.mesh is ArrayMesh:
					var array_mesh := node.mesh as ArrayMesh
					has_uv2 = 0 != (array_mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2)
				if node.mesh is PrimitiveMesh:
					var prim_mesh := node.mesh as PrimitiveMesh
					prim_mesh.add_uv2 = true
					has_uv2 = true
				if has_uv2:
					node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				else:
					node.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			else:
				# GI_MODE_DISABLED seems buggy and ignores light probes.
				node.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

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
		return [null, 0, "", 0]

	func get_vector(uprops: Dictionary, key: String, dfl := Vector3.ZERO) -> Variant:
		if uprops.has(key):
			return uprops.get(key)
		# log_debug("key is " + str(key) + "; " + str(uprops))
		if uprops.has(key + ".x") or uprops.has(key + ".y") or uprops.has(key + ".z"):
			var xreturn: Vector3 = Vector3(uprops.get(key + ".x", dfl.x), uprops.get(key + ".y", dfl.y), uprops.get(key + ".z", dfl.z))
			# log_debug("xreturn is " + str(xreturn))
			return xreturn
		return null

	static func get_quat(uprops: Dictionary, key: String, dfl := Quaternion.IDENTITY) -> Variant:
		if uprops.has(key):
			return uprops.get(key)
		if uprops.has(key + ".x") or uprops.has(key + ".y") or uprops.has(key + ".z") or uprops.has(key + ".w"):
			return Quaternion(uprops.get(key + ".x", dfl.x), uprops.get(key + ".y", dfl.y), uprops.get(key + ".z", dfl.z), uprops.get(key + ".w", dfl.w)).normalized()
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
				#	log_debug(str(self.uniq_key) + " WITHIN " + str(self.meta.guid) + " / " + str(self.meta.path) + " keys:" + str(self.keys))
				pass  #assert (prefab_source_object[1] == 0 or prefab_instance[1] == 0)
			else:
				# Might have source object=0 if the object is a dummy / broken prefab?
				pass  # assert (prefab_source_object[1] != 0 and prefab_instance[1] != 0)
			return prefab_source_object[1] != 0 and prefab_instance[1] != 0

	func get_component_key() -> Variant:
		if self.utype == 114:
			return monoscript.convert_unityref_to_npidentifier(self.keys["m_Script"])
		return self.utype

	var children_refs: Array:
		get:
			return keys.get("m_Children")


### ================ ASSET TYPES ================
# FIXME: All of these are native Godot types. I'm not sure if these types are needed or warranted.
class UnityMesh:
	extends UnityObject

	func get_primitive_format(submesh: Dictionary) -> int:
		match submesh.get("topology", 0):
			0:
				return Mesh.PRIMITIVE_TRIANGLES
			1:
				return Mesh.PRIMITIVE_TRIANGLES  # quad meshes handled specially later
			2:
				return Mesh.PRIMITIVE_LINES
			3:
				return Mesh.PRIMITIVE_LINE_STRIP
			4:
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
			log_fail("Unity has the wrong number of vertex channels: " + str(len(unity_to_godot_mesh_channels)) + " vs " + str(len(channel_info_array)))

		for array_idx in range(len(unity_to_godot_mesh_channels)):
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
			if submesh.get("topology", 0) == 1:
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
							# assert(dimension == 4) # Unity docs says always word aligned, so I think this means it is guaranteed to be 4.
							surface_arrays[godot_array_type] = vertex_buf.formatted_uint8_subarray(format, offset, 4 * vertexCount, stream_strides[stream], 4)
							compress_flags |= ((ArrayMesh.ARRAY_CUSTOM_RGBA8_UNORM if format == FORMAT_UNORM8 else ArrayMesh.ARRAY_CUSTOM_RGBA8_SNORM) << custom_shift)
						elif format == FORMAT_FLOAT16:
							assert(dimension == 2 or dimension == 4)  # Unity docs says always word aligned, so I think this means it is guaranteed to be 2 or 4.
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
		return ".mesh.res"

	func get_vertex_data() -> RefCounted:
		return aligned_byte_buffer.new(keys.get("m_VertexData", ""))

	func get_index_data() -> RefCounted:
		return aligned_byte_buffer.new(keys.get("m_IndexBuffer", ""))


class UnityMaterial:
	extends UnityObject

	# Old:
	#    m_Colors:
	#    - _EmissionColor: {r: 0, g: 0, b: 0, a: 0}
	#    - _Color: {r: 1, g: 1, b: 1, a: 1}
	# [{_EmissionColor:Color.TRANSPARENT,_Color:Color.WHITE}]

	# New:
	#    m_Colors:
	#      data:
	#        first:
	#          name: _EmissionColor
	#        second: {r: 0, g: 0, b: 0, a: 0}
	#      data:
	#        first:
	#          name: _Color
	#        second: {r: 1, g: 1, b: 1, a: 1}
	# ...
	# [{first:{name:_EmissionColor},second:Color.TRANSPARENT},{first:{name:_Color},second:Color.WHITE}]

	func get_float_properties() -> Dictionary:
		var flts = keys.get("m_SavedProperties", {}).get("m_Floats", [])
		var ret = {}.duplicate()
		# log_debug("material floats: " + str(flts))
		for dic in flts:
			if len(dic) == 2 and dic.has("first") and dic.has("second"):
				ret[dic["first"]["name"]] = dic["second"]
			else:
				for key in dic:
					ret[key] = dic.get(key)
		return ret

	func get_color_properties() -> Dictionary:
		var cols = keys.get("m_SavedProperties", {}).get("m_Colors", [])
		var ret = {}.duplicate()
		for dic in cols:
			if len(dic) == 2 and dic.has("first") and dic.has("second"):
				ret[dic["first"]["name"]] = dic["second"]
			else:
				for key in dic:
					ret[key] = dic.get(key)
		return ret

	func get_tex_properties() -> Dictionary:
		var texs = keys.get("m_SavedProperties", {}).get("m_TexEnvs", [])
		var ret = {}.duplicate()
		for dic in texs:
			if len(dic) == 2 and dic.has("first") and dic.has("second"):
				ret[dic["first"]["name"]] = dic["second"]
			else:
				for key in dic:
					ret[key] = dic.get(key)
		return ret

	func get_texture_ref(texProperties: Dictionary, name: String) -> Array:
		var env = texProperties.get(name, {})
		return env.get("m_Texture", [null, 0, "", 0])

	func get_texture(texProperties: Dictionary, name: String) -> Texture:
		var texref: Array = get_texture_ref(texProperties, name)
		if not texref.is_empty():
			return meta.get_godot_resource(texref)
		return null

	func get_texture_scale(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var scale: Vector2 = env.get("m_Scale", Vector2(1, 1))
		return Vector3(scale.x, scale.y, 0.0)

	func get_texture_offset(texProperties: Dictionary, name: String) -> Vector3:
		var env = texProperties.get(name, {})
		var offset: Vector2 = env.get("m_Offset", Vector2(0, 0))
		return Vector3(offset.x, offset.y, 0.0)

	func get_color(colorProperties: Dictionary, name: String, dfl: Color) -> Color:
		var col: Color = colorProperties.get(name, dfl)
		return col

	func get_float(floatProperties: Dictionary, name: String, dfl: float) -> float:
		var ret: float = floatProperties.get(name, dfl)
		return ret

	func get_vector_from_color(colorProperties: Dictionary, name: String, dfl: Color) -> Plane:
		var col: Color = colorProperties.get(name, dfl)
		return Plane(Vector3(col.r, col.g, col.b), col.a)

	func get_keywords() -> Dictionary:
		var ret: Dictionary = {}.duplicate()
		var kwd = keys.get("m_ShaderKeywords", "")
		if typeof(kwd) == TYPE_STRING:
			for x in kwd.split(" "):
				ret[x] = true
		var validkws: Array = keys.get("m_ValidKeywords", [])
		for x in validkws:
			ret[str(x)] = true
		var invalidkws: Array = keys.get("m_InvalidKeywords", [])
		for x in invalidkws:
			# Keywords from before the material was switched to another shader.
			# Since we don't parse shaders, this will sometimes give the equivalent Standard shader keywords.
			ret[str(x)] = true
		return ret

	func get_godot_type() -> String:
		return "StandardMaterial3D"

	func create_godot_resource() -> Resource:  #Material:
		#log_debug("keys: " + str(keys))
		var kws = get_keywords()
		var floatProperties = get_float_properties()
		#log_debug(str(floatProperties))
		var texProperties = get_tex_properties()
		#log_debug(str(texProperties))
		var colorProperties = get_color_properties()
		#log_debug(str(colorProperties))
		var ret = StandardMaterial3D.new()
		ret.resource_name = self.name
		# FIXME: Kinda hacky since transparent stuff doesn't always draw depth in Unity
		# But it seems to workaround a problem with some materials for now.
		ret.depth_draw_mode = true  ##### BaseMaterial3D.DEPTH_DRAW_ALWAYS
		ret.albedo_color = get_color(colorProperties, "_Color", Color.WHITE)
		var albedo_textures_to_try = ["_MainTex", "_Tex", "_Albedo", "_Diffuse", "_BaseColor", "_BaseColorMap"]
		for name in texProperties:
			if albedo_textures_to_try.has(name):
				continue
			if not name.ends_with("Map"):
				albedo_textures_to_try.append(name)
		# Pick a random non-null texture property as albedo. Prefer texture slots not ending with "Map"
		for name in texProperties:
			if name == "_BumpMap" or name == "_OcclusionMap" or name == "_MetallicGlossMap" or name == "_ParallaxMap":
				continue
			if name.ends_with("ColorMap") or name.ends_with("BaseMap"):
				albedo_textures_to_try.append(name)
		for name in albedo_textures_to_try:
			var env = texProperties.get(name, {})
			var texref: Array = env.get("m_Texture", [null, 0, "", 0])
			if not texref.is_empty():
				ret.albedo_texture = meta.get_godot_resource(texref)
				if ret.albedo_texture != null:
					log_debug("Trying to get albedo from " + str(name) + ": " + str(ret.albedo_texture))
					ret.uv1_scale = get_texture_scale(texProperties, name)
					ret.uv1_offset = get_texture_offset(texProperties, name)
					break

		if ret.albedo_texture == null:
			ret.uv1_scale = get_texture_scale(texProperties, "_MainTex")
			ret.uv1_offset = get_texture_offset(texProperties, "_MainTex")

		# TODO: ORM not yet implemented.
		if true: # kws.get("_NORMALMAP", false):
			ret.normal_texture = get_texture(texProperties, "_BumpMap")
			ret.normal_scale = get_float(floatProperties, "_BumpScale", 1.0)
			if ret.normal_texture != null:
				ret.normal_enabled = true
		if kws.get("_EMISSION", false):
			var emis_vec: Plane = get_vector_from_color(colorProperties, "_EmissionColor", Color.BLACK)
			var emis_mag = max(emis_vec.x, max(emis_vec.y, emis_vec.z))
			ret.emission = Color.BLACK
			if emis_mag > 0.01:
				ret.emission_enabled = true
				ret.emission = Color(emis_vec.x / emis_mag, emis_vec.y / emis_mag, emis_vec.z / emis_mag).linear_to_srgb()
				ret.emission_energy = emis_mag
				ret.emission_texture = get_texture(texProperties, "_EmissionMap")
				if ret.emission_texture != null:
					ret.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		if true: # kws.get("_PARALLAXMAP", false):
			ret.heightmap_texture = get_texture(texProperties, "_ParallaxMap")
			if ret.heightmap_texture != null:
				ret.heightmap_enabled = true
				# Godot generated standard shader code looks something like this:
				# float depth = 1.0 - texture(texture_heightmap, base_uv).r;
				# vec2 ofs = base_uv - view_dir.xy * depth * heightmap_scale * 0.01;
				# ------
				# Note in particular the * 0.01 multiplier.
				# Unfortunately, Godot does not have a heightmap bias setting (such as 0.5)
				# Therefore, it is not possible to represent a heightmap completely accurately
				# And we must pick a direction: positive or negative. In this case I choose negative.
				# Which causes the heightmap to "pop out" of the surface.
				ret.heightmap_scale = -100.0 * get_float(floatProperties, "_Parallax", 1.0)
		if kws.get("_SPECULARHIGHLIGHTS_OFF", false):
			ret.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if kws.get("_GLOSSYREFLECTIONS_OFF", false):
			pass
		var occlusion = get_texture(texProperties, "_OcclusionMap")
		if occlusion != null:
			ret.ao_enabled = true
			ret.ao_texture = occlusion
			ret.ao_light_affect = get_float(floatProperties, "_OcclusionStrength", 1.0)  # why godot defaults to 0???
			ret.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		var metallic_texture: Texture = null
		var use_glossmap := false
		if true: # kws.get("_METALLICGLOSSMAP"):
			var metallic_gloss_texture_ref: Array = get_texture_ref(texProperties, "_MetallicGlossMap")
			if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
				metallic_gloss_texture_ref = get_texture_ref(texProperties, "_MetallicSmoothness")
			if not metallic_gloss_texture_ref.is_empty() and metallic_gloss_texture_ref[1] != 0:
				metallic_gloss_texture_ref[1] = -metallic_gloss_texture_ref[1]
				if not is_equal_approx(get_float(floatProperties, "_GlossMapScale", 1.0), 0.0):
					metallic_texture = meta.get_godot_resource(metallic_gloss_texture_ref, false)
					log_debug("Found metallic roughness texture " + str(metallic_gloss_texture_ref) + " => " + str(metallic_texture))
					use_glossmap = true
				if metallic_texture == null:
					if use_glossmap:
						log_debug("Load roughness " + str(load("res://Assets/ArchVizPRO Interior Vol.6/3D MATERIAL/Tiles_White/Tiles_White_metallic.roughness.png")))
						log_warn("Unable to load metallic roughness texture. Trying metallic gloss.", "_MetallicGlossMap", metallic_gloss_texture_ref)
					metallic_gloss_texture_ref[1] = -metallic_gloss_texture_ref[1]
					metallic_texture = meta.get_godot_resource(metallic_gloss_texture_ref)
					log_debug("Found metallic gloss texture " + str(metallic_gloss_texture_ref) + " => " + str(metallic_texture))
					use_glossmap = false
			ret.metallic_texture = metallic_texture
			ret.metallic = get_float(floatProperties, "_Metallic", 0.0)
			ret.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			if use_glossmap:
				ret.roughness_texture = metallic_texture
				ret.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
				ret.roughness = 1.0 # We scaled down the roughness in code.
		# TODO: Glossiness: invert color channels??
		if metallic_texture == null:
			# UnityStandardInput.cginc ignores _Glossiness if _METALLICGLOSSMAP.
			ret.roughness = 1.0 - get_float(floatProperties, "_Glossiness", 0.0)
		if kws.get("_ALPHATEST_ON"):
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			var cutoff: float = get_float(floatProperties, "_Cutoff", 0.0)
			if cutoff > 0.0:
				ret.alpha_scissor_threshold = cutoff
		elif kws.get("_ALPHABLEND_ON") or kws.get("_ALPHAPREMULTIPLY_ON"):
			# FIXME: No premultiply
			ret.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Godot's detail map is a bit lacking right now...
		#if kws.get("_DETAIL_MULX2"):
		#	ret.detail_enabled = true
		#	ret.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		assign_object_meta(ret)
		return ret

	func bake_roughness_texture_if_needed(tmp_path: String, guid_to_pkgasset: Dictionary, stage2_dict_lock: Mutex, stage2_extra_asset_dict: Dictionary) -> String:
		var kws = get_keywords()
		var floatProperties = get_float_properties()
		var texProperties = get_tex_properties()
		# Note that this must be pre-baked into the texture to bring it towards 1.
		# _GlossMapScale ????
		var glossiness_value: float = get_float(floatProperties, "_GlossMapScale", 1.0)
		if is_equal_approx(glossiness_value, 0.0):
			log_debug("Material has 0 _GlossMapScale")
			return "" # We can ignore the texture
		var metallic_gloss_texture_ref: Array = get_texture_ref(texProperties, "_MetallicGlossMap")
		if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
			metallic_gloss_texture_ref = get_texture_ref(texProperties, "_MetallicSmoothness")
		# Not any more: Material has _METALLICGLOSSMAP enabled.
		if metallic_gloss_texture_ref.is_empty() or metallic_gloss_texture_ref[1] == 0:
			log_debug("Material has null _MetallicGlossMap")
			# null gloss: no roughness to bake
			return ""
		log_debug("gloss map ref is " + str(metallic_gloss_texture_ref))
		#var metallic_gloss_texture = get_texture(texProperties, "_MetallicGlossMap")
		var target_meta: Object
		if not metallic_gloss_texture_ref.is_empty() and guid_to_pkgasset.has(metallic_gloss_texture_ref[2]):
			target_meta = guid_to_pkgasset[metallic_gloss_texture_ref[2]].parsed_meta
		else:
			target_meta = meta.lookup_meta(metallic_gloss_texture_ref)
		if target_meta == null:
			log_warn("Failed to lookup gloss texture ref", "_MetallicGlossMap", metallic_gloss_texture_ref)
			return ""
		target_meta.mutex.lock()
		var pathname: String = target_meta.path
		var roughness_filename = pathname.get_basename() + ".roughness.png"
		# Sometimes multiple materials reference the same roughness texture. We to avoid generating the same texture multiple times.
		stage2_dict_lock.lock()
		if stage2_extra_asset_dict.has(roughness_filename):
			stage2_dict_lock.unlock()
			target_meta.mutex.unlock()
			return ""
		stage2_extra_asset_dict[roughness_filename] = true
		stage2_dict_lock.unlock()
		var ret: String = _bake_roughness_texture_locked(tmp_path, target_meta, roughness_filename, glossiness_value, guid_to_pkgasset)
		target_meta.mutex.unlock()
		return ret

	func _bake_roughness_texture_locked(tmp_path: String, target_meta: Object, roughness_filename: String, glossiness_value: float, guid_to_pkgasset: Dictionary) -> String:
		var pathname: String = target_meta.path
		if FileAccess.file_exists(roughness_filename):
			var fa := FileAccess.open(roughness_filename, FileAccess.READ)
			if fa != null:
				if fa.get_length() > 0:
					if not target_meta.godot_resources.has(-target_meta.main_object_id):
						target_meta.insert_resource_path(-target_meta.main_object_id, "res://" + roughness_filename)
					log_debug("Roughness texture already exists. Modified " + str(target_meta.guid) + "/" + str(target_meta.path) + " godot_resources: " + str(target_meta.godot_resources))
					return "" # Nothing new to import.
		var image: Image
		if FileAccess.file_exists(tmp_path + "/" + pathname):
			image = Image.load_from_file(tmp_path + "/" + pathname)
		elif FileAccess.file_exists(pathname):
			image = Image.load_from_file(pathname)
		if image != null:
			log_debug("Texture " + str(pathname) + " exists. Loaded " + str(image))
			if image != null and image.get_width() > 0 and image.get_height() > 0:
				if not meta.internal_data.has("extra_textures"):
					meta.internal_data["extra_textures"] = {}
				meta.internal_data["extra_textures"][roughness_filename] = {
					"temp_path": tmp_path + "/" + roughness_filename,
					"source_meta_guid": target_meta.guid,
					"roughness/mode": 5,
				}
				if not FileAccess.file_exists(roughness_filename + ".import"):
					var cfile = ConfigFile.new()
					cfile.set_value("remap", "path", "unidot_default_remap_path")  # must be non-empty. hopefully ignored.
					# Make an empty "keep" importer file so it will not be imported.
					cfile.set_value("remap", "importer", "keep")
					cfile.save("res://" + roughness_filename + ".import")
					log_debug("Generated dummy roughness " + str(roughness_filename))
				if not FileAccess.file_exists(roughness_filename):
					# Make an empty file so it will be found by a scan!
					var f: FileAccess = FileAccess.open(roughness_filename, FileAccess.WRITE_READ)
					f.close()
					f = null
				else:
					log_debug("Already existing roughness " + str(roughness_filename))
				var col: Color
				for x in range(image.get_width()):
					for y in range(image.get_width()):
						col = image.get_pixel(x, y)
						col.a = 1.0 - glossiness_value * col.a
						image.set_pixel(x, y, col)
				image.save_png(tmp_path + "/" + roughness_filename)
				target_meta.insert_resource_path(-target_meta.main_object_id, "res://" + roughness_filename)
				log_debug("Roughness texture modified " + str(target_meta.guid) + "/" + str(target_meta.path) + " godot_resources: " + str(target_meta.godot_resources))
				log_debug("Generated " + str(tmp_path) + "/" + str(roughness_filename) + " " + str(image.get_size()))
				return roughness_filename
		# TODO: Glossiness: invert color channels??
		log_warn("Failed to generate roughness texture at " + str(pathname) + " from " + str(target_meta.guid), "_MetallicGlossMap", [null, target_meta.main_object_id, target_meta.guid, 0])
		return ""

	func get_godot_extension() -> String:
		return ".mat.tres"


class UnityShader:
	extends UnityObject

	func get_godot_type() -> String:
		return "Shader"

	pass


class UnityAvatar:
	extends UnityObject

	static func read_transform(xform: Dictionary) -> Transform3D:
		var translation: Vector3 = xform["t"] * Vector3(-1, 1, 1)
		var quaternion: Quaternion = xform["q"]
		quaternion.y = -quaternion.y
		quaternion.z = -quaternion.z
		var scale: Vector3 = xform["s"]
		return Transform3D(Basis(Quaternion(quaternion)).scaled(scale), translation)

	func get_godot_type() -> String:
		return "BoneMap"

	func create_godot_resource() -> Resource:
		var fileid_to_human_bone_index: Dictionary
		var fileid_to_skeleton_bone: Dictionary
		var transform_fileid_to_rotation_delta: Dictionary
		var transform_fileid_to_parent_fileid: Dictionary
		var hip_position: Vector3

		var avatar_keys = keys["m_Avatar"]
		var skeleton_size := len(avatar_keys["m_AvatarSkeleton"]["m_Node"])
		var human_size := len(avatar_keys["m_Human"]["m_Skeleton"]["m_Node"])
		var crc32_skeleton_bones_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_SkeletonNameIDArray"])
		var crc32_skeleton_bones: PackedInt32Array = crc32_skeleton_bones_buf.uint32_subarray(0, skeleton_size)

		var human_to_skeleton_bone_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_HumanSkeletonIndexArray"])
		var human_to_skeleton_bone_indices: PackedInt32Array = human_to_skeleton_bone_indices_buf.uint32_subarray(0, human_size)

		# These arrays are fixed, totaling len(human_trait.HumanBodyBones)
		var human_bone_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_HumanBoneIndex"])
		var human_bone_indices: PackedInt32Array = human_bone_indices_buf.uint32_subarray(0, 25) # 25 human bones excluding hands
		while len(human_bone_indices) < 25:
			human_bone_indices.append(-1)

		var human_left_hand_indices: PackedInt32Array
		if avatar_keys["m_Human"].get("m_HasLeftHand", 1) == 1:
			var human_left_hand_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_LeftHand"]["m_HandBoneIndex"])
			human_left_hand_indices = human_left_hand_indices_buf.uint32_subarray(0, 15) # 3 * 5 fingers
		while len(human_left_hand_indices) < 15:
			human_left_hand_indices.append(-1)
		human_bone_indices.append_array(human_left_hand_indices)

		var human_right_hand_indices: PackedInt32Array
		if avatar_keys["m_Human"].get("m_HasRightHand", 1) == 1:
			var human_right_hand_indices_buf: Variant = aligned_byte_buffer.new(avatar_keys["m_Human"]["m_RightHand"]["m_HandBoneIndex"])
			human_right_hand_indices = human_right_hand_indices_buf.uint32_subarray(0, 15) # 3 * 5 fingers
		while len(human_right_hand_indices) < 15:
			human_right_hand_indices.append(-1)
		human_bone_indices.append_array(human_right_hand_indices)

		var crc32_human_skeleton_bones: PackedInt32Array
		for unity_human_skel_index in range(human_size):
			var unity_skeleton_index: int = human_to_skeleton_bone_indices[unity_human_skel_index]
			var crc32_orig_name: int = crc32_skeleton_bones[unity_skeleton_index]
			crc32_human_skeleton_bones.append(crc32_orig_name)

		for human_mono_bone_idx in range(human_trait.BoneCount):
			var human_bone_idx: int = human_trait.boneIndexToMono[human_mono_bone_idx]
			var godot_bone_name: String = human_trait.GodotHumanNames[human_bone_idx]
			var unity_human_skel_index: int = human_bone_indices[human_mono_bone_idx]
			if unity_human_skel_index == -1:
				log_debug("Avatar: Godot bone " + godot_bone_name + " is not assigned")
				continue
			var crc32_orig_name: int = crc32_human_skeleton_bones[unity_human_skel_index]
			log_debug("Avatar: Godot bone " + godot_bone_name + " has crc " + ("%08x" % (0xffffffff&crc32_orig_name)))
			meta.humanoid_bone_map_crc32_dict[crc32_orig_name] = godot_bone_name
			# We're pretending CRC32 are fileids. These are just used temporarily to indirect into transform_fileid_to_rotation_delta
			fileid_to_skeleton_bone[crc32_orig_name] = godot_bone_name
			fileid_to_human_bone_index[crc32_orig_name] = human_bone_idx

		var human_skel_nodes: Array = avatar_keys["m_Human"]["m_Skeleton"]["m_Node"]
		var human_skel_axes: Array = avatar_keys["m_Human"]["m_Skeleton"]["m_AxesArray"]
		var root_xform: Transform3D = read_transform(avatar_keys["m_Human"]["m_RootX"])
		var hips_y: float = root_xform.origin.y
		var root_xform_delta: Transform3D = Transform3D(root_xform.basis.inverse(), Vector3(-root_xform.origin.x, 0, -root_xform.origin.z))
		for unity_human_skel_index in range(human_size):
			var crc32_orig_name: int = crc32_human_skeleton_bones[unity_human_skel_index]
			var parent_id: int = human_skel_nodes[unity_human_skel_index]["m_ParentId"]
			if parent_id > 0x7fffffff or parent_id < 0:
				parent_id = -1
			var axes_id: int = human_skel_nodes[unity_human_skel_index]["m_AxesId"]
			if axes_id > 0x7fffffff or axes_id < 0:
				axes_id = -1
			var crc32_parent_name: int = crc32_human_skeleton_bones[parent_id]
			if parent_id == -1 and axes_id == -1:
				transform_fileid_to_rotation_delta[crc32_orig_name] = root_xform_delta
			else:
				transform_fileid_to_parent_fileid[crc32_orig_name] = crc32_parent_name
				if axes_id != -1:
					if not fileid_to_human_bone_index.has(crc32_orig_name):
						log_warn("Bone hash %08x has parent %08x and axes_id=%d but missing from skeleton map" % [crc32_orig_name, crc32_parent_name, axes_id])
						continue
					var bone_index: int = fileid_to_human_bone_index[crc32_orig_name]
					var gd_postqinv: Quaternion = human_trait.postQ_inverse_exported[bone_index]
					var uni_postq: Quaternion = human_skel_axes[axes_id]["m_PostQ"]
					uni_postq.y = -uni_postq.y
					uni_postq.z = -uni_postq.z
					if bone_index != 0:
						transform_fileid_to_rotation_delta[crc32_orig_name] = root_xform_delta * Transform3D(Basis(gd_postqinv.inverse() * uni_postq.inverse()))
					if bone_index == 0: # Hips
						hips_y = (transform_fileid_to_rotation_delta[crc32_parent_name] * read_transform(avatar_keys["m_Human"]["m_SkeletonPose"]["m_X"][unity_human_skel_index])).origin.y

		var humanDescriptionHuman: Array = keys["m_HumanDescription"]["m_Human"]
		meta.humanoid_bone_map_dict = UnityModelImporter.generate_bone_map_dict_no_root(self, humanDescriptionHuman)

		meta.humanoid_skeleton_hip_position = Vector3(0, hips_y, 0)
		meta.transform_fileid_to_parent_fileid = transform_fileid_to_parent_fileid
		meta.transform_fileid_to_rotation_delta = transform_fileid_to_rotation_delta
		meta.fileid_to_skeleton_bone = fileid_to_skeleton_bone
		return meta # Indicates no resource will be written to disk


class UnityAvatarMask:
	extends UnityObject
	pass
	#func create_godot_resource() -> Resource:
	#	# TODO: Create mask object on newer godot versions.
	#	var ret = Resource.new()
	#	var filtered_paths: Array[NodePath]
	#	ret.set_meta("filtered_paths", filtered_paths)
	#	return ret


class UnityAnimatorRelated:
	extends UnityObject  # Helper functions

	func get_unique_identifier(p_name: String, used_names: Dictionary) -> StringName:
		var out_str: String = ""
		for ch in p_name:
			if not out_str.is_empty() and ("a" + ch).is_valid_identifier():
				out_str += ch
			elif ch.is_valid_identifier():
				out_str += ch
			else:
				out_str += "_"
		return get_unique_name(StringName(out_str), used_names)

	func get_unique_name(p_name: StringName, used_names: Dictionary) -> StringName:
		var name: StringName = StringName(str(p_name).replace("/", "-").replace(":", ";"))
		var renamed_layer: StringName = name
		while used_names.has(renamed_layer):
			used_names[name] = used_names.get(name, 0) + 1
			renamed_layer = StringName(str(name) + str(used_names[name]))
		used_names[renamed_layer] = 0
		log_debug("get_unique_name: " + str(p_name) + " => " + str(renamed_layer))
		return renamed_layer

	func ref_to_anim_key(motion_ref: Array) -> String:
		return "%s:%d" % [meta.guid if typeof(motion_ref[2]) == TYPE_NIL else motion_ref[2], motion_ref[1]]

	func recurse_to_motion(controller: RefCounted, layer_index: int, motion_ref: Array, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool):
		var motion_node: AnimationRootNode = null
		var anim_key: String = ref_to_anim_key(motion_ref)
		if animation_guid_fileid_to_name.has(anim_key):
			motion_node = AnimationNodeAnimation.new()
			motion_node.animation = animation_guid_fileid_to_name[anim_key]
			if reverse_animations:
				motion_node.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		else:
			var blend_tree = meta.lookup(motion_ref)
			log_debug("type: " + str(blend_tree.type) + " class " + str(blend_tree.get_class()) + " " + str(blend_tree.uniq_key))
			if blend_tree.type != "BlendTree":
				log_fail("Animation not in animation_guid_fileid_to_name: " + str(anim_key))
				motion_node = AnimationNodeAnimation.new()
			else:
				motion_node = blend_tree.create_animation_node(controller, layer_index, animation_guid_fileid_to_name, reverse_animations)
		return motion_node


class UnityRuntimeAnimatorController:
	extends UnityAnimatorRelated

	func get_godot_extension() -> String:
		return ".controller.tres"

	func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnityAnimator
		return null

	func create_animation_library_clips_at_node(animator: RefCounted, node_parent: Node, animation_guid_fileid_to_name: Dictionary, requested_clips: Dictionary) -> AnimationLibrary:
		var animation_guid_fileid_to_name_new: Dictionary
		for key in animation_guid_fileid_to_name:
			var guid_fid = key.split(":")
			var anim_guid = guid_fid[0]
			var anim_fileid: int = guid_fid[1].to_int()
			var anim_ref = [null, anim_fileid, anim_guid, 2]
			var clip_name = animation_guid_fileid_to_name[key]
			if not requested_clips.has(clip_name):
				requested_clips[clip_name] = anim_ref
				log_debug("Requesting clip " + str(clip_name) + " at " + str(anim_ref))

		var anim_library = AnimationLibrary.new()
		for clip_name in requested_clips:
			var anim_clip_obj: UnityAnimationClip = meta.lookup(requested_clips[clip_name], true)  # TODO: What if this fails? What if animation in glb file?
			var anim_res: Animation = meta.get_godot_resource(requested_clips[clip_name], true)
			log_debug("clip " + str(clip_name) + " animation " + str(anim_res) + " obj " + str(anim_clip_obj))
			if anim_res == null and anim_clip_obj == null:
				meta.lookup(requested_clips[clip_name])
				continue
			elif anim_res == null and anim_clip_obj != null:
				anim_res = anim_clip_obj.create_animation_clip_at_node(animator, node_parent)
			elif anim_res != null and anim_clip_obj != null and node_parent != null:
				anim_res = anim_clip_obj.adapt_animation_clip_at_node(animator, node_parent, anim_res)
			var clip_sn := StringName(clip_name)
			if anim_res != null:
				anim_library.add_animation(clip_sn, anim_res)
			var target_guid: String
			if typeof(requested_clips[clip_name][2]) == TYPE_NIL:
				target_guid = meta.guid
			else:
				target_guid = requested_clips[clip_name][2]
			animation_guid_fileid_to_name_new[target_guid + ":" + str(requested_clips[clip_name][1])] = clip_sn
		anim_library.set_meta(&"guid_fileid_to_animation_name", animation_guid_fileid_to_name_new)
		return anim_library

	func adapt_animation_player_at_node(animator: RefCounted, anim_player: AnimationPlayer):
		var node_parent: Node = anim_player.get_parent()
		var virtual_generic_animation_clip: UnityAnimationClip = adapter.instantiate_unity_object(meta, 0, 0, "AnimationClip")
		log_debug("Current fileid_to_nodepath: " + str(meta.fileid_to_nodepath.keys()) + " prefab " + str(meta.prefab_fileid_to_nodepath.keys()))
		for library_name in anim_player.get_animation_library_list():
			var library: AnimationLibrary = anim_player.get_animation_library(library_name)
			var animation_guid_fileid_to_name: Dictionary = library.get_meta(&"guid_fileid_to_animation_name", {})
			var done_names: Dictionary
			for key in animation_guid_fileid_to_name:
				var guid_fid = key.split(":")
				var anim_guid = guid_fid[0]
				var anim_fileid: int = guid_fid[1].to_int()
				var anim_ref = [null, anim_fileid, anim_guid, 2]
				var clip_name = animation_guid_fileid_to_name[key]
				done_names[clip_name] = true
				if not library.has_animation(clip_name):
					log_warn("Library is missing animation " + str(clip_name))
					continue
				var clip = library.get_animation(clip_name)
				log_debug("Adapting AnimationClip " + clip_name + " at node " + str(node_parent.name))
				var virtual_animation_clip: UnityAnimationClip = adapter.instantiate_unity_object(meta.lookup_meta(anim_ref), anim_ref[1], 0, "AnimationClip")
				var new_clip: Animation = virtual_animation_clip.adapt_animation_clip_at_node(animator, node_parent, clip)
				if new_clip != null and new_clip != clip:
					library.remove_animation(clip_name)
					library.add_animation(clip_name, new_clip)
			for clip_name in library.get_animation_list():
				if done_names.has(clip_name) or clip_name == &"RESET" or clip_name == &"_T-Pose_":
					continue
				var clip: Animation = library.get_animation(clip_name)
				log_warn("Adapting unrecognized AnimationClip " + clip_name + " at node " + str(node_parent.name))
				var new_clip: Animation = virtual_generic_animation_clip.adapt_animation_clip_at_node(animator, node_parent, clip)
				if new_clip != null and new_clip != clip:
					library.remove_animation(clip_name)
					library.add_animation(clip_name, new_clip)

	func get_godot_type() -> String:
		return "AnimationNodeBlendTree"

	func create_godot_resource() -> Resource:
		return null


class UnityAnimatorOverrideController:
	extends UnityRuntimeAnimatorController

	# Store original unity object!
	func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnityAnimator
		var controller_ref: Array = keys["m_Controller"]
		var referenced_sm: AnimationRootNode = self.meta.get_godot_resource(controller_ref)
		var lib_ref: Array = [null, -controller_ref[1], controller_ref[2], controller_ref[3]]
		var referenced_library: AnimationLibrary = self.meta.get_godot_resource(lib_ref)
		if referenced_sm == null or referenced_library == null:
			log_fail("Override controller's base controller is missing. Creating dummy library")
			var anim_library: AnimationLibrary = AnimationLibrary.new()
			for clip in keys["m_Clips"]:
				var orig_clip: Array = clip["m_OriginalClip"]
				var override_clip: Array = clip["m_OverrideClip"]
				var anim: Animation = self.meta.get_godot_resource(override_clip)
				if anim != null:
					anim_library.add_animation(anim.resource_name, anim)
			return anim_library
		var animation_guid_fileid_to_name: Dictionary = referenced_sm.get_meta(&"guid_fileid_to_animation_name", {})
		var override_clips = {}.duplicate()
		for clip in keys["m_Clips"]:
			var orig_clip: Array = clip["m_OriginalClip"]
			var override_clip: Array = clip["m_OverrideClip"]
			override_clips[animation_guid_fileid_to_name[ref_to_anim_key(orig_clip)]] = override_clip
		# m_Clips: m_OriginalClip / m_OverrideClip
		var anim_library = self.create_animation_library_clips_at_node(animator, node_parent, animation_guid_fileid_to_name, override_clips)
		anim_library.set_meta("base_node", referenced_sm)
		anim_library.set_meta("base_library", referenced_library)
		return anim_library

	func get_godot_type() -> String:
		return "AnimationLibrary"

	func create_godot_resource() -> Resource:
		return create_animation_library_at_node(null, null)


class UnityAnimatorController:
	extends UnityRuntimeAnimatorController

	var parameters: Dictionary = {}

	# An AnimationController references two things:\
	# 1. an animation library which depends on the node.
	# 2.
	func create_animation_library_at_node(animator: RefCounted, node_parent: Node) -> AnimationLibrary:  # UnityAnimator
		var this_res: AnimationRootNode = meta.get_godot_resource([null, self.fileID, null, 0])
		var animation_guid_fileid_to_name: Dictionary = this_res.get_meta(&"guid_fileid_to_animation_name", {})
		assert(not animation_guid_fileid_to_name.is_empty())
		return self.create_animation_library_clips_at_node(animator, node_parent, animation_guid_fileid_to_name, {}.duplicate())

	func get_animation_guid_fileid_to_name():
		var animation_guid_fileid_to_name: Dictionary = {}.duplicate()
		var animation_used_names: Dictionary = {}.duplicate()
		var sm_path: Array = [].duplicate()
		var lay_idx: int = -1
		for lay in keys["m_AnimatorLayers"]:
			lay_idx += 1
			var sm: UnityAnimatorStateMachine = meta.lookup(lay["m_StateMachine"])
			sm_path.append(lay.get("m_Name", "layer"))
			sm.get_all_animations(sm_path, animation_used_names, animation_guid_fileid_to_name)
			sm_path.clear()
		return animation_guid_fileid_to_name

	func get_extra_resources() -> Dictionary:
		return {-self.fileID: ".library.tres"}

	func get_extra_resource(fileID: int) -> Resource:  #AnimationLibrary:
		var sk: AnimationLibrary = AnimationLibrary.new()
		var fileid_to_name: Dictionary = get_animation_guid_fileid_to_name()
		var anim_library = self.create_animation_library_clips_at_node(null, null, fileid_to_name, {}.duplicate())
		return anim_library

	func create_godot_resource() -> Resource:
		return create_animation_node()

	func create_animation_node() -> AnimationRootNode:
		# Add all layers to a blend tree.
		var blended_layers = AnimationNodeBlendTree.new()
		var tmp_used_params: Dictionary = {}.duplicate()
		self.parameters = {}.duplicate()
		for param in keys["m_AnimatorParameters"]:
			var type: String = "unknown"
			var defval: Variant = 0
			match str(param["m_Type"]):
				"1":
					type = "float"
					defval = float(param["m_DefaultFloat"])
				"3":
					type = "int"
					defval = int(param["m_DefaultInt"])
				"4":
					type = "bool"
					if param["m_DefaultBool"]:
						defval = true
					else:
						defval = false
				"9":
					type = "trigger"
					if param["m_DefaultBool"]:
						defval = true
					else:
						defval = false
			var param_name: StringName = get_unique_identifier(param["m_Name"], tmp_used_params)
			parameters[param["m_Name"]] = {"uniq_name": param_name, "type": type, "default": defval}
			blended_layers.set_meta(param_name, defval)  # toplevel meta is used.
		var lay_x: float = 0.0
		var last_output: StringName = &""
		var used_names: Dictionary = {}.duplicate()
		var animation_guid_fileid_to_name: Dictionary = {}.duplicate()
		var animation_used_names: Dictionary = {}.duplicate()
		var sm_path: Array = [].duplicate()
		var lay_idx: int = -1
		for lay in keys["m_AnimatorLayers"]:
			lay_idx += 1
			var sm: UnityAnimatorStateMachine = meta.lookup(lay["m_StateMachine"])
			sm_path.append(lay.get("m_Name", "layer"))
			sm.get_all_animations(sm_path, animation_used_names, animation_guid_fileid_to_name)
			sm_path.clear()

		# Godot: "An AnimationNodeOutput node named output is created by default."
		used_names[&"output"] = 0
		lay_idx = -1
		for lay in keys["m_AnimatorLayers"]:
			lay_idx += 1
			'''
	m_Name: Base Layer
	m_StateMachine: {fileID: 8941230547955804434}
	m_Mask: {fileID: 0}
	m_Motions: []
	m_Behaviours: []
	m_BlendingMode: 0
	m_SyncedLayerIndex: -1
	m_DefaultWeight: 0
	m_IKPass: 0
	m_SyncedLayerAffectsTiming: 0
	m_Controller: {fileID: 9100000}
			'''
			var renamed_layer = get_unique_name(lay["m_Name"], used_names)
			lay["m_Controller"] = [null, self.fileID, null, 0]
			var node_to_add: AnimationRootNode = create_flat_state_machine(lay_idx, animation_guid_fileid_to_name)
			log_debug("aaa")
			blended_layers.add_node(renamed_layer, node_to_add, Vector2(100 + lay_x, 200))
			log_debug("bbb " + str(renamed_layer))
			if last_output != &"":
				# TODO: We may wish to generate the correct mask based on animation clip outputs...
				# but this will depend on the animation clips in question, and I wanted to keep this agnostic.

				# Add2 will be a reasonable output in most cases, except when clips override each others' outputs.
				# So I will use this for now.
				var mixing_node = AnimationNodeAdd2.new()
				# parameter is &"blend" for Blend2 and &"add_amount" for Add2. Make sure to switch if we change types.
				mixing_node.set_meta(&"add_amount", lay["m_DefaultWeight"])
				var mixing_name = get_unique_name(&"Blend", used_names)
				lay_x += 400.0
				blended_layers.add_node(mixing_name, mixing_node, Vector2(100 + lay_x, 0))
				blended_layers.connect_node(mixing_name, 0, last_output)
				blended_layers.connect_node(mixing_name, 1, renamed_layer)
				last_output = mixing_name
			else:
				lay_x += 400.0
				last_output = renamed_layer
		blended_layers.connect_node(&"output", 0, last_output)
		blended_layers.set_node_position(&"output", Vector2(200 + lay_x, 350))
		# Create a StateMachine for m_StateMachine and all child state machines too.
		# State Machine blending does not currently seem to work.
		# Then, add to blended_layers
		blended_layers.set_meta(&"guid_fileid_to_animation_name", animation_guid_fileid_to_name)
		return blended_layers

#	func allows_dupe_transitions() -> bool:
#		var sm = AnimationNodeStateMachine.new()
#		var n1 = AnimationNodeAnimation.new()
#		var n2 = AnimationNodeAnimation.new()
#		var t1 = AnimationNodeStateMachineTransition.new()
#		var t2 = AnimationNodeStateMachineTransition.new()
#		sm.add_node(&"test1", n1)
#		sm.add_node(&"test2", n2)
#		sm.add_transition(&"test1", &"test2", t1)
#		sm.add_transition(&"test1", &"test2", t2)
#		var has_dupe_transitions: bool = sm.get_transition(0) == t1 && sm.get_transition(1) == t2
#		sm.remove_transition_by_index(1)
#		sm.remove_transition_by_index(0)
#		sm.remove_node(&"test1")
#		sm.remove_node(&"test2")
#		return has_dupe_transitions

	func get_parameter_uniq_name(param_name: String) -> StringName:
		if not self.parameters.has(param_name):
			log_warn("Parameter " + param_name + " is missing from " + str(self.parameters.keys()), param_name)
			return &""
		return self.parameters[param_name]["uniq_name"]

	const STATE_MACHINE_SCALE: float = 1.0
	const STATE_MACHINE_OFFSET: Vector3 = Vector3(300, 100, 0)

	func create_flat_state_machine(layer_index: int, animation_guid_fileid_to_name: Dictionary) -> AnimationRootNode:
		var lay: Dictionary = keys["m_AnimatorLayers"][layer_index]
		var root_state_machine_ref: Array = lay["m_StateMachine"]
		var root_sm: UnityAnimatorStateMachine = meta.lookup(root_state_machine_ref)
		var state_uniq_names = {}.duplicate()
		var state_duplicates = {}.duplicate()  # such as any state self transitions; other self transitions; multi transitions.
		var state_data = {}.duplicate()
		state_uniq_names[&"Start"] = 0
		state_uniq_names[&"End"] = 0
		state_uniq_names[&"playback"] = 0
		state_uniq_names[&"conditions"] = 0
		root_sm.get_state_data("", state_data, state_uniq_names, STATE_MACHINE_OFFSET, STATE_MACHINE_SCALE)

		# var exit_state_name: StringName = &""
		var any_transition_list = [].duplicate()
		root_sm.get_any_state_transitions(any_transition_list)
		any_transition_list.reverse()
		var exit_parent = {}.duplicate()
		exit_parent[root_sm.uniq_key] = root_sm  # null # make a sort of temporary exit node which holds it for one frame.
		root_sm.get_exit_parent(exit_parent)
		var sm = AnimationNodeStateMachine.new()
		sm.resource_name = keys.get("m_Name", "")
		var tmppos: Vector3 = STATE_MACHINE_OFFSET + keys.get("m_EntryPosition", Vector3()) * STATE_MACHINE_SCALE
		sm.set_node_position(&"Start", Vector2(tmppos.x, tmppos.y))
		tmppos = STATE_MACHINE_OFFSET + keys.get("m_ExitPosition", Vector3()) * STATE_MACHINE_SCALE
		sm.set_node_position(&"End", Vector2(tmppos.x, tmppos.y))
		var allow_dupe_transitions: bool = false  # allows_dupe_transitions()

		var transition_count = {}.duplicate()
		var state_count = {}.duplicate()
		for state_key in state_data:
			transition_count[state_key + state_key] = 1  # state to itself is not allowed anyway.
			state_count[state_key] = 1

		for transition_obj in any_transition_list:  # Godot favors last transition.
			var can_trans_to_self: bool = transition_obj.keys.get("m_CanTransitionToSelf", 0) != 0
			var transition_list = transition_obj.resolve_state_transitions(exit_parent, null)
			for src_state_key in state_data:
				for condition_list in transition_list:
					var dst_state: UnityAnimatorState = condition_list[-1]
					if dst_state == null:
						continue
					if not can_trans_to_self and dst_state.uniq_key == src_state_key:
						continue
					var trans_key: String = src_state_key + dst_state.uniq_key
					if allow_dupe_transitions:
						if dst_state.uniq_key != src_state_key:
							continue
						transition_count[trans_key] = 2
					else:
						if not transition_count.has(trans_key):
							transition_count[trans_key] = 0
						transition_count[trans_key] += 1
					if state_count.has(dst_state.uniq_key):
						state_count[dst_state.uniq_key] = max(state_count[dst_state.uniq_key], transition_count[trans_key])
					else:
						log_warn("state_count " + dst_state.uniq_key + " is missing for Any transition " + trans_key)
						state_count[dst_state.uniq_key] = transition_count[trans_key]

		for state_key in state_data:
			var this_state: Dictionary = state_data[state_key]
			for trans in this_state["state"].keys["m_Transitions"]:
				var transition_obj = this_state["state"].meta.lookup(trans)
				var transition_list = transition_obj.resolve_state_transitions(exit_parent, this_state["sm"])
				for condition_list in transition_list:
					var dst_state: UnityAnimatorState = condition_list[-1]
					if dst_state == null:
						continue
					var trans_key: String = state_key + dst_state.uniq_key
					if allow_dupe_transitions:
						if dst_state.uniq_key != state_key:
							continue
						transition_count[trans_key] = 2
					else:
						if not transition_count.has(trans_key):
							transition_count[trans_key] = 0
						transition_count[trans_key] += 1
					if state_count.has(dst_state.uniq_key):
						state_count[dst_state.uniq_key] = max(state_count[dst_state.uniq_key], transition_count[trans_key])
					else:
						log_warn("state_count " + dst_state.uniq_key + " is missing for normal transition " + trans_key)
						state_count[dst_state.uniq_key] = transition_count[trans_key]
		for state_key in state_data:
			var this_state: Dictionary = state_data[state_key]
			var anim_node = this_state["state"].create_animation_node(self, layer_index, animation_guid_fileid_to_name)
			sm.add_node(this_state["name"], anim_node, this_state["pos"])
			var dup_prefix = StringName(str(this_state["name"]) + "~Dup")
			get_unique_name(dup_prefix, state_uniq_names)
			var dupes = [].duplicate()
			dupes.append(this_state["name"])
			for i in range(1, state_count[state_key]):
				var dup_name = get_unique_name(dup_prefix, state_uniq_names)
				anim_node = this_state["state"].create_animation_node(self, layer_index, animation_guid_fileid_to_name)
				sm.add_node(dup_name, anim_node, this_state["pos"] + i * Vector2(25, 25))
				dupes.append(dup_name)
			state_duplicates[this_state["name"]] = dupes

		transition_count = {}.duplicate()
		for x_transition_obj in any_transition_list:  # Godot favors last transition.
			var transition_obj: UnityAnimatorStateTransition = x_transition_obj
			var can_trans_to_self: bool = transition_obj.keys.get("m_CanTransitionToSelf", 0) != 0
			var transition_list: Array = transition_obj.resolve_state_transitions(exit_parent, null)
			for src_state_key in state_data:
				for condition_list in transition_list:
					var dst_state: UnityAnimatorState = condition_list[-1]
					if dst_state == null:
						continue
					if not can_trans_to_self and dst_state.uniq_key == src_state_key:
						continue
					var trans_key: String = src_state_key + dst_state.uniq_key
					if not state_data.has(dst_state.uniq_key) or not state_data.has(src_state_key):
						log_fail("Missing state_data for dupe any state transition from " + src_state_key + " to " + dst_state.uniq_key)
						continue
					create_dupe_transitions(sm, transition_obj, state_data[src_state_key]["name"], state_data[dst_state.uniq_key]["name"], state_duplicates, transition_count.get(trans_key, 0), condition_list)
					if not allow_dupe_transitions:
						if not transition_count.has(trans_key):
							transition_count[trans_key] = 0
						transition_count[trans_key] += 1

		for state_key in state_data:
			var this_state: Dictionary = state_data[state_key]
			var trans_list: Array = this_state["state"].keys["m_Transitions"].duplicate()
			trans_list.reverse()
			for trans in trans_list:
				var transition_obj = this_state["state"].meta.lookup(trans)
				var transition_list = transition_obj.resolve_state_transitions(exit_parent, this_state["sm"])
				for condition_list in transition_list:
					var dst_state: UnityAnimatorState = condition_list[-1]
					if dst_state == null:
						continue
					var trans_key: String = state_key + dst_state.uniq_key
					if not state_data.has(dst_state.uniq_key):
						log_fail("Missing state_data for dupe normal transition from " + state_key + " to " + dst_state.uniq_key)
						continue
					create_dupe_transitions(sm, transition_obj, this_state["name"], state_data[dst_state.uniq_key]["name"], state_duplicates, transition_count.get(trans_key, 0), condition_list)
					if not allow_dupe_transitions:
						if not transition_count.has(trans_key):
							transition_count[trans_key] = 0
						transition_count[trans_key] += 1

		var def_state = meta.lookup(root_sm.keys["m_DefaultState"])
		if def_state != null and state_data.has(def_state.uniq_key):
			if sm.get_node(&"Start") != null:
				var trans = AnimationNodeStateMachineTransition.new()
				trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
				sm.add_transition(&"Start", state_data[def_state.uniq_key]["name"], trans)
			else:
				sm.set_start_node(state_data[def_state.uniq_key]["name"])
		return sm

	func create_dupe_transitions(sm: AnimationNodeStateMachine, transition_obj: UnityAnimatorStateTransition, src_state_name: StringName, dst_state_name: StringName, state_duplicates: Dictionary, dst_idx: int, condition_list: Array):
		var conditions: String = ""
		var is_muted: bool = transition_obj.keys.get("m_Mute", false)
		for trans in condition_list:
			if trans == null or not trans.type.ends_with("Transition"):
				continue
			is_muted = is_muted or trans.keys.get("m_Mute", false)
			for cond in trans.keys["m_Conditions"]:
				var parameter: String = get_parameter_uniq_name(str(cond["m_ConditionEvent"]))
				var thresh: float = float(cond["m_EventTreshold"])
				var event: int = cond["m_ConditionMode"]
				var cond_to_add = ""
				match event:
					1:
						cond_to_add = "%s" % [parameter]  # bool true
					2:
						cond_to_add = "not %s" % [parameter]
					3:
						cond_to_add = "%s > %f" % [parameter, thresh]
					4:
						cond_to_add = "%s < %f" % [parameter, thresh]
					6:
						cond_to_add = "%s == %f" % [parameter, thresh]
					7:
						cond_to_add = "%s != %f" % [parameter, thresh]
				if not cond_to_add.is_empty():
					if not conditions.is_empty():
						conditions += " and "
					conditions += cond_to_add

		var trans = AnimationNodeStateMachineTransition.new()
		# During 4.0 beta, xfade_time > 0 sometimes causes hung machines
		# TODO: We need to check if this is still true?
		trans.xfade_time = transition_obj.keys["m_TransitionDuration"]
		# Godot does not currently support exit time. transition_obj.keys["m_ExitTime"]
		if transition_obj.keys["m_HasExitTime"] and transition_obj.keys["m_ExitTime"] > 0.0001:
			trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		else:
			trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		if conditions == "":
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		else:
			trans.advance_expression = conditions
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO # All conditions use Auto now.
		if is_muted:
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		# TODO: Solo is not implemented yet. It requires knowledge of all sibling transitions at each stage of state machine.
		# Not too hard to do if someone uses the Solo feature for something.

		var src_dupe_idx = 0
		for src_dupe in state_duplicates[src_state_name]:
			var actual_dst_idx = dst_idx
			if src_state_name == dst_state_name:
				actual_dst_idx = 1 if src_dupe_idx == 0 else 0
			var dst_dupe: StringName = state_duplicates[dst_state_name][actual_dst_idx]
			sm.add_transition(src_dupe, dst_dupe, trans)
			src_dupe_idx += 1


class UnityAnimatorStateMachine:
	extends UnityAnimatorRelated

	func get_godot_type() -> String:
		return "AnimationNodeStateMachine"

	func get_state_data(sm_prefix: String, state_data: Dictionary, unique_names: Dictionary, sm_pos: Vector3, pos_scale: float):
		for state in keys["m_ChildStates"]:
			var child: UnityAnimatorState = meta.lookup(state["m_State"])
			var child_name: StringName = get_unique_name(StringName(sm_prefix + child.keys["m_Name"]), unique_names)
			var child_pos: Vector3 = sm_pos + state["m_Position"] * pos_scale
			state_data[child.uniq_key] = {"name": child_name, "state": child, "pos": Vector2(child_pos.x, child_pos.y), "sm": self}

		for state_machine in keys["m_ChildStateMachines"]:
			var child: UnityAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
			var child_pos: Vector3 = sm_pos + state_machine["m_Position"] * pos_scale
			child.get_state_data(sm_prefix + child.keys["m_Name"] + "/", state_data, unique_names, child_pos, pos_scale * 0.5)

	func get_exit_parent(sm_to_parent: Dictionary):
		for state_machine in keys["m_ChildStateMachines"]:
			var child: UnityAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
			sm_to_parent[child.uniq_key] = self
			child.get_exit_parent(sm_to_parent)

	func get_any_state_transitions(transition_list: Array):
		for transition in keys["m_AnyStateTransitions"]:
			transition_list.append(meta.lookup(transition))

		for state_machine in keys["m_ChildStateMachines"]:
			var child: UnityAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
			child.get_any_state_transitions(transition_list)

	func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
		for state in keys["m_ChildStates"]:
			var child: UnityAnimatorState = meta.lookup(state["m_State"])
			var basename: String = child.keys["m_Name"]
			var motion_ref: Array = child.keys["m_Motion"]
			if out_guid_fid_to_anim_name.has(child.ref_to_anim_key(motion_ref)):
				continue
			var motion: UnityMotion = child.meta.lookup(motion_ref, true) # motion_ref[1] != 7400000)
			if motion != null:
				sm_path.append(basename)
				motion.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
				sm_path.remove_at(len(sm_path) - 1)
			else:
				var name: String = basename
				for i in range(len(uniq_name_dict) + 1):
					if not uniq_name_dict.has(name):
						break
					for sm_name in sm_path:
						if not uniq_name_dict.has(name):
							break
						if i > 0:
							name = "%s %s %d" % [sm_name, basename, i]
						else:
							name = "%s %s" % [sm_name, basename]
						log_debug("Trying %s name %s from %s %s" % [str(sm_name), str(name), str(basename), str(uniq_name_dict)])
				uniq_name_dict[name] = 1
				out_guid_fid_to_anim_name[child.ref_to_anim_key(motion_ref)] = name

		for state_machine in keys["m_ChildStateMachines"]:
			var child: UnityAnimatorStateMachine = meta.lookup(state_machine["m_StateMachine"])
			sm_path.append(child.keys["m_Name"])
			child.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
			sm_path.remove_at(len(sm_path) - 1)

	func resolve_entry_state_transitions(exit_src: Object, exit_parent: Dictionary, transition_list: Array, transition_dict: Dictionary, inp_condition_list: Array):
		var trans_list: Array = keys["m_EntryTransitions"]
		if exit_src != null and exit_src.uniq_key != self.uniq_key:  # if root, we use entry transitions anyway.
			trans_list = []
			#m_StateMachineTransitions:
			#- first: {fileID: 7243501764948564761}
			#  second:
			#  - {fileID: -5738504938746420287}
			#  - {fileID: -1730057159985691264}
			for elem in keys["m_StateMachineTransitions"]:
				var src_sm = meta.lookup(elem["first"])
				if src_sm != null and src_sm.uniq_key == exit_src.uniq_key:
					trans_list = elem["second"]
		for etrans in trans_list:
			var trans_obj: UnityAnimatorTransition = meta.lookup(etrans)
			var condition_list = inp_condition_list.duplicate()
			condition_list.append(trans_obj)
			if transition_dict.has(trans_obj.uniq_key):
				log_warn("Cycle detected... " + str(transition_dict) + " " + trans_obj.uniq_key)
				continue
			transition_dict[trans_obj.uniq_key] = 1
			var dst_state = meta.lookup(trans_obj.keys["m_DstState"])
			var dst_sm = meta.lookup(trans_obj.keys["m_DstStateMachine"])
			if dst_state != null and not trans_obj.keys["m_IsExit"]:
				condition_list.append(dst_state)
				transition_list.append(condition_list)
			else:  # if dst_sm != null or trans_obj.keys["m_IsExit"]:
				var new_exit_src: Object = null
				if trans_obj.keys["m_IsExit"]:
					new_exit_src = self
					dst_sm = exit_parent.get(self.uniq_key)
				if dst_sm == null:
					dst_sm = exit_parent.get(self.uniq_key)
				if dst_sm == null:
					log_warn("Unable to find exit state parent " + str(self.uniq_key))
					# condition_list.append(null)
					# transition_list.append(condition_list) # transition to broken link or top-level exit: go to special exit state.
				else:
					dst_sm.resolve_entry_state_transitions(new_exit_src, exit_parent, transition_list, transition_dict, condition_list)
			transition_dict.erase(trans_obj.uniq_key)
		var def_state = meta.lookup(keys["m_DefaultState"])
		if def_state != null:
			inp_condition_list.append(def_state)
			transition_list.append(inp_condition_list)


class UnityAnimatorState:
	extends UnityAnimatorRelated

	func get_godot_type() -> String:
		return "AnimationRootNode"

	func create_animation_node(controller: RefCounted, layer_index: int, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool=false) -> AnimationRootNode:
		var speed: float = keys.get("m_Speed", 1)
		if speed < 0:
			speed *= -1
			reverse_animations = not reverse_animations
		var motion_ref: Array = keys["m_Motion"]
		var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, motion_ref, animation_guid_fileid_to_name, reverse_animations)
		# TODO: Convert states with motion time, speed or other parameters into AnimationBlendTree graphs.
		var cycle_off: float = keys.get("m_CycleOffset", 0)
		var speed_param_active: int = keys.get("m_SpeedParameterActive", 0) and not keys.get("m_SpeedParameter", "").is_empty()
		var time_param_active: int = keys.get("m_TimeParameterActive", 0) and not keys.get("m_TimeParameter", "").is_empty()
		var cycle_param_active: int = keys.get("m_CycleParameterActive", 0) and not keys.get("m_CycleParameter", "").is_empty()
		var ret = motion_node
		# not sure we support cycle offset?
		if speed != 1 or speed_param_active == 1 or time_param_active == 1:
			var bt = AnimationNodeBlendTree.new()
			ret = bt
			bt.add_node(&"Animation", motion_node, Vector2(200, 200))
			var last_node = &"Animation"
			var xval = 500
			if speed != 1:
				var tsnode = AnimationNodeTimeScale.new()
				tsnode.set_meta("scale", speed)
				bt.add_node(&"TimeScale", tsnode, Vector2(xval, 0))
				xval += 200
				bt.connect_node(&"TimeScale", 0, last_node)
				last_node = &"TimeScale"
			if time_param_active:
				var seeknode = AnimationNodeTimeSeek.new()
				seeknode.set_meta("seek_request", controller.get_parameter_uniq_name(keys["m_TimeParameter"]))
				var node_name = StringName("TimeSeek")
				bt.add_node(node_name, seeknode, Vector2(xval, 0))
				xval += 200
				bt.connect_node(node_name, 0, last_node)
				last_node = node_name
			if speed_param_active:
				var tsnode = AnimationNodeTimeScale.new()
				tsnode.set_meta("scale", controller.get_parameter_uniq_name(keys["m_SpeedParameter"]))
				var node_name = StringName("TimeScaleParam")
				bt.add_node(node_name, tsnode, Vector2(xval, 0))
				xval += 200
				bt.connect_node(node_name, 0, last_node)
				last_node = node_name
			bt.connect_node(&"output", 0, last_node)
			bt.set_node_position(&"output", Vector2(xval, 0))
		return ret


class UnityAnimatorTransitionBase:
	extends UnityAnimatorRelated

	func get_godot_type() -> String:
		return "AnimationNodeStateMachineTransition"

	pass  # abstract


class UnityAnimatorStateTransition:
	extends UnityAnimatorTransitionBase

	func resolve_state_transitions(exit_parent: Dictionary, this_sm: Object):
		var dst_sm: UnityAnimatorStateMachine = meta.lookup(keys.get("m_DstStateMachine"))
		var dst_state: UnityAnimatorState = meta.lookup(keys.get("m_DstState"))

		var transition_list = [].duplicate()
		var condition_list = [].duplicate()
		condition_list.append(self)
		var exit_src = null
		if keys["m_IsExit"]:
			dst_state = null
			dst_sm = exit_parent[this_sm.uniq_key]
			exit_src = this_sm
		if dst_state != null:
			condition_list.append(dst_state)
			transition_list.append(condition_list)
		elif dst_sm != null:
			var transition_dict = {}.duplicate()  # avoid cycles
			dst_sm.resolve_entry_state_transitions(exit_src, exit_parent, transition_list, transition_dict, condition_list)
		return transition_list


class UnityAnimatorTransition:
	extends UnityAnimatorTransitionBase
	pass


class UnityMotion:
	extends UnityAnimatorRelated
	pass  # abstract


class UnityBlendTree:
	extends UnityMotion

	func get_godot_type() -> String:
		return "AnimationNodeBlendSpace2D"

	func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
		for child in keys["m_Childs"]:
			var basename: String = sm_path[-1]
			if keys["m_BlendType"] == 0:
				basename = "%s_%s" % [basename, child.get("m_Threshold", 0)]
			elif keys["m_BlendType"] == 4:
				basename = "%s_%s" % [basename, child.get("m_DirectBlendParameter", "")]
			else:
				var pos: Vector2 = child.get("m_Position", Vector2())
				basename = "%s_%.02f_%.02f" % [basename, pos.x, pos.y]
			var motion_ref: Array = child["m_Motion"]
			if out_guid_fid_to_anim_name.has(ref_to_anim_key(motion_ref)):
				continue
			var motion: Object = meta.lookup(motion_ref, true)  # TODO: Need to get the godot resource's name for imported glb
			if motion != null:
				sm_path.append(basename)
				motion.get_all_animations(sm_path, uniq_name_dict, out_guid_fid_to_anim_name)
				sm_path.remove_at(len(sm_path) - 1)
			else:
				var name: String = basename
				for i in range(len(uniq_name_dict) + 1):
					if not uniq_name_dict.has(name):
						break
					for j in range(len(sm_path) - 1, -1, -1):
						var sm_name = sm_path[j]
						if not uniq_name_dict.has(name):
							break
						if i > 0:
							name = "%s %s %d" % [sm_name, basename, i]
						else:
							name = "%s %s" % [sm_name, basename]
						log_debug("Trying %s name %s from %s %s" % [str(sm_name), str(name), str(basename), str(uniq_name_dict)])
				uniq_name_dict[name] = 1
				out_guid_fid_to_anim_name[ref_to_anim_key(motion_ref)] = name

	func create_animation_node(controller: RefCounted, layer_index: int, animation_guid_fileid_to_name: Dictionary, reverse_animations: bool=false) -> AnimationRootNode:
		var minmax: Rect2 = Rect2(-1.1, -1.1, 2.2, 2.2)
		var ret: AnimationRootNode = null
		match keys["m_BlendType"]:
			0:  # Simple1D
				var bs = AnimationNodeBlendSpace1D.new()
				for child in keys["m_Childs"]:
					var speed: float = child.get("m_TimeScale", 1)
					if speed < 0:
						speed *= -1
						reverse_animations = not reverse_animations
					# TODO: m_TimeScale and m_CycleOffset
					var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
					if speed != 1:
						var bt = AnimationNodeBlendTree.new()
						var tsnode = AnimationNodeTimeScale.new()
						tsnode.set_meta("scale", speed)
						bt.add_node(&"Motion", motion_node, Vector2(200, 200))
						bt.add_node(&"TimeScale", tsnode, Vector2(500, 200))
						bt.connect_node(&"TimeScale", 0, &"Motion")
						bt.connect_node(&"output", 0, &"TimeScale")
						bt.set_node_position(&"output", Vector2(700, 200))
						motion_node = bt
					bs.add_blend_point(motion_node, child["m_Threshold"])
					minmax = minmax.expand(Vector2(child["m_Threshold"] * 1.1, 0.0))
				bs.min_space = minmax.position.x
				bs.max_space = minmax.end.x
				bs.set_meta("blend_position", controller.get_parameter_uniq_name(keys.get("m_BlendParameter", "Blend")))
				ret = bs
			1, 2, 3:  # SimpleDirectional2D, FreeformDirectional2D, FreeformCartesian2D
				# TODO: Does Godot support the different types of 2D blending?
				var bs = AnimationNodeBlendSpace2D.new()
				for child in keys["m_Childs"]:
					var speed: float = child.get("m_TimeScale", 1)
					if speed < 0:
						speed *= -1
						reverse_animations = not reverse_animations
					# TODO: m_TimeScale and m_CycleOffset
					var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
					if speed != 1:
						var bt = AnimationNodeBlendTree.new()
						var tsnode = AnimationNodeTimeScale.new()
						tsnode.set_meta("scale", speed)
						bt.add_node(&"Motion", motion_node, Vector2(200, 200))
						bt.add_node(&"TimeScale", tsnode, Vector2(500, 200))
						bt.connect_node(&"TimeScale", 0, &"Motion")
						bt.connect_node(&"output", 0, &"TimeScale")
						bt.set_node_position(&"output", Vector2(700, 200))
						motion_node = bt
					bs.add_blend_point(motion_node, child["m_Position"])
					minmax = minmax.expand(child["m_Position"] * 1.1)
				bs.min_space = minmax.position
				bs.max_space = minmax.end
				bs.set_meta("blend_position_x", controller.get_parameter_uniq_name(keys.get("m_BlendParameter", "Blend")))
				bs.set_meta("blend_position_y", controller.get_parameter_uniq_name(keys.get("m_BlendParameterY", "Blend")))
				ret = bs
			4:  # Direct
				# Add a bunch of AnimationNodeAdd2? Do these get chained somehow?
				var bt = AnimationNodeBlendTree.new()
				var uniq_dict: Dictionary = {}.duplicate()
				uniq_dict[&"output"] = 1
				uniq_dict[&"Child"] = 1
				uniq_dict[&"TimeScale"] = 1
				uniq_dict[&"Transition"] = 1
				bt.add_node(&"Transition", AnimationNodeTransition.new(), Vector2(200, 200))
				var last_name = &"Transition"

				var i = 0
				for child in keys["m_Childs"]:
					var speed: float = child.get("m_TimeScale", 1)
					if speed < 0:
						speed *= -1
						reverse_animations = not reverse_animations
					var motion_node: AnimationRootNode = recurse_to_motion(controller, layer_index, child["m_Motion"], animation_guid_fileid_to_name, reverse_animations)
					var motion_name = get_unique_name("Child", uniq_dict)
					bt.add_node(motion_name, motion_node, Vector2(500, i * 200))
					if speed != 1:
						var tsnode = AnimationNodeTimeScale.new()
						var tsname = get_unique_name("TimeScale", uniq_dict)
						tsnode.set_meta("scale", speed)
						bt.add_node(tsname, tsnode, Vector2(700, i * 200 - 50))
						bt.connect_node(tsname, 0, motion_name)
						motion_name = tsname
					var add_node = AnimationNodeAdd2.new()
					add_node.set_meta("add_amount", controller.get_parameter_uniq_name(child.get("m_DirectBlendParameter", "Blend")))
					var add_name = get_unique_name(child.get("m_DirectBlendParameter", "Blend"), uniq_dict)
					bt.add_node(add_name, add_node, Vector2(900, i * 200 - 100))
					bt.connect_node(add_name, 0, last_name)
					bt.connect_node(add_name, 1, motion_name)
					last_name = add_name
					i += 1
				bt.connect_node(&"output", 0, last_name)
				ret = bt
		return ret


class UnityAnimationClip:
	extends UnityMotion

	func get_godot_type() -> String:
		return "Animation"

	func get_godot_extension() -> String:
		return ".anim.tres"

	func create_godot_resource() -> Resource:  #Animation:
		if not meta.godot_resources.is_empty():
			return null  # We will create them when referenced.

		# We will try our best to infer this data, but we get better results
		# if created relative to a particular node.
		return create_animation_clip_at_node(null, null)

	func get_all_animations(sm_path: Array, uniq_name_dict: Dictionary, out_guid_fid_to_anim_name: Dictionary):
		var anim_key = "%s:%d" % [self.meta.guid, self.fileID]
		if out_guid_fid_to_anim_name.has(anim_key):
			return
		var basename: String = self.keys["m_Name"]
		var num = 1
		var name: String = basename
		while uniq_name_dict.has(name):
			name = "%s %d" % [name, num]
			num += 1
		uniq_name_dict[name] = 1
		out_guid_fid_to_anim_name[anim_key] = name

	func default_gameobject_component_path(unipath: String, unicomp: Variant) -> NodePath:
		if typeof(unicomp) == TYPE_INT and (unicomp == 1 or unicomp == 4):
			return NodePath(unipath)
		return NodePath(unipath + "/" + adapter.to_classname(unicomp))

	func resolve_gameobject_component_path(animator: Object, unipath: String, unicomp: Variant) -> NodePath:  # UnityAnimator
		if animator == null:
			return default_gameobject_component_path(unipath, unicomp)
		var animator_go: UnityGameObject = animator.gameObject
		var path_split: PackedStringArray = unipath.split("/")
		var current_fileID: int = 0 if animator_go == null else animator_go.fileID
		var animator_nodepath: NodePath = animator.meta.prefab_fileid_to_nodepath.get(current_fileID, animator.meta.fileid_to_nodepath.get(current_fileID, NodePath()))
		var current_obj: Dictionary = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
		var extra_path: String = ""
		for path_component in path_split:
			log_debug("Look for component %s in %d:%s" % [path_component, current_fileID, str(current_obj)])
			if extra_path.is_empty() and current_obj.has(path_component):
				current_fileID = current_obj[path_component]
				current_obj = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
			else:
				extra_path += "/" + str(path_component)
		log_debug("Path %s became %d comp %s %s current %s" % [str(path_split), current_fileID, str(unicomp), extra_path, str(current_obj)])
		if extra_path.is_empty() and (typeof(unicomp) != TYPE_INT or unicomp != 1):
			current_fileID = current_obj.get(unicomp, current_fileID)
		var nodepath: NodePath = animator.meta.prefab_fileid_to_nodepath.get(current_fileID, animator.meta.fileid_to_nodepath.get(current_fileID, NodePath()))
		log_debug("Resolving %d to %s" % [current_fileID, str(nodepath)])
		if nodepath == NodePath():
			log_debug("Returning default nodepath because some path failed to resolve.")
			if typeof(unicomp) == TYPE_INT:
				if unicomp == 1 or unicomp == 4:
					return NodePath(unipath)
				return NodePath(unipath + "/" + adapter.to_classname(unicomp))
			return NodePath(unipath)
		if nodepath == animator_nodepath:
			nodepath = "."
		elif str(nodepath).begins_with(str(animator_nodepath) + "/"):
			nodepath = NodePath(str(nodepath).substr(len(str(animator_nodepath)) + 1))
		elif str(animator_nodepath) == "." or str(nodepath) == ".":
			pass
		else:
			log_warn("NodePath " + str(nodepath) + " not within the animator path " + str(animator_nodepath), "", [null,current_fileID,"",0])
		if not extra_path.is_empty():
			nodepath = NodePath(str(nodepath) + extra_path)
		var skeleton_bone: String = animator.meta.prefab_fileid_to_skeleton_bone.get(current_fileID, animator.meta.fileid_to_skeleton_bone.get(current_fileID, ""))
		if not skeleton_bone.is_empty() and (typeof(unicomp) == TYPE_INT or unicomp == 4):
			return NodePath(str(nodepath) + ":" + skeleton_bone)
		return nodepath

	class KeyframeIterator:
		extends RefCounted
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

	class LockstepKeyframeiterator:
		extends RefCounted

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

	func adapt_track_nodepaths_for_node(animator: RefCounted, node_parent: Node, clip: Animation) -> Array:
		var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
		var new_track_names: Array = []
		var identical: int = 0
		var scale_tracks: Dictionary
		var rot_tracks: Dictionary
		var transform_nodepath_to_fileid: Dictionary
		var mesh_nodepath_to_fileid: Dictionary
		var reverse_gameobject_to_name: Dictionary
		var reverse_gameobject_to_parent: Dictionary
		for fileid in meta.gameobject_name_to_fileid_and_children:
			var dic: Dictionary = meta.gameobject_name_to_fileid_and_children[fileid]
			for chld in dic:
				if typeof(chld) == TYPE_STRING:
					reverse_gameobject_to_name[dic[chld]] = chld
					reverse_gameobject_to_parent[dic[chld]] = fileid
		for fileid in meta.fileid_to_nodepath:
			var nodepath: NodePath = meta.fileid_to_nodepath[fileid]
			var skel_bone: String = meta.fileid_to_skeleton_bone.get(fileid, "")
			if not skel_bone.is_empty():
				nodepath = NodePath(String(nodepath) + ":" + skel_bone)
			# internal_data.get("godot_sanitized_to_orig_remap", {})
			if meta.fileid_to_utype[fileid] == 4: # Transform
				transform_nodepath_to_fileid[nodepath] = meta.fileid_to_gameobject_fileid.get(fileid, 0)
			elif meta.fileid_to_utype[fileid] == 137: # SkinnedMeshRenderer
				mesh_nodepath_to_fileid[nodepath] = meta.fileid_to_gameobject_fileid.get(fileid, 0)
		for track_idx in range(clip.get_track_count()):
			var typ: int = clip.track_get_type(track_idx)
			var resolved_key: String = str(clip.track_get_path(track_idx)).replace("%GeneralSkeleton/", "")
			match typ:
				Animation.TYPE_ROTATION_3D:
					rot_tracks["T" + resolved_key] = track_idx
				Animation.TYPE_SCALE_3D:
					scale_tracks["T" + resolved_key] = track_idx
		for track_idx in range(clip.get_track_count()):
			var typ: int = clip.track_get_type(track_idx)
			var resolved_key: String = str(clip.track_get_path(track_idx)).replace("%GeneralSkeleton/", "")
			var resolved_subpath: String = NodePath(resolved_key).get_concatenated_subnames()
			var source_fileid: int = 0
			match typ:
				Animation.TYPE_BLEND_SHAPE:
					var mesh_key: NodePath = NodePath(clip.track_get_path(track_idx).get_concatenated_names())
					if mesh_nodepath_to_fileid.has(mesh_key):
						source_fileid = mesh_nodepath_to_fileid[mesh_key]
				Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
					var transform_key: NodePath = clip.track_get_path(track_idx)
					if str(transform_key).begins_with("%GeneralSkeleton:"):
						new_track_names.append([clip.track_get_path(track_idx), "", []])
						identical += 1
						continue
					if transform_nodepath_to_fileid.has(transform_key):
						source_fileid = transform_nodepath_to_fileid[transform_key]

			var orig_info: Array
			if source_fileid != 0:
				var source_path_components: PackedStringArray
				var parent_fileid := source_fileid
				while parent_fileid != 0 and reverse_gameobject_to_name.has(parent_fileid) and len(source_path_components) < 100:
					source_path_components.append(reverse_gameobject_to_name[parent_fileid])
					parent_fileid = reverse_gameobject_to_parent[parent_fileid]
				if source_path_components.is_empty():
					log_warn("Unable to lookup reverse name " + str(parent_fileid))
				source_path_components.reverse()
				var source_path: String = "/".join(source_path_components)
				var source_classID: int
				if typ == Animation.TYPE_BLEND_SHAPE:
					resolved_key = "B" + source_path + ":" + resolved_subpath
					source_classID = 137
				else:
					resolved_key = "T" + source_path
					resolved_subpath = ""
					source_classID = 4
				orig_info = [source_path, resolved_key, source_classID]
				log_debug("Converting imported Godot NodePath to " + str([source_path, resolved_key, source_classID]))
			else:
				match typ:
					Animation.TYPE_BLEND_SHAPE:
						resolved_key = "B" + resolved_key
					Animation.TYPE_VALUE:
						resolved_key = "V" + resolved_key
					Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
						resolved_key = "T" + resolved_key
					_:
						log_warn(str(self.uniq_key) + ": anim Unsupported track type " + str(typ) + " at " + resolved_key)
						new_track_names.append([clip.track_get_path(track_idx), "", []])
						identical += 1
						continue  # unsupported track type.
				if not resolved_to_default_paths.has(resolved_key):
					if not resolved_key.begins_with("T%GeneralSkeleton"): # This is normal
						log_warn(str(self.uniq_key) + ": anim No default " + str(typ) + " track path at " + resolved_key)
					new_track_names.append([clip.track_get_path(track_idx), "", []])
					identical += 1
					continue
				orig_info = resolved_to_default_paths[resolved_key]
			var path: String = orig_info[0]
			var attr: String = orig_info[1]
			var classID: int = orig_info[2]
			#var orig_path: String = NodePath(path).get_concatenated_subnames()
			#var orig_pathname: String = orig_path
			var new_path: NodePath = NodePath()
			var new_resolved_key: String = ""
			match typ:
				Animation.TYPE_BLEND_SHAPE:
					classID = 137
					new_path = resolve_gameobject_component_path(animator, path, classID)
					if new_path != NodePath():
						new_path = NodePath(str(new_path) + ":" + str(resolved_subpath))
					new_resolved_key = "B" + str(new_path)
				Animation.TYPE_VALUE:
					new_path = resolve_gameobject_component_path(animator, path, classID)
					if new_path != NodePath():
						new_path = NodePath(str(new_path) + ":" + str(resolved_subpath))
					log_debug("Adapt TYPE_VALUE track " + str(path) + " to " + str(new_path))
					new_resolved_key = "V" + str(new_path)
				Animation.TYPE_ROTATION_3D:
					classID = 4
					new_path = resolve_gameobject_component_path(animator, path, classID)
					log_debug("Adapt TYPE_ROTATION_3D track " + str(path) + " to " + str(new_path))
					new_resolved_key = "T" + str(new_path)
				Animation.TYPE_SCALE_3D:
					classID = 4
					new_path = resolve_gameobject_component_path(animator, path, classID)
					log_debug("Adapt TYPE_SCALE_3D track " + str(path) + " to " + str(new_path))
					new_resolved_key = "T" + str(new_path)
				Animation.TYPE_POSITION_3D:
					classID = 4
					new_path = resolve_gameobject_component_path(animator, path, classID)
					log_debug("Adapt TYPE_POSITION_3D track " + str(path) + " to " + str(new_path))
					new_resolved_key = "T" + str(new_path)
					var resolved_node: Node3D = node_parent.get_node_or_null(new_path)
					log_debug(str(node_parent.name) + ": " + str(resolved_node))
					if resolved_node != null:
						var animator_go: UnityGameObject = animator.gameObject
						var path_split: PackedStringArray = path.split("/")
						var current_fileID: int = 0 if animator_go == null else animator_go.fileID
						var current_obj: Dictionary = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
						for path_component in path_split:
							if current_obj.has(path_component):
								current_fileID = current_obj[path_component]
								current_obj = animator.meta.prefab_gameobject_name_to_fileid_and_children.get(current_fileID, {})
						current_fileID = current_obj.get(classID, current_fileID)
						log_debug("Found fileID " + str(current_fileID))
						var virtual_transform_obj: UnityObject = adapter.instantiate_unity_object_from_utype(animator.meta, current_fileID, classID)
						var godot_rotation: Quaternion = resolved_node.quaternion
						var godot_scale: Vector3 = resolved_node.get_scale()
						var rot_track: int = rot_tracks.get(resolved_key, -1)
						var scale_track: int = scale_tracks.get(resolved_key, -1)
						for key in range(clip.track_get_key_count(track_idx)):
							var ts: float = clip.track_get_key_time(track_idx, key)
							if rot_track != -1:
								godot_rotation = clip.rotation_track_interpolate(rot_track, ts)
							if scale_track != -1:
								godot_scale = clip.scale_track_interpolate(scale_track, ts)
							var pos: Vector3 = clip.position_track_interpolate(track_idx, ts)
							var upos: Vector3 = Vector3(-pos.x, pos.y, pos.z)
							var uquat: Quaternion = godot_rotation
							uquat.y = -uquat.y
							uquat.z = -uquat.z
							var converted_pos: Vector3 = virtual_transform_obj._convert_properties_pos_scale({"m_LocalPosition": upos}, upos, uquat, godot_scale)["position"]
							# log_debug("Adapt key " + str(key) + " ts " + str(ts) + " rot=" + str(godot_rotation.get_euler()) + " scale=" + str(godot_scale) + " pos " + str(pos) + " -> " + str(converted_pos))
							clip.track_set_key_value(track_idx, key, converted_pos)
			if new_path == NodePath():
				log_warn(str(self.uniq_key) + ": anim Unable to resolve " + str(typ) + " track at " + resolved_key + " orig " + str(orig_info))
				identical += 1
				new_track_names.append([clip.track_get_path(track_idx), resolved_key, orig_info])
				continue
			new_track_names.append([new_path, new_resolved_key, orig_info])
			if new_resolved_key == resolved_key:
				identical += 1
		if identical == len(new_track_names):
			return []
		return new_track_names

	func adapt_animation_clip_at_node(animator: RefCounted, node_parent: Node, clip: Animation):
		var generated_track_nodepaths: Array = adapt_track_nodepaths_for_node(animator, node_parent, clip)
		if generated_track_nodepaths.is_empty():  # Already adapted.
			return clip
		if meta.importer_type != "NativeFormatImporter" and meta.importer_type != "DefaultImporter":
			if meta.godot_resources.has(-fileID):
				return meta.get_godot_resource([null, -fileID, null, 0])
			var adapted_resource_path: String = clip.resource_path.get_basename().get_basename() + ".adaptedanim.tres"
			clip = clip.duplicate()
			clip.resource_path = adapted_resource_path
			meta.insert_resource_path(-fileID, clip.resource_path)
		# var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
		var new_resolved_to_default: Dictionary = {}.duplicate()
		for track_idx in range(clip.get_track_count()):
			var new_path: NodePath = generated_track_nodepaths[track_idx][0]
			var new_resolved_key: String = generated_track_nodepaths[track_idx][1]
			var orig_info: Array = generated_track_nodepaths[track_idx][2]
			if not orig_info.is_empty():
				new_resolved_to_default[new_resolved_key] = orig_info
			clip.track_set_path(track_idx, new_path)
		clip.set_meta("resolved_to_default_paths", new_resolved_to_default)
		if clip.resource_path != StringName():
			adapter.unidot_utils.save_resource(clip, clip.resource_path)
		return clip

	# NOTE: This function is dead code (unused).
	# The idea is if there are multiple "solutions" to adapting animation clips, this could allow storing both
	# variants of the animation clip by hash, allowing multiple scenes to share their versions of adapted clips.
	func get_adapted_clip_path_hash(animator: RefCounted, node_parent: Node, clip: Animation) -> int:
		var generated_track_nodepaths: Array = adapt_track_nodepaths_for_node(animator, node_parent, clip)
		if generated_track_nodepaths.is_empty():  # Already adapted.
			return 0
		# var resolved_to_default_paths: Dictionary = clip.get_meta("resolved_to_default_paths", {})
		var new_hash_data: PackedByteArray = PackedByteArray().duplicate()
		var hashctx = HashingContext.new()
		hashctx.start(HashingContext.HASH_MD5)
		for track_idx in range(clip.get_track_count()):
			var new_path: NodePath = generated_track_nodepaths[track_idx][0]
			var new_resolved_key: String = generated_track_nodepaths[track_idx][1]
			var orig_info: Array = generated_track_nodepaths[track_idx][2]
			if not orig_info.is_empty():
				hashctx.update(new_resolved_key.to_utf8_buffer())
				hashctx.update(str(orig_info).to_utf8_buffer())
		# This is arbitrary--just so we can cache existing versions of animation clips
		return hashctx.finish().decode_s64(0)

	func create_animation_clip_at_node(animator: RefCounted, node_parent: Node) -> Animation:  # UnityAnimator
		var anim: Animation = Animation.new()

		var bone_name_to_index := human_trait.bone_name_to_index() # String -> int
		var muscle_name_to_index := human_trait.muscle_name_to_index() # String -> int
		var muscle_index_to_bone_and_axis := human_trait.muscle_index_to_bone_and_axis() # int -> Vector2i
		var special_humanoid_transforms : Dictionary
		for pfx in human_trait.IKPrefixNames:
			for sfx in human_trait.IKSuffixNames:
				special_humanoid_transforms[pfx + sfx] = human_trait.IKSuffixNames[sfx]
		for pfx in human_trait.BoneName:
			special_humanoid_transforms[pfx + "TDOF.x"] = ""
			special_humanoid_transforms[pfx + "TDOF.y"] = ""
			special_humanoid_transforms[pfx + "TDOF.z"] = ""

		var settings: Dictionary = keys.get("m_AnimationClipSettings", {})
		var is_mirror: bool = settings.get("m_Mirror", 0) == 1
		var bake_orientation_into_pose: bool = settings.get("m_LoopBlendOrientation", 0) == 1
		var bake_position_y_into_pose: bool = settings.get("m_LoopBlendPositionY", 0) == 1
		var bake_position_xz_into_pose: bool = settings.get("m_LoopBlendPositionXZ", 0) == 1
		var keep_original_orientation: bool = settings.get("m_KeepOriginalOrientation", 0) == 1
		var keep_original_position_y: bool = settings.get("m_KeepOriginalPositionY", 0) == 1
		var keep_original_position_xz: bool = settings.get("m_KeepOriginalPositionXZ", 0) == 1
		var orientation_offset: float = settings.get("m_OrientationOffsetY", 0.0) * PI / 180.0
		var root_y_level: float = settings.get("m_Level", 0.0)

		# m_AnimationClipSettings[m_StartTime,m_StopTime,m_LoopTime,
		# m_KeepOriginPositionY/XZ/Orientation,m_HeightFromFeet,m_CycleOffset],
		# m_Bounds[m_Center,m_Extent],
		# m_ClipBindingConstant[genericBindings:Array[attribute:hash,customType:20,isPPtrCurve:0,path:hash,script:MonoScript],pptrCurveMapping[??]]
		# m_Compressed:[0,1], m_CompressedRotationCurves, m_Legacy, m_SampleRate (60)
		# m_EditorCurves, m_EulerEditorCurves
		# m_EulerCurves, m_FloatCurves, m_PositionCruves, m_PPtrCurves, m_RotationCurves, m_ScaleCurves
		var resolved_to_default: Dictionary = {}
		var max_ts: float = 0.0
		var humanoid_track_sets: Array[Array]
		var has_humanoid: bool = false
		for i in range(human_trait.BoneCount + 1):
			if i == 0:
				humanoid_track_sets.append([null, null, null, null])
			else:
				humanoid_track_sets.append([null, null, null])
		# humanoid bone idx -> array of Curve object indexed by muscle axis
		# [ [{attr:RootT.x},{attr:RootT.y},{attr:RootT.z}], [{attr:RootQ.x},y,z,w], [Shoulder In-Out,...] ...]

		for track in keys["m_FloatCurves"]:
			var attr: String = track["attribute"]
			var path: String = track.get("path", "")  # Some omit path if for the current GameObject...?
			var classID: int = track["classID"]  # Todo: convet classID to class guid+id
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_warn("Float curve is array")
				track_curve = {"m_Curve": track_curve}
			track_curve = track_curve.duplicate()
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty float curve detected " + path + ":" + attr)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
			if classID == 95 and special_humanoid_transforms.has(attr):
				var flip_sign: bool = false
				if is_mirror:
					if attr.find("Left-Right") != -1:
						track_curve["unidot-mirror"] = true
					elif attr.find("Left") != -1:
						attr = attr.replace("Left", "Right")
					elif attr.find("Right") != -1:
						attr = attr.replace("Right", "Left")
				# Humanoid Root / IK target parameters
				if attr.begins_with("RootT."):
					# hips position (scaled by human scale?)
					humanoid_track_sets[human_trait.BoneCount][special_humanoid_transforms[attr]] = track_curve
				elif attr.begins_with("RootQ."):
					# hips rotation
					humanoid_track_sets[0][special_humanoid_transforms[attr]] = track_curve
				has_humanoid = true
			elif classID == 95 and muscle_name_to_index.has(attr) or human_trait.TraitMapping.has(attr):
				# Humanoid muscle parameters
				var bone_idx_axis: Vector2i = muscle_index_to_bone_and_axis[muscle_name_to_index[human_trait.TraitMapping.get(attr, attr)]]
				humanoid_track_sets[bone_idx_axis.x][bone_idx_axis.y] = track_curve
				has_humanoid = true
			elif classID == 137 and attr.begins_with("blendShape."):
				var bstrack = anim.add_track(Animation.TYPE_BLEND_SHAPE)
				var str_nodepath: String = str(nodepath)
				if str_nodepath.ends_with("/SkinnedMeshRenderer"):
					str_nodepath = "%GeneralSkeleton/" + str_nodepath.split("/")[-2]
				nodepath = NodePath(str_nodepath + ":" + attr.substr(11))
				resolved_to_default["B" + str_nodepath] = [path, attr, classID]
				anim.track_set_path(bstrack, nodepath)
				anim.track_set_interpolation_type(bstrack, Animation.INTERPOLATION_LINEAR)
				var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
				while not key_iter.is_eof:
					var val_variant: Variant = key_iter.next()
					if typeof(val_variant) == TYPE_STRING:
						val_variant = val_variant.to_float()
					var value: float = val_variant
					var ts: float = key_iter.timestamp
					anim.blend_shape_track_insert_key(bstrack, ts, value / 100.0)
			else:
				if classID == 95: # animated Animator parameters / aaps. Humanoid should be done separately.
					nodepath = NodePath(".:metadata/" + attr)
				else:
					var target_node: Node = null
					if node_parent != null:
						target_node = node_parent.get_node(nodepath)
						log_debug("nodepath %s from %s %s became %s" % [str(nodepath), str(node_parent), str(node_parent.name), str(target_node)])
						if target_node == null:
							var gdscriptweird: Node = null
							target_node = gdscriptweird
					# yuk yuk. This needs to be improved but should be a good start for some properties:
					var adapted_obj: UnityObject = adapter.instantiate_unity_object_from_utype(meta, 0, classID)  # no fileID??
					var converted_property_keys = adapted_obj.convert_properties(target_node, {attr: 0.0}).keys()
					if converted_property_keys.is_empty():
						log_warn("Unknown property " + str(attr) + " for " + str(path) + " type " + str(adapted_obj.type), attr, adapted_obj)
						continue
					var converted_property: String = converted_property_keys[0]
					nodepath = NodePath(str(nodepath) + ":" + converted_property)
				log_debug("Generated TYPE_VALUE node path " + str(nodepath))
				var valtrack = anim.add_track(Animation.TYPE_VALUE)
				resolved_to_default["V" + str(nodepath)] = [path, attr, classID]
				anim.track_set_path(valtrack, nodepath)
				anim.track_set_interpolation_type(valtrack, Animation.INTERPOLATION_LINEAR)
				var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
				while not key_iter.is_eof:
					var val_variant: Variant = key_iter.next()
					if typeof(val_variant) == TYPE_STRING:
						val_variant = val_variant.to_float()
					var value: float = val_variant
					var ts: float = key_iter.timestamp
					# FIXME: How does the last optional transition argument work?
					# It says it's used for easing, but I don't see it on blendshape or position tracks?!
					anim.track_insert_key(valtrack, ts, value)
		if has_humanoid:
			var key_iters: Array[LockstepKeyframeiterator]
			key_iters.resize(human_trait.BoneCount + 1)
			var used_ts: Dictionary
			var keyframe_timestamps: Array[float] # will sort
			var keyframe_affects_rootQ: Dictionary
			var per_bone_keyframe_used_ts: Array[Dictionary]
			var per_bone_timestamps: Array[PackedFloat64Array]
			per_bone_keyframe_used_ts.resize(human_trait.BoneCount + 1)
			per_bone_timestamps.resize(human_trait.BoneCount + 1)
			#var donated_limb_keyframe_times_and_twists: Array[PackedVector2Array]
			#var transforms: Array[Transform3D]
			#transforms.resize(human_trait.BoneCount)
			for bone_idx in range(0, human_trait.BoneCount + 1):
				var humanoid_track_set: Array = humanoid_track_sets[bone_idx]
				var keyframe_iters: Array[KeyframeIterator]
				keyframe_iters.resize(len(humanoid_track_set))
				for i in range(len(humanoid_track_set)):
					# may contain null if no animation curve exists.
					if typeof(humanoid_track_set[i]) == TYPE_DICTIONARY:
						# This is the outer object (["curve"]["m_Curve"])
						keyframe_iters[i] = KeyframeIterator.new(humanoid_track_set[i])
				var is_position_track: bool = bone_idx == human_trait.BoneCount
				var key_iter := LockstepKeyframeiterator.new(keyframe_iters, is_position_track)
				key_iters[bone_idx] = key_iter
				var last_ts: float = 0.0
				var same_ts: bool = false
				var itercnt: int = 0
				var affecting_bone_idx: int = human_trait.extraAffectingBones.get(bone_idx, -1)
				while not key_iter.is_eof and itercnt < 100000:
					itercnt += 1
					key_iter.next()
					var ts: float = key_iter.timestamp
					if human_trait.rootQAffectingBones.has(bone_idx) and not keyframe_affects_rootQ.has(ts):
						keyframe_affects_rootQ[ts] = true
					if not used_ts.has(ts):
						keyframe_timestamps.append(ts)
						used_ts[ts] = true
					if not per_bone_keyframe_used_ts[bone_idx].has(ts):
						per_bone_keyframe_used_ts[bone_idx][ts] = true
						per_bone_timestamps[bone_idx].append(ts)
					if affecting_bone_idx != -1 and not per_bone_keyframe_used_ts[affecting_bone_idx].has(ts):
						per_bone_keyframe_used_ts[affecting_bone_idx][ts] = true
						per_bone_timestamps[affecting_bone_idx].append(ts)
				key_iter.reset()
			keyframe_timestamps.sort()
			per_bone_keyframe_used_ts.clear()
			used_ts.clear()
			var timestamp_count := len(keyframe_timestamps)
			var body_bone_count := len(human_trait.boneIndexToParent)

			for bone_idx in range(1, human_trait.BoneCount):
				var godot_human_name: String = human_trait.GodotHumanNames[bone_idx]
				var gd_track: int = anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(gd_track, "%GeneralSkeleton:" + godot_human_name)
				anim.track_set_interpolation_type(gd_track, Animation.INTERPOLATION_LINEAR)
				var bone_name: String = godot_human_name

				var key_iter := key_iters[bone_idx]
				var bone_timestamps: PackedFloat64Array = per_bone_timestamps[bone_idx]
				bone_timestamps.sort()
				var affected_by_bone_idx: int = human_trait.extraAffectedByBones.get(bone_idx, -1)
				var affected_by_key_iter: LockstepKeyframeiterator = null
				if affected_by_bone_idx != -1:
					affected_by_key_iter = key_iters[affected_by_bone_idx]
				var last_ts: float = 0
				for ts_idx in range(len(bone_timestamps)):
					var ts: float = bone_timestamps[ts_idx]
					var val_variant: Variant = key_iter.next(ts - last_ts)
					var this_swing_twist: Vector3 = val_variant as Vector3
					var weight = 1.0
					var pre_value := Quaternion.IDENTITY
					if affected_by_bone_idx != -1:
						weight = 0.5
						this_swing_twist.x *= weight
						var affected_by_variant: Variant = affected_by_key_iter.next(ts - last_ts)
						var affected_by_twist: Vector3 = affected_by_variant as Vector3
						affected_by_twist = Vector3(affected_by_twist.x * (1.0 - weight), 0, 0)
						pre_value = humanoid_transform_util.calculate_humanoid_rotation(affected_by_bone_idx, affected_by_twist, true)
					# swing-twist muscle track
					var value: Quaternion = humanoid_transform_util.calculate_humanoid_rotation(bone_idx, this_swing_twist)
					anim.rotation_track_insert_key(gd_track, ts, pre_value * value)
					last_ts = ts
				key_iter.reset()
				if affected_by_bone_idx != -1:
					affected_by_key_iter.reset()

			if not keyframe_timestamps.is_empty():
				# Root position track
				var gd_track_root_pos: int = anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(gd_track_root_pos, "%GeneralSkeleton:Root")
				anim.track_set_interpolation_type(gd_track_root_pos, Animation.INTERPOLATION_LINEAR)
				var base_root_pos_offset := Vector3.ZERO
				if bake_position_xz_into_pose and bake_position_y_into_pose:
					if not bake_position_y_into_pose:
						if keep_original_position_y:
							base_root_pos_offset.y = root_y_level # Hips offset is always precisely 1
						else:
							# Ignoring m_HeightFromFeet boolean. it's a small effect and not sure how it's calculated.
							base_root_pos_offset.y = 1.0 + root_y_level

					anim.position_track_insert_key(gd_track_root_pos, 0.0, Vector3())
				# Hips position track
				var gd_track_pos: int = anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(gd_track_pos, "%GeneralSkeleton:Hips")
				anim.track_set_interpolation_type(gd_track_pos, Animation.INTERPOLATION_LINEAR)
				var key_iter_pos := key_iters[human_trait.BoneCount] # LockstepKeyframeiterator.new(keyframe_iters)

				# Root rotation track
				var gd_track_root_rot: int = anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(gd_track_root_rot, "%GeneralSkeleton:Root")
				anim.track_set_interpolation_type(gd_track_root_rot, Animation.INTERPOLATION_LINEAR)
				var base_y_rotation := Quaternion.IDENTITY
				if bake_position_xz_into_pose and bake_position_y_into_pose:
					var euler_y: float = - orientation_offset
					base_y_rotation = Quaternion.from_euler(Vector3(0, euler_y, 0))
					anim.rotation_track_insert_key(gd_track_root_rot, 0.0, base_y_rotation) # Root rest rotation is identity

				# Hips rotation track
				var gd_track_rot: int = anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(gd_track_rot, "%GeneralSkeleton:Hips")
				anim.track_set_interpolation_type(gd_track_rot, Animation.INTERPOLATION_LINEAR)
				var key_iter_rot := key_iters[0] # LockstepKeyframeiterator.new(keyframe_iters)

				var last_ts: float = 0
				var body_positions: Array[Vector3]
				var body_rotations: Array[Quaternion]
				body_positions.resize(body_bone_count)
				body_rotations.resize(body_bone_count)
				# We need to evaluate the position tracks at each timestep and calculate
				# the human pose so we can apply the center of mass corerction
				for ts_idx in range(len(keyframe_timestamps)):
					var ts: float = keyframe_timestamps[ts_idx]
					body_positions[0] = human_trait.xbot_positions[0] # Hips position is hardcoded
					body_rotations[0] = Quaternion.IDENTITY # rest Hips rotation in Godot is always identity
					for body_bone_idx in range(1, body_bone_count):
						var bone_idx: int = human_trait.boneIndexToMono[body_bone_idx]
						var parent_body_bone_idx: int = human_trait.boneIndexToParent[body_bone_idx]
						var local_bone_pos: Vector3 = human_trait.xbot_positions[body_bone_idx]
						var key_iter := key_iters[bone_idx]
						var pre_dbg: String = key_iter.debug()
						var val_variant: Variant = key_iter.next(ts - last_ts)
						var swing_twist: Vector3 = val_variant as Vector3
						# swing-twist muscle track
						var local_rot: Quaternion = humanoid_transform_util.calculate_humanoid_rotation(bone_idx, swing_twist)
						if not local_rot.is_normalized():
							push_error("local_rot " + str(body_bone_idx) + " is not normalized!")
							return
						if (key_iter.timestamp != ts) and not key_iter.is_eof:
							push_warning("State was: " + pre_dbg)
							push_error("bone " + str(human_trait.GodotHumanNames[bone_idx]) + " timestamp " + str(key_iter.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter.debug())
						var par_position := body_positions[parent_body_bone_idx]
						var par_rotation := body_rotations[parent_body_bone_idx]
						if not par_rotation.is_normalized():
							push_error("par_rotation " + str(parent_body_bone_idx) + " is not normalized!")
							return
						body_positions[body_bone_idx] = par_position + par_rotation * local_bone_pos
						body_rotations[body_bone_idx] = par_rotation * local_rot
						if not body_rotations[body_bone_idx].is_normalized():
							push_error("body_rotation " + str(body_bone_idx) + " is not normalized!")
							return

					# Calulcate center of mass
					var pre_dbg_rot: String = key_iter_rot.debug()
					var val_rotation_variant: Variant = key_iter_rot.next(ts - last_ts)
					var root_q: Quaternion = val_rotation_variant as Quaternion
					if is_mirror:
						root_q.y = -root_q.y
						root_q.z = -root_q.z
					if not root_q.is_normalized():
						push_error("root q is not normalized!")
						return
					if (key_iter_rot.timestamp != ts) and not key_iter_rot.is_eof:
						push_warning("RootQ State was: " + pre_dbg_rot)
						push_error("RootQ timestamp " + str(key_iter_rot.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter_rot.debug())
					var delta_q: Quaternion = humanoid_transform_util.get_hips_rotation_delta(body_positions, root_q)
					if not delta_q.is_normalized():
						push_error("delta_q is not normalized!")
						return
					if keyframe_affects_rootQ.has(ts):
						var y_rotation: Quaternion = base_y_rotation
						if not bake_orientation_into_pose:
							var euler_y: float = root_q.get_euler(EULER_ORDER_YZX).y - orientation_offset
							y_rotation = Quaternion.from_euler(Vector3(0, euler_y, 0))
							anim.rotation_track_insert_key(gd_track_root_rot, ts, y_rotation) # Root rest rotation is identity
						anim.rotation_track_insert_key(gd_track_rot, ts, y_rotation.inverse() * delta_q) # Hips rest rotation is identity

					var pre_dbg_pos: String = key_iter_pos.debug()
					var val_position_variant: Variant = key_iter_pos.next(ts - last_ts)
					var root_t: Vector3 = val_position_variant as Vector3
					if is_mirror:
						root_t.x = -root_t.x
					if (key_iter_pos.timestamp != ts) and not key_iter_pos.is_eof:
						push_warning("RootT State was: " + pre_dbg_pos)
						push_error("RootT timestamp " + str(key_iter_pos.timestamp) + " is not ts " + str(ts) + " from " + str(last_ts) + " dbg " + key_iter_pos.debug())
					var hips_pos: Vector3 = humanoid_transform_util.get_hips_position(body_positions, body_rotations, delta_q, root_t)
					var root_pos_offset := base_root_pos_offset
					if not bake_position_xz_into_pose:
						if keep_original_position_xz:
							root_pos_offset = Vector3(hips_pos.x, 0, hips_pos.z)
						else:
							root_pos_offset = Vector3(root_t.x, 0, root_t.z)
					if not bake_position_y_into_pose:
						if keep_original_position_y:
							root_pos_offset.y = hips_pos.y - 1.0 + root_y_level # Hips offset is always precisely 1
						else:
							# Ignoring m_HeightFromFeet boolean. it's a small effect and not sure how it's calculated.
							root_pos_offset.y = root_t.y + root_y_level
					if not bake_position_xz_into_pose or not bake_position_y_into_pose:
						anim.position_track_insert_key(gd_track_root_pos, ts, root_pos_offset)
					anim.position_track_insert_key(gd_track_pos, ts, hips_pos - root_pos_offset)
					last_ts = ts
		for track in keys["m_PositionCurves"]:
			var path: String = track.get("path", "")
			var classID: int = 4
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_warn("position curve is array")
				track_curve = {"m_Curve": track_curve}
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty position curve detected " + path)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
			var postrack = anim.add_track(Animation.TYPE_POSITION_3D)
			resolved_to_default["T" + str(nodepath)] = [path, "", classID]
			anim.track_set_path(postrack, nodepath)
			anim.track_set_interpolation_type(postrack, Animation.INTERPOLATION_LINEAR)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var value: Vector3 = key_iter.next()
				var ts: float = key_iter.timestamp
				if path.ends_with("Spine"):
					log_debug("Spine " + str(ts) + " value " + str(value) + " -> " + str(Vector3(-1, 1, 1) * value))
				anim.position_track_insert_key(postrack, ts, Vector3(-1, 1, 1) * value)

		for track in keys["m_EulerCurves"]:
			var path: String = track.get("path", "")
			var classID: int = 4
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_warn("euler curve is array")
				track_curve = {"m_Curve": track_curve}
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty euler curve detected " + path)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
			var rottrack = anim.add_track(Animation.TYPE_ROTATION_3D)
			resolved_to_default["T" + str(nodepath)] = [path, "", classID]
			anim.track_set_path(rottrack, nodepath)
			anim.track_set_interpolation_type(rottrack, Animation.INTERPOLATION_LINEAR)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var value: Vector3 = key_iter.next()
				var ts: float = key_iter.timestamp
				# NOTE: value is assumed to be YXZ in Godot terms, but it has 6 different modes in Unity.
				var godot_euler_mode: int = EULER_ORDER_YXZ
				match track["curve"].get("m_RotationOrder", 2):
					0:  # XYZ
						godot_euler_mode = EULER_ORDER_ZYX
					1:  # XZY
						godot_euler_mode = EULER_ORDER_YZX
					2:  # YZX
						godot_euler_mode = EULER_ORDER_XZY
					3:  # YXZ
						godot_euler_mode = EULER_ORDER_ZXY
					4:  # ZXY
						godot_euler_mode = EULER_ORDER_YXZ
					5:  # ZYX
						godot_euler_mode = EULER_ORDER_XYZ
				# This is more complicated than this...
				# The keys need to be baked out and sampled using this mode.
				anim.rotation_track_insert_key(rottrack, ts, Basis.FLIP_X.inverse() * Basis.from_euler(value * PI / 180.0, godot_euler_mode) * Basis.FLIP_X)

		for track in keys["m_RotationCurves"]:
			var path: String = track.get("path", "")
			var classID: int = 4
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_warn("rotation curve is array")
				track_curve = {"m_Curve": track_curve}
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty rotation curve detected " + path)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
			var rottrack = anim.add_track(Animation.TYPE_ROTATION_3D)
			resolved_to_default["T" + str(nodepath)] = [path, "", classID]
			anim.track_set_path(rottrack, nodepath)
			anim.track_set_interpolation_type(rottrack, Animation.INTERPOLATION_LINEAR)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var value: Quaternion = key_iter.next()
				var ts: float = key_iter.timestamp
				anim.rotation_track_insert_key(rottrack, ts, Basis.FLIP_X.inverse() * Basis(value) * Basis.FLIP_X)

		for track in keys["m_ScaleCurves"]:
			var path: String = track.get("path", "")
			var classID: int = 4
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_warn("scale curve is array")
				track_curve = {"m_Curve": track_curve}
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty scale curve detected " + path)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			var nodepath = NodePath(str(resolve_gameobject_component_path(animator, path, classID)))
			var scaletrack = anim.add_track(Animation.TYPE_SCALE_3D)
			resolved_to_default["T" + str(nodepath)] = [path, "", classID]
			anim.track_set_path(scaletrack, nodepath)
			anim.track_set_interpolation_type(scaletrack, Animation.INTERPOLATION_LINEAR)
			var key_iter: KeyframeIterator = KeyframeIterator.new(track_curve)
			while not key_iter.is_eof:
				var value: Vector3 = key_iter.next()
				var ts: float = key_iter.timestamp
				anim.scale_track_insert_key(scaletrack, ts, value)

		for track in keys["m_PPtrCurves"]:
			var path: String = track.get("path", "")
			var classID: int = 4
			var track_curve = track["curve"]
			if typeof(track_curve) == TYPE_ARRAY:
				log_debug("pptr curve is array: " + str(track_curve))
				track_curve = {"m_Curve": track_curve}
			if len(track_curve.get("m_Curve", [])) == 0:
				log_warn("Empty pptr curve detected " + path)
				continue
			for keyframe in track_curve["m_Curve"]:
				max_ts = maxf(max_ts, keyframe["time"])
			log_warn("PPtr curves (material swaps) are not yet implemented")
			# TYPE_VALUE track should mostly work for this.
			# This is mostly only used for material overrides.
			# Which will map to MeshInstance3D:surface_material_override/0 and so on.
			pass

		if max_ts <= 0.0:
			max_ts = 1.0 # Animations are 1 second long by default, but can be shorter based on keyframe
		if settings.get("m_StopTime", 0.0) > 0.0:
			max_ts = settings.get("m_StopTime", 0.0)
		anim.length = max_ts
		if settings.get("m_LoopTime", 0) != 0:
			anim.loop_mode = Animation.LOOP_LINEAR
		anim.set_meta("resolved_to_default_paths", resolved_to_default)
		if anim.resource_path == StringName():
			var res_path = StringName()
			if self.fileID == meta.main_object_id:
				if not meta.path.ends_with(".tres"):
					meta.rename(meta.path + ".tres")
				res_path = meta.path
			else:
				res_path = meta.path.get_basename() + (".%d.tres" % [self.fileID])
			res_path = "res://" + res_path
			adapter.unidot_utils.save_resource(anim, res_path)
			meta.insert_resource(self.fileID, anim)
		else:
			adapter.unidot_utils.save_resource(anim, anim.resource_path)
		return anim


class UnityTexture:
	extends UnityObject

	func get_godot_extension() -> String:
		return ".tex.tres"

	func get_image_data() -> PackedByteArray:
		# hex_decode
		if typeof(self.keys["image data"]) == TYPE_PACKED_BYTE_ARRAY:
			return self.keys["image data"]
		var tld = self.keys["_typelessdata"]
		var hexdec: PackedByteArray = aligned_byte_buffer.new().hex_decode(tld)  # a bit slow :'-(
		log_debug("get_image_data _typelessdata LEN " + str(len(tld)) + " is " + str(len(hexdec)))
		return hexdec

	var width: int:
		get:
			return self.keys["m_Width"]

	var height: int:
		get:
			return self.keys["m_Height"]

	var mipmaps: int:
		get:
			return self.keys["m_MipCount"]

	func get_unaligned_size() -> int:
		var format_index: int = keys.get("m_TextureFormat", keys.get("m_Format", 0))
		match format_index:
			1, 63:
				return 1
			2, 7, 9, 13, 15, 62:
				return 2
			3:
				return 3
			73:
				return 6
			17, 19, 74:
				return 8
			20:
				return 16
			4, 5, 14, 16, 18, 72:
				return 4
			_:
				return 0  # Compressed formats. Untested...

	func get_godot_format() -> int:
		var format_index: int = keys.get("m_TextureFormat", keys.get("m_Format", 0))
		match format_index:
			1:  # A8
				return Image.FORMAT_R8
			2:  # ARGB4444
				return Image.FORMAT_RGBA4444
			3:
				return Image.FORMAT_RGB8
			4:
				return Image.FORMAT_RGBA8
			5:  # ARGB32
				return Image.FORMAT_RGBA8
			7:
				return Image.FORMAT_RGB565
			9:  # R16 (16-bit int). not supported in Godot
				return Image.FORMAT_RH
			10:
				return Image.FORMAT_DXT1
			11:
				return Image.FORMAT_DXT3
			12:
				return Image.FORMAT_DXT5
			13:
				return Image.FORMAT_RGBA4444
			14:  # BGRA32
				return Image.FORMAT_RGBA8
			15:
				return Image.FORMAT_RH
			16:
				return Image.FORMAT_RGH
			17:
				return Image.FORMAT_RGBAH
			18:
				return Image.FORMAT_RF
			19:
				return Image.FORMAT_RGF
			20:
				return Image.FORMAT_RGBAF
			21:  # YUY2 for video playback
				return Image.FORMAT_RGBA8
			22:
				return Image.FORMAT_RGBE9995
			24:  # BC6H
				return Image.FORMAT_BPTC_RGBFU
			25:
				return Image.FORMAT_BPTC_RGBA
			26:  # BC4, compressed one-channel texture
				return Image.FORMAT_RGTC_R
			27:  # BC5, compressed two-channel texture
				return Image.FORMAT_RGTC_RG
			28:  # DXT1 crunched
				log_fail("ERROR: DXT1 Crunch not supported")
			29:  # DXT5 crunched
				log_fail("ERROR: DXT5 Crunch not supported")
			30:
				log_fail("ERROR: PVRTC RGB2 not supported")
			31:
				log_fail("ERROR: PVRTC RGBA2 not supported")
			32:
				log_fail("ERROR: PVRTC RGB4 not supported")
			33:
				log_fail("ERROR: PVRTC RGBA4 not supported")
			34:
				return Image.FORMAT_ETC
			41:
				return Image.FORMAT_ETC2_R11
			42:
				return Image.FORMAT_ETC2_R11S
			43:
				return Image.FORMAT_ETC2_RG11
			44:
				return Image.FORMAT_ETC2_RG11S
			45:
				return Image.FORMAT_ETC2_RGB8
			46:
				return Image.FORMAT_ETC2_RGB8A1
			47:
				return Image.FORMAT_ETC2_RGBA8
			62:  # RG16 int
				return Image.FORMAT_RG8
			63:  # R8 int
				return Image.FORMAT_R8
			64:  # ETC crunched
				log_fail("ERROR: ETC Crunch not supported")
			65:  # ETC2 crunched
				log_fail("ERROR: ETC2 Crunch not supported")
			72:  # RG32 int
				return Image.FORMAT_RGH
			73:  # RGB48 int
				return Image.FORMAT_RGBH
			74:  # RGB64 int
				return Image.FORMAT_RGBAH
			_:
				log_fail("ERROR: Format " + str(format_index) + " is not supported")
		return Image.FORMAT_RGBA8  # most common

	func gen_image_layer(imgdata: PackedByteArray, byteoffset: int, length: int) -> Image:
		var format: int = self.get_godot_format()
		log_debug("Format for " + meta.path + " is " + str(format))
		var img: Image = Image.new()
		log_debug(str(len(imgdata)) + "," + str(byteoffset) + "," + str(byteoffset + length))
		if byteoffset != 0 or length != 0:
			imgdata = imgdata.slice(byteoffset, byteoffset + length)
		log_debug(" is now " + str(len(imgdata)))
		#elif length != 0:
		img.create_from_data(self.width, self.height, self.mipmaps > 1, format, imgdata)
		return img

	func get_godot_type() -> String:
		return "Texture"

	func gen_image() -> Image:
		var imgdata: PackedByteArray = self.get_image_data()
		return gen_image_layer(imgdata, 0, 0)


class UnityTexture2D:
	extends UnityTexture

	func get_godot_type() -> String:
		return "Texture2D"

	func create_godot_resource() -> Resource:
		var imgtex: ImageTexture = ImageTexture.new()
		imgtex.create_from_image(self.gen_image())
		return imgtex


class UnityTextureLayered:
	extends UnityTexture

	var depth: int:
		get:
			return keys["m_Depth"]

	func gen_images(is_3d: bool = false) -> Array:
		var imgdata: PackedByteArray = self.get_image_data()
		log_debug("Depth is " + str(self.depth) + " len(imgdata) is " + str(len(imgdata)))
		if self.depth <= 0:
			return []
		var stride_per: int = len(imgdata) / self.depth
		if stride_per <= 0:
			log_fail("len(imgdata) per layer is 0")
			return []
		var images: Array = []
		var offset: int = 0
		var unaligned = (self.width * self.height * self.get_unaligned_size()) % 4
		var length_per: int = stride_per
		var unaligned_size: int = get_unaligned_size()
		if unaligned_size != 0:
			length_per = 0
			var mip_dim = max(self.width, self.height)
			var mip_w = self.width
			var mip_h = self.height
			while mip_dim != 0:
				length_per += mip_w * mip_h * unaligned_size
				mip_w = max(1, mip_w / 2)
				mip_h = max(1, mip_h / 2)
				mip_dim /= 2
				if is_3d or self.mipmaps == 0:
					break
		else:
			length_per = 0
			var tmp_img = Image.new()
			tmp_img.create(self.width, self.height, true, self.get_godot_format())
			var mip_idx = 0
			var mip_dim = max(self.width, self.height)
			var last_off = 0
			while mip_dim != 1:
				mip_dim /= 2
				length_per = tmp_img.get_mipmap_offset(mip_idx)
				mip_idx += 1
				if mip_dim == 1:
					length_per += length_per - last_off  # last two mipmaps are always the same for compressed.
					break
				last_off = length_per
		log_debug(str(length_per) + " -> " + str(stride_per))

		for i in range(self.depth):
			images.append(self.gen_image_layer(imgdata, offset, length_per))
			offset += stride_per
		return images


class UnityTexture2DArray:
	extends UnityTextureLayered

	func get_godot_type() -> String:
		return "Texture2DArray"

	func create_godot_resource() -> Resource:
		var imgtex: Texture2DArray = Texture2DArray.new()
		imgtex.create_from_images(self.gen_images())
		return imgtex


class UnityTexture3D:
	extends UnityTextureLayered

	func get_godot_type() -> String:
		return "Texture3D"

	func create_godot_resource() -> Resource:
		var imgtex: ImageTexture3D = ImageTexture3D.new()
		imgtex.create(self.get_godot_format(), self.width, self.height, self.depth, false, self.gen_images(true))
		return imgtex


class UnityCubemap:
	extends UnityTextureLayered

	func get_godot_type() -> String:
		return "Cubemap"

	func create_godot_resource() -> Resource:
		var imgtex: Cubemap = Cubemap.new()
		imgtex.create_from_images(self.gen_images())
		return imgtex


class UnityCubemapArray:
	extends UnityTextureLayered

	func get_godot_type() -> String:
		return "CubemapArray"

	func create_godot_resource() -> Resource:
		var imgtex: CubemapArray = CubemapArray.new()
		imgtex.create_from_images(self.gen_images())
		return imgtex


class UnityRenderTexture:
	extends UnityTexture

	func get_godot_type() -> String:
		return "ViewportTexture"

	pass


class UnityCustomRenderTexture:
	extends UnityRenderTexture
	pass


class UnityTerrainLayer:
	extends UnityObject

	func get_godot_type() -> String:
		return "MeshLibrary"

	func get_godot_extension() -> String:
		return ".terrainlayer.tres"

	func create_godot_resource() -> Resource:
		var mat = StandardMaterial3D.new()
		var diffuse_tex: Texture2D = meta.get_godot_resource(keys.get("m_DiffuseTexture", [null, 0, null, null]))
		var tilesize: Vector2 = keys.get("m_TileSize", Vector2(1, 1))
		var tileoffset: Vector2 = keys.get("m_TileOffset", Vector2(0, 0))
		var spec: Color = keys.get("m_Specular", Color.TRANSPARENT)
		var metal: float = keys.get("m_Metallic", 0.0)
		var smooth: float = keys.get("m_Smoothness", 0.0)
		mat.albedo_texture = diffuse_tex
		mat.roughness = 1.0 - smooth
		mat.metallic = metal
		# mat.metallic_specular = spec.a
		mat.uv1_scale = Vector3(1.0 / tilesize.x, 1.0 / tilesize.y, 0.0)
		mat.uv1_offset = Vector3(tileoffset.x / tilesize.x, tileoffset.y / tilesize.x, 0.0)

		var normal_tex: Texture2D = meta.get_godot_resource(keys.get("m_NormalMapTexture", [null, 0, null, null]))
		var normalscale: float = keys.get("m_NormalScale", 1.0)
		mat.normal_enabled = normal_tex != null
		mat.normal_texture = normal_tex
		mat.normal_scale = normalscale

		# Mask not implemented for now.
		# m_DiffuseRemapMin: {x: 0, y: 0, z: 0, w: 0}
		# m_DiffuseRemapMax: {x: 1, y: 1, z: 1, w: 1}
		# m_MaskMapRemapMin: {x: 0, y: 0, z: 0, w: 0}
		# m_MaskMapRemapMax: {x: 1, y: 1, z: 1, w: 1}
		#var maskmap_tex: Texture2D = meta.get_godot_resource(keys.get("m_MaskMapTexture", [null,0,null,null]))
		return mat


class UnityTerrainData:
	extends UnityObject
	var mesh_data: ArrayMesh = null
	var collision_mesh: ConcavePolygonShape3D = null
	var terrain_mat: Material = null
	var other_resources: Dictionary = {}
	var scale: Vector3 = Vector3.ONE
	var resolution: int = 0

	func get_godot_type() -> String:
		return "HeightMapShape3D"

	func resolve_godot_resource(fileRef: Array) -> Resource:
		if fileRef[2] == null or fileRef[2] == meta.guid:
			return other_resources[fileRef[1]]
		return meta.get_godot_resource(fileRef)

	func find_meshinst(node: Node) -> MeshInstance3D:
		if node is MeshInstance3D:
			log_debug("Returning " + str(node.name))
			return node
		for n in node.get_children():
			var res: MeshInstance3D = find_meshinst(n)
			if res != null:
				return res
		return null

	func gen_multimeshes() -> Array:
		var tree_prototype_matrices: Array[Transform3D]
		var multimeshes: Array[MultiMesh]
		var material_overrides: Array  # can't use typed array if some elements are null
		var transform_counts: PackedInt32Array = PackedInt32Array().duplicate()
		var detail_data: Dictionary = keys.get("m_DetailDatabase", {})
		var bend_factors: Array[float]
		for detail in detail_data.get("m_TreePrototypes", []):
			var target_ref: Array = detail.get("prefab", [null, 0, null, null])
			var tree_scene: Node = meta.get_godot_node(target_ref)
			var meshinst: MeshInstance3D = null
			var mesh: Mesh = null
			if tree_scene != null:
				recursive_log_debug(tree_scene, " %d>   " % [len(multimeshes)])
				meshinst = find_meshinst(tree_scene)  # tree_scene.find_nodes("*", "MeshInstance3D")
			if meshinst != null:
				mesh = meshinst.mesh
				if meshinst.material_override != null:
					material_overrides.append(meshinst.material_override)
				elif meshinst.get_surface_override_material_count() >= 1 and meshinst.get_surface_override_material(0) != null:
					if meshinst.get_surface_override_material_count() > 1:
						log_fail("Godot Multimesh does not implement per-surface override materials! Will look wrong.")
					material_overrides.append(meshinst.get_surface_override_material(0))
				else:
					material_overrides.append(null)
				var xform: Transform3D = meshinst.transform
				var tmpnode: Node3D = meshinst.get_parent_node_3d()
				while tmpnode != null:
					xform = tmpnode.transform * xform
					tmpnode = tmpnode.get_parent_node_3d()
				tree_prototype_matrices.append(xform)
			else:
				tree_prototype_matrices.append(Transform3D.IDENTITY)
				material_overrides.append(null)
			var mm: MultiMesh = MultiMesh.new()
			mm.resource_name = (str(meta.lookup_meta(target_ref).resource_name).get_file().get_basename() if tree_scene != null else "")
			if mm.resource_name == "":
				mm.resource_name = StringName("tree%d" % [len(multimeshes)])
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			bend_factors.append(detail.get("bendFactor", 0.0))  # not yet implemented.
			multimeshes.append(mm)
			transform_counts.append(0)
			if tree_scene != null:
				tree_scene.queue_free()
		# instances:
		# {'position': {'x': 0.378, 'y': 0.0074, 'z': 0.716}, 'widthScale': 0.73, 'heightScale': 0.73,
		# 'rotation': 2.5, 'color': {'rgba': 4293848814}, 'lightmapColor': {'rgba': 4294967295}, 'index': 5}
		for inst in detail_data.get("m_TreeInstances", []):
			var idx: int = inst["index"]
			transform_counts[idx] += 1
		for idx in range(len(multimeshes)):
			multimeshes[idx].instance_count = transform_counts[idx]
			transform_counts[idx] = 0
		for inst in detail_data.get("m_TreeInstances", []):
			var idx: int = inst["index"]
			var wid: float = inst.get("widthScale", 1.0)
			var hei: float = inst.get("heightScale", 1.0)
			var rot: float = inst.get("rotation", 0.0)
			var pos: Vector3 = inst["position"] * scale * Vector3(resolution, 1.0, resolution)
			var col: Color = inst.get("color", Color.WHITE)
			var bas: Basis = Basis.from_euler(Vector3(0, rot, 0)).scaled(Vector3(wid, hei, wid))
			var xform: Transform3D = Transform3D(bas, pos) * tree_prototype_matrices[idx]
			xform = Transform3D.FLIP_X.inverse() * xform * Transform3D.FLIP_X
			multimeshes[idx].set_instance_transform(transform_counts[idx], xform)
			multimeshes[idx].set_instance_color(transform_counts[idx], col)
			transform_counts[idx] += 1
		return [multimeshes, material_overrides]

	func recursive_log_debug(node: Node, indent: String = ""):
		var fnstr = "" if str(node.scene_file_path) == "" else (" (" + str(node.scene_file_path) + ")")
		log_debug(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
		#log_debug(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
		var new_indent: String = indent + "  "
		for c in node.get_children():
			recursive_log_debug(c, new_indent)

	func get_extra_resources() -> Dictionary:
		var dict = (
			{
				self.fileID ^ 0x1234567: ".terrain.mat.tres",
				self.fileID ^ 0xdeca604: ".terrain.mesh.res",
				self.fileID ^ 0xc0111de4: ".terrain.collider.res",
			}
			. duplicate()
		)
		var found_splatmap: bool = false
		for other_id in meta.fileid_to_utype:
			if other_id != self.fileID:
				var other_object: UnityObject = meta.parsed.assets.get(other_id)
				if meta.parsed.assets.has(other_id):
					var res: Resource = meta.parsed.assets.get(other_id).create_godot_resource()
					if res != null:
						other_resources[other_id] = res
						if other_object.type.begins_with("Texture"):
							if found_splatmap:
								dict[other_id] = "." + str(other_id) + ".res"
							else:
								dict[other_id] = ".splatmap.res"
								found_splatmap = true
						else:
							dict[other_id] = other_object.get_godot_extension()

		#var vertices: PackedVector3Array = PackedVector3Array().duplicate()
		var heightmap: Dictionary = keys.get("m_Heightmap")
		self.resolution = heightmap["m_Resolution"]
		var vertex_count = resolution * resolution
		var index_count = (resolution - 1) * (resolution - 1)
		assert(resolution * resolution == len(heightmap["m_Heights"]))
		var heights: PackedInt32Array = heightmap.get("m_Heights")
		self.scale = heightmap.get("m_Scale")
		#var surface = SurfaceTool.new()
		#surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vertices: PackedVector3Array = PackedVector3Array().duplicate()
		vertices.resize(resolution * resolution)
		var uvs: PackedVector2Array = PackedVector2Array().duplicate()
		uvs.resize(resolution * resolution)
		var indices_tris: PackedInt32Array = PackedInt32Array().duplicate()
		indices_tris.resize((resolution - 1) * (resolution - 1) * 6 + (resolution - 1) * 3)
		var idx: int = 0
		for resy in range(resolution):
			for resx in range(resolution):
				var heightint: int = heights[resy * resolution + resx]
				vertices[idx] = scale * Vector3(-1.0 * resx, heightint / 32767.0, 1.0 * resy)
				uvs[idx] = Vector2((1.0 * resx) / resolution, (1.0 * resy) / resolution)
				#surface.set_uv(Vector2((1.0 * resx) / resolution, (1.0 * resy) / resolution))
				#surface.add_vertex(vertices[idx])
				idx += 1
		idx = 0
		# Big hack because we are using SurfaceTool to generate vertices.
		# SurfaceTool outputs vertices in index order. We want to ensure each vertex is referenced once in order.
		# This seems to only affect the first row, because the second row is already referenced in order below.
		for resx in range(resolution - 1):
			indices_tris[idx] = resx
			indices_tris[idx + 1] = resx + 1
			indices_tris[idx + 2] = resx
			idx += 3
		for resy in range(resolution - 1):
			for resx in range(resolution - 1):
				var baseidx: int = resy * resolution + resx
				indices_tris[idx] = (baseidx + resolution)
				indices_tris[idx + 1] = (baseidx + resolution + 1)
				indices_tris[idx + 2] = (baseidx)
				indices_tris[idx + 3] = (baseidx)
				indices_tris[idx + 4] = (baseidx + resolution + 1)
				indices_tris[idx + 5] = (baseidx + 1)
				#surface.add_index(baseidx + resolution)
				#surface.add_index(baseidx)
				#surface.add_index(baseidx + resolution + 1)
				#surface.add_index(baseidx + resolution + 1)
				#surface.add_index(baseidx)
				#surface.add_index(baseidx + 1)
				idx += 6
		var temp_mesh: ArrayMesh = ArrayMesh.new()
		var really_temp_arrays: Array = []
		really_temp_arrays.resize(Mesh.ARRAY_MAX)
		really_temp_arrays[Mesh.ARRAY_VERTEX] = vertices
		really_temp_arrays[Mesh.ARRAY_TEX_UV] = uvs
		really_temp_arrays[Mesh.ARRAY_INDEX] = indices_tris
		temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, really_temp_arrays)
		var mesh_arrays: Array
		if len(vertices) < 10000000:
			var surface = SurfaceTool.new()
			surface.create_from(temp_mesh, 0)  # Missing API here to create directly from arrays!!!! :'-(
			# generate_normals does not support triangle strip.
			surface.generate_normals()
			surface.generate_tangents()
			# Missing API: No way to clear indices or convert to triangle strip?
			temp_mesh = surface.commit()
			collision_mesh = temp_mesh.create_trimesh_shape()
			mesh_arrays = temp_mesh.surface_get_arrays(0)
		else:
			mesh_arrays = really_temp_arrays
		# Missing API: No way to make SurfaceTool from arrays???
		# I guess we just do it ourselves
		var indices_optimized: PackedInt32Array = PackedInt32Array().duplicate()
		indices_optimized.resize((resolution) * ((resolution - 1) / 2) * 4)
		indices_optimized.fill(0)
		# Triangle strip:
		idx = 0
		for resy in range(0, resolution - 1, 2):
			for resx in range(resolution):
				indices_optimized[idx] = (resy * resolution + resx)
				indices_optimized[idx + 1] = ((resy + 1) * resolution + resx)
				idx += 2
			for resx in range(resolution - 1, -1, -1):
				indices_optimized[idx] = ((resy + 2) * resolution + resx)
				indices_optimized[idx + 1] = ((resy + 1) * resolution + resx)
				idx += 2
		assert(len(indices_optimized) == idx)
		mesh_arrays[Mesh.ARRAY_INDEX] = indices_optimized

		#mesh_data = temp_mesh
		mesh_data = ArrayMesh.new()
		mesh_data.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, mesh_arrays)
		terrain_mat = self.gen_terrain_mat()

		mesh_data.resource_name = self.keys.get("m_Name", meta.resource_name) + "_mesh"
		mesh_data.surface_set_name(0, "TerrainSurf")
		mesh_data.surface_set_material(0, terrain_mat)

		return dict

	func gen_terrain_mat() -> Material:
		var terrain_mat: Material = null
		var mat = ShaderMaterial.new()
		var matshader = Shader.new()
		matshader.code = '''
shader_type spatial;
		'''
		var splat_database = keys.get("m_SplatDatabase", {})
		var terrain_layers: Array = splat_database.get("m_TerrainLayers", [])
		var alpha_textures: Array = splat_database.get("m_AlphaTextures", [])
		if len(terrain_layers) == 0:
			terrain_layers.append(null)
		if len(alpha_textures) > 0:
			var normal_enabled = []
			var any_normal_enabled = false
			for terrain_layer in terrain_layers:
				var layer_mat: StandardMaterial3D = resolve_godot_resource(terrain_layer)
				var this_normal_enabled: bool = layer_mat.normal_enabled if layer_mat != null else true
				normal_enabled.append(this_normal_enabled)
				any_normal_enabled = any_normal_enabled or this_normal_enabled

			var shader_code: String = "shader_type spatial;\n"
			for i in range(len(terrain_layers)):
				shader_code += "uniform sampler2D albedo%d: source_color, hint_default_%s;\n" % [i, "white" if i == 0 else "black"]
			for i in range(len(terrain_layers)):
				if normal_enabled[i]:
					shader_code += "uniform sampler2D normal%d: hint_normal;\n" % [i]
			for splati in range(len(alpha_textures)):
				shader_code += "uniform sampler2D splat%d;\n" % [splati * 4]
			for i in range(len(terrain_layers)):
				shader_code += "uniform vec4 smoothMetalNormal%d = vec4(0);\n" % [i]
				shader_code += "uniform vec4 scaleOffset%d = vec4(1,1,0,0);\n" % [i]
			shader_code += "\n\nvoid fragment() {\n"
			shader_code += "\tvec4 splat, albedo0col = vec4(0), albedo = vec4(0); vec2 thisUV, normalXY = vec2(0);\n"
			shader_code += "\tvec4 smoothMetalNormal = vec4(0); float normalStrength = 0.0; float strength = 0.0;\n\n"
			for splati in range(len(alpha_textures)):
				shader_code += "\tsplat = texture(splat%d, UV);\n" % [splati * 4]
				for idx in range(min(len(terrain_layers) - splati * 4, 4)):
					var i = splati * 4 + idx
					shader_code += "\tthisUV = UV * scaleOffset%d.xy + scaleOffset%d.zw;\n" % [i, i]
					if i == 0:
						shader_code += ("\talbedo0col = splat[%d] * texture(albedo%d, thisUV); albedo = splat[%d] * albedo0col;\n" % [idx, i, idx])
					else:
						shader_code += "\talbedo += splat[%d] * texture(albedo%d, thisUV);\n" % [idx, i]
					shader_code += "\tstrength += splat[%d];\n" % [idx]
					if normal_enabled[i]:
						shader_code += "\tnormalStrength += splat[%d] * smoothMetalNormal%d.z;\n" % [idx, i]
						shader_code += ("\tnormalXY += splat[%d] * smoothMetalNormal%d.z * (texture(albedo%d, thisUV).xy * 2.0 - 1.0);\n" % [idx, i, i])
					shader_code += "\tsmoothMetalNormal += splat[%d] * smoothMetalNormal%d;\n\n" % [idx, i]
			shader_code += "\tsmoothMetalNormal = max(0.0, 1.0 - strength) * smoothMetalNormal0 + min(1.0, 1.0 / strength) * smoothMetalNormal;\n"
			shader_code += "\tALBEDO = max(0.0, 1.0 - strength) * albedo0col.xyz + min(1.0, 1.0 / strength) * albedo.xyz;\n"
			shader_code += "\tROUGHNESS = 1.0 - albedo.w * smoothMetalNormal.x;\n"
			shader_code += "\tMETALLIC = smoothMetalNormal.y;\n"
			if any_normal_enabled:
				shader_code += "\tnormalXY = mix(vec2(0.0), normalXY / normalStrength, smoothstep(0.01, 0.1, normalStrength));\n"
				shader_code += "\tNORMAL_MAP = vec3(normalXY.xy, sqrt(1.0 - dot(normalXY, normalXY)));\n"
				shader_code += "\tNORMAL_MAP_DEPTH = normalStrength;\n"
			shader_code += "}\n"
			matshader.code = shader_code
			mat.shader = matshader
			var i: int = 0
			for terrain_layer in terrain_layers:
				var layer_mat: StandardMaterial3D = resolve_godot_resource(terrain_layer)
				if layer_mat == null:
					continue
				mat.set_shader_parameter("albedo%d" % [i], layer_mat.albedo_texture)
				var normal_scale = 0.0
				if layer_mat.normal_enabled:
					mat.set_shader_parameter("normal%d" % [i], layer_mat.normal_texture)
					normal_scale = layer_mat.normal_scale
				var roughness = layer_mat.roughness
				var metallic = layer_mat.metallic
				var uv1_scale: Vector2 = Vector2(layer_mat.uv1_scale.x, layer_mat.uv1_scale.y) * Vector2(scale.x, scale.z) * resolution
				var uv1_offset = layer_mat.uv1_offset
				mat.set_shader_parameter("smoothMetalNormal%d" % [i], Plane(1.0 - roughness, metallic, normal_scale, 0.0))
				mat.set_shader_parameter("scaleOffset%d" % [i], Plane(uv1_scale.x, uv1_scale.y, uv1_offset.x, uv1_offset.y))
				i += 1
			i = 0
			for splat_texture_obj in alpha_textures:
				var splat_texture: Texture2D = resolve_godot_resource(splat_texture_obj)
				mat.set_shader_parameter("splat%d" % [i], splat_texture)
				i += 1
			mat.resource_name = self.keys.get("m_Name", meta.resource_name) + "_material"
			terrain_mat = mat
		else:
			terrain_mat = terrain_layers[0]
		return terrain_mat

	func create_godot_resource() -> Resource:
		var packed_scene = PackedScene.new()
		var rootnode = Node3D.new()
		# rootnode.top_level = true  # ideally only ignore rotation, scale.
		rootnode.name = self.keys.get("m_Name", meta.resource_name)
		var meshinst: MeshInstance3D = MeshInstance3D.new()
		meshinst.name = "TerrainMesh"
		meshinst.mesh = mesh_data
		rootnode.add_child(meshinst)
		meshinst.owner = rootnode  # must happen after add_child
		var multimeshes_and_materials = self.gen_multimeshes()
		var multimeshes: Array[MultiMesh] = multimeshes_and_materials[0]
		var material_overrides: Array = multimeshes_and_materials[1]
		var i = 0
		for mm in multimeshes:
			var multimesh: MultiMesh = mm
			var mminst: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mminst.name = multimesh.resource_name
			mminst.multimesh = multimesh
			mminst.material_override = material_overrides[i]
			rootnode.add_child(mminst, true)
			mminst.owner = rootnode  # must happen after add_child
			i += 1
		var err = packed_scene.pack(rootnode)
		if err != OK:
			log_fail("Error packing terrain scene. " + str(err))
			return null
		return packed_scene

	func get_godot_extension() -> String:
		return ".terrain.tscn"

	func get_extra_resource(fileID: int) -> Resource:
		if fileID == self.fileID ^ 0x1234567:
			return self.terrain_mat
		if fileID == self.fileID ^ 0xdeca604:
			return self.mesh_data
		if fileID == self.fileID ^ 0xc0111de4:
			return self.collision_mesh
		if other_resources.has(fileID):
			return other_resources.get(fileID)
		assert(fileID == 0)
		return null


class UnityTextAsset:
	extends UnityObject

	func get_godot_type() -> String:
		return "TextFile"

	func get_godot_extension() -> String:
		return "." + meta.path.get_extension()

	func create_godot_resource() -> Resource:
		var fa: FileAccess = FileAccess.open(meta.path, FileAccess.WRITE)
		var script: Variant = keys.get("m_Script", PackedByteArray())
		if typeof(script) == TYPE_STRING:
			script = script.to_utf8_buffer()
		fa.store_buffer(script)
		fa.close()
		return meta # Don't error even though we didn't technically create a Godot resource.


class UnityPhysicMaterial:
	extends UnityObject

	func get_godot_type() -> String:
		return "PhysicsMaterial"

	func get_godot_extension() -> String:
		return ".phymat"

	func create_godot_resource() -> Resource:
		var mat := PhysicsMaterial.new()
		mat.bounce = keys.get("bounciness", 0.0)
		mat.friction = keys.get("dynamicFriction", 1.0)
		# Average, Minimum, Multiply, Maximum
		# Godot's "rough" behavior is closest to Maximum so we use that.
		mat.rough = (keys.get("frictionCombine", 0) == 3)
		# Minimum or Multiply are probably closest to the absorbent behavior.
		mat.absorbent = (keys.get("bounceCombine", 0) % 3 != 0)
		return mat

### ================ GAME OBJECT TYPE ================
class UnityGameObject:
	extends UnityObject

	func get_godot_type() -> String:
		return "Node3D"

	func recurse_to_child_transform(state: RefCounted, child_transform: UnityObject, new_parent: Node3D) -> Array:  # prefab_fileID,prefab_name,go_fileID,node
		if child_transform.type == "PrefabInstance":
			# PrefabInstance child of stripped Transform part of another PrefabInstance
			var prefab_instance: UnityPrefabInstance = child_transform
			return prefab_instance.instantiate_prefab_node(state, new_parent)
		elif child_transform.is_prefab_reference:
			# PrefabInstance child of ordinary Transform
			if not child_transform.is_stripped:
				log_debug("Expected a stripped transform for prefab root as child of transform")
			var prefab_instance: UnityPrefabInstance = meta.lookup(child_transform.prefab_instance)
			return prefab_instance.instantiate_prefab_node(state, new_parent)
		else:
			if child_transform.is_stripped:
				log_fail("*!*!*! CHILD IS STRIPPED " + str(child_transform) + "; " + str(child_transform.is_prefab_reference) + ";" + str(child_transform.prefab_source_object) + ";" + str(child_transform.prefab_instance), "child", child_transform)
			var child_game_object: UnityGameObject = child_transform.gameObject
			if child_game_object.is_prefab_reference:
				log_warn("child gameObject is a prefab reference!", "chi;d", child_game_object)
			var new_skelley: RefCounted = state.uniq_key_to_skelley.get(child_transform.uniq_key, null)  # Skelley
			if new_skelley == null and new_parent == null:
				log_warn("We did not create a node for this child, but it is not a skeleton bone! " + uniq_key + " child " + child_transform.uniq_key + " gameObject " + child_game_object.uniq_key + " name " + child_game_object.name, "child", child_game_object)
			elif new_skelley != null:
				# log_debug("Go from " + transform_asset.uniq_key + " to " + str(child_game_object) + " transform " + str(child_transform) + " found skelley " + str(new_skelley))
				child_game_object.create_skeleton_bone(state, new_skelley)
			else:
				child_game_object.create_godot_node(state, new_parent)
			return [null]

	func create_skeleton_bone(xstate: RefCounted, skelley: RefCounted):  # SceneNodeState, Skelley
		var state: Object = xstate
		var godot_skeleton: Skeleton3D = skelley.godot_skeleton
		# Instead of a transform, this sets the skeleton transform position maybe?, etc. etc. etc.
		var transform: UnityTransform = self.transform
		var skeleton_bone_index: int = transform.skeleton_bone_index
		var skeleton_bone_name: String = godot_skeleton.get_bone_name(skeleton_bone_index)
		var ret: Node3D = null
		var animator = GetComponent("Animator")
		if animator != null:
			var sub_avatar_meta = animator.get_avatar_meta()
			if sub_avatar_meta != null:
				state = state.state_with_avatar_meta(sub_avatar_meta)
				if godot_skeleton.name != "GeneralSkeleton":
					log_fail("Skelley object should have ensured godot_skeleton with avatar is named GeneralSkeleton")
					godot_skeleton.unique_name_in_owner = true
				log_warn("Humanoid Animator component on skeleton bone " + str(skeleton_bone_name) + " does not fully support unique_name_in_owner")
				# TODO: Implement scene saving for partial skeleton humanoid avatar
		var avatar_bone_name = state.consume_avatar_bone(self.name, skeleton_bone_name, transform.fileID, godot_skeleton, skeleton_bone_index)
		#var configure_root_bone: bool = false
		if not avatar_bone_name.is_empty():
			var conflicting_bone := godot_skeleton.find_bone(avatar_bone_name)
			var dedupe := 1
			if conflicting_bone != -1:
				while godot_skeleton.find_bone(avatar_bone_name + " " + str(dedupe)) != -1:
					dedupe += 1
				godot_skeleton.set_bone_name(conflicting_bone, avatar_bone_name + " " + str(dedupe))
			godot_skeleton.set_bone_name(skeleton_bone_index, avatar_bone_name)
			skeleton_bone_name = avatar_bone_name
			if avatar_bone_name == "Hips":
				if state.consume_root(transform.fileID):
					dedupe = 1
					conflicting_bone = godot_skeleton.find_bone("Root")
					if conflicting_bone != -1:
						while godot_skeleton.find_bone("Root " + str(dedupe)) != -1:
							dedupe += 1
						godot_skeleton.set_bone_name(conflicting_bone, "Root " + str(dedupe))
					var root_idx = godot_skeleton.get_bone_count()
					godot_skeleton.add_bone("Root") # identity transform 0,0,0 is ok
					#configure_root_bone = true
					godot_skeleton.set_bone_parent(root_idx, godot_skeleton.get_bone_parent(skeleton_bone_index)) # parent *should be* -1
					godot_skeleton.set_bone_parent(skeleton_bone_index, root_idx)
		elif state.is_bone_name_reserved(skeleton_bone_name):
			var dedupe := 1
			while godot_skeleton.find_bone(skeleton_bone_name + " " + str(dedupe)) != -1:
				dedupe += 1
			godot_skeleton.set_bone_name(skeleton_bone_index, skeleton_bone_name + " " + str(dedupe))
			skeleton_bone_name = skeleton_bone_name + " " + str(dedupe)
		var rigidbody = GetComponent("Rigidbody")
		var name_map = {}
		name_map[1] = self.fileID
		name_map[4] = transform.fileID
		name_map[transform.utype] = transform.fileID  # RectTransform may also point to this.
		if rigidbody != null:
			ret = rigidbody.create_physical_bone(state, godot_skeleton, skeleton_bone_name)
			rigidbody.configure_node(ret)
			state.add_fileID(ret, self)
			state.add_fileID(ret, transform)
		else:
			state.add_fileID(godot_skeleton, self)
			state.add_fileID(godot_skeleton, transform)
			state.add_fileID_to_skeleton_bone(skeleton_bone_name, fileID)
			state.add_fileID_to_skeleton_bone(skeleton_bone_name, transform.fileID)
			if len(components) > 1 or state.skelley_parents.has(transform.uniq_key):
				ret = BoneAttachment3D.new()
				ret.name = self.name
				ret.bone_name = skeleton_bone_name
				state.add_child(ret, godot_skeleton, null)
				# state.add_fileID(ret, transform)
		# TODO: do we need to configure GameObject here? IsActive, Name on a skeleton bone?
		transform.configure_skeleton_bone(godot_skeleton, skeleton_bone_name)
		var rest_bone_pose := godot_skeleton.get_bone_pose(skeleton_bone_index)
		if avatar_bone_name == "Root":
			rest_bone_pose = Transform3D()
		if not avatar_bone_name.is_empty():
			var sph : SkeletonProfileHumanoid = skelley.skeleton_profile_humanoid
			rest_bone_pose.basis = Basis(sph.get_reference_pose(sph.find_bone(avatar_bone_name)).basis.get_rotation_quaternion()).scaled(rest_bone_pose.basis.get_scale())
			if avatar_bone_name == "Hips":
				rest_bone_pose.origin = state.last_humanoid_skeleton_hip_position
				godot_skeleton.motion_scale = state.last_humanoid_skeleton_hip_position.y
		godot_skeleton.set_bone_rest(skeleton_bone_index, rest_bone_pose)
		var smrs: Array[UnitySkinnedMeshRenderer]
		if ret != null:
			var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
			for new_skelley in list_of_skelleys:
				ret.add_child(godot_skeleton, true)
				godot_skeleton.owner = state.owner
				for smr in new_skelley.skinned_mesh_renderers:
					smrs.append(smr)

		var skip_first: bool = true

		var transform_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(transform.fileID, meta.prefab_transform_fileid_to_rotation_delta.get(transform.fileID, Transform3D()))
		var animator_node_to_object: Dictionary
		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				var component = meta.lookup(component_ref.values()[0])
				if keys.has("m_StaticEditorFlags"):
					component.keys["m_StaticEditorFlags"] = keys["m_StaticEditorFlags"]
				if keys.has("m_Layer"):
					component.keys["m_Layer"] = keys["m_Layer"]
				if keys.has("m_TagString"):
					component.keys["m_TagString"] = keys["m_TagString"]
				if ret == null:
					log_fail("Unable to create godot node " + component.type + " on null skeleton", "bone", self)
				var tmp = component.create_godot_node(state, ret)
				if tmp is AnimationPlayer or tmp is AnimationTree:
					animator_node_to_object[tmp] = component
				if tmp != null:
					component.configure_node(tmp)
					while tmp.get_parent() != null and tmp.get_parent() != ret:
						tmp = tmp.get_parent()
					if tmp is Node3D:
						tmp.transform = transform_delta * tmp.transform
				var component_key = component.get_component_key()
				if not name_map.has(component_key):
					name_map[component_key] = component.fileID

		var prefab_name_map = name_map.duplicate()
		for child_ref in transform.children_refs:
			var child_transform: UnityTransform = meta.lookup(child_ref)
			if ret == null and child_transform.is_prefab_reference or child_transform.type == "PrefabInstance":
				#log_warn("Unable to recurse to child_transform " + child_transform.uniq_key + " on null skeleton bone ret", "children", self)
				ret = BoneAttachment3D.new()
				ret.name = self.name
				ret.bone_name = skeleton_bone_name
				state.add_child(ret, godot_skeleton, null)
			var prefab_data: Array = recurse_to_child_transform(state, child_transform, ret)
			if len(prefab_data) == 4:
				name_map[prefab_data[1]] = prefab_data[2]
				prefab_name_map[prefab_data[1]] = prefab_data[2]
				state.add_prefab_to_parent_transform(transform.fileID, prefab_data[0])
			elif len(prefab_data) == 1:
				name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
				prefab_name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID

		for smr in smrs:
			var smrnode: Node = smr.create_skinned_mesh(state)
			if smrnode != null:
				smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr.uniq_key) + " into node Skeleton " + str(state.owner.get_path_to(smrnode)))

		state.prefab_state.gameobject_name_map[self.fileID] = name_map
		state.prefab_state.prefab_gameobject_name_map[self.fileID] = prefab_name_map
		for animtree in animator_node_to_object:
			var obj: RefCounted = animator_node_to_object[animtree]
			# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
			# If not found, we can't recreate the animationLibrary
			obj.setup_post_children(animtree)

	func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node:  # -> Node3D:
		var state: Object = xstate
		var ret: Node3D = null
		var components: Array = self.components
		var has_collider: bool = false
		var extra_fileID: Array = [self]
		var transform: UnityTransform = self.transform
		var sub_avatar_meta = null
		var name_map = {}
		name_map[1] = self.fileID
		name_map[4] = transform.fileID
		name_map[transform.utype] = transform.fileID  # RectTransform may also point to this.

		for component_ref in components:
			var component = meta.lookup(component_ref.values()[0])
			if component.type == "CharacterController":
				ret = component.create_physics_body(state, new_parent, name)
				transform.configure_node(ret)
				component.configure_node(ret)
				extra_fileID.push_back(transform)
				state = state.state_with_body(ret)
		for component_ref in components:
			var component = meta.lookup(component_ref.values()[0])
			# Some components take priority and must be created here.
			if ret == null and component.type == "Rigidbody":
				ret = component.create_physics_body(state, new_parent, name)
				transform.configure_node(ret)
				component.configure_node(ret)
				extra_fileID.push_back(transform)
				state = state.state_with_body(ret)
			if component.is_collider():
				extra_fileID.push_back(component)
				log_debug("Has a collider " + self.name)
				has_collider = true
			if component.type == "Animator":
				sub_avatar_meta = component.get_avatar_meta()
				if sub_avatar_meta != null:
					state = state.state_with_avatar_meta(sub_avatar_meta)
					if state.owner == null or ret == state.owner:
						sub_avatar_meta = null
		if ret == null:
			ret = Node3D.new()
			transform.configure_node(ret)
			ret.name = name
			state.add_child(ret, new_parent, transform)
		for ext in extra_fileID:
			state.add_fileID(ret, ext)
		var skip_first: bool = true
		var orig_meta_owner: Node = state.owner
		if sub_avatar_meta != null:
			state = state.state_with_owner(ret)

		var transform_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(transform.fileID, meta.prefab_transform_fileid_to_rotation_delta.get(transform.fileID, Transform3D()))
		var animator_node_to_object: Dictionary
		for component_ref in components:
			if skip_first:
				#Is it a fair assumption that Transform is always the first component???
				skip_first = false
			else:
				var component = meta.lookup(component_ref.values()[0])
				if keys.has("m_StaticEditorFlags"):
					component.keys["m_StaticEditorFlags"] = keys["m_StaticEditorFlags"]
				if keys.has("m_Layer"):
					component.keys["m_Layer"] = keys["m_Layer"]
				if keys.has("m_TagString"):
					component.keys["m_TagString"] = keys["m_TagString"]
				var tmp = component.create_godot_node(state, ret)
				if tmp is AnimationPlayer or tmp is AnimationTree:
					animator_node_to_object[tmp] = component
				if tmp != null:
					component.configure_node(tmp)
					while tmp.get_parent() != null and tmp.get_parent() != ret:
						tmp = tmp.get_parent()
					if tmp is Node3D:
						tmp.transform = transform_delta * tmp.transform
				var component_key = component.get_component_key()
				if not name_map.has(component_key):
					name_map[component_key] = component.fileID

		var list_of_skelleys: Array = state.skelley_parents.get(transform.uniq_key, [])
		var smrs: Array[UnitySkinnedMeshRenderer]
		for new_skelley in list_of_skelleys:
			if not new_skelley.godot_skeleton:
				log_fail("Skelley " + str(new_skelley) + " is missing a godot_skeleton")
			else:
				ret.add_child(new_skelley.godot_skeleton, true)
				if not state.active_avatars.is_empty():
					new_skelley.godot_skeleton.name = "GeneralSkeleton"
				new_skelley.godot_skeleton.owner = state.owner
				if not state.active_avatars.is_empty():
					new_skelley.godot_skeleton.unique_name_in_owner = true
				for smr in new_skelley.skinned_mesh_renderers:
					smrs.append(smr)

		var prefab_name_map = name_map.duplicate()
		for child_ref in transform.children_refs:
			var child_transform: UnityTransform = meta.lookup(child_ref)
			var prefab_data: Array = recurse_to_child_transform(state, child_transform, ret)
			if len(prefab_data) == 4:
				name_map[prefab_data[1]] = prefab_data[2]
				prefab_name_map[prefab_data[1]] = prefab_data[2]
				state.add_prefab_to_parent_transform(transform.fileID, prefab_data[0])
			elif len(prefab_data) == 1:
				name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
				prefab_name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID

		for smr in smrs:
			var smrnode: Node = smr.create_skinned_mesh(state)
			if smrnode != null:
				smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr.uniq_key) + " into nested Skeleton " + str(state.owner.get_path_to(smrnode)))

		state.prefab_state.gameobject_name_map[self.fileID] = name_map
		state.prefab_state.prefab_gameobject_name_map[self.fileID] = prefab_name_map
		for animtree in animator_node_to_object:
			var obj: RefCounted = animator_node_to_object[animtree]
			# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
			# If not found, we can't recreate the animationLibrary
			obj.setup_post_children(animtree)
		if sub_avatar_meta != null:
			var sub_scene_filename: String = meta.path.substr(0, len(meta.path) - 5) + "." + str(self.name) + ".tscn"
			var ps: PackedScene = PackedScene.new()
			ps.pack(ret)
			adapter.unidot_utils.save_resource(ps, sub_scene_filename)
			ret.scene_file_path = sub_scene_filename
			orig_meta_owner.set_editable_instance(ret, true)
			#ps = ResourceLoader.load(sub_scene_filename)
			#ret = ps.instantiate()

		return ret

	var components: Variant:  # Array:
		get:
			if is_stripped:
				log_fail("Attempted to access the component array of a stripped " + type + " " + uniq_key, "components")
				# FIXME: Stripped objects do not know their name.
				return 12345.678  # ????
			return keys.get("m_Component")

	func get_transform() -> Object:  # UnityTransform:
		if is_stripped:
			log_fail("Attempted to access the transform of a stripped " + type + " " + uniq_key, "transform")
			# FIXME: Stripped objects do not know their name.
			return null  # ????
		if typeof(components) != TYPE_ARRAY:
			log_fail(uniq_key + " has component array: " + str(components), "transform")
		elif len(components) < 1 or typeof(components[0]) != TYPE_DICTIONARY:
			log_fail(uniq_key + " has invalid first component: " + str(components), "transform")
		elif len(components[0].values()[0]) < 3:
			log_fail(uniq_key + " has invalid component: " + str(components), "transform")
		else:
			var component = meta.lookup(components[0].values()[0])
			if component.type != "Transform" and component.type != "RectTransform":
				log_fail(str(self) + " does not have Transform as first component! " + str(component.type) + ": components " + str(components), "transform")
			return component
		return null

	func GetComponent(typ: String) -> RefCounted:
		for component_ref in components:
			var component = meta.lookup(component_ref.values()[0])
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

	func is_toplevel() -> bool:
		if is_stripped:
			# Stripped objects are part of a Prefab, so by definition will never be toplevel
			# (The PrefabInstance itself will be the toplevel object)
			return false
		if typeof(transform) == TYPE_NIL:
			log_warn(uniq_key + " has no transform in toplevel: " + str(transform))
			return false
		if typeof(transform.parent_ref) != TYPE_ARRAY:
			log_warn(uniq_key + " has invalid or missing parent_ref: " + str(transform.parent_ref))
			return false
		return transform.parent_ref[1] == 0

	func get_gameObject() -> UnityGameObject:  # UnityGameObject:
		return self


# Is a PrefabInstance a GameObject? Unity seems to treat it that way at times. Other times not...
# Is this canon? We'll never know because the documentation denies even the existence of a "PrefabInstance" class
class UnityPrefabInstance:
	extends UnityGameObject

	func get_godot_type() -> String:
		return "PackedScene"

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

	func get_name() -> String:
		# The default name of a prefab instance will always be the filename, regardless of m_Name.
		# But it can be overridden.
		var source_prefab_meta = meta.lookup_meta(self.source_prefab)
		var go_id = 400000
		if source_prefab_meta != null:
			go_id = source_prefab_meta.prefab_main_gameobject_id
		else:
			log_debug("During prefab name lookup, ailed to lookup meta from " + str(self.uniq_key) + " for source prefab " + str(self.source_prefab))
		for mod in modifications:
			var property_key: String = mod.get("propertyPath", "")
			var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
			var value: String = mod.get("value", "")
			if property_key == "m_Name" and source_obj_ref[1] == go_id:
				log_debug("Found overridden m_Name: Mod is " + str(mod))
				return value
		return source_prefab_meta.get_main_object_name()

	func create_godot_node(xstate: RefCounted, new_parent: Node3D) -> Node:  # Node3D
		# called from toplevel (scene, inherited prefab?)
		var ret_data: Array = self.instantiate_prefab_node(xstate, new_parent)
		if len(ret_data) < 4:
			return null
		return ret_data[3]  # godot node.

	# Generally, all transforms which are sub-objects of a prefab will be marked as such ("Create map from corresponding source object id (stripped id, PrefabInstanceId^target object id) and do so recursively, to target path...")
	func instantiate_prefab_node(xstate: RefCounted, new_parent: Node3D) -> Array:  # [prefab_fileid, prefab_name, prefab_root_gameobject_id, godot_node]
		meta.prefab_id_to_guid[self.fileID] = self.source_prefab[2]  # UnityRef[2] is guid
		var state: RefCounted = xstate  # scene_node_state
		var ps: RefCounted = state.prefab_state  # scene_node_state.PrefabState
		var target_prefab_meta = meta.lookup_meta(source_prefab)
		if target_prefab_meta == null or target_prefab_meta.guid == self.meta.guid:
			log_fail("Unable to load prefab dependency " + str(source_prefab) + " from " + str(self.meta.guid), "prefab", source_prefab)
			return []
		var packed_scene: PackedScene = target_prefab_meta.get_godot_resource(source_prefab)
		if packed_scene == null:
			log_fail("Failed to instantiate prefab with guid " + uniq_key + " from " + str(self.meta.guid), "prefab", source_prefab)
			return []
		meta.transform_fileid_to_parent_fileid[meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, self.fileID)] = self.parent_ref[1]
		log_debug("Assigning prefab root transform " + str(meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, self.fileID)) + " parent fileid " + str(self.parent_ref[1]))
		log_debug("Instancing PackedScene at " + str(packed_scene.resource_path) + ": " + str(packed_scene.resource_name))
		var instanced_scene: Node3D = null
		var toplevel_rename: String = ""
		for mod in modifications:
			var property_key: String = mod.get("propertyPath", "")
			var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
			var value: String = mod.get("value", "")
			var mod_fileID: int = source_obj_ref[1]
			if property_key == "m_Name" and mod_fileID == target_prefab_meta.prefab_main_gameobject_id:
				toplevel_rename = value
				break
		if new_parent == null:
			# This is the "Inherited Scene" case (Godot), or "Prefab Variant" as it is called.
			# Godot does not have an API to create an inherited scene. However, luckily, the file format is simple.
			# We just need a [instance=ExtResource(1)] attribute on the root node.

			# FIXME: This may be unstable across Godot versions, if .tscn format ever changes.
			# node->set_scene_inherited_state(sdata->get_state()) is not exposed to GDScript. Let's HACK!!!
			var stub_filename = "res://_temp_scene.tscn"
			var dres = DirAccess.open("res://")
			var fres = FileAccess.open(stub_filename, FileAccess.WRITE_READ)
			log_debug("Writing stub scene to " + stub_filename)
			var to_write: String = "[gd_scene load_steps=2 format=2]\n\n" + '[ext_resource path="' + str(packed_scene.resource_path) + '" type="PackedScene" id=1]\n\n' + "[node name=" + var_to_str(str(toplevel_rename)) + " instance=ExtResource( 1 )]\n"
			fres.store_string(to_write)
			#log_debug(to_write)
			fres.flush()
			fres.close()
			fres = null
			var temp_packed_scene: PackedScene = ResourceLoader.load(stub_filename, "", ResourceLoader.CACHE_MODE_IGNORE)
			instanced_scene = temp_packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			dres.remove(stub_filename)
			instanced_scene.name = StringName(toplevel_rename)
			state.add_child(instanced_scene, new_parent, self)
		else:
			# Traditional instanced scene case: It only requires calling instantiate() and setting the filename.
			instanced_scene = packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			instanced_scene.name = StringName(toplevel_rename)
			#instanced_scene.scene_file_path = packed_scene.resource_path
			state.add_child(instanced_scene, new_parent, self)

			if set_editable_children(state, instanced_scene) != instanced_scene:
				instanced_scene.scene_file_path = ""
				set_owner_rec(instanced_scene, state.owner)
		## using _bundled.editable_instance happens after the data is discarded...
		## This whole system doesn't work. We need an engine mod instead that allows set_editable_instance.
		##if new_parent != null:
		# In this case, we must also set editable children later in convert_scene.gd
		# Here is how we keep track of it:
		##	ps.prefab_instance_paths.push_back(state.owner.get_path_to(instanced_scene))
		# state = state.state_with_owner(instanced_scene)
		var anim_player: AnimationPlayer = instanced_scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim_player != null:
			var root_node: Node = anim_player.get_node(anim_player.root_node)
			var reset_anim: Animation = anim_player.get_animation(&"RESET")
			if reset_anim != null:
				# Copied from AnimationMixer::reset()
				var aux_player := AnimationPlayer.new()
				root_node.add_child(aux_player)
				aux_player.reset_on_save = false
				var al := AnimationLibrary.new()
				al.add_animation(&"RESET", reset_anim)
				aux_player.add_animation_library(&"", al)
				aux_player.assigned_animation = &"RESET"
				aux_player.seek(0.0, true)
				aux_player.queue_free()

		var pgntfac = target_prefab_meta.prefab_gameobject_name_to_fileid_and_children
		var gntfac = target_prefab_meta.gameobject_name_to_fileid_and_children
		#state.prefab_state.prefab_gameobject_name_map[meta.xor_or_stripped(self.meta.prefab_main_gameobject_id, self.fileID] =
		meta.remap_prefab_gameobject_names_update(self.fileID, target_prefab_meta, gntfac, ps.prefab_gameobject_name_map)
		meta.remap_prefab_gameobject_names_update(self.fileID, target_prefab_meta, pgntfac, ps.prefab_gameobject_name_map)
		#log_debug("Resulting name_map: " + str(ps.prefab_gameobject_name_map))
		meta.remap_prefab_fileids(self.fileID, target_prefab_meta)

		state.add_bones_to_prefabbed_skeletons(self.uniq_key, target_prefab_meta, instanced_scene)

		log_debug("Prefab " + str(packed_scene.resource_path) + " ------------")
		log_debug("Adding to parent " + str(new_parent))
		#log_debug(str(target_prefab_meta.fileid_to_nodepath))
		#log_debug(str(target_prefab_meta.prefab_fileid_to_nodepath))
		#log_debug(str(target_prefab_meta.fileid_to_skeleton_bone))
		#log_debug(str(target_prefab_meta.prefab_fileid_to_skeleton_bone))
		#log_debug(" ------------")
#				var component_key = component.get_component_key()
#				if not name_map.has(component_key):
#					name_map[component_key] = component.fileID
		var fileID_to_keys = {}.duplicate()
		var nodepath_to_first_virtual_object = {}.duplicate()
		var nodepath_to_keys = {}.duplicate()
		for mod in modifications:
			# log_debug("Preparing to apply mod: Mod is " + str(mod))
			var property_key: String = mod.get("propertyPath", "")
			var source_obj_ref: Array = mod.get("target", [null, 0, "", null])
			var obj_value: Array = mod.get("objectReference", [null, 0, "", null])
			var value: String = mod.get("value", "")

			if property_key == "m_StaticEditorFlags" or property_key == "m_Layer" or property_key == "m_TagString":
				var value_var: Variant = value
				if property_key != "m_TagString":
					value_var = value.to_int()
				# 33 - filter, 23 - renderer
				# We really want the MeshRenderer and Rigidbody to learn about the static lightmap flag.
				var child_components: Dictionary = pgntfac.get(source_obj_ref[1], gntfac.get(source_obj_ref[1], {}))
				for key in child_components:
					if typeof(key) != TYPE_STRING:
						var component_fileID: int = child_components[key]
						if component_fileID != 0:
							if not fileID_to_keys.has(component_fileID):
								fileID_to_keys[component_fileID] = {}.duplicate()
							fileID_to_keys.get(component_fileID)[property_key] = value_var

			var fileID: int = source_obj_ref[1]
			if not fileID_to_keys.has(fileID):
				fileID_to_keys[fileID] = {}.duplicate()
			if STRING_KEYS.has(property_key):
				fileID_to_keys.get(fileID)[property_key] = value
			elif value.is_empty():
				fileID_to_keys.get(fileID)[property_key] = obj_value
			elif obj_value[1] != 0:
				log_warn("Object has both value " + str(value) + " and objref " + str(obj_value) + " for " + str(mod), property_key, obj_value)
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
				# log_debug("Legacy prefab override fileID " + str(fileID) + " key " + str(key) + " value " + str(asset.keys[key]))
				fileID_to_keys[fileID][key] = asset.keys[key]
		var animator_node_to_object: Dictionary
		for fileID in fileID_to_keys:
			var target_utype: int = target_prefab_meta.fileid_to_utype.get(fileID, target_prefab_meta.prefab_fileid_to_utype.get(fileID, 0))
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(fileID, target_prefab_meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(fileID, target_prefab_meta.prefab_fileid_to_skeleton_bone.get(fileID, ""))
			var virtual_fileID = meta.xor_or_stripped(fileID, self.fileID)
			var virtual_unity_object: UnityObject = adapter.instantiate_unity_object_from_utype(meta, virtual_fileID, target_utype)
			var uprops: Dictionary = fileID_to_keys.get(fileID, {})
			log_debug("XXXd Calculating prefab modifications " + str(target_prefab_meta.guid) + "/" + str(fileID) + "/" + str(target_nodepath) + ":" + target_skel_bone + " " + str(uprops))
			if uprops.has("m_Name"):
				var m_Name: String = uprops["m_Name"]
				state.add_prefab_rename(fileID, m_Name)
			var existing_node = instanced_scene.get_node(target_nodepath)
			if uprops.get("m_Controller", [null, 0])[1] != 0:
				var animtree: AnimationTree = null
				if target_utype == 95:  # Animator component
					if existing_node != null and existing_node.get_class() == "AnimationPlayer":
						log_debug("Adding AnimationTree as sibling to existing AnimationPlayer component")
						animtree = AnimationTree.new()
						animtree.name = "AnimationTree"
						animtree.set("deterministic", false) # New feature in 4.2, acts like Untiy write defaults off
						if uprops.get("m_ApplyRootMotion", 0) == 0:
							animtree.root_motion_track = NodePath("%GeneralSkeleton:Root")
						existing_node.get_parent().add_child(animtree, true)
						animtree.owner = state.owner
						animtree.anim_player = animtree.get_path_to(existing_node)
						animtree.active = ANIMATION_TREE_ACTIVE
						animtree.set_script(anim_tree_runtime)
						# Weird special case, likely to break.
						# The original file was a .glb and doesn't have an AnimationTree node.
						# We add one and try to pretend it's ours.
						# Maybe better to change glb post-import script to add one.
						state.add_fileID(animtree, virtual_unity_object)
					else:
						animtree = existing_node
					virtual_unity_object.keys = uprops
					animator_node_to_object[animtree] = virtual_unity_object
					virtual_unity_object.assign_controller(animtree.get_node(animtree.anim_player), animtree, uprops["m_Controller"])
			log_debug("Looking up instanced object at " + str(target_nodepath) + ": " + str(existing_node))
			if target_skel_bone.is_empty() and existing_node == null:
				log_fail(str(fileID) + " FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(uprops), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unity_object)
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
								log_debug("Splitting array key: " + str(uprop) + " prop_piece " + str(prop_piece) + ": " + str(exist_prop) + " / all props: " + str(uprops))
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
				if not nodepath_to_first_virtual_object.has(target_nodepath) or nodepath_to_first_virtual_object[target_nodepath] is UnityTransform or nodepath_to_first_virtual_object[target_nodepath] is UnityGameObject:
					nodepath_to_first_virtual_object[target_nodepath] = virtual_unity_object
				var converted: Dictionary = virtual_unity_object.convert_properties(existing_node, uprops)
				log_debug("Converted props " + str(converted) + " from " + str(nodepath_to_keys.get(target_nodepath)) + " at " + str(virtual_unity_object.uniq_key))
				virtual_unity_object.apply_component_props(existing_node, converted)
				if not nodepath_to_keys.has(target_nodepath):
					nodepath_to_keys[target_nodepath] = converted
				else:
					var dict: Dictionary = nodepath_to_keys.get(target_nodepath)
					for key in converted:
						dict[key] = converted.get(key)
					nodepath_to_keys[target_nodepath] = dict
			else:
				if existing_node != null:
					# Test this:
					log_debug("Applying mod to skeleton bone " + str(existing_node) + " at path " + str(target_nodepath) + ":" + str(target_skel_bone) + "!! Mod is " + str(uprops))
					virtual_unity_object.configure_skeleton_bone_props(existing_node, target_skel_bone, uprops)
				else:
					log_fail("FAILED to get_node to apply mod to skeleton at path " + str(target_nodepath) + ":" + target_skel_bone + "!! Mod is " + str(uprops), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unity_object)
		for target_nodepath in nodepath_to_keys:
			var virtual_unity_object: UnityObject = nodepath_to_first_virtual_object.get(target_nodepath)
			var existing_node = instanced_scene.get_node(target_nodepath)
			var uprops: Dictionary = fileID_to_keys.get(fileID, {})
			var props: Dictionary = nodepath_to_keys.get(target_nodepath, {})
			if existing_node != null:
				log_debug("Applying mod to node " + str(existing_node) + " at path " + str(target_nodepath) + "!! Mod is " + str(props) + "/" + str(props.has("name")))
				virtual_unity_object.apply_node_props(existing_node, props)
				if target_nodepath == NodePath(".") and props.has("name"):
					log_debug("Applying name " + str(props.get("name")))
					existing_node.name = props.get("name")
			else:
				log_fail("FAILED to get_node to apply mod to node at path " + str(target_nodepath) + "!! Mod is " + str(props), "empty" if uprops.is_empty() else uprops.keys()[0], virtual_unity_object)

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
		for gameobject_asset in ps.gameobjects_by_parented_prefab.get(self.fileID, {}).values():
			# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
			var par: UnityGameObject = gameobject_asset
			var source_obj_ref = par.prefab_source_object
			var source_transform_id: int = gntfac.get(source_obj_ref[1], pgntfac.get(source_obj_ref[1], {})).get(4, 0)
			var transform_delta: Transform3D = target_prefab_meta.transform_fileid_to_rotation_delta.get(source_transform_id, target_prefab_meta.prefab_transform_fileid_to_rotation_delta.get(source_transform_id, Transform3D()))
			log_debug("Checking stripped GameObject " + str(par.uniq_key) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
			assert(target_prefab_meta.guid == source_obj_ref[2])
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
			nodepath_bone_to_stripped_gameobject[str(target_nodepath) + "/" + str(target_skel_bone)] = gameobject_asset
			log_debug("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.scene_file_path))
			var target_parent_obj = instanced_scene.get_node(target_nodepath)
			var attachment: Node3D = target_parent_obj
			if attachment == null:
				log_fail("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path), "prefab_source", source_obj_ref)
				continue
			log_debug("Found gameobject: " + str(target_parent_obj.name))
			if not target_skel_bone.is_empty() or target_parent_obj is BoneAttachment3D:
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
						attachment.name = target_skel_bone  # target_parent_obj.name if not stripped??
						attachment.bone_name = target_skel_bone
						state.add_child(attachment, godot_skeleton, gameobject_asset)
						gameobject_fileid_to_attachment[gameobject_asset.fileID] = attachment
			for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				if component.type == "MeshFilter":
					if not component.is_stripped:
						log_debug("Prefab found a non-stripped MeshFilter " + str(component.fileID))
						gameobject_asset.meshFilter = component
			if gameobject_asset.meshFilter == null:
				for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
					if component.type == "MeshCollider":
						log_debug("Found a MeshCollider " + str(component.fileID) + " without a MeshFilter")
						var source_fileID_mr: int = pgntfac.get(source_obj_ref[1], gntfac.get(source_obj_ref[1], {})).get(33, 0)
						if source_fileID_mr != 0:
							log_debug("Found a MeshFilter source id " + str(source_fileID_mr))
							var source_fileID_path: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_fileID_mr, NodePath())
							if source_fileID_path != NodePath():
								log_debug("Found a MeshFilter source path " + str(source_fileID_path))
								var source_node: Node = instanced_scene.get_node(source_fileID_path)
								if source_node is MeshInstance3D:
									log_debug("Found a MeshInstance " + str(source_node) + " mesh " + str(source_node.mesh))
									component.source_mesh_instance = source_node
			var comp_map = {}
			for component in ps.components_by_stripped_id.get(gameobject_asset.fileID, []):
				if attachment == null:
					log_fail("Unable to create godot node " + component.type + " on null attachment ", "attachment", component)
				# FIXME: We do not currently store m_StaticEditorFlags on the GameObject
				# so there is no way to assign m_StaticEditorFlags on newly-created MeshFilter components.
				var tmp = component.create_godot_node(state, attachment)
				if tmp is AnimationPlayer or tmp is AnimationTree:
					animator_node_to_object[tmp] = component
				if tmp != null:
					component.configure_node(tmp)
					while tmp.get_parent() != null and tmp.get_parent() != attachment:
						tmp = tmp.get_parent()
					if tmp is Node3D:
						tmp.transform = transform_delta * tmp.transform
				var ckey = component.get_component_key()
				if not comp_map.has(ckey):
					comp_map[ckey] = component.fileID
			gameobject_fileid_to_body[gameobject_asset.fileID] = state.body
			state.body = orig_state_body
			state.add_component_map_to_prefabbed_gameobject(gameobject_asset.fileID, comp_map)

		var smrs: Array[UnitySkinnedMeshRenderer]
		# And now for the analogous code to process stripped Transforms.
		for transform_asset in ps.transforms_by_parented_prefab.get(self.fileID, {}).values():
			# NOTE: transform_asset may be a GameObject, in case it was referenced by a Component.
			var par: UnityTransform = transform_asset
			var source_obj_ref = par.prefab_source_object
			log_debug("Checking stripped Transform " + str(par.uniq_key) + ": " + str(source_obj_ref) + " is it " + target_prefab_meta.guid)
			assert(target_prefab_meta.guid == source_obj_ref[2])
			var target_nodepath: NodePath = target_prefab_meta.fileid_to_nodepath.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_nodepath.get(source_obj_ref[1], NodePath()))
			var target_skel_bone: String = target_prefab_meta.fileid_to_skeleton_bone.get(source_obj_ref[1], target_prefab_meta.prefab_fileid_to_skeleton_bone.get(source_obj_ref[1], ""))
			var gameobject_asset: UnityGameObject = nodepath_bone_to_stripped_gameobject.get(str(target_nodepath) + "/" + str(target_skel_bone), null)
			log_debug("Get target node " + str(target_nodepath) + " bone " + str(target_skel_bone) + " from " + str(instanced_scene.scene_file_path))
			var target_parent_obj = instanced_scene.get_node(target_nodepath)
			var attachment: Node3D = target_parent_obj
			var already_has_attachment: bool = false
			if attachment == null:
				log_fail("Unable to find node " + str(target_nodepath) + " on scene " + str(packed_scene.resource_path), "prefab_source", source_obj_ref)
				continue
			log_debug("Found transform: " + str(target_parent_obj.name))
			if gameobject_asset != null:
				state.body = gameobject_fileid_to_body.get(gameobject_asset.fileID, state.body)
			if gameobject_asset != null and gameobject_fileid_to_attachment.has(gameobject_asset.fileID):
				log_debug("We already got one! " + str(gameobject_asset.fileID) + " " + str(target_skel_bone))
				attachment = state.owner.get_node(state.fileid_to_nodepath.get(gameobject_asset.fileID))
				state.add_fileID(attachment, transform_asset)
				already_has_attachment = true
			elif !already_has_attachment and (not target_skel_bone.is_empty() or target_parent_obj is BoneAttachment3D):  # and len(state.skelley_parents.get(transform_asset.uniq_key, [])) >= 1):
				var godot_skeleton: Node3D = target_parent_obj
				if target_parent_obj is BoneAttachment3D:
					attachment = target_parent_obj
					godot_skeleton = target_parent_obj.get_parent()
				else:
					attachment = BoneAttachment3D.new()
					attachment.name = target_skel_bone  # target_parent_obj.name if not stripped??
					attachment.bone_name = target_skel_bone
					log_debug("Made a new attachment! " + str(target_skel_bone))
					state.add_child(attachment, godot_skeleton, transform_asset)

			var list_of_skelleys: Array = state.skelley_parents.get(transform_asset.uniq_key, [])
			if not list_of_skelleys.is_empty():
				log_debug("It's Peanut Butter Skelley time: " + str(transform_asset.uniq_key))
			for new_skelley in list_of_skelleys:
				if new_skelley.godot_skeleton != null:
					if not state.active_avatars.is_empty():
						new_skelley.godot_skeleton.name = "GeneralSkeleton"
					attachment.add_child(new_skelley.godot_skeleton, true)
					new_skelley.godot_skeleton.owner = state.owner
					if not state.active_avatars.is_empty():
						new_skelley.godot_skeleton.unique_name_in_owner = true
				for smr in new_skelley.skinned_mesh_renderers:
					smrs.append(smr)

			var name_map = {}
			for child_transform in ps.child_transforms_by_stripped_id.get(transform_asset.fileID, []):
				if child_transform.gameObject != null and attachment != null:
					log_debug("Adding " + str(child_transform.gameObject.name) + " to " + str(attachment.name))
				# child_transform usually Transform; occasionally can be PrefabInstance
				if attachment == null:
					log_fail("Unable to recurse to child_transform " + child_transform.uniq_key + " on null bone attachment", "children", self)
				var prefab_data: Array = recurse_to_child_transform(state, child_transform, attachment)
				if child_transform.gameObject != null:
					name_map[child_transform.gameObject.name] = child_transform.gameObject.fileID
				if len(prefab_data) == 4:
					name_map[prefab_data[1]] = prefab_data[2]
					if gameobject_asset != null:
						state.add_prefab_to_parent_transform(transform_asset.fileID, prefab_data[0])
			state.add_name_map_to_prefabbed_transform(transform_asset.fileID, name_map)
			state.body = orig_state_body

		for skelley in state.prefab_state.skelleys_by_parented_prefab.get(self.uniq_key, []):
			for smr in skelley.skinned_mesh_renderers:
				smrs.append(smr)
		for smr in smrs:
			var smrnode: Node = smr.create_skinned_mesh(state)
			if smrnode != null:
				smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr.uniq_key) + " into prefabbed Skeleton " + str(state.owner.get_path_to(smrnode)))
		for animtree in animator_node_to_object:
			var obj: RefCounted = animator_node_to_object[animtree]
			# var controller_object = pkgasset.parsed_meta.lookup(obj.keys["m_Controller"])
			# If not found, we can't recreate the animationLibrary
			obj.setup_post_children(animtree)

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
		#	var stripped_id = meta.xor_or_stripped(int(target_fileid), fileID)
		#	prefab_fileid_to_nodepath =
		#stripped_id_to_nodepath
		#for mod in self.modifications:
		#	# TODO: Assign godot properties for each modification
		#	pass

		# FIXME: If we're in a top-level scene with its own stripped components, then we should use those IDs, not xor.
		# The ID numbers might not match up 1-to-1.

		return [self.fileID, toplevel_rename, meta.xor_or_stripped(target_prefab_meta.prefab_main_gameobject_id, self.fileID), instanced_scene]

	func get_transform() -> Object:  # Not really... but there usually isn't a stripped transform for the prefab instance itself.
		return self

	var rootOrder: int:
		get:
			return 0  # no idea..

	func get_gameObject() -> UnityGameObject:
		return self

	var parent_ref: Array:  # UnityRef
		get:
			return keys.get("m_Modification", {}).get("m_TransformParent", [null, 0, "", 0])

	# Special case: this is used to find a common ancestor for Skeletons. We stop at the prefab instance and do not go further.
	var parent_no_stripped: UnityObject:  # Array #UnityRef
		get:
			return null  # meta.lookup(parent_ref)

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

	var source_prefab: Array:  # UnityRef
		get:
			# new: m_SourcePrefab; old: m_ParentPrefab
			return keys.get("m_SourcePrefab", keys.get("m_ParentPrefab", [null, 0, "", 0]))

	var is_legacy_parent_prefab: bool:
		get:
			# Legacy prefabs will stick one of these at the root of the Prefab file. It serves no purpose
			# the legacy "prefab parent" object has a m_RootGameObject reference, but you can determine that
			# the same way modern prefabs do, the only GameObject whose Transform has m_Father == null
			return keys.get("m_IsPrefabParent", false)


class UnityPrefabLegacyUnused:
	extends UnityPrefabInstance
	# I think this will never exist in practice, but it's here anyway:
	# Old Unity's "Prefab" used utype 1001 which is now "PrefabInstance", not 1001480554.
	# so those objects should instantiate UnityPrefabInstance anyway.
	pass


### ================ COMPONENT TYPES ================
class UnityComponent:
	extends UnityObject

	func get_godot_type() -> String:
		return "Node"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var new_node: Node = Node.new()
		new_node.name = type
		state.add_child(new_node, new_parent, self)
		assign_object_meta(new_node)
		new_node.editor_description = str(self)
		return new_node

	func get_gameObject() -> UnityGameObject:
		if is_stripped:
			log_fail("Attempted to access the gameObject of a stripped " + type + " " + uniq_key, "gameObject")
			# FIXME: Stripped objects do not know their name.
			return null  # ????
		return meta.lookup(keys.get("m_GameObject", [null, 0, "", 0]))

	func get_name() -> String:
		if is_stripped:
			log_fail("Attempted to access the name of a stripped " + type + " " + uniq_key, "name")
			# FIXME: Stripped objects do not know their name.
			# FIXME: Make the calling function crash, since we don't have stacktraces wwww
			return "[stripped]"  # ????
		return str(gameObject.name)

	func is_toplevel() -> bool:
		return false


class UnityBehaviour:
	extends UnityComponent

	func convert_properties_component(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = {}
		if uprops.has("m_Enabled"):
			outdict["visible"] = uprops.get("m_Enabled") != 0
		return outdict

	var enabled: bool:
		get:
			return keys.get("m_Enabled", 0) != 0


class UnityTransform:
	extends UnityComponent

	func get_godot_type() -> String:
		return "Node3D"

	var skeleton_bone_index: int = -1

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		# FIXME: Do we need convert_properties_component?
		# var outdict = convert_properties_component(node, uprops)
		var n3d: Node3D = node as Node3D
		if n3d == null:
			log_warn("Unable to convert Transform properties using original values.")
			return _convert_properties_pos_scale(uprops, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE)
		elif n3d is Skeleton3D and skeleton_bone_index != -1:
			return _convert_properties_pos_scale(uprops,
				n3d.get_bone_pose_position(skeleton_bone_index),
				n3d.get_bone_pose_rotation(skeleton_bone_index),
				n3d.get_bone_pose_scale(skeleton_bone_index))
		else:
			return _convert_properties_pos_scale(uprops, n3d.position, n3d.quaternion, n3d.scale)

	func _convert_properties_pos_scale(uprops: Dictionary, orig_pos_godot: Vector3, orig_rot_godot: Quaternion, orig_scale_godot: Vector3) -> Dictionary:
		# We only insert them here if it's not 1,1,1 or -1,-1,-1 which are the only two godot supported scale signs.
		var cur_signs: Vector3 = (orig_scale_godot.sign() + Vector3(0.5,0.5,0.5)).sign()
		# We need to be careful not to double-apply the sign logic, since Godot will cache the correct signs in memory sometimes.
		# log_debug("signs are " + str(meta.transform_fileid_to_scale_signs) + " | prefab signs are " + str(meta.prefab_transform_fileid_to_scale_signs) + "  fileID is " + str(fileID) + " " + str(cur_signs))
		if cur_signs.is_equal_approx(Vector3.ONE) or cur_signs.is_equal_approx(-Vector3.ONE):
			if meta.transform_fileid_to_scale_signs.has(fileID) or meta.prefab_transform_fileid_to_scale_signs.has(fileID):
				var signs: Vector3 = meta.transform_fileid_to_scale_signs.get(fileID, meta.prefab_transform_fileid_to_scale_signs.get(fileID))
				cur_signs = signs
				var cnt: int = int(signs.x < 0) + int(signs.y < 0) + int(signs.z < 0)
				orig_scale_godot = abs(orig_scale_godot) * signs
				if cnt != 1:
					signs *= -1 # Make sure exactly one is negative
				if signs.x < 0: # Rotate about X axis 180 degrees
					log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about x, now cur_signs is " + str(cur_signs))
					orig_rot_godot = Quaternion(1, 0, 0, 0) * orig_rot_godot
				elif signs.y < 0: # Rotate about Y axis 180 degrees
					log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about y, now cur_signs is " + str(cur_signs))
					orig_rot_godot = Quaternion(0, 1, 0, 0) * orig_rot_godot
				else: # Rotate about Z axis 180 degrees
					log_debug("Restored scale signs " + str(orig_scale_godot) + ". rotate about z, now cur_signs is " + str(cur_signs))
					orig_rot_godot = Quaternion(0, 0, 1, 0) * orig_rot_godot

		var outdict: Dictionary
		var rotation_delta: Transform3D
		#var pos_rotation_delta: Transform3D
		var rotation_delta_post := Transform3D.IDENTITY
		var has_post: bool = false
		if meta.transform_fileid_to_rotation_delta.has(fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(fileID):
			rotation_delta_post = meta.transform_fileid_to_rotation_delta.get(fileID, meta.prefab_transform_fileid_to_rotation_delta.get(fileID, Transform3D.IDENTITY))
			rotation_delta_post = rotation_delta_post.affine_inverse()
			#log_debug("convert_properties: This fileID is a humanoid bone position offset=" + str(rotation_delta_post.origin) + " rotation offset=" + str(rotation_delta_post.basis.get_rotation_quaternion()) + " scale offset=" + str(rotation_delta_post.basis.get_scale()))
			has_post = true
		if meta.transform_fileid_to_parent_fileid.has(fileID) or meta.prefab_transform_fileid_to_parent_fileid.has(fileID):
			var parent_fileid: int = meta.transform_fileid_to_parent_fileid.get(fileID, meta.prefab_transform_fileid_to_parent_fileid.get(fileID))
			if meta.transform_fileid_to_rotation_delta.has(parent_fileid) or meta.prefab_transform_fileid_to_rotation_delta.has(parent_fileid):
				rotation_delta = meta.transform_fileid_to_rotation_delta.get(parent_fileid, meta.prefab_transform_fileid_to_rotation_delta.get(parent_fileid))
				#log_debug("convert_properties: parent fileID " + str(parent_fileid) + " is a humanoid bone with child position offset=" + str(rotation_delta.origin) + " rotation offset=" + str(rotation_delta.basis.get_rotation_quaternion()) + " scale offset=" + str(rotation_delta.basis.get_scale()))
		#else:
		#	log_debug("convert_properties: Node has no parent.")

		var rot_quat: Quaternion = Quaternion.IDENTITY
		var orig_rot_quat: Quaternion = rotation_delta.basis.get_rotation_quaternion().inverse() * orig_rot_godot * rotation_delta_post.basis.get_rotation_quaternion().inverse()
		orig_rot_quat.y = -orig_rot_quat.y
		orig_rot_quat.z = -orig_rot_quat.z
		var rot_vec: Variant = get_quat(uprops, "m_LocalRotation", orig_rot_quat) # left-handed
		if typeof(rot_vec) == TYPE_QUATERNION:
			rot_quat = rot_vec as Quaternion
			# Assuming t-pose, in a humanoid a lot of these expressions will cancel out nicely to godot's bone rest (T-pose)
			# This is
			# Previously:
			# (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() *  this_unity_rest.affine_inverse() * node.get_bone_rest(p_skel_bone) = node.get_bone_rest(p_skel_bone)
			# Quaternion.IDENTITY == (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() * this_unity_rest.affine_inverse()
			# node.get_bone_rest(p_skel_bone)

			# Now:
			# this_unity_global_rest = parent_unity_global_rest * ... * this_unity_rest
			# par_global_rest.affine_inverse() * parent_unity_global_rest * (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion() * this_unity_rest.affine_inverse() * parent_unity_global_rest.affine_inverse() * par_global_rest * this_bone_rest
			# par_global_rest.affine_inverse() * parent_unity_global_rest * parent_unity_global_rest.affine_inverse() * par_global_rest * this_bone_rest
			# par_global_rest.atffine_inverse() * par_global_rest * this_bone_rest
			# this_bone_rest
			# WANT: this_bone_rest
			# Same as (Basis.FLIP_X.inverse() * Basis(rot_vec) * Basis.FLIP_X).get_rotation_quaternion()
			rot_quat.y = -rot_quat.y
			rot_quat.z = -rot_quat.z
			rot_quat = rotation_delta.basis.get_rotation_quaternion() * rot_quat * rotation_delta_post.basis.get_rotation_quaternion()
			outdict["quaternion"] = rot_quat
			#log_debug("Rotation would be " + str(outdict["quaternion"]) + " (" + str(rot_quat.get_euler() * 180.0 / PI) + " deg)")
		else:
			rot_quat = orig_rot_godot
		rot_quat = rotation_delta.basis.get_rotation_quaternion().inverse() * rot_quat * rotation_delta_post.basis.get_rotation_quaternion().inverse()
		rot_quat.y = -rot_quat.y
		rot_quat.z = -rot_quat.z

		var orig_scale: Vector3 = cur_signs * (rotation_delta.basis.inverse() * Basis.from_scale(orig_scale_godot.abs()) * rotation_delta_post.basis.inverse()).get_scale()
		#log_debug("Original scale: " + str(orig_scale_godot) + " -> " + str(orig_scale))
		var input_scale_vec: Vector3
		var scale: Variant = get_vector(uprops, "m_LocalScale", orig_scale)
		if typeof(scale) == TYPE_VECTOR3:
			input_scale_vec = scale as Vector3
			var scale_vec: Vector3 = scale as Vector3
			#log_debug("Scale originally is " + str(scale_vec))
			# FIXME: Godot handles scale 0 much worse than Unity. Try to avoid it.
			if scale_vec.x > -1e-7 && scale_vec.x < 1e-7:
				scale_vec.x = 1e-7
			if scale_vec.y > -1e-7 && scale_vec.y < 1e-7:
				scale_vec.y = 1e-7
			if scale_vec.z > -1e-7 && scale_vec.z < 1e-7:
				scale_vec.z = 1e-7
			var new_signs: Vector3 = (scale_vec.sign() + Vector3(0.5,0.5,0.5)).sign()
			scale_vec = new_signs * (rotation_delta.basis * Basis.from_scale(scale_vec.abs()) * rotation_delta_post.basis).get_scale()
			outdict["scale"] = scale_vec
			#log_debug("Scale would be " + str(outdict["scale"]))
		else:
			input_scale_vec = orig_scale

		var orig_pos: Vector3 = (rotation_delta.basis.inverse() * orig_pos_godot) * Vector3(-1, 1, 1)
		#log_debug("Original position: " + str(orig_pos_godot) + " -> " + str(orig_pos))
		var pos_tmp: Variant = get_vector(uprops, "m_LocalPosition", orig_pos)
		if typeof(pos_tmp) == TYPE_VECTOR3:
			var pos_vec: Vector3 = pos_tmp as Vector3
			#log_debug("Position originally is " + str(pos_vec * Vector3(-1, 1, 1)) + " adding " + str(rot_quat * (input_scale_vec * rotation_delta_post.origin)))
			pos_vec = rotation_delta * (pos_vec * Vector3(-1, 1, 1) + rot_quat * (input_scale_vec * rotation_delta_post.origin)) # * rotation_delta_post.basis #.get_rotation_quaternion()
			outdict["position"] = pos_vec
			#log_debug("Position would be " + str(outdict["position"]))

		return outdict

	func convert_skeleton_properties(skel: Skeleton3D, bone_name: String, uprops: Dictionary):
		var bone_idx: int = skel.find_bone(bone_name)
		return _convert_properties_pos_scale(uprops, skel.get_bone_pose_position(bone_idx), skel.get_bone_pose_rotation(bone_idx), skel.get_bone_pose_scale(bone_idx))

	var rootOrder: int:
		get:
			return keys.get("m_RootOrder", 0)

	var parent_ref: Variant:  # Array: # UnityRef
		get:
			if is_stripped:
				log_fail("Attempted to access the parent of a stripped " + type + " " + uniq_key, "parent")
				return 12345.678  # FIXME: Returning bogus value to crash whoever does this
			return keys.get("m_Father", [null, 0, "", 0])

	var parent_no_stripped: UnityObject:  # UnityTransform
		get:
			if is_stripped or is_non_stripped_prefab_reference:
				return meta.lookup(self.prefab_instance)  # Not a UnityTransform, but sufficient for determining a common "ancestor" for skeleton bones.
			return meta.lookup(parent_ref)

	var parent: Variant:  # UnityTransform:
		get:
			if is_stripped:
				log_fail("Attempted to access the parent of a stripped " + type + " " + uniq_key, "parent")
				return 12345.678  # FIXME: Returning bogus value to crash whoever does this
			return meta.lookup(parent_ref)


class UnityRectTransform:
	extends UnityTransform

	func get_godot_type() -> String:
		return "Control"

	pass


class UnityCollider:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "StaticBody3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var new_node: CollisionShape3D = CollisionShape3D.new()
		log_debug("Creating collider at " + self.name + " type " + self.type + " parent name " + str(new_parent.name if new_parent != null else "NULL") + " path " + str(state.owner.get_path_to(new_parent) if new_parent != null else NodePath()) + " body name " + str(state.body.name if state.body != null else "NULL") + " path " + str(state.owner.get_path_to(state.body) if state.body != null else NodePath()))
		new_node.shape = self.shape
		if state.body == null or keys.get("m_IsTrigger", 0) != 0:
			var new_body: Node3D
			if keys.get("m_IsTrigger", 0) != 0:
				new_body = Area3D.new()
			else:
				new_body = StaticBody3D.new()
			new_body.name = self.type
			new_parent.add_child(new_body, true)
			new_body.owner = state.owner
			new_node.name = "CollisionShape3D"
			state.add_child(new_node, new_body, self)
		else:
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
					log_debug("Found node " + str(cur_node) + " class " + str(cur_node.get_class()))
					log_debug("Found node " + str(cur_node) + " transform " + str(cur_node.transform))
					xform = cur_node.transform.affine_inverse() * xform
			#while cur_node != state.body and cur_node != null:
			#	xform = cur_node.transform * xform
			#	cur_node = cur_node.get_parent()
			#if cur_node == null:
			#	xform = Transform3D(self.basis, self.center)
			if not xform.is_equal_approx(Transform3D()):
				new_node.set_meta("__xform_storage", xform)
		return new_node

	# TODO: Colliders are complicated because of the transform hierarchy issue above.
	func convert_properties_collider(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		var complex_xform: Transform3D = Transform3D.IDENTITY
		if node != null and node.has_meta("__xform_storage"):
			complex_xform = node.get_meta("__xform_storage")
		var center: Vector3 = Vector3()
		var basis: Basis = Basis.IDENTITY

		var center_prop: Variant = get_vector(uprops, "m_Center")
		if typeof(center_prop) == TYPE_VECTOR3:
			center = Vector3(-1.0, 1.0, 1.0) * center_prop
			if not complex_xform.is_equal_approx(Transform3D.IDENTITY):
				outdict["transform"] = complex_xform * Transform3D(basis, center)
			else:
				outdict["position"] = center
		if uprops.has("m_Direction"):
			basis = get_basis_from_direction(uprops.get("m_Direction"))
			if not complex_xform.is_equal_approx(Transform3D.IDENTITY):
				outdict["transform"] = complex_xform * Transform3D(basis, center)
			else:
				outdict["rotation_degrees"] = basis.get_euler() * 180 / PI
		if uprops.has("m_Material"):
			outdict["_material"] = meta.get_godot_resource(uprops.get("m_Material"))
		return outdict

	func apply_node_props(node: Node, props: Dictionary):
		if props.get("_material") != null:
			var parent_rigid: RigidBody3D = node.get_parent() as RigidBody3D
			if parent_rigid != null:
				parent_rigid.physics_material_override = props.get("_material")
			var parent_static: StaticBody3D = node.get_parent() as StaticBody3D
			if parent_static != null:
				parent_static.physics_material_override = props.get("_material")
			props.erase("_material")
		super.apply_node_props(node, props)

	func get_basis_from_direction(direction: int):
		return Basis()

	var shape: Shape3D:
		get:
			return get_shape()

	func get_shape() -> Shape3D:
		return null

	func is_collider() -> bool:
		return true


class UnityBoxCollider:
	extends UnityCollider

	func get_shape() -> Shape3D:
		var bs: BoxShape3D = BoxShape3D.new()
		return bs

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		var size = get_vector(uprops, "m_Size")
		if typeof(size) != TYPE_NIL:
			outdict["shape:size"] = size
		log_debug("convert_properties: " + str(outdict))
		return outdict


class UnitySphereCollider:
	extends UnityCollider

	func get_shape() -> Shape3D:
		var bs: SphereShape3D = SphereShape3D.new()
		return bs

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		if uprops.has("m_Radius"):
			outdict["shape:radius"] = uprops.get("m_Radius")
		log_debug("**** SPHERE COLLIDER RADIUS " + str(outdict))
		return outdict


class UnityCapsuleCollider:
	extends UnityCollider

	func get_shape() -> Shape3D:
		var bs: CapsuleShape3D = CapsuleShape3D.new()
		return bs

	func get_basis_from_direction(direction: int):
		if direction == 0:  # Along the X-Axis
			return Basis.from_euler(Vector3(0.0, 0.0, PI / 2.0))
		if direction == 1:  # Along the Y-Axis (Godot default)
			return Basis.from_euler(Vector3(0.0, 0.0, 0.0))
		if direction == 2:  # Along the Z-Axis
			return Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0))

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		var radius: float = 0.0  # FIXME: height including radius???? Did godot change this???
		if node != null:
			radius = node.shape.radius
			log_debug("Convert capsules " + str(node.shape.radius) + " " + str(node.name) + " and " + str(outdict))
		if typeof(uprops.get("m_Radius")) != TYPE_NIL:
			radius = uprops.get("m_Radius")
			outdict["shape:radius"] = radius
		if typeof(uprops.get("m_Height")) != TYPE_NIL:
			var adj_height: float = uprops.get("m_Height") - 2 * radius
			if adj_height < 0.0:
				adj_height = 0.0
			outdict["shape:height"] = adj_height
		return outdict


class UnityMeshCollider:
	extends UnityCollider

	var source_mesh_instance: MeshInstance3D # Used only for component added to instanced prefab.

	# Not making these animatable?
	var convex: bool:
		get:
			return keys.get("m_Convex", 0) != 0

	func get_shape() -> Shape3D:
		var source_mesh: Mesh
		if source_mesh_instance != null:
			source_mesh = source_mesh_instance.mesh
		else:
			source_mesh = meta.get_godot_resource(get_mesh(keys))
		if convex:
			return source_mesh.create_convex_shape()
		else:
			return source_mesh.create_trimesh_shape()

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
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
						log_warn("Oh no i am stripped MeshCollider")
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

	func get_mesh(uprops: Dictionary) -> Array:  # UnityRef
		var ret = get_ref(uprops, "m_Mesh")
		if ret[1] == 0:
			if is_stripped or gameObject.is_stripped:
				log_warn("Oh no i am stripped MeshCollider get_mesh")
			var mf: RefCounted = gameObject.get_meshFilter()
			if mf != null:
				if mf.is_stripped:
					log_warn("Oh no i am stripped MeshFilter get_mesh")
				return mf.mesh
		return ret


class UnityTerrainCollider:
	extends UnityMeshCollider

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var coll: Node3D = super.create_godot_node(state, new_parent)
		return coll

	func get_shape() -> Shape3D:
		return get_collision_shape(self.keys)

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_collider(node, uprops)
		outdict["shape"] = get_collision_shape(uprops)
		return outdict

	func get_collision_shape(uprops: Dictionary) -> Shape3D:  # UnityRef
		var coll_ref: Array = uprops.get("m_TerrainData")
		coll_ref = [null, 0xc0111de4 ^ coll_ref[1], coll_ref[2], coll_ref[3]]
		var concave: ConcavePolygonShape3D = self.meta.get_godot_resource(coll_ref)
		return concave


class UnityRigidbody:
	extends UnityComponent

	func get_godot_type() -> String:
		return "RigidBody3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func create_physics_body(state: RefCounted, new_parent: Node3D, name: String) -> Node:
		var new_node: Node3D
		var rigid: RigidBody3D = RigidBody3D.new()
		rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		new_node = rigid

		new_node.name = name  # Not type: This replaces the usual transform node.
		state.add_child(new_node, new_parent, self)
		return new_node

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_IsKinematic"):
			outdict["freeze"] = uprops["m_IsKinematic"] != 0
		if uprops.has("m_Mass"):
			outdict["mass"] = uprops["m_Mass"]
		if uprops.has("m_Drag"):
			outdict["linear_damp"] = uprops["m_Drag"]
		if uprops.has("m_UseGravity"):
			outdict["gravity_scale"] = 1.0 * uprops["m_UseGravity"] # 0 or 1
		if uprops.has("m_AngularDrag"):
			outdict["angular_damp"] = uprops["m_AngularDrag"]
		if uprops.has("m_CollisionDetection"):
			outdict["continuous_cd"] = uprops["m_CollisionDetection"] != 0
		if uprops.has("m_Constraints"):
			outdict["lock_rotation"] = (uprops["m_Constraints"] & 112) == 112 # 16, 32, 64 lock axes.
			outdict["axis_lock_angular_x"] = (uprops["m_Constraints"] & 16) != 0
			outdict["axis_lock_angular_y"] = (uprops["m_Constraints"] & 32) != 0
			outdict["axis_lock_angular_z"] = (uprops["m_Constraints"] & 64) != 0
			outdict["axis_lock_linear_x"] = (uprops["m_Constraints"] & 2) != 0
			outdict["axis_lock_linear_y"] = (uprops["m_Constraints"] & 4) != 0
			outdict["axis_lock_linear_z"] = (uprops["m_Constraints"] & 8) != 0
		if uprops.has("m_Layer"):
			outdict["collision_layer"] = uprops.get("m_Layer")
		return outdict

	func create_physical_bone(state: RefCounted, godot_skeleton: Skeleton3D, name: String):
		var new_node: PhysicalBone3D = PhysicalBone3D.new()
		new_node.bone_name = name
		new_node.name = name
		state.add_child(new_node, godot_skeleton, self)
		return new_node


class UnityCharacterController:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "CharacterBody3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func create_physics_body(state: RefCounted, new_parent: Node3D, name: String) -> Node:
		var character: CharacterBody3D = CharacterBody3D.new()
		character.name = name  # Not type: This replaces the usual transform node.
		state.add_child(character, new_parent, self)
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CapsuleShape3D"
		var capsule := CapsuleShape3D.new()
		collision_shape.shape = capsule
		character.add_child(collision_shape)
		collision_shape.owner = character.owner
		return character

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_Height"):
			outdict["_height"] = uprops.get("m_Height", 2.0)
		if uprops.has("m_Radius"):
			outdict["_radius"] = uprops.get("m_Radius", 0.5)
		if uprops.has("m_Center"):
			outdict["_center"] = uprops.get("m_Center", Vector3.ZERO) * Vector3(-1,1,1)
		if uprops.has("m_SlopeLimit"):
			outdict["floor_max_angle"] = uprops.get("m_SlopeLimit", 45) * PI / 180.0
		if uprops.has("m_SkinWidth"):
			outdict["floor_snap_length"] = uprops.get("m_SkinWidth", 0.1)
		# What to do with m_StepOffset... Godot doesn't have this?
		if uprops.has("m_Material"):
			outdict["_material"] = meta.get_godot_resource(uprops.get("m_Material"))
		if uprops.has("m_Layer"):
			outdict["collision_layer"] = uprops.get("m_Layer")
		return outdict

	func apply_node_props(node: Node, props: Dictionary):
		var coll_shape: CollisionShape3D = node.get_node("CapsuleShape3D") as CollisionShape3D
		if coll_shape != null:
			var capsule_shape: CapsuleShape3D = coll_shape.shape as CapsuleShape3D
			if capsule_shape != null:
				if props.has("_height"):
					capsule_shape.height = props["_height"]
					props.erase("_height")
				if props.has("_radius"):
					capsule_shape.radius = props["_radius"]
					props.erase("_radius")
				if props.has("_center"):
					coll_shape.position = props["_center"]
					props.erase("_center")
				# TODO: Godot does not yet support per-collision-shape materials
				#if props.has("_material"):
				#	capsule_shape.physics_material_override = props["_material"]
				#	props.erase("_material")
		super.apply_node_props(node, props)

class UnityMeshFilter:
	extends UnityComponent

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		var flags_val: int = keys.get("m_StaticEditorFlags", 0) # We copy this from the GameObject to the MeshRenderer.
		var lightmap_static: bool = (flags_val & 1) != 0
		outdict["_lightmap_static"] = lightmap_static
		if uprops.has("m_Mesh"):
			var mesh_ref: Array = get_ref(uprops, "m_Mesh")
			var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
			log_debug("MeshFilter " + str(self.uniq_key) + " ref " + str(mesh_ref) + " new mesh " + str(new_mesh) + " old mesh " + str(node.mesh))
			outdict["_mesh"] = new_mesh  # property track?
		return outdict

	func get_filter_mesh() -> Array:  # UnityRef
		return keys.get("m_Mesh", [null, 0, "", null])


class UnityRenderer:
	extends UnityBehaviour

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_Layer"):
			outdict["layers"] = (1 << uprops["m_Layer"])
		if uprops.has("m_StaticEditorFlags"):
			var flags_val: int = uprops.get("m_StaticEditorFlags", 0) # We copy this from the GameObject to the MeshRenderer.
			var lightmap_static: bool = (flags_val & 1) != 0
			outdict["_lightmap_static"] = lightmap_static
		if uprops.has("m_ScaleInLightmap"):
			var lightmap_scale: float = uprops.get("m_ScaleInLightmap", 1)
			if lightmap_scale <= 1.55:
				outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_1X
			elif lightmap_scale <= 3.05:
				outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_2X
			elif lightmap_scale <= 6.05:
				outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_4X
			else:
				outdict["gi_lightmap_scale"] = MeshInstance3D.LIGHTMAP_SCALE_8X

		# if flags_val & 16: # Occludee static
		# if flags_val & 2: # Occluder static
		if uprops.has("m_DynamicOccludee"):
			outdict["ignore_occlusion_culling"] = uprops.get("m_DynamicOccludee", 1) != 1

		if uprops.has("m_CastShadows"):
			match uprops.get("m_CastShadows", 1):
				0:
					outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				2:
					outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
				3:
					outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				_:
					outdict["cast_shadow"] = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		if uprops.has("m_Materials"):
			outdict["_materials_size"] = len(uprops.get("m_Materials"))
			var idx: int = 0
			for m in uprops.get("m_Materials", []):
				outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
				idx += 1
			log_debug("Converted mesh prop " + str(outdict))
		else:
			if uprops.has("m_Materials.Array.size"):
				outdict["_materials_size"] = uprops.get("m_Materials.Array.size")
			const MAT_ARRAY_PREFIX: String = "m_Materials.Array.data["
			for prop in uprops:
				if str(prop).begins_with(MAT_ARRAY_PREFIX) and str(prop).ends_with("]"):
					var idx: int = str(prop).substr(len(MAT_ARRAY_PREFIX), len(str(prop)) - 1 - len(MAT_ARRAY_PREFIX)).to_int()
					var m: Array = get_ref(uprops, prop)
					outdict["_materials/" + str(idx)] = meta.get_godot_resource(m)
			log_debug("Converted mesh prop " + str(outdict) + "  for uprop " + str(uprops))
		return outdict


class UnityMeshRenderer:
	extends UnityRenderer

	func get_godot_type() -> String:
		return "MeshInstance3D"

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
			log_fail("Oh no i am stripped MeshRenderer create_godot_node_orig")
		var mf: RefCounted = gameObject.get_meshFilter()
		if mf != null:
			state.add_fileID(new_node, mf)
		var idx: int = 0
		for m in keys.get("m_Materials", []):
			new_node.set_surface_override_material(idx, meta.get_godot_resource(m))
			idx += 1
		return new_node

	# TODO: convert_properties
	# both material properties as well as material references??
	# anything else to animate?

	func get_mesh() -> Array:  # UnityRef
		if is_stripped or gameObject.is_stripped:
			log_fail("Oh no i am stripped MeshRenderer get_mesh")
		var mf: RefCounted = gameObject.get_meshFilter()
		if mf != null:
			return mf.get_filter_mesh()
		return [null, 0, "", null]


class UnitySkinnedMeshRenderer:
	extends UnityMeshRenderer

	const ENABLE_CLOTH := false

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		if len(bones) == 0:
			var cloth: UnityCloth = gameObject.GetComponent("Cloth")
			if cloth != null:
				return create_cloth_godot_node(state, new_parent, type, cloth)
			return create_godot_node_orig(state, new_parent, type)
		else:
			return null

	func create_cloth_godot_node(state: RefCounted, new_parent: Node3D, component_name: String, cloth: UnityCloth) -> Node:
		if not ENABLE_CLOTH:
			return create_godot_node_orig(state, new_parent, component_name)
		var new_node: MeshInstance3D = cloth.create_cloth_godot_node(state, new_parent, component_name, self, self.get_mesh(), null, [])
		var idx: int = 0
		for m in keys.get("m_Materials", []):
			new_node.set_surface_override_material(idx, meta.get_godot_resource(m))
			idx += 1
		return new_node

	func get_skelley(state: RefCounted) -> RefCounted: # Skelley
		var bones: Array = self.bones
		if len(self.bones) == 0:
			return null
		var first_bone_obj: RefCounted = meta.lookup(bones[0])
		#if first_bone_obj.is_stripped:
		#	log_fail("Cannot create skinned mesh on stripped skeleton!")
		#	return null
		var first_bone_key: String = first_bone_obj.uniq_key
		log_debug("SkinnedMeshRenderer: Looking up " + first_bone_key + " for " + str(self.gameObject))
		var skelley: RefCounted = state.uniq_key_to_skelley.get(first_bone_key, null)  # Skelley
		if skelley == null:
			log_fail("Unable to find Skelley to add a mesh " + name + " for " + first_bone_key, "bones", first_bone_obj)
		return skelley

	func create_skinned_mesh(state: RefCounted) -> Node:
		var skelley: RefCounted = get_skelley(state) # Skelley
		if skelley == null:
			return null
		var gdskel: Skeleton3D = skelley.godot_skeleton
		if gdskel == null:
			log_fail("Unable to find skeleton to add a mesh " + name + " for " + meta.lookup(bones[0]).uniq_key, "bones", meta.lookup(bones[0]))
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
		ret.skin = edit_skin(component_name, get_skin(), gdskel)
		# TODO: duplicate skin and assign the correct bone names to match self.bones array
		ret.lod_bias = 128 # Disable builtin LODs on skinned meshes due to multiple bugs.
		return ret

	var bones: Array:
		get:
			return keys.get("m_Bones", [])

	func edit_skin(component_name: String, skin_ref: Array, gdskel: Skeleton3D) -> Skin:
		var original_is_humanoid: bool = false
		var skin: Skin = meta.get_godot_resource(skin_ref)
		var skin_humanoid_rotation_delta: Dictionary
		if skin.has_meta("humanoid_rotation_delta"):
			skin_humanoid_rotation_delta = skin.get_meta("humanoid_rotation_delta")
		if skin == null:
			log_fail("Mesh " + component_name + " has bones " + str(len(bones)) + " has null skin", "skin")
		elif len(bones) != skin.get_bind_count():
			log_fail("Mesh " + component_name + "has bones " + str(len(bones)) + " mismatched with bind bones " + str(skin.get_bind_count()), "bones")

		var edited: bool = false
		for idx in range(len(bones)):
			var bone_transform: UnityTransform = meta.lookup(bones[idx])
			if bone_transform == null:
				log_warn("Mesh " + component_name + " has null bone " + str(idx), "bones")
				continue
			if bone_transform.skeleton_bone_index != -1 and skin.get_bind_bone(idx) != bone_transform.skeleton_bone_index:
				edited = true
				break
			var bone_fileID = bone_transform.fileID
			if meta.transform_fileid_to_rotation_delta.has(bone_fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(bone_fileID):
				if !skin_humanoid_rotation_delta.get(skin.get_bind_name(idx), Transform3D.IDENTITY).is_equal_approx(meta.transform_fileid_to_rotation_delta.get(bone_fileID, meta.prefab_transform_fileid_to_rotation_delta.get(bone_fileID))):
					edited = true
					break
		if edited:
			skin = skin.duplicate()
			for idx in range(len(bones)):
				var bone_transform: UnityTransform = meta.lookup(bones[idx])
				if bone_transform == null:
					log_warn("Mesh " + component_name + " has null bone " + str(idx), "bones")
					continue
				if bone_transform.skeleton_bone_index != -1:
					skin.set_bind_bone(idx, bone_transform.skeleton_bone_index)
					skin.set_bind_name(idx, gdskel.get_bone_name(bone_transform.skeleton_bone_index))
				var bone_fileID = bone_transform.fileID
				if meta.transform_fileid_to_rotation_delta.has(bone_fileID) or meta.prefab_transform_fileid_to_rotation_delta.has(bone_fileID):
					var skin_rotation_delta: Transform3D = skin_humanoid_rotation_delta.get(skin.get_bind_name(idx), Transform3D.IDENTITY)
					var rotation_delta: Transform3D = meta.transform_fileid_to_rotation_delta.get(bone_fileID, meta.prefab_transform_fileid_to_rotation_delta.get(bone_fileID))
					if !rotation_delta.is_equal_approx(skin_rotation_delta):
						log_debug("skin " + str(idx) + " : This fileID is a humanoid bone rotation offset=" + str(rotation_delta.basis.get_rotation_quaternion()) + " scale " + str(rotation_delta.basis.get_scale()))
						skin.set_bind_pose(idx, rotation_delta * skin_rotation_delta.affine_inverse() * skin.get_bind_pose(idx))
		return skin

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = super.convert_properties(node, uprops)
		if uprops.has("m_Mesh"):
			var mesh_ref: Array = get_ref(uprops, "m_Mesh")
			var new_mesh: Mesh = meta.get_godot_resource(mesh_ref)
			outdict["_mesh"] = new_mesh  # property track?
			var skin_ref: Array = mesh_ref
			skin_ref = [null, -skin_ref[1], skin_ref[2], skin_ref[3]]
			outdict["skin"] = edit_skin(node.name, skin_ref, node.get_parent() as Skeleton3D)

			# TODO: blend shapes

			# TODO: m_Bones modifications? what even is the syntax. I think we shouldn't allow changes to bones.
		return outdict

	func get_skin() -> Array:  # UnityRef
		var ret: Array = keys.get("m_Mesh", [null, 0, "", null])
		return [null, -ret[1], ret[2], ret[3]]

	func get_mesh() -> Array:  # UnityRef
		return keys.get("m_Mesh", [null, 0, "", null])


class UnityCloth:
	extends UnityBehaviour

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null

	func get_bone_transform(skel: Skeleton3D, bone_idx: int) -> Transform3D:
		var transform: Transform3D = Transform3D.IDENTITY
		while bone_idx != -1:
			transform = skel.get_bone_pose(bone_idx) * transform
			bone_idx = skel.get_bone_parent(bone_idx)
		return transform

	func get_or_upgrade_bone_attachment(skel: Skeleton3D, state: RefCounted, bone_transform: UnityTransform) -> BoneAttachment3D:
		var fileID: int = bone_transform.fileID
		var target_nodepath: NodePath = meta.fileid_to_nodepath.get(fileID, meta.prefab_fileid_to_nodepath.get(fileID, NodePath()))
		var ret: Node3D = skel
		if target_nodepath != NodePath():
			ret = state.owner.get_node(target_nodepath)
		if ret is Skeleton3D:
			ret = BoneAttachment3D.new()
			ret.name = skel.get_bone_name(bone_transform.skeleton_bone_index)  # target_skel_bone
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
		var mesh_arrays: Array = new_node.mesh.surface_get_arrays(0)  # Godot SoftBody ignores other surfaces.
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
		var idxlen: int = len(mesh_verts)
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

		log_debug("Verts " + str(len(mesh_verts)) + " " + str(len(mesh_bones)) + " " + str(len(mesh_weights)) + " dedupe_len=" + str(vert_idx) + " unity_len=" + str(len(self.coefficients)))

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
						bone_idx_to_bone_transform[most_bone] = (get_bone_transform(skel, skel.find_bone(attachment.bone_name)).affine_inverse())
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


class UnityLight:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "Light3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var light: Light3D
		# TODO: Change Light to use set() and convert_properties system
		var unityLightType = lightType
		if unityLightType == 0:
			# Assuming default cookie
			# Assuming Legacy pipeline:
			# Scriptable Rendering Pipeline: shape and innerSpotAngle not supported.
			# Assuming RenderSettings.m_SpotCookie: == {fileID: 10001, guid: 0000000000000000e000000000000000, type: 0}
			var spot_light: SpotLight3D = SpotLight3D.new()
			spot_light.set_param(Light3D.PARAM_SPOT_ANGLE, spotAngle * 0.5)
			spot_light.set_param(Light3D.PARAM_SPOT_ATTENUATION, 0.5)  # Eyeball guess for Unity's default spotlight texture
			spot_light.set_param(Light3D.PARAM_ATTENUATION, 0.333)  # Was 1.0
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
			log_warn("Rectangle Area Light not supported!", "lightType")
			# areaSize?
			return super.create_godot_node(state, new_parent)
		elif unityLightType == 4:
			log_warn("Disc Area Light not supported!", "lightType")
			return super.create_godot_node(state, new_parent)

		# TODO: Layers
		if keys.get("useColorTemperature"):
			log_warn("Color Temperature not implemented.", "useColorTemperature")
		light.name = type
		state.add_child(light, new_parent, self)
		light.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)))
		light.light_color = color
		light.set_param(Light3D.PARAM_ENERGY, intensity)
		light.set_param(Light3D.PARAM_INDIRECT_ENERGY, bounceIntensity)
		light.shadow_enabled = shadowType != 0
		light.set_param(Light3D.PARAM_SHADOW_BIAS, shadowBias)
		if lightmapBakeType == 1:
			light.light_bake_mode = Light3D.BAKE_DYNAMIC  # INDIRECT??
		elif lightmapBakeType == 2:
			light.light_bake_mode = Light3D.BAKE_DYNAMIC  # BAKE_ALL???
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
			return keys.get("m_BounceIntensity", 1.0)

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
			return keys.get("m_Shadows").get("m_NormalBias", 0.01)

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		if uprops.has("m_CullingMask"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask").get("m_Bits")
		elif uprops.has("m_CullingMask.m_Bits"):
			outdict["light_cull_mask"] = uprops.get("m_CullingMask.m_Bits")
		if uprops.has("m_TagString"):
			outdict["editor_only"] = uprops["m_TagString"] == "EditorOnly"
		return outdict


class UnityAudioClip:
	extends UnityObject

	# We only support importing audio clips for now.
	func create_godot_resource() -> Resource:
		return null


class UnityAudioSource:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "AudioStreamPlayer3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var audio: Node = null
		var panlevel_curve: Dictionary = keys.get("panLevelCustomCurve", {})
		var curves: Array = panlevel_curve.get("m_Curve", [])
		#if len(curves) == 1:
		#	log_debug("Curve is " + str(curves) + " value is " + str(curves[0].get("value", 1.0)))
		if len(curves) == 1 and str(curves[0].get("value", 1.0)).to_float() < 0.001:
			# Completely 2D: use non-spatialized player.
			audio = AudioStreamPlayer.new()
		else:
			audio = AudioStreamPlayer3D.new()
		audio.name = "AudioSource"
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


class UnityCamera:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "Camera3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var par: Node = new_parent
		var texref: Array = keys.get("m_TargetTexture", [null, 0, null, null])
		var rendertex: UnityObject = null
		if texref[1] != 0:
			rendertex = meta.lookup(texref)  # FIXME: This might not find separate assets.
		if rendertex != null:
			var viewport: SubViewport = SubViewport.new()
			viewport.name = "SubViewport"
			new_parent.add_child(viewport, true)
			viewport.owner = state.owner
			viewport.size = Vector2(rendertex.keys.get("m_Width"), rendertex.keys.get("m_Height"))
			if keys.get("m_AllowMSAA", 0) == 1:
				if rendertex.keys.get("m_AntiAliasing", 0) == 1:
					viewport.msaa = Viewport.MSAA_8X
			viewport.use_occlusion_culling = keys.get("m_OcclusionCulling", 0)
			viewport.clear_mode = (SubViewport.CLEAR_MODE_ALWAYS if keys.get("m_ClearFlags") < 3 else SubViewport.CLEAR_MODE_NEVER)
			# Godot is always HDR? if keys.get("m_AllowHDR", 0) == 1
			par = viewport
		var cam: Camera3D = Camera3D.new()
		cam.name = "Camera"
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
			cenv.background_energy_multiplier = eng
		assign_object_meta(cam)
		state.add_child(cam, par, self)
		cam.transform = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)))
		return cam

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
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
			outdict["projection"] = Camera3D.PROJECTION_ORTHOGONAL if uprops.get("orthographic") else Camera3D.PROJECTION_PERSPECTIVE
		if uprops.has("orthographic size"):
			if uprops.get("orthographic", 0):
				outdict["size"] = min(0.000011, uprops.get("orthographic size"))
		return outdict


class UnityLightProbeGroup:
	extends UnityComponent

	func get_godot_type() -> String:
		return "LightmapProbe"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var i = 0
		var probe_positions: PackedVector3Array
		for pos in keys.get("m_SourcePositions", []):
			pos.x = -pos.x
			i += 1
			var probe: LightmapProbe = LightmapProbe.new()
			probe.name = "Probe" + str(i)
			new_parent.add_child(probe)
			probe.owner = state.owner
			probe.position = pos
			probe_positions.append(pos)
		# The LightmapProbe objects will be deleted later if there are too many...
		# We store the full original list here so users can reconstruct the probe positions
		# if Godot fixes the performance bugs in the lightmapper.
		new_parent.set_meta("lightmap_probe_positions", probe_positions)
		return null


class UnityReflectionProbe:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "ReflectionProbe"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var probe: ReflectionProbe = ReflectionProbe.new()
		probe.name = "ReflectionProbe"
		# UPDATE_ALWAYS can crash Godot if multiple probes "see" each other
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		assign_object_meta(probe)
		state.add_child(probe, new_parent, self)
		return probe

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
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
			log_warn("Reflection Probe = Baked is not supported. Treating as Realtime / Once")
		if uprops.get("m_Mode", 0) == 2:
			log_warn("Reflection Probe = Custom is not supported. Treating as Realtime / Once")
		'''
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
		'''
		return outdict


class UnityTerrain:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "MultiMeshInstance3D"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		#var terrain: MeshInstance3D = MeshInstance3D.new()
		#terrain.name = "Terrain"
		#assign_object_meta(terrain)
		#state.add_child(terrain, new_parent, self)
		# Traditional instanced scene case: It only requires calling instantiate() and setting the filename.
		var packed_scene: PackedScene = meta.get_godot_resource(keys.get("m_TerrainData", [null, 0, null, null]))
		if packed_scene == null:
			return null
		var instanced_terrain: Node3D = packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		#instanced_scene.scene_file_path = packed_scene.resource_path
		state.add_child(instanced_terrain, new_parent, self)
		state.owner.set_editable_instance(instanced_terrain, true)
		#instanced_terrain.top_level = true
		#instanced_terrain.position = new_parent.global_transform.origin
		instanced_terrain.name = "Terrain"
		return instanced_terrain

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		return outdict


class UnityMonoBehaviour:
	extends UnityBehaviour
	var monoscript: Array:
		get:
			return keys.get("m_Script", [null, 0, null, null])

	func get_godot_type() -> String:
		return "GDScript"

	# No need yet to override create_godot_node...
	func create_godot_resource() -> Resource:
		if monoscript[1] == 11500000:
			if monoscript[2] == "8e6292b2c06870d4495f009f912b9600":
				return create_post_processing_profile()
		return null

	func create_post_processing_profile() -> Environment:
		var env: Environment = Environment.new()
		for setting in keys.get("settings"):
			var sobj = meta.lookup(setting)
			match str(sobj.monoscript[2]):
				"adb84e30e02715445aeb9959894e3b4d":  # Tonemap
					env.set_meta("tonemap", sobj.keys)
				"48a79b01ea5641d4aa6daa2e23605641":  # Glow
					env.set_meta("glow", sobj.keys)
		return env


class UnityAnimation:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "AnimationPlayer"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var animplayer: AnimationPlayer = AnimationPlayer.new()
		state.add_child(animplayer, new_parent, self)
		animplayer.name = "Animation"
		# TODO: Add AnimationTree as well.
		return animplayer

	func setup_post_children(node: Node):
		var animplayer: AnimationPlayer = node
		var which_playing: StringName = &""
		var default_ref = keys["m_Animation"]
		var anim_library = AnimationLibrary.new()
		for anim_ref in keys["m_Animations"]:
			var anim_clip_obj: UnityAnimationClip = meta.lookup(anim_ref, true)
			var anim_res: Animation = meta.get_godot_resource(anim_ref, true)
			var anim_name = StringName()
			if anim_res == null and anim_clip_obj == null:
				meta.lookup(anim_ref)
				continue
			elif anim_res == null and anim_clip_obj != null:
				anim_res = anim_clip_obj.create_animation_clip_at_node(self, node.get_parent())
				anim_name = StringName(anim_clip_obj.keys["m_Name"])
			elif anim_res != null and anim_clip_obj != null:
				anim_res = anim_clip_obj.adapt_animation_clip_at_node(self, node.get_parent(), anim_res)
				anim_name = StringName(anim_clip_obj.keys["m_Name"])
			else:
				anim_name = StringName(anim_res.resource_name)
			anim_library.add_animation(anim_name, anim_res)
			if default_ref == anim_ref:
				which_playing = anim_name
		animplayer.add_animation_library(&"", anim_library)
		animplayer.autoplay = which_playing

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		log_debug("convert_properties Animator" + str(outdict))
		return outdict


class UnityAnimator:
	extends UnityBehaviour

	func get_godot_type() -> String:
		return "AnimationTree"

	func get_avatar_meta() -> Object:
		return meta.lookup_meta(keys.get("m_Avatar", [null, 0, "", null]))

	func assign_controller(anim_player: AnimationPlayer, anim_tree: AnimationTree, controller_ref: Array):
		var main_library: AnimationLibrary = null
		var base_library: AnimationLibrary = null
		var root_node: AnimationRootNode = null
		var referenced_resource: Resource = meta.get_godot_resource(controller_ref)
		if referenced_resource is AnimationLibrary:
			main_library = referenced_resource
			root_node = main_library.get_meta("base_node")
			base_library = main_library.get_meta("base_library")
		else:
			root_node = referenced_resource
			var lib_ref: Array = [null, -controller_ref[1], controller_ref[2], controller_ref[3]]
			main_library = meta.get_godot_resource(lib_ref)
		for libname in anim_player.get_animation_library_list():
			anim_player.remove_animation_library(StringName(libname))
		anim_player.add_animation_library(&"", main_library)
		if base_library != null:
			anim_player.add_animation_library(&"base", base_library)
		anim_tree.tree_root = root_node

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var animplayer: AnimationPlayer = AnimationPlayer.new()
		animplayer.name = "AnimationPlayer"
		state.add_child(animplayer, new_parent, self)
		animplayer.root_node = NodePath("..")
		if keys.get("m_ApplyRootMotion", 0) == 0:
			if not state.active_avatars.is_empty():
				animplayer.root_motion_track = NodePath("%GeneralSkeleton:Root")

		var animtree: AnimationTree = AnimationTree.new()
		animtree.name = "AnimationTree"
		animtree.set("deterministic", false) # New feature in 4.2, acts like Untiy write defaults off
		if keys.get("m_ApplyRootMotion", 0) == 0:
			if not state.active_avatars.is_empty():
				animtree.root_motion_track = NodePath("%GeneralSkeleton:Root")
		state.add_child(animtree, new_parent, self)
		animtree.anim_player = animtree.get_path_to(animplayer)
		animtree.active = ANIMATION_TREE_ACTIVE
		animtree.set_script(anim_tree_runtime)
		# TODO: Add AnimationTree as well.
		assign_controller(animplayer, animtree, keys["m_Controller"])
		return animtree

	func setup_post_children(node: Node):
		var animtree: AnimationTree = node
		var animplayer: AnimationPlayer = animtree.get_node(animtree.anim_player)
		var anim_controller_meta: Resource = meta.lookup_meta(keys["m_Controller"])
		var virtual_unity_object: UnityRuntimeAnimatorController = meta.lookup_or_instantiate(keys["m_Controller"], "RuntimeAnimatorController")
		if virtual_unity_object == null:
			return  # couldn't find meta. this means it probably won't work.
		virtual_unity_object.adapt_animation_player_at_node(self, animplayer)
		#if anim_controller != null:
		#	animplayer.add_animation_library(&"", anim_controller.create_animation_library_at_node(self, node.get_parent()))

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = self.convert_properties_component(node, uprops)
		log_debug("Animator convert_properties " + str(outdict))
		if uprops.has("m_Controller"):
			if node is AnimationTree:
				assign_controller(node.get_node(node.anim_player), node, uprops["m_Controller"])
		if uprops.has("m_ApplyRootMotion"):
			if uprops.get("m_ApplyRootMotion", 0) == 0:
				outdict["root_motion_track"] = NodePath("%GeneralSkeleton:Root")
			else:
				outdict["root_motion_track"] = NodePath()
		return outdict


class UnityLODGroup:
	extends UnityBehaviour

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		if keys.get("m_Enabled"):
			state.prefab_state.lod_groups.append(self)
		return super.create_godot_node(state, new_parent) # make a default node.


class UnityTextMesh:
	extends UnityRenderer

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		var text: String = keys.get("m_Text", "")

		var label := Label3D.new()
		label.text = text
		label.name = text.get_slice("\n", 0).strip_edges().validate_node_name().substr(50).strip_edges()
		state.add_child(label, new_parent, self)
		label.outline_size = 4
		return label

	func convert_properties(node: Node, uprops: Dictionary) -> Dictionary:
		var outdict = super.convert_properties(node, uprops) # UnityRenderer
		var color: Color
		if uprops.has("m_Color"):
			var v: Variant = uprops.get("m_Color", Color())
			if typeof(v) == TYPE_COLOR:
				color = uprops.get("m_Color", Color())
			elif typeof(v) == TYPE_DICTIONARY:
				var color32: int = v.get("rgba")
				color = Color(((color32 & 0xff000000) >> 24) / 255.0, ((color32 & 0xff0000) >> 16) / 255.0, ((color32 & 0xff00) >> 8) / 255.0, (color32 & 0xff) / 255.0)
			outdict["modulate"] = color
		if uprops.has("m_Alignment"):
			match uprops.get("m_Alignment", 0):
				0:
					outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_LEFT
				1:
					outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_CENTER
				2:
					outdict["horizontal_alignment"] = HORIZONTAL_ALIGNMENT_RIGHT
		var font_size: int = 13
		if node as Label3D != null:
			font_size = node.font_size
		if uprops.has("m_FontSize"):
			font_size = uprops.get("m_FontSize", 0)
			if font_size <= 0:
				font_size = 13 # ?? default Arial?
			outdict["font_size"] = font_size
		if uprops.has("m_LineSpacing"):
			var line_spacing: float = uprops.get("m_LineSpacing")
			outdict["line_spacing"] = (line_spacing - 1.0) * font_size * 1.5 # Not sure why the 1.5 but it seems to be.
		if uprops.has("m_Font"):
			outdict["font"] = meta.get_godot_resource(uprops.get("m_Font", [null, 0, "", 0]))
		if uprops.has("m_CharacterSize"):
			outdict["pixel_size"] = 0.005 * uprops.get("m_CharacterSize", 1)
		if uprops.has("m_OffsetZ"):
			outdict["position"] = Vector3(0, 0, uprops.get("m_OffsetZ", 0))
		if uprops.has("m_Anchor"):
			var anchor: int = uprops.get("m_Anchor", 0)
			if anchor >= 0 and anchor <= 2:
				outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_TOP
			if anchor >= 3 and anchor <= 5:
				outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_CENTER
			if anchor >= 6 and anchor <= 8:
				outdict["vertical_alignment"] = VERTICAL_ALIGNMENT_BOTTOM
			# In Godot, Horizontal alignment is tied to left/right anchor.
		return outdict


### ================ IMPORTER TYPES ================
class UnityAssetImporter:
	extends UnityObject

	func get_main_object_id() -> int:
		return 0  # Unknown

	var main_object_id: int:
		get:
			return get_main_object_id()  # Unknown

	func get_external_objects() -> Dictionary:
		var eo: Dictionary = {}.duplicate()
		var extos: Variant = keys.get("externalObjects")
		if typeof(extos) != TYPE_ARRAY:
			return eo
		for srcAssetIdent in extos:
			var type_str: String = srcAssetIdent.get("first", {}).get("type", "")
			var type_key: String = type_str.split(":")[-1]
			var key: Variant = srcAssetIdent.get("first", {}).get("name", "")  # FIXME: Returns null sometimes????
			var val: Array = srcAssetIdent.get("second", [null, 0, "", null])  # UnityRef
			if typeof(key) != TYPE_NIL and not key.is_empty() and type_str.begins_with("UnityEngine"):
				if not eo.has(type_key):
					eo[type_key] = {}.duplicate()
				eo[type_key][key] = val
		return eo

	var addCollider: bool:
		get:
			return keys.get("meshes", {}).get("addCollider") == 1

	func get_animation_clips() -> Array[Dictionary]:
		var unityClips = keys.get("animations", {}).get("clipAnimations", [])
		var outClips: Array[Dictionary] = []
		for unityClip in unityClips:
			var clip = {}.duplicate()
			clip["name"] = unityClip.get("name", "")
			clip["start_frame"] = unityClip.get("firstFrame", 0.0)
			clip["end_frame"] = unityClip.get("lastFrame", 0.0)
			# "loop" also exists but appears to be unused at least
			clip["loop_mode"] = 0 if unityClip.get("loopTime", 0) == 0 else 1
			clip["take_name"] = unityClip.get("takeName", "default")
			outClips.append(clip)
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
			# Godot uses: Disabled,Static,StaticLightmaps,Dynamic
			# 1 = Static (defauylt setting)
			# 2 = StaticLightmaps
			return keys.get("meshes", {}).get("generateSecondaryUV", 0) + 1

	# The following parameters have special meaning when importing FBX files and do not map one-to-one with godot importer.
	var useFileScale: bool:
		get:
			return keys.get("meshes", {}).get("useFileScale", 0) == 1

	var extractLegacyMaterials: bool:
		get:
			return keys.get("materials", {}).get("materialLocation", 0) == 0

	var globalScale: float:
		get:
			return keys.get("meshes", {}).get("globalScale", 1)

	var ensure_tangents: bool:
		get:
			var importTangents: int = keys.get("tangentSpace", {}).get("tangentImportMode", 3)
			return importTangents != 4 and importTangents != 0

	var animation_import: bool:
		# legacyGenerateAnimations = 4 ??
		# animationType = 3 ??
		get:
			return keys.get("importAnimation") and keys.get("animationType") != 0

	var fileIDToRecycleName: Dictionary:
		get:
			return keys.get("fileIDToRecycleName", {})

	var internalIDToNameTable: Array:
		get:
			return keys.get("internalIDToNameTable", [])

	var preserveHierarchy: bool:
		get:
			return keys.get("meshes").get("preserveHierarchy", 0) != 0

	# 0: No compression; 1: keyframe reduction; 2: keyframe reduction and compress
	# 3: all of the above and choose best curve for runtime memory.
	func animation_optimizer_settings() -> Dictionary:
		var rotError: float = keys.get("animations").get("animationRotationError", 0.5)  # Degrees
		var rotErrorHalfRevs: float = rotError / 180  # p_alowed_angular_err is defined this way (divides by PI)
		return {
			"enabled": keys.get("animations").get("animationCompression") != 0,
			"max_linear_error": keys.get("animations").get("animationPositionError", 0.5),
			"max_angular_error": rotErrorHalfRevs,  # Godot defaults this value to
		}


class UnityModelImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		return 100100000  # a model is a type of Prefab

	const SINGULAR_UNITY_TO_BONE_MAP: Dictionary = {
		"Spine": "Spine",
		"UpperChest": "UpperChest",
		"Chest": "Chest",
		"Head": "Head",
		"Hips": "Hips",
		"Jaw": "Jaw",
		"Neck": "Neck",
	}

	const HANDED_UNITY_TO_BONE_MAP: Dictionary = {
		" Index Distal": "IndexDistal",
		" Index Intermediate": "IndexIntermediate",
		" Index Proximal": "IndexProximal",
		" Little Distal": "LittleDistal",
		" Little Intermediate": "LittleIntermediate",
		" Little Proximal": "LittleProximal",
		" Middle Distal": "MiddleDistal",
		" Middle Intermediate": "MiddleIntermediate",
		" Middle Proximal": "MiddleProximal",
		" Ring Distal": "RingDistal",
		" Ring Intermediate": "RingIntermediate",
		" Ring Proximal": "RingProximal",
		" Thumb Distal": "ThumbDistal",
		" Thumb Intermediate": "ThumbProximal",
		" Thumb Proximal": "ThumbMetacarpal",
		"Eye": "Eye",
		"Foot": "Foot",
		"Hand": "Hand",
		"LowerArm": "LowerArm",
		"LowerLeg": "LowerLeg",
		"Shoulder": "Shoulder",
		"Toes": "Toes",
		"UpperArm": "UpperArm",
		"UpperLeg": "UpperLeg",
	}

	static func generate_bone_map_dict_no_root(log_obj: UnityObject, humanDescriptionHuman: Array, humanNameKey := "m_HumanName", boneNameKey := "m_BoneName"):
		var bone_map_dict: Dictionary = {}
		for human in humanDescriptionHuman:
			var human_name: String = human[humanNameKey]
			var bone_name: String = human[boneNameKey]
			if human_name.begins_with("Left") or human_name.begins_with("Right"):
				var leftright = "Left" if human_name.begins_with("Left") else "Right"
				var human_key: String = human_name.substr(len(leftright))
				if human_key in HANDED_UNITY_TO_BONE_MAP:
					bone_map_dict[bone_name] = leftright + HANDED_UNITY_TO_BONE_MAP[human_key]
				else:
					log_obj.log_warn("Unrecognized " + str(leftright) + " humanName " + str(human_name) + " boneName " + str(bone_name))
			else:
				if human_name in SINGULAR_UNITY_TO_BONE_MAP:
					bone_map_dict[bone_name] = SINGULAR_UNITY_TO_BONE_MAP[human_name]
				else:
					log_obj.log_warn("Unrecognized humanName " + str(human_name) + " boneName " + str(bone_name))
		return bone_map_dict

	func generate_bone_map_dict_from_human() -> Dictionary:
		if not meta.autodetected_bone_map_dict.is_empty():
			return meta.autodetected_bone_map_dict
		var humanDescription: Dictionary = self.keys["humanDescription"]
		var bone_map_dict: Dictionary = generate_bone_map_dict_no_root(self, humanDescription["human"], "humanName", "boneName")

		if not meta.internal_data.get("humanoid_root_bone", "").is_empty():
			bone_map_dict[meta.internal_data.get("humanoid_root_bone", "")] = "Root"
		meta.humanoid_bone_map_dict = bone_map_dict
		return bone_map_dict

	func generate_bone_map_from_human() -> BoneMap:
		var bone_map: BoneMap = BoneMap.new()
		bone_map.profile = SkeletonProfileHumanoid.new()
		var bone_map_dict: Dictionary = generate_bone_map_dict_from_human()
		for skeleton_bone_name in bone_map_dict:
			var profile_bone_name = bone_map_dict[skeleton_bone_name]
			bone_map.set_skeleton_bone_name(profile_bone_name, skeleton_bone_name)
		return bone_map


class UnityShaderImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		return 4800000  # Shader


class UnityTextureImporter:
	extends UnityAssetImporter
	var textureShape: int:
		get:
			# 1: Texture2D
			# 2: Cubemap
			# 3: Texture2DArray (Unity 2020)
			# 4: Texture3D (Unity 2020)
			return keys.get("textureShape", 0)  # Some old files do not have this

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
				return 2800000  # "Texture2D",
			2:
				return 8900000  # "Cubemap",
			3:
				return 18700000  # "Texture2DArray",
			4:
				return 11700000  # "Texture3D",
			_:
				return 0


class UnityTrueTypeFontImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		return 12800000  # Font


class UnityNativeFormatImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		var ret: int = keys.get("mainObjectFileID", 0)
		if ret == -1:
			return 0
		return ret


class UnityPrefabImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		# PrefabInstance is 1001. Multiply by 100000 to create default ID.
		return 100100000  # Always should be this ID.


class UnityTextScriptImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		return 4900000  # TextAsset


class UnityAudioImporter:
	extends UnityAssetImporter

	func get_main_object_id() -> int:
		return 8300000  # AudioClip


class UnityDefaultImporter:
	extends UnityAssetImporter

	# Will depend on filetype or file extension?
	# Check file extension from `meta.path`???
	func get_main_object_id() -> int:
		match meta.path.get_extension().to_lower():
			"tscn", "unity":
				# Scene file.
				# 1: OcclusionCullingSettings (29),
				# 2: RenderSettings (104),
				# 3: LightmapSettings (157),
				# 4: NavMeshSettings (196),
				# We choose 1 to represent the default id, but there is no actual root node.
				return 1
			"txt", "html", "htm", "xml", "bytes", "json", "csv", "yaml", "fnt":
				# Supported file extensions for text (.bytes is special)
				return 4900000  # TextAsset
			_:
				# Folder, or unsupported type.
				return 102900000  # DefaultAsset


class DiscardUnityComponent:
	extends UnityComponent

	func get_godot_type() -> String:
		return "MissingNode"

	func create_godot_node(state: RefCounted, new_parent: Node3D) -> Node:
		return null


var _type_dictionary: Dictionary = {
	# "AimConstraint": UnityAimConstraint,
	# "AnchoredJoint2D": UnityAnchoredJoint2D,
	"Animation": UnityAnimation,
	"AnimationClip": UnityAnimationClip,
	"Animator": UnityAnimator,
	"AnimatorController": UnityAnimatorController,
	"AnimatorOverrideController": UnityAnimatorOverrideController,
	"AnimatorState": UnityAnimatorState,
	"AnimatorStateMachine": UnityAnimatorStateMachine,
	"AnimatorStateTransition": UnityAnimatorStateTransition,
	"AnimatorTransition": UnityAnimatorTransition,
	"AnimatorTransitionBase": UnityAnimatorTransitionBase,
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
	"AudioClip": UnityAudioClip,
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
	"Avatar": UnityAvatar,
	"AvatarMask": UnityAvatarMask,
	# "BaseAnimationTrack": UnityBaseAnimationTrack,
	# "BaseVideoTexture": UnityBaseVideoTexture,
	"Behaviour": UnityBehaviour,
	# "BillboardAsset": UnityBillboardAsset,
	# "BillboardRenderer": UnityBillboardRenderer,
	"BlendTree": UnityBlendTree,
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
	"CharacterController": UnityCharacterController,
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
	"LODGroup": UnityLODGroup,
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
	"Motion": UnityMotion,
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
	"PhysicMaterial": UnityPhysicMaterial,
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
	"RuntimeAnimatorController": UnityRuntimeAnimatorController,
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
	"Terrain": UnityTerrain,
	"TerrainCollider": UnityTerrainCollider,
	"TerrainData": UnityTerrainData,
	"TerrainLayer": UnityTerrainLayer,
	"TextAsset": UnityTextAsset,
	"TextMesh": UnityTextMesh,
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
