class_name UnidotObject extends RefCounted

const monoscript_util := preload("../../monoscript.gd")

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
	return "[" + str(type) + ":" + str(utype) + " " + str(get_debug_name()) + " @" + str(meta.guid) + ":" + str(fileID) + "]"

var name: String:
	get:
		return get_name()

func get_name() -> String:
	if fileID == meta.main_object_id:
		return meta.get_main_object_name()
	if not keys.get("m_Name", "").is_empty():
		return keys.get("m_Name", "")
	return str(keys.get("m_Name", "NO_NAME_" + str(fileID)))

func get_debug_name() -> String:
	return get_name()

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

#var gameObject: UnidotGameObject:
var gameObject:
	get:
		return get_gameObject()

#func get_gameObject() -> UnidotGameObject:
func get_gameObject():
	return null

# Belongs in UnidotComponent, but we haven't implemented all types yet.
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
		if meta.get_database().enable_unidot_keys:
			ret.set_meta("unidot_keys", self.keys)

func configure_skeleton_bone(skel: Skeleton3D, bone_name: String):
	configure_skeleton_bone_props(skel, bone_name, self.keys)

func configure_skeleton_bone_props(skel: Node3D, bone_name: String, uprops: Dictionary):
	if skel is BoneAttachment3D:
		skel = skel.get_parent() # Should be the Skeleton3D
	if not (skel is Skeleton3D):
		log_fail("Unable to configure skeleton bone props on node " + str(skel) + " bone " + str(bone_name))
		return
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
	var current_materials_raw: Array = [].duplicate()

	var prefix: String = material_prefix + str(old_surface_count - 1) + ":"
	var new_prefix: String = prefix

	var material_idx: int = 0
	while material_idx < old_surface_count:
		var mat: Resource = node.get_active_material(material_idx)
		if mat != null and str(mat.resource_name).begins_with(prefix):
			break
		current_materials_raw.push_back(mat)
		material_idx += 1

	var mat_slots: PackedInt32Array = meta.fileid_to_material_order_rev.get(fileID, meta.prefab_fileid_to_material_order_rev.get(fileID, PackedInt32Array()))
	var current_materials: Array
	current_materials.resize(len(mat_slots))
	for i in range(len(mat_slots)):
		current_materials[i] = current_materials_raw[mat_slots[i]]
	for i in range(len(mat_slots), len(current_materials_raw)):
		current_materials.append(current_materials_raw[i])
	log_debug("Current mat slots " + str(mat_slots) + " materials before: " + str(current_materials))

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
		var mesh_ref: Array = props["_mesh_ref"]
		var mesh_meta: Resource = meta.lookup_meta(mesh_ref)
		if mesh_meta != null:
			meta.fileid_to_material_order_rev[fileID] = mesh_meta.fileid_to_material_order_rev.get(mesh_ref[1], PackedInt32Array())
			log_debug("GET " + str(fileID) + ": " + str(mesh_ref[1]) + " from " + str(mesh_meta.fileid_to_material_order_rev.get(mesh_ref[1])))
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


	mat_slots = meta.fileid_to_material_order_rev.get(fileID, meta.prefab_fileid_to_material_order_rev.get(fileID, PackedInt32Array()))
	current_materials.resize(new_materials_size)
	for i in range(new_materials_size):
		var idx = mat_slots[i] if i < len(mat_slots) else i
		if idx < new_materials_size:
			current_materials[idx] = props.get("_materials/" + str(i), current_materials[i])

	log_debug("After mat slots " + str(mat_slots) + " materials after: " + str(current_materials))

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
# version 2018+:
#  m_CorrespondingSourceObject: {fileID: 100176, guid: ca6da198c98777940835205234d6323d, type: 3}
#  m_PrefabInstance: {fileID: 2493014228082835901}
#  m_PrefabAsset: {fileID: 0}
# (m_PrefabAsset is always(?) 0 no matter what. I guess we can ignore it?

# version 2017-:
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
		# Might be some 5.6 content. See arktoon Shaders/ExampleScene
		# non-stripped prefab references are allowed to override properties.
		return not is_stripped and not (prefab_source_object[1] == 0 or prefab_instance[1] == 0)

var is_prefab_reference: bool:
	get:
		if not is_stripped:
			#if not (prefab_source_object[1] == 0 or prefab_instance[1] == 0):
			#	log_debug(str(self) + " WITHIN " + str(self.meta.guid) + " / " + str(self.meta.path) + " keys:" + str(self.keys))
			pass  #assert (prefab_source_object[1] == 0 or prefab_instance[1] == 0)
		else:
			# Might have source object=0 if the object is a dummy / broken prefab?
			pass  # assert (prefab_source_object[1] != 0 and prefab_instance[1] != 0)
		return prefab_source_object[1] != 0 and prefab_instance[1] != 0

func get_component_key() -> Variant:
	if self.utype == 114:
		return monoscript_util.convert_unidot_ref_to_npidentifier(self.keys["m_Script"])
	return self.utype

var children_refs: Array:
	get:
		return keys.get("m_Children", [])
